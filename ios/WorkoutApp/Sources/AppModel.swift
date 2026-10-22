import Foundation
import GRDB
import Observation
import WorkoutEngine
import WorkoutStore

/// App-wide state: the store, the engine, identity, and the current session. One instance per app.
@Observable @MainActor
final class AppModel {
    let store: WorkoutStore
    /// Seed catalog merged with the user's custom exercises; the engines are rebuilt whenever that set changes.
    private(set) var catalog: Catalog
    private(set) var planner: Planner
    private(set) var progression: Progression
    let runPlanner = RunPlanner()
    private(set) var rebaseliner: Rebaseliner
    private let seedCatalog: Catalog
    let api: APIClient

    var userId: String
    var activeSession: ActiveSession?
    /// Bumped after every committed write; computed reads touch it so @Observable views refresh.
    private(set) var dataVersion = 0
    @ObservationIgnored private var observer: AnyDatabaseCancellable?
    var lastSyncError: String?
    var isSyncing = false

    /// Partner (or any shared user) currently being viewed read-only in Progress; nil = me.
    var viewingUserId: String?

    init(store: WorkoutStore, catalog: Catalog, api: APIClient, userId: String) {
        self.store = store
        self.seedCatalog = catalog
        self.catalog = catalog
        self.planner = Planner(catalog: catalog)
        self.progression = Progression(catalog: catalog)
        self.rebaseliner = Rebaseliner(catalog: catalog)
        self.api = api
        self.userId = userId
        reloadCatalogIfNeeded()
        observer = DatabaseRegionObservation(tracking: .fullDatabase).start(in: store.db, onError: { _ in }) { [weak self] _ in
            Task { @MainActor in self?.dataVersion &+= 1; self?.reloadCatalogIfNeeded() }
        }
    }

    // MARK: Custom exercises

    var customExercises: [UserExercise] {
        _ = dataVersion
        return (try? store.db.read {
            try UserExercise.filter(Column("userId") == userId && Column("deleted") == false).order(Column("name")).fetchAll($0)
        }) ?? []
    }

    /// Rebuilds catalog + engines when the custom set differs from what they were built with (cheap otherwise).
    func reloadCatalogIfNeeded() {
        let rows = customExercises
        let custom = rows.map { r in
            Exercise(key: r.key, name: r.name, movementPattern: r.pattern, requiredEquipment: r.equipment,
                     loadable: r.loadable, dumbbellBased: r.dumbbellBased, isCustom: true)
        }
        let current = catalog.exercises.values.filter(\.isCustom)
        guard Set(current.map { "\($0.key)|\($0.name)|\($0.movementPattern)|\($0.requiredEquipment)|\($0.loadable)|\($0.dumbbellBased)" })
            != Set(custom.map { "\($0.key)|\($0.name)|\($0.movementPattern)|\($0.requiredEquipment)|\($0.loadable)|\($0.dumbbellBased)" }) else { return }
        catalog = seedCatalog.adding(custom: custom)
        planner = Planner(catalog: catalog)
        progression = Progression(catalog: catalog)
        rebaseliner = Rebaseliner(catalog: catalog)
    }

    /// Saves a user-defined exercise and returns it as part of the (reloaded) catalog.
    func createExercise(name: String, pattern: String, equipment: [String], loadable: Bool, dumbbellBased: Bool) -> Exercise? {
        let slug = name.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let key = "custom_\(slug.isEmpty ? "exercise" : slug)_\(UUIDv7.generate().suffix(6))"
        let row = UserExercise(userId: userId, key: key, name: name.trimmingCharacters(in: .whitespaces), pattern: pattern,
                               equipment: equipment.isEmpty ? ["bodyweight"] : equipment, loadable: loadable, dumbbellBased: dumbbellBased)
        try? store.save(row)
        dataVersion &+= 1
        reloadCatalogIfNeeded()
        return catalog.exercises[key]
    }

