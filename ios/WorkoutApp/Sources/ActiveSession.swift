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
    /// Manual deck order from the overview; empty = slot order.
    private(set) var order: [UUID]
    var restEndsAt: Date? {
        didSet { UserDefaults.standard.set(restEndsAt, forKey: "restEndsAt") }
    }
    var restTotal: TimeInterval = 0

    var id: String { row.id }

    init(row: SessionRow, plan: Plan, input: PlannerInput, model: AppModel, existingLogs: [SetLog] = []) {
        if let saved = UserDefaults.standard.object(forKey: "restEndsAt") as? Date, saved > Date(), !existingLogs.isEmpty {
            restEndsAt = saved
        }
        self.row = row; self.plan = plan; self.input = input; self.model = model; self.logs = existingLogs
        order = (UserDefaults.standard.array(forKey: "deckOrder-\(row.id)") as? [String])?.compactMap(UUID.init(uuidString:)) ?? []
    }

    // MARK: Ordering

    /// Slot order with supersetted blocks right after their host, overridden by any manual order.
    var orderedBlocks: [PlanBlock] {
        var base: [PlanBlock] = []
        for b in plan.blocks.sorted(by: { $0.slot < $1.slot }) where !b.isSupersetted {
            base.append(b)
            if let partner = plan.supersetPartner(of: b) { base.append(partner) }
        }
        if !order.isEmpty {
            let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
            base.sort { (rank[$0.id] ?? .max, $0.slot) < (rank[$1.id] ?? .max, $1.slot) }
        }
        return base
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        let current = orderedBlocks
        var ids = current.map(\.id)
        ids.move(fromOffsets: fromOffsets, toOffset: toOffset)
        order = ids
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: "deckOrder-\(row.id)")
    }

    func logs(for block: PlanBlock) -> [SetLog] {
        logs.filter { $0.slot == block.slot && $0.exerciseKey == block.exerciseKey && !$0.deleted }
    }

    func workingSetsDone(_ block: PlanBlock) -> Int { logs(for: block).filter { !$0.isWarmup }.count }

    func isComplete(_ block: PlanBlock) -> Bool { workingSetsDone(block) >= block.sets }

    /// Next block to work. A superset partner alternates with its host (partner set during host rest).
    var currentBlock: PlanBlock? {
        for b in orderedBlocks where !isComplete(b) {
            if let p = plan.supersetPartner(of: b), !isComplete(p), workingSetsDone(p) < workingSetsDone(b) {
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
        return Array(orderedBlocks.filter { $0.id != cur.id && !isComplete($0) }.prefix(limit))
    }

    var isFinished: Bool { currentBlock == nil }

    var completedCount: Int { plan.blocks.filter { isComplete($0) }.count }

    var remainingCount: Int { plan.blocks.filter { !isComplete($0) }.count }

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
        let timed = b.measure == .seconds
        let reps: Int = switch effort {
        case .hard: timed ? b.repHigh : b.repLow
        case .didNotFinish: timed ? b.repLow : max(0, b.repLow - 1)
        default: b.repHigh
        }
        append(block: b, reps: reps, weight: b.weight, effort: effort, isWarmup: false)
        guard let next = currentBlock else { skipRest(); return }
        if next.supersetHostID == b.id { skipRest(); return }   // partner's set fills the host's rest
        startRest(seconds: plan.host(of: b)?.restSeconds ?? b.restSeconds)
    }

    private func append(block: PlanBlock, reps: Int, weight: Double?, effort: EffortRating?, isWarmup: Bool) {
        let index = logs(for: block).count
        let set = SetLog(userId: model.userId, sessionId: row.id, exerciseKey: block.exerciseKey, slot: block.slot, setIndex: index,
                         isPadding: !isWarmup && (index - block.warmups.count) >= block.prescribedSets, isWarmup: isWarmup,
                         weight: weight, targetReps: block.measure == .seconds ? block.repHigh : block.repLow, repsDone: reps, effort: effort)
        try? model.store.save(set)
        logs.append(set)
    }

    func undoLast(block: PlanBlock) {
        guard let last = logs(for: block).max(by: { $0.setIndex < $1.setIndex }) else { return }
        try? model.store.delete(last)
        logs.removeAll { $0.id == last.id }
        skipRest()
    }

    func startRest(seconds: Int) {
        restTotal = TimeInterval(seconds)
        restEndsAt = Date().addingTimeInterval(restTotal)
        RestNotifier.schedule(at: restEndsAt!)
    }

    func skipRest() { restEndsAt = nil; RestNotifier.cancel() }

    // MARK: Deck management (overview)

    /// Delete: the block leaves the plan. Sets already logged stay in history; a superset partner becomes standalone.
    func remove(_ block: PlanBlock) {
        plan.blocks.removeAll { $0.id == block.id }
        for i in plan.blocks.indices where plan.blocks[i].supersetHostID == block.id { plan.blocks[i].supersetHostID = nil }
        order.removeAll { $0 == block.id }
        skipRest()
        persistPlan()
    }

    /// Adds an exercise at the end of the deck (next free slot, day's template for its pattern).
    func add(_ exercise: Exercise) {
        plan.blocks.append(model.planner.block(adding: exercise, to: plan, input: input))
        persistPlan()
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

    func increment(for block: PlanBlock) -> Double {
        model.catalog.exercises[block.exerciseKey]?.dumbbellBased == true ? EngineConfig.default.dumbbellIncrement : input.location.plateIncrement
    }

    private func mutate(_ block: PlanBlock, _ change: (inout PlanBlock) -> Void) {
        guard let i = plan.blocks.firstIndex(where: { $0.id == block.id }) else { return }
        change(&plan.blocks[i])
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
        let used = Set(plan.blocks.map(\.exerciseKey)).subtracting(block.map { [$0.exerciseKey] } ?? [])
        let dayPatterns = model.planner.resolvedSlots(dayType: plan.dayType, heavyRotation: input.heavyRotation).map(\.pattern)
        var suggested: [Candidate] = []
        if let block {
            suggested = model.planner.candidates(pattern: block.pattern, in: plan, input: input, excluding: used).filter(\.isAvailable)
        } else {
            for p in dayPatterns.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } } {
                suggested += model.planner.candidates(pattern: p, in: plan, input: input, excluding: used).filter(\.isAvailable).prefix(2)
            }
        }
        let all = model.catalog.patterns.keys.flatMap { model.planner.candidates(pattern: $0, in: plan, input: input, excluding: used) }
            .sorted { $0.exercise.name < $1.exercise.name }
        return (suggested, all)
    }

    /// Substitution keeps the slot and superset relationship; the weight is re-estimated (§7.3). Any pattern is allowed.
    func swap(_ block: PlanBlock, to exercise: Exercise) {
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
