import Foundation
import Observation
import WorkoutEngine
import WorkoutStore
#if canImport(UserNotifications)
import UserNotifications
#endif

/// The one thing to do right now: a warm-up or a working set of a block.
struct DeckStep: Equatable {
    let block: PlanBlock
    let isWarmup: Bool
    /// 0-based within its kind (warm-up n / working set n).
    let index: Int

    var warmup: WarmupSet? { isWarmup ? block.warmups[index] : nil }
    var id: String { "\(block.id)-\(isWarmup ? "w" : "s")-\(index)" }
}

/// The live deck (§7). Every logged set is written to SQLite immediately; the deck is derived from those rows.
@Observable @MainActor
final class ActiveSession: Identifiable {
    private(set) var row: SessionRow
    private(set) var plan: Plan
    private(set) var input: PlannerInput
    private unowned let model: AppModel
    private(set) var logs: [SetLog]
    /// Manual order plus the blocks skipped (swiped away in the deck) or deleted (swiped out of the overview).
    /// Both kinds stay in the plan and restorable. Order and skipped are device-local (UserDefaults); deleted
    /// mirrors `PlanBlock.isDeleted`, which lives in the synced plan so another device resumes the same deck.
    private(set) var edits: DeckEdits {
        didSet {
            let defaults = UserDefaults.standard
            defaults.set(edits.order.map(\.uuidString), forKey: "deckOrder-\(row.id)")
            defaults.set(edits.skipped.map(\.uuidString), forKey: "deckSkipped-\(row.id)")
        }
    }
    var restEndsAt: Date? {
        didSet { UserDefaults.standard.set(restEndsAt, forKey: "restEndsAt") }
    }
    /// Seconds left when the timer was paused; `nil` while it runs.
    private(set) var restPausedRemaining: TimeInterval? {
        didSet { UserDefaults.standard.set(restPausedRemaining, forKey: "restPausedRemaining") }
    }
    var restTotal: TimeInterval = 0
    /// The last swipe, so a mis-swipe can be taken back. One level deep, in memory only.
    enum DeckAction { case logged(SetLog), skipped(UUID) }
    private(set) var lastAction: DeckAction?
    /// False while the user is still confirming the deck in the overview; true once they tap Start workout.
    private(set) var started: Bool {
        didSet { UserDefaults.standard.set(started, forKey: "deckStarted-\(row.id)") }
    }

    var id: String { row.id }

    init(row: SessionRow, plan: Plan, input: PlannerInput, model: AppModel, existingLogs: [SetLog] = []) {
        if !existingLogs.isEmpty, let paused = UserDefaults.standard.object(forKey: "restPausedRemaining") as? TimeInterval, paused > 0 {
            restPausedRemaining = paused
            restEndsAt = Date().addingTimeInterval(paused)
            restTotal = paused
        } else if let saved = UserDefaults.standard.object(forKey: "restEndsAt") as? Date, saved > Date(), !existingLogs.isEmpty {
            restEndsAt = saved
        }
        self.row = row; self.plan = plan; self.input = input; self.model = model; self.logs = existingLogs
        let saved = { (key: String) in (UserDefaults.standard.array(forKey: "\(key)-\(row.id)") as? [String])?.compactMap(UUID.init(uuidString:)) ?? [] }
        edits = DeckEdits(order: saved("deckOrder"), skipped: Set(saved("deckSkipped")), deleted: Set(plan.blocks.filter(\.isDeleted).map(\.id)))
        started = !existingLogs.isEmpty || UserDefaults.standard.bool(forKey: "deckStarted-\(row.id)")
    }

    /// The clock starts here, not when the deck was built, so time spent confirming it isn't counted.
    func start() {
        row.startedAt = Date()
        try? model.store.save(row)
        started = true
    }
    /// Back out of an unstarted deck; nothing was logged so the session row is dropped.
    func cancel() { model.cancel(self) }

    // MARK: Ordering

