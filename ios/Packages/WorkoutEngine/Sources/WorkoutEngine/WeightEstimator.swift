import Foundation

public struct WeightEstimate: Sendable, Hashable {
    public let weight: Double
    public let source: WeightSource
}

/// §4.3 cold-start weight selection.
public struct WeightEstimator: Sendable {
    let catalog: Catalog
    let config: EngineConfig

    public init(catalog: Catalog, config: EngineConfig = .default) {
        self.catalog = catalog; self.config = config
    }

    public func increment(for exercise: Exercise, at location: LocationInventory) -> Double {
        exercise.dumbbellBased ? config.dumbbellIncrement : location.plateIncrement
    }

    /// Returns nil for non-loadable exercises (weight never applies).
    public func estimate(
        _ exercise: Exercise, states: [String: ExerciseState], location: LocationInventory
    ) -> WeightEstimate? {
        guard exercise.loadable else { return nil }
        if let s = states[exercise.key], let w = s.workingWeight {
            return WeightEstimate(weight: w, source: s.weightSource)
        }
        let inc = increment(for: exercise, at: location)
        // Ratio table: find any source lift with a known weight.
        for (source, targets) in catalog.ratioTable {
            guard let ratio = targets[exercise.key] ?? targets[exercise.key + "_added_load"],
                  let w = states[source]?.workingWeight else { continue }
            return WeightEstimate(weight: max(floor(exercise, location), Rounding.down(w * ratio, to: inc)), source: .estimated)
        }
        return WeightEstimate(weight: floor(exercise, location), source: .estimated)
    }

    /// The lightest sensible load when nothing is known.
    func floor(_ exercise: Exercise, _ location: LocationInventory) -> Double {
        if exercise.usesBarbell { return config.barWeight }
        if exercise.dumbbellBased { return config.dumbbellIncrement * 2 }
        if exercise.isBodyweightOnly { return 0 }
        return location.plateIncrement * 4
    }
}
