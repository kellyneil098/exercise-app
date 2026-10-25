import Foundation

/// Every tunable constant in the engine. §4.2: "All constants live in a single config module."
public struct EngineConfig: Sendable, Hashable {
    public var heavyRepSecondsDefault: Double = 3.5
    public var otherRepSecondsDefault: Double = 2.5
    public var warmupRestSeconds: Double = 45
    public var warmupReps: [Int] = [8, 5]
    public var warmupFractions: [Double] = [0.5, 0.75]
    public var transitionSeconds: Double = 60
    public var supersetBlockSeconds: Double = 60
    public var minSupersetHostRest: Int = 90
    public var paddingSlackThreshold: Double = 180
    public var shortRestFloorSeconds: Double = 30
    public var barWeight: Double = 45
    public var dumbbellIncrement: Double = 5
    public var defaultPlateIncrement: Double = 5
    public var nonLoadableMaxSets: Int = 4
    public var durationBuckets: [Int] = [30, 45, 60, 90]
    public var deloadFactor: Double = 0.90
    public var rebaselineStaleDays: Int = 21
    public var rebaselineMinIntervalDays: Int = 14
    public var rebaselineDamping: Double = 0.5
    public var rebaselineCap: Double = 0.10
    public var rotateSlotLookbackSessions: Int = 2

    public init() {}
    public static let `default` = EngineConfig()

    /// Snaps a saved duration (e.g. a retired 40-minute bucket) to the nearest offered bucket; ties go to the shorter one.
    public func durationBucket(nearest minutes: Int) -> Int {
        durationBuckets.min { (abs($0 - minutes), $0) < (abs($1 - minutes), $1) } ?? minutes
    }
}

public enum Rounding {
    /// §5.2: round down, always. Weight 0 stays 0.
    public static func down(_ weight: Double, to increment: Double) -> Double {
        guard increment > 0, weight > 0 else { return max(0, weight) }
        return (weight / increment).rounded(.down) * increment
    }
}
