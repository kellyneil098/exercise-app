import Foundation

public enum EffortRating: String, Codable, Sendable, Hashable {
    case easy, good, didNotFinish
}

/// One logged working set. `value` is reps, or seconds for timed holds.
public struct SetResult: Codable, Sendable, Hashable {
    public var value: Int
    public var weight: Double?
    public var completed: Bool
    public var isPadding: Bool

    public init(value: Int, weight: Double? = nil, completed: Bool = true, isPadding: Bool = false) {
        self.value = value; self.weight = weight; self.completed = completed; self.isPadding = isPadding
    }
}

public struct ExerciseResult: Codable, Sendable, Hashable {
    public var exerciseKey: String
    public var band: Band
    public var repLow: Int
    public var repHigh: Int
    public var prescribedSets: Int
    public var sets: [SetResult]
    public var rating: EffortRating
    /// 0-based index of the first set the user failed to complete (DNF only).
    public var firstFailedSetIndex: Int?

    public init(exerciseKey: String, band: Band, repLow: Int, repHigh: Int, prescribedSets: Int,
                sets: [SetResult], rating: EffortRating = .good, firstFailedSetIndex: Int? = nil) {
        self.exerciseKey = exerciseKey; self.band = band; self.repLow = repLow; self.repHigh = repHigh
        self.prescribedSets = prescribedSets; self.sets = sets; self.rating = rating
        self.firstFailedSetIndex = firstFailedSetIndex ?? sets.firstIndex { !$0.completed && !$0.isPadding }
    }

    /// The sets the progression test looks at: non-padding, up to the template's count.
    public var workingSets: [SetResult] { Array(sets.filter { !$0.isPadding }.prefix(prescribedSets)) }
}

public enum ProgressionChange: Sendable, Hashable {
    case increase(by: Double)
    case hold
    case deload(to: Double)
    case revert(to: Double)
    case addSet(to: Int)
    case maintain
}

public struct ProgressionOutcome: Sendable, Hashable {
    public let state: ExerciseState
    public let change: ProgressionChange
}

/// §5 double progression, rating modifiers, DNF severity. Pure.
public struct Progression: Sendable {
    let catalog: Catalog
    let config: EngineConfig

    public init(catalog: Catalog, config: EngineConfig = .default) {
        self.catalog = catalog; self.config = config
    }

    /// §5.2 step size for one weight increase.
    public func step(for exercise: Exercise, band: Band, location: LocationInventory) -> Double {
        let p = catalog.progressionSteps
        switch band {
        case .heavy:
            return catalog.patterns[exercise.movementPattern]?.dayType == "legs" ? p.heavyLower : p.heavyUpper
        case .medium:
            return exercise.dumbbellBased ? p.mediumDumbbellPerHand : p.medium
        case .volume:
            if exercise.dumbbellBased { return config.dumbbellIncrement }
            return location.plateIncrement <= p.volume ? p.volume : p.volumeFallback
        }
    }

    public func apply(_ result: ExerciseResult, to state: ExerciseState, exercise: Exercise,
                      location: LocationInventory, now: Date = Date()) -> ProgressionOutcome {
        var s = state
        s.lastPerformedAt = now
        let inc = exercise.dumbbellBased ? config.dumbbellIncrement : location.plateIncrement
        let sets = result.workingSets
        let allTop = !sets.isEmpty && sets.allSatisfy { $0.completed && $0.value >= result.repHigh }
        let anyBelow = sets.contains { !$0.completed || $0.value < result.repLow }

        guard exercise.loadable else {
            return nonLoadable(result, s, allTop: allTop)
        }
        let w = s.workingWeight ?? sets.compactMap(\.weight).max() ?? 0
        s.workingWeight = w

        if result.rating == .didNotFinish {
            let first = result.firstFailedSetIndex ?? 0
            if first == 0 {
                if s.weightSource != .measured {
                    // §5.4: the only immediate downgrade — a bad estimate exposed on set 1.
                    let target = s.preRebaselineWeight ?? Rounding.down(w * config.deloadFactor, to: inc)
                    s.workingWeight = target; s.weightSource = .measured; s.preRebaselineWeight = nil
                    return ProgressionOutcome(state: s, change: .revert(to: target))
                }
                s.consecutiveFailures += 1
                if s.consecutiveFailures >= 2 {
                    let target = Rounding.down(w * config.deloadFactor, to: inc)
                    s.workingWeight = target; s.consecutiveFailures = 0
                    return ProgressionOutcome(state: s, change: .deload(to: target))
                }
            }
            return ProgressionOutcome(state: s, change: .hold)
        }

        let step = self.step(for: exercise, band: result.band, location: location)
        if allTop {
            let by = result.rating == .easy ? step * 2 : step
            s.workingWeight = w + by; s.weightSource = .measured; s.consecutiveFailures = 0; s.preRebaselineWeight = nil
            return ProgressionOutcome(state: s, change: .increase(by: by))
        }
        if result.rating == .easy {
            s.workingWeight = w + step; s.weightSource = .measured; s.consecutiveFailures = 0; s.preRebaselineWeight = nil
            return ProgressionOutcome(state: s, change: .increase(by: step))
        }
        if anyBelow {
            s.consecutiveFailures += 1
            if s.consecutiveFailures >= 2 {
                let target = Rounding.down(w * config.deloadFactor, to: inc)
                s.workingWeight = target; s.consecutiveFailures = 0
                return ProgressionOutcome(state: s, change: .deload(to: target))
            }
            return ProgressionOutcome(state: s, change: .hold)
        }
        s.consecutiveFailures = 0
        return ProgressionOutcome(state: s, change: .hold)
    }

    /// §5.2 reps-then-sets for bodyweight/timed work.
    private func nonLoadable(_ result: ExerciseResult, _ state: ExerciseState, allTop: Bool) -> ProgressionOutcome {
        var s = state
        s.weightSource = .measured
        let current = s.setCount ?? result.prescribedSets
        if result.rating == .didNotFinish { return ProgressionOutcome(state: s, change: .hold) }
        if allTop || result.rating == .easy {
            if current < config.nonLoadableMaxSets {
                s.setCount = current + 1
                return ProgressionOutcome(state: s, change: .addSet(to: current + 1))
            }
            return ProgressionOutcome(state: s, change: .maintain)
        }
        s.setCount = current
        return ProgressionOutcome(state: s, change: .hold)
    }
}
