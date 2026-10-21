import Foundation
import Observation
import WorkoutEngine
import WorkoutStore

/// The live deck (§7). Every logged set is written to SQLite immediately; the deck is derived from those rows.
@Observable @MainActor
final class ActiveSession: Identifiable {
    private(set) var row: SessionRow
    private(set) var plan: Plan
    private(set) var input: PlannerInput
    private unowned let model: AppModel
    private(set) var logs: [SetLog]
    /// Blocks the user deferred; they come back at the end.
    private(set) var deferred: Set<UUID> = []
    private(set) var skipped: Set<UUID> = []
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
    }

    // MARK: Ordering

    /// Supersetted blocks sit right after their host; the deck shows them paired.
    var orderedBlocks: [PlanBlock] {
        var out: [PlanBlock] = []
        for b in plan.blocks.sorted(by: { $0.slot < $1.slot }) where !b.isSupersetted {
            out.append(b)
            if let partner = plan.supersetPartner(of: b) { out.append(partner) }
        }
        let active = out.filter { !deferred.contains($0.id) }
        let later = out.filter { deferred.contains($0.id) }
        return active + later
    }

    func logs(for block: PlanBlock) -> [SetLog] {
        logs.filter { $0.slot == block.slot && $0.exerciseKey == block.exerciseKey && !$0.deleted }
    }

    func workingSetsDone(_ block: PlanBlock) -> Int { logs(for: block).filter { !$0.isWarmup }.count }

    func isComplete(_ block: PlanBlock) -> Bool { skipped.contains(block.id) || workingSetsDone(block) >= block.sets }

    var currentBlock: PlanBlock? { orderedBlocks.first { !isComplete($0) } }

    var isFinished: Bool { currentBlock == nil }

    var completedCount: Int { plan.blocks.filter { !skipped.contains($0.id) && workingSetsDone($0) >= $0.sets }.count }

    // MARK: Logging

    func log(block: PlanBlock, reps: Int, weight: Double?, effort: EffortRating?, isWarmup: Bool = false) {
        let index = logs(for: block).count
        let set = SetLog(userId: model.userId, sessionId: row.id, exerciseKey: block.exerciseKey, slot: block.slot, setIndex: index,
                         isPadding: !isWarmup && (index - block.warmups.count) >= block.prescribedSets, isWarmup: isWarmup,
                         weight: weight, targetReps: block.measure == .seconds ? block.repHigh : block.repLow, repsDone: reps, effort: effort)
        try? model.store.save(set)
        logs.append(set)
        if !isComplete(block) || plan.supersetPartner(of: block) != nil {
            startRest(seconds: block.restSeconds)
        } else {
            restEndsAt = nil
        }
    }

    func undoLast(block: PlanBlock) {
        guard let last = logs(for: block).max(by: { $0.setIndex < $1.setIndex }) else { return }
        try? model.store.delete(last)
        logs.removeAll { $0.id == last.id }
        restEndsAt = nil
    }

    func startRest(seconds: Int) {
        restTotal = TimeInterval(seconds)
        restEndsAt = Date().addingTimeInterval(restTotal)
        RestNotifier.schedule(at: restEndsAt!)
    }

    func skipRest() { restEndsAt = nil; RestNotifier.cancel() }

    // MARK: Deck actions

    func defer_(_ block: PlanBlock) { deferred.insert(block.id); restEndsAt = nil }
    func skip(_ block: PlanBlock) { skipped.insert(block.id); restEndsAt = nil }

    /// Swipe-left substitution: same slot, same superset relationship, weight re-estimated (§7.3).
    func candidates(for block: PlanBlock) -> [Candidate] {
        guard let slot = model.planner.resolvedSlots(dayType: plan.dayType, heavyRotation: input.heavyRotation).first(where: { $0.slot == block.slot }) else { return [] }
        let used = Set(plan.blocks.map(\.exerciseKey)).subtracting([block.exerciseKey])
        return model.planner.candidates(pattern: block.pattern, slot: slot, input: input, excluding: used)
    }

    func swap(_ block: PlanBlock, to exercise: Exercise) {
        plan = model.planner.swap(block: block, to: exercise, in: plan, input: input)
        row = SessionRow(id: row.id, userId: row.userId, dayType: plan.dayType, locationId: row.locationId, durationMin: row.durationMin,
                         startedAt: row.startedAt, plan: plan)
        try? model.store.save(row)
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

#if canImport(UserNotifications)
import UserNotifications
#endif

extension EffortRating {
    var label: String {
        switch self { case .easy: "Easy"; case .good: "Good"; case .didNotFinish: "Didn't finish" }
    }
}
