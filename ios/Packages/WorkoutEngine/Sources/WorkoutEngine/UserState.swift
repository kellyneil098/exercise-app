import Foundation

public enum WeightSource: String, Codable, Sendable, Hashable {
    case measured, estimated, rebaselined
}

/// Per-(user, exercise) training state. §4.3, §4.4, §5.1.
public struct ExerciseState: Codable, Sendable, Hashable {
    public var exerciseKey: String
    public var workingWeight: Double?
    public var weightSource: WeightSource
    public var consecutiveFailures: Int
    public var lastPerformedAt: Date?
    public var lastRebaselinedAt: Date?
    public var preRebaselineWeight: Double?
    /// For non-loadable exercises: the current prescribed set count (reps-then-sets progression, §5.2).
    public var setCount: Int?

    public init(
        exerciseKey: String, workingWeight: Double? = nil, weightSource: WeightSource = .estimated,
        consecutiveFailures: Int = 0, lastPerformedAt: Date? = nil, lastRebaselinedAt: Date? = nil,
        preRebaselineWeight: Double? = nil, setCount: Int? = nil
    ) {
        self.exerciseKey = exerciseKey; self.workingWeight = workingWeight; self.weightSource = weightSource
        self.consecutiveFailures = consecutiveFailures; self.lastPerformedAt = lastPerformedAt
        self.lastRebaselinedAt = lastRebaselinedAt; self.preRebaselineWeight = preRebaselineWeight
        self.setCount = setCount
    }
}

/// Per-user, per-day-type slot-1 pattern cycle. §3.4.
public struct HeavyRotation: Codable, Sendable, Hashable {
    public var sequence: [String]
    public var position: Int

    public init(sequence: [String], position: Int = 0) {
        self.sequence = sequence
        self.position = sequence.isEmpty ? 0 : position % sequence.count
    }

    public var current: String? { sequence.isEmpty ? nil : sequence[position % sequence.count] }

    public mutating func advance() {
        guard !sequence.isEmpty else { return }
        position = (position + 1) % sequence.count
    }
}

/// §3.5. Sequence-driven, not calendar-driven.
public struct SplitState: Codable, Sendable, Hashable {
    public var lastDayType: DayType?
    public var lastCompletedAt: Date?

    public init(lastDayType: DayType? = nil, lastCompletedAt: Date? = nil) {
        self.lastDayType = lastDayType; self.lastCompletedAt = lastCompletedAt
    }

    public var nextDayType: DayType { lastDayType?.next ?? .push }
}

/// What the generator needs to know about a location. §3.1.
public struct LocationInventory: Codable, Sendable, Hashable {
    public var locationKey: String
    public var name: String
    public var available: Set<String>
    public var dumbbellMaxWeight: Double?
    public var plateIncrement: Double

    public init(locationKey: String, name: String, available: Set<String>, dumbbellMaxWeight: Double?, plateIncrement: Double) {
        self.locationKey = locationKey; self.name = name
        self.available = available.union(["bodyweight"])
        self.dumbbellMaxWeight = dumbbellMaxWeight; self.plateIncrement = plateIncrement
    }

    public func hasAll(_ equipment: [String]) -> Bool {
        equipment.allSatisfy { available.contains($0) }
    }
}

/// A completed session, newest first, as the generator sees history. §3.4 recency rules.
public struct RecentSession: Codable, Sendable, Hashable {
    public var dayType: DayType
    public var performedAt: Date
    public var exerciseKeys: [String]

    public init(dayType: DayType, performedAt: Date, exerciseKeys: [String]) {
        self.dayType = dayType; self.performedAt = performedAt; self.exerciseKeys = exerciseKeys
    }
}
