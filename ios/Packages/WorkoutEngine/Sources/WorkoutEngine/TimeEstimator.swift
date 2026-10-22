import Foundation

/// §4.2. Runs once, at generation. A coarse sizing heuristic, not a schedule.
public struct TimeEstimator: Sendable {
    let config: EngineConfig
    public init(config: EngineConfig = .default) { self.config = config }

    public func repSeconds(for exercise: Exercise, band: Band) -> Double {
        exercise.repSeconds ?? (band == .heavy ? config.heavyRepSecondsDefault : config.otherRepSecondsDefault)
    }

    public func warmupSeconds(exercise: Exercise, band: Band, warmupSets: Int) -> Double {
        guard warmupSets > 0 else { return 0 }
        let r = repSeconds(for: exercise, band: band)
        return Double(warmupSets) * (8 * r) + Double(warmupSets) * config.warmupRestSeconds
    }

    public func setSeconds(exercise: Exercise, band: Band, repHigh: Int) -> Double {
        exercise.measure == .seconds ? Double(repHigh) : Double(repHigh) * repSeconds(for: exercise, band: band)
    }

    public func blockSeconds(exercise: Exercise, slot: SlotTemplate, sets: Int, supersetted: Bool) -> Double {
        if supersetted { return config.supersetBlockSeconds }
        let working = Double(sets) * setSeconds(exercise: exercise, band: slot.band, repHigh: slot.repHigh)
        let rest = Double(max(0, sets - 1)) * Double(slot.restSeconds)
        return warmupSeconds(exercise: exercise, band: slot.band, warmupSets: slot.warmupSets) + working + rest + config.transitionSeconds
    }

    /// Cost of adding one more set to an existing block.
    public func extraSetSeconds(exercise: Exercise, slot: SlotTemplate) -> Double {
        setSeconds(exercise: exercise, band: slot.band, repHigh: slot.repHigh) + Double(slot.restSeconds)
    }
}