    /// Slot order with supersetted blocks right after their host, overridden by any manual order.
    /// A partner whose host is deleted (or that is deleted itself) is listed on its own, so neither side of a
    /// pair ever drops out of the deck or the Deleted section while the other is set aside.
    var orderedBlocks: [PlanBlock] {
        func standalone(_ b: PlanBlock) -> Bool { b.isDeleted || plan.host(of: b) == nil }
        var base: [PlanBlock] = []
        for b in plan.slotOrdered where standalone(b) {
            base.append(b)
            if let partner = plan.supersetPartner(of: b) { base.append(partner) }
        }
        if !edits.order.isEmpty {
            let rank = Dictionary(edits.order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
            base.sort { (rank[$0.id] ?? .max, $0.slot) < (rank[$1.id] ?? .max, $1.slot) }
            // A partner always sits right behind its host so the pair keeps alternating, wherever it was dragged.
            var glued: [PlanBlock] = []
            for b in base where standalone(b) {
                glued.append(b)
                if let partner = plan.supersetPartner(of: b) { glued.append(partner) }
            }
            return glued
        }
        return base
    }

    /// Deck order minus skipped and deleted blocks — what the overview lists and reorders.
    var activeBlocks: [PlanBlock] { edits.active(orderedBlocks) }

    var skippedBlocks: [PlanBlock] { edits.skippedBlocks(orderedBlocks) }

    var deletedBlocks: [PlanBlock] { edits.deletedBlocks(orderedBlocks) }

    func isSkipped(_ block: PlanBlock) -> Bool { edits.isSkipped(block.id) }

    func isDeleted(_ block: PlanBlock) -> Bool { edits.isDeleted(block.id) }

    /// A supersetted block whose host is still in the deck; without the host it stands on its own.
    func isSupersetLinked(_ block: PlanBlock) -> Bool {
        guard let host = block.supersetHostID else { return false }
        return !edits.isSetAside(host)
    }

    /// Reorders within the active deck; skipped and deleted blocks keep their place behind it.
    func move(fromOffsets: IndexSet, toOffset: Int) {
        edits.move(fromOffsets: fromOffsets, toOffset: toOffset, in: orderedBlocks)
    }

    func logs(for block: PlanBlock) -> [SetLog] {
        logs.filter { $0.slot == block.slot && $0.exerciseKey == block.exerciseKey && !$0.deleted }
    }

    func workingSetsDone(_ block: PlanBlock) -> Int { logs(for: block).filter { !$0.isWarmup }.count }

    func isComplete(_ block: PlanBlock) -> Bool { workingSetsDone(block) >= block.sets }

    /// Still has sets to do and hasn't been skipped or deleted.
    func isActive(_ block: PlanBlock) -> Bool { !isComplete(block) && !edits.isSetAside(block.id) }

    /// Next block to work. A superset partner alternates with its host (partner set during host rest).
    var currentBlock: PlanBlock? {
        for b in orderedBlocks where isActive(b) {
            if let p = plan.supersetPartner(of: b), isActive(p), workingSetsDone(p) < workingSetsDone(b) {
                return p
            }
            return b
        }
        return nil
    }

    var currentStep: DeckStep? {
        guard let b = currentBlock else { return nil }
        let warm = logs(for: b).filter(\.isWarmup).count
        if b.band == .heavy, warm < b.warmups.count { return DeckStep(block: b, isWarmup: true, index: warm) }
        return DeckStep(block: b, isWarmup: false, index: workingSetsDone(b))
    }

    /// Blocks queued behind the current one — what peeks out of the stack.
    func upcoming(limit: Int) -> [PlanBlock] {
        guard let cur = currentBlock else { return [] }
        return Array(orderedBlocks.filter { $0.id != cur.id && isActive($0) }.prefix(limit))
    }

    var isFinished: Bool { currentBlock == nil }

    var completedCount: Int { plan.blocks.filter { isComplete($0) && !edits.isDeleted($0.id) }.count }

    /// Blocks in play — the `m` of "n of m" — excludes what was skipped or deleted (a finished skipped block still counts).
    var deckCount: Int { plan.blocks.filter { !edits.isDeleted($0.id) && (isComplete($0) || !edits.isSkipped($0.id)) }.count }

    var remainingCount: Int { plan.blocks.filter { isActive($0) }.count }

    // MARK: Logging

    /// Swipe-right / rating: logs the current step. Reps are implied by the rating (the deck asks for nothing else):
    /// easy and good hit the top of the range, hard the bottom, didn't-finish falls short of the target.
    func complete(effort: EffortRating?) {
        guard let step = currentStep else { return }
        let b = step.block
        if let w = step.warmup {
            append(block: b, reps: w.reps, weight: w.weight, effort: nil, isWarmup: true)
            startRest(seconds: 60)
            return
        }
        // The stretch is one timed reminder: logged as done (so resume knows), no load, no rating, no rest after.
        if b.isCooldown {
            append(block: b, reps: b.repHigh, weight: nil, effort: nil, isWarmup: false)
            skipRest()
            return
        }
        let timed = b.measure == .seconds
        let reps: Int = switch effort {
        case .hard: timed ? b.repHigh : b.repLow
        case .didNotFinish: timed ? b.repLow : max(0, b.repLow - 1)
        default: b.repHigh
        }
        append(block: b, reps: reps, weight: b.weight, effort: effort, isWarmup: false)
        guard let next = currentBlock else { skipRest(); return }
        if next.supersetHostID == b.id { skipRest(); return }   // partner's set fills the host's rest
        if next.isCooldown { skipRest(); return }   // straight into the stretch, no countdown in front of it
        startRest(seconds: plan.restSeconds(for: b))
    }

    private func append(block: PlanBlock, reps: Int, weight: Double?, effort: EffortRating?, isWarmup: Bool) {
        let index = logs(for: block).count
        let set = SetLog(userId: model.userId, sessionId: row.id, exerciseKey: block.exerciseKey, slot: block.slot, setIndex: index,
                         isPadding: !isWarmup && (index - block.warmups.count) >= block.prescribedSets, isWarmup: isWarmup,
                         weight: weight, targetReps: block.measure == .seconds ? block.repHigh : block.repLow, repsDone: reps, effort: effort)
        try? model.store.save(set)
        logs.append(set)
        lastAction = .logged(set)
    }

    /// Reverses the most recent Done or Skip: the set is deleted (and any rest cancelled) or the block rejoins the deck
    /// where it was.
    func undo() {
        guard let action = lastAction else { return }
        switch action {
        case .logged(let set):
            try? model.store.delete(set)
            logs.removeAll { $0.id == set.id }
            skipRest()
        case .skipped(let id):
            edits.skipped.remove(id)
        }
        lastAction = nil
    }

    func undoLast(block: PlanBlock) {
        guard let last = logs(for: block).max(by: { $0.setIndex < $1.setIndex }) else { return }
        try? model.store.delete(last)
        logs.removeAll { $0.id == last.id }
        if case .logged(let s) = lastAction, s.id == last.id { lastAction = nil }
        skipRest()
    }

    func startRest(seconds: Int) {
        restPausedRemaining = nil
        restTotal = TimeInterval(seconds)
        restEndsAt = Date().addingTimeInterval(restTotal)
        RestNotifier.schedule(at: restEndsAt!)
    }

    func skipRest() { restEndsAt = nil; restPausedRemaining = nil; RestNotifier.cancel() }

    // MARK: Rest timer controls

    var isRestPaused: Bool { restPausedRemaining != nil }

    /// Seconds left on the rest card at `date`; frozen while paused.
    func restRemaining(at date: Date) -> TimeInterval {
        if let paused = restPausedRemaining { return paused }
        return max(0, restEndsAt?.timeIntervalSince(date) ?? 0)
    }

    func pauseRest() {
        guard let end = restEndsAt, restPausedRemaining == nil else { return }
        restPausedRemaining = max(0, end.timeIntervalSinceNow)
        RestNotifier.cancel()
    }

    func resumeRest() {
        guard let remaining = restPausedRemaining else { return }
        restPausedRemaining = nil
        restEndsAt = Date().addingTimeInterval(remaining)
        RestNotifier.schedule(at: restEndsAt!)
    }

    /// ±10 s. Going below zero ends the rest; going past the original length stretches the ring to match.
    func adjustRest(by seconds: TimeInterval) {
        guard restEndsAt != nil else { return }
        let remaining = restRemaining(at: Date()) + seconds
        guard remaining > 0 else { skipRest(); return }
        restTotal = max(restTotal, remaining)
        if restPausedRemaining != nil {
            restPausedRemaining = remaining
        } else {
            restEndsAt = Date().addingTimeInterval(remaining)
            RestNotifier.schedule(at: restEndsAt!)
        }
    }

    // MARK: Skipping

    /// Swipe-left: the block leaves the stack for this session. Sets already logged stay; restorable from the overview.
    func skip(_ block: PlanBlock) {
        edits.skip(block.id)
        lastAction = .skipped(block.id)
        if currentBlock == nil { skipRest() }   // a running rest stays; only an emptied deck ends it
    }

    /// Puts a skipped or deleted block back into the deck, at the end of what's left.
    func restore(_ block: PlanBlock) {
        edits.restore(block.id, in: orderedBlocks)
        if block.isDeleted { setDeleted(block, false) }
        if case .skipped(let id) = lastAction, id == block.id { lastAction = nil }
    }

    // MARK: Deck management (overview)

    /// Swipe-left in the overview: the block leaves the deck for this session but is listed under Deleted, where a
    /// swipe brings it back. Sets already logged stay in history. Deleting the block whose set was just logged
    /// also drops the deck's Undo, which would otherwise point at a row that is no longer in play.
    func delete(_ block: PlanBlock) {
        edits.delete(block.id)
        setDeleted(block, true)
        switch lastAction {
        case .skipped(let id) where id == block.id: lastAction = nil
        case .logged(let set) where set.slot == block.slot && set.exerciseKey == block.exerciseKey: lastAction = nil
        default: break
        }
        if currentBlock == nil { skipRest() }
    }

    /// Adds an exercise at the end of the deck (next free slot, day's template for its pattern).
    func add(_ exercise: Exercise) {
        let block = model.planner.block(adding: exercise, to: plan, input: input)
        plan.blocks.append(block)
        persistPlan()
        edits.add(block.id, in: orderedBlocks)
    }

    func setWeight(_ block: PlanBlock, _ w: Double) {
        mutate(block) { $0.weight = max(0, w); $0.weightSource = .measured }
    }

    /// Fewer sets than prescribed re-prescribes; extra sets are padding and don't gate progression.
    func setSets(_ block: PlanBlock, _ n: Int) {
        mutate(block) { $0.sets = max(1, n); $0.prescribedSets = min($0.prescribedSets, $0.sets) }
    }

    func shiftReps(_ block: PlanBlock, by d: Int) {
        mutate(block) { guard $0.repLow + d >= 1 else { return }; $0.repLow += d; $0.repHigh += d }
    }

    /// Rest after this block's sets — what the next rest card counts down from. Shared with the host for a superset partner.
    func restSeconds(for block: PlanBlock) -> Int { plan.restSeconds(for: block) }

    /// Plan-editor stepper: ±10 s per tap; takes effect on the next rest card for this exercise.
    func stepRest(_ block: PlanBlock, by steps: Int) {
        guard plan.blocks.contains(where: { $0.id == block.id }) else { return }
        plan.stepRest(of: block, by: steps)
        persistPlan()
    }

    func increment(for block: PlanBlock) -> Double {
        model.catalog.exercises[block.exerciseKey]?.dumbbellBased == true ? EngineConfig.default.dumbbellIncrement : input.location.plateIncrement
    }

    private func mutate(_ block: PlanBlock, _ change: (inout PlanBlock) -> Void) {
        guard let i = plan.blocks.firstIndex(where: { $0.id == block.id }), !plan.blocks[i].isCooldown else { return }
        change(&plan.blocks[i])
        persistPlan()
    }

    private func setDeleted(_ block: PlanBlock, _ deleted: Bool) {
        guard let i = plan.blocks.firstIndex(where: { $0.id == block.id }) else { return }
        plan.blocks[i].isDeleted = deleted
        persistPlan()
    }

    private func persistPlan() {
        row = SessionRow(id: row.id, userId: row.userId, dayType: plan.dayType, locationId: row.locationId, durationMin: row.durationMin,
                         startedAt: row.startedAt, plan: plan)
        try? model.store.save(row)
    }

    /// Picker rows. Suggested: when swapping, the block's own pattern; when adding, the day's patterns in slot order
    /// (top few of each). `all` is the whole catalog, A–Z, with availability at this location.
    func pickerSections(replacing block: PlanBlock?) -> (suggested: [Candidate], all: [Candidate]) {
        // A deleted block doesn't hold its exercise: the user may add it back as a fresh row. The block being
        // swapped does, so it never suggests itself.
        let used = Set(plan.liveBlocks.map(\.exerciseKey))
        let dayPatterns = model.planner.resolvedSlots(dayType: plan.dayType, heavyRotation: input.heavyRotation).map(\.pattern)
        var suggested: [Candidate] = []
        if let block {
            suggested = model.planner.candidates(pattern: block.pattern, replacing: block, in: plan, input: input, excluding: used).filter(\.isAvailable)
        } else {
            for p in dayPatterns.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } } {
                suggested += model.planner.candidates(pattern: p, in: plan, input: input, excluding: used).filter(\.isAvailable).prefix(2)
            }
        }
        let all = model.catalog.patterns.keys.flatMap { p in
            block.map { model.planner.candidates(pattern: p, replacing: $0, in: plan, input: input, excluding: used) }
                ?? model.planner.candidates(pattern: p, in: plan, input: input, excluding: used)
        }
            .sorted { $0.exercise.name < $1.exercise.name }
        return (suggested, all)
    }

    /// Substitution keeps the slot and superset relationship; the weight is re-estimated (§7.3). Any pattern is allowed.
    func swap(_ block: PlanBlock, to exercise: Exercise) {
        guard !block.isCooldown else { return }
        plan = model.planner.swap(block: block, to: exercise, in: plan, input: input)
        persistPlan()
    }

    func finish() { model.finish(self, abandoned: false) }
    func abandon() { model.finish(self, abandoned: true) }
}

/// Rest timer is derived from a stored end timestamp, so it survives backgrounding; a local notification
/// covers the locked-screen case (§7.4).
enum RestNotifier {
    static let id = "rest-timer"

    static func schedule(at date: Date) {
        #if canImport(UserNotifications)
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            center.removePendingNotificationRequests(withIdentifiers: [id])
            let content = UNMutableNotificationContent()
            content.title = "Rest over"
            content.body = "Next set."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        #endif
    }

    static func cancel() {
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        #endif
    }
}

extension EffortRating {
    var label: String {
        switch self { case .easy: "Easy"; case .good: "Good"; case .hard: "Hard"; case .didNotFinish: "Didn't finish" }
    }
}