    static func live() -> AppModel {
        let catalog = try! SeedLoader.loadBundled()
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = try! WorkoutStore(path: dir.appending(path: "workout.sqlite").path)
        let base = (Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://exercise-app-api.fly.dev")!
        let api = APIClient(baseURL: base, token: { Keychain.get(Keychain.tokenKey) })
        // Local identity exists before any server login so the app is fully usable offline (§9).
        let userId = Keychain.get(Keychain.userIdKey) ?? {
            let id = UUIDv7.generate(); Keychain.set(id, for: Keychain.userIdKey); return id
        }()
        return AppModel(store: store, catalog: catalog, api: api, userId: userId)
    }

    static func preview() -> AppModel {
        let catalog = try! SeedLoader.loadBundled()
        let store = try! WorkoutStore.inMemory()
        let api = APIClient(baseURL: URL(string: "http://localhost:8080")!, token: { nil })
        return AppModel(store: store, catalog: catalog, api: api, userId: "preview")
    }

    // MARK: Reads

    var isOnboarded: Bool {
        _ = dataVersion
        return settings != nil && !locations.isEmpty
    }

    var settings: SettingsRow? {
        _ = dataVersion
        return try? store.db.read { try SettingsRow.filter(Column("userId") == userId && Column("deleted") == false).fetchOne($0) }
    }

    var locations: [Location] {
        _ = dataVersion
        return (try? store.db.read {
            try Location.filter(Column("userId") == userId && Column("deleted") == false).order(Column("sortOrder")).fetchAll($0)
        }) ?? []
    }

    func equipment(for location: Location) -> Set<String> {
        let rows = (try? store.db.read {
            try LocationEquipment.filter(Column("locationId") == location.id && Column("deleted") == false).fetchAll($0)
        }) ?? []
        return Set(rows.map(\.equipmentType)).union(["bodyweight"])
    }

    func inventory(for location: Location) -> LocationInventory {
        LocationInventory(locationKey: location.id, name: location.name, available: equipment(for: location),
                          dumbbellMaxWeight: location.dumbbellMaxWeight, plateIncrement: location.barbellIncrement)
    }

    var splitState: SplitStateRow {
        _ = dataVersion
        if let row = try? store.db.read({ try SplitStateRow.filter(Column("userId") == userId).fetchOne($0) }) { return row }
        var row = SplitStateRow(userId: userId)
        row.heavyRotations = Dictionary(uniqueKeysWithValues: catalog.heavyRotationDefaults.map { ($0.key, HeavyRotation(sequence: $0.value)) })
        try? store.save(row)
        return row
    }

    var exerciseStates: [String: ExerciseState] {
        _ = dataVersion
        let rows = (try? store.db.read {
            try ExerciseStateRow.filter(Column("userId") == userId && Column("deleted") == false).fetchAll($0)
        }) ?? []
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.exerciseKey, $0.engineState) })
    }

    func recentSessions(limit: Int = 12) -> [RecentSession] {
        _ = dataVersion
        let rows = (try? store.db.read {
            try SessionRow.filter(Column("userId") == userId && Column("deleted") == false && Column("completedAt") != nil)
                .order(Column("startedAt").desc).limit(limit).fetchAll($0)
        }) ?? []
        return rows.compactMap { r in
            guard let d = DayType(rawValue: r.dayType) else { return nil }
            return RecentSession(dayType: d, performedAt: r.completedAt ?? r.startedAt, exerciseKeys: r.plan?.blocks.map(\.exerciseKey) ?? [])
        }
    }

    /// Every seeded location exists for this user so Home can offer all of them; installs that predate a seed
    /// entry (or its current name) get it on first launch. Equipment defaults mirror onboarding.
    func ensureSeededLocations() {
        var existing = locations
        for (i, seed) in catalog.seededLocations.enumerated() where !existing.contains(where: { $0.seedKey == seed.key }) {
            // Rows from before `seedKey` existed are recognised by their seed name (incl. the old "Building Gym") and stamped.
            let legacyNames: [String] = [seed.name] + (seed.key == "building_gym" ? ["Building Gym"] : [])
            if let j = existing.firstIndex(where: { $0.seedKey == nil && legacyNames.contains($0.name) }) {
                existing[j].seedKey = seed.key
                if existing[j].name == "Building Gym" { existing[j].name = seed.name }
                existing[j].updatedAt = Date()
                try? store.save(existing[j])
                continue
            }
            let loc = Location(userId: userId, name: seed.name, seedKey: seed.key, dumbbellMaxWeight: seed.dumbbellMaxWeight,
                               dumbbellIncrement: 5, barbellIncrement: seed.plateIncrement, sortOrder: i)
            try? store.save(loc)
            let equipment = seed.defaultAvailable ? catalog.equipmentTypes.map(\.key) : Self.homeGymEquipment
            try? store.save(equipment.map { LocationEquipment(userId: userId, locationId: loc.id, equipmentType: $0) })
            existing.append(loc)
        }
        dataVersion += 1
    }

    static let homeGymEquipment = ["bodyweight", "dumbbells", "bench_adjustable", "bench_flat", "cable_machine", "treadmill"]

    var nextDayType: DayType {
        _ = dataVersion
        let last = recentSessions(limit: 1).first
        return SplitState(lastDayType: last?.dayType, lastCompletedAt: last?.performedAt).nextDayType
    }

    // MARK: Planning

    func plannerInput(dayType: DayType, duration: Int, location: Location) -> PlannerInput {
        let rotation = splitState.heavyRotations[dayType] ?? HeavyRotation(sequence: catalog.heavyRotationDefaults[dayType] ?? [])
        return PlannerInput(dayType: dayType, durationMinutes: duration, location: inventory(for: location),
                            heavyRotation: rotation, states: exerciseStates, recentSessions: recentSessions())
    }

    func preview(dayType: DayType, duration: Int, location: Location) -> Plan {
        planner.generate(plannerInput(dayType: dayType, duration: duration, location: location))
    }

    func startSession(dayType: DayType, duration: Int, location: Location) {
        let input = plannerInput(dayType: dayType, duration: duration, location: location)
        let plan = planner.generate(input)
        let row = SessionRow(userId: userId, dayType: dayType, locationId: location.id, durationMin: duration, plan: plan)
        try? store.save(row)
        var split = splitState
        split.defaultDurationMin = duration
        split.defaultLocationId = location.id
        try? store.save(split)
        activeSession = ActiveSession(row: row, plan: plan, input: input, model: self)
    }

    /// Resume an unfinished session after relaunch (§9: the deck survives kills and airplane mode).
    func restoreActiveSession() {
        guard activeSession == nil,
              let row = try? store.db.read({
                  try SessionRow.filter(Column("userId") == userId && Column("completedAt") == nil && Column("abandoned") == false)
                      .order(Column("startedAt").desc).fetchOne($0)
              }),
              let plan = row.plan,
              let dayType = DayType(rawValue: row.dayType),
              let location = locations.first(where: { $0.id == row.locationId })
        else { return }
        let input = plannerInput(dayType: dayType, duration: row.durationMin, location: location)
        let logs = (try? store.db.read { try SetLog.filter(Column("sessionId") == row.id).fetchAll($0) }) ?? []
        activeSession = ActiveSession(row: row, plan: plan, input: input, model: self, existingLogs: logs)
    }

    // MARK: Session completion

    func finish(_ session: ActiveSession, abandoned: Bool) {
        var row = session.row
        row.completedAt = Date()
        row.abandoned = abandoned
        try? store.save(row)
        if abandoned {
            for log in session.logs where !log.deleted { try? store.delete(log) }
        } else {
            applyProgression(session)
            var split = splitState
            split.nextDayIndex += 1
            let day = session.plan.dayType
            var rot = split.heavyRotations[day] ?? HeavyRotation(sequence: catalog.heavyRotationDefaults[day] ?? [])
            rot.position = (rot.position + 1) % max(1, rot.sequence.count)
            var rots = split.heavyRotations; rots[day] = rot; split.heavyRotations = rots
            try? store.save(split)
            runRebaseline()
        }
        activeSession = nil
        Task { await syncIfPossible() }
    }

    private func applyProgression(_ session: ActiveSession) {
        var states = exerciseStates
        for block in session.plan.blocks {
            guard let exercise = catalog.exercises[block.exerciseKey] else { continue }
            let logs = session.logs(for: block).filter { !$0.isWarmup }.sorted { $0.setIndex < $1.setIndex }
            guard !logs.isEmpty else { continue }
            let sets = logs.map { SetResult(value: $0.repsDone, weight: $0.weight, completed: $0.repsDone >= $0.targetReps, isPadding: $0.isPadding) }
            let rating = logs.compactMap { $0.effort.flatMap(EffortRating.init(rawValue:)) }.last ?? .good
            let firstFailed = sets.enumerated().first { !$0.element.isPadding && !$0.element.completed }?.offset
            let result = ExerciseResult(exerciseKey: block.exerciseKey, band: block.band, repLow: block.repLow, repHigh: block.repHigh,
                                        prescribedSets: block.prescribedSets, sets: sets, rating: rating, firstFailedSetIndex: firstFailed)
            let current = states[block.exerciseKey] ?? ExerciseState(exerciseKey: block.exerciseKey, workingWeight: block.weight, weightSource: block.weightSource ?? .estimated)
            let outcome = progression.apply(result, to: current, exercise: exercise, location: session.input.location)
            states[block.exerciseKey] = outcome.state
            persist(state: outcome.state)
        }
    }

    private func persist(state: ExerciseState) {
        let existing = try? store.db.read { try ExerciseStateRow.filter(Column("userId") == userId && Column("exerciseKey") == state.exerciseKey).fetchOne($0) }
        var row = existing ?? ExerciseStateRow(userId: userId, state: state)
        row.apply(state)
        try? store.save(row)
    }

    private func runRebaseline() {
        let history = (try? store.db.read {
            try SetLog.filter(Column("userId") == userId && Column("isWarmup") == false && Column("isPadding") == false && Column("weight") != nil)
                .order(Column("completedAt").desc).limit(2000).fetchAll($0)
        }) ?? []
        let records = history.map { WorkingSetRecord(exerciseKey: $0.exerciseKey, performedAt: $0.completedAt, weight: $0.weight ?? 0) }
        guard let location = locations.first(where: { $0.id == splitState.defaultLocationId }) ?? locations.first else { return }
        let (states, changes) = rebaseliner.run(states: exerciseStates, history: records, location: inventory(for: location))
        for change in changes { if let s = states[change.exerciseKey] { persist(state: s) } }
    }

    // MARK: Sync

    var isSignedIn: Bool { Keychain.get(Keychain.tokenKey) != nil }

    func syncIfPossible() async {
        guard isSignedIn, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await SyncClient(api: api, store: store).sync()
            lastSyncError = nil
        } catch {
            lastSyncError = "\(error)"
        }
    }

    /// Dev login (server must run with DEV_LOGIN_ENABLED). Sign in with Apple lands in `AppleSignIn.swift`.
    func devLogin(email: String, inviteCode: String?) async throws {
        struct Body: Encodable { var email: String; var invite_code: String?; var display_name: String?; var device_name: String }
        let out = try await api.post("/auth/dev", Body(email: email, invite_code: inviteCode, display_name: settings?.displayName, device_name: "iPhone"), as: TokenDTO.self, auth: false)
        adopt(token: out.token, serverUserId: out.user.id)
    }

    func appleLogin(identityToken: String, inviteCode: String?, displayName: String?) async throws {
        struct Body: Encodable { var identity_token: String; var invite_code: String?; var display_name: String?; var device_name: String }
        let out = try await api.post("/auth/apple", Body(identity_token: identityToken, invite_code: inviteCode, display_name: displayName, device_name: "iPhone"), as: TokenDTO.self, auth: false)
        adopt(token: out.token, serverUserId: out.user.id)
    }

    /// First sign-in: re-key every local row from the provisional device id to the server user id, then sync.
    private func adopt(token: String, serverUserId: String) {
        Task { @MainActor in await adoptAsync(token: token, serverUserId: serverUserId) }
    }

    private func adoptAsync(token: String, serverUserId: String) async {
        let old = userId
        // Only a never-signed-in local identity is folded into the account. If `old` was itself a server account,
        // its history stays its own: anything it still has to upload goes out under its own token first, then
        // its rows are purged from this device on the next pull.
        let oldWasAnotherAccount = serverUserId != old && Keychain.get(Keychain.serverIssuedUserIdKey) == old
        if oldWasAnotherAccount {
            if Keychain.get(Keychain.tokenKey) != nil { await syncIfPossible() }
            let pending = pendingUploads(for: old)
            if pending > 0 {
                // Never switch while the previous account still has unsent sets: they'd be unrecoverable once its rows are purged.
                lastSyncError = "\(pending) change\(pending == 1 ? "" : "s") from the previous account haven't uploaded yet. Get online and sign in again."
                return
            }
        }
        Keychain.set(token, for: Keychain.tokenKey)
        if serverUserId != userId {
            moveLocalRows(from: old, to: serverUserId, keepOldAccountRows: oldWasAnotherAccount)
            if oldWasAnotherAccount { try? store.setPullCursor(0) }   // re-pull this account's history from the start
            Keychain.set(serverUserId, for: Keychain.userIdKey)
            userId = serverUserId
        }
        Keychain.set(serverUserId, for: Keychain.serverIssuedUserIdKey)
        await syncIfPossible()
    }

    private func pendingUploads(for user: String) -> Int {
        (try? store.db.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM outbox WHERE payload LIKE ?", arguments: ["%\"userId\":\"\(user)\"%"]) }) ?? 0
    }

    /// Synchronous on purpose: inside an async context GRDB's `write` resolves to its async overload.
    private func moveLocalRows(from old: String, to new: String, keepOldAccountRows: Bool) {
        try? store.db.write { db in
            if keepOldAccountRows {
                try db.execute(sql: "DELETE FROM outbox WHERE payload LIKE ?", arguments: ["%\"userId\":\"\(old)\"%"])
            } else {
                for t in WorkoutStore.allTables {
                    try db.execute(sql: "UPDATE \(t.tableName) SET userId = ? WHERE userId = ?", arguments: [new, old])
                }
                try db.execute(sql: "UPDATE outbox SET payload = replace(payload, ?, ?)", arguments: ["\"userId\":\"\(old)\"", "\"userId\":\"\(new)\""])
            }
        }
    }

    func signOut() {
        Keychain.remove(Keychain.tokenKey)
    }

    func createInvite(viewMe: Bool, viewThem: Bool) async throws -> InviteDTO {
        struct Body: Encodable { var grant_view_to_inviter: Bool; var grant_view_of_inviter: Bool }
        return try await api.post("/invites", Body(grant_view_to_inviter: viewThem, grant_view_of_inviter: viewMe), as: InviteDTO.self)
    }

    func shares() async throws -> SharesDTO { try await api.get("/shares", as: SharesDTO.self) }
}
