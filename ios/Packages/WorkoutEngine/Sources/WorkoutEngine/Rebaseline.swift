import Foundation

/// A measured working set in history, the input the rebaseliner needs (§4.4).
public struct WorkingSetRecord: Codable, Sendable, Hashable {
    public var exerciseKey: String
    public var performedAt: Date
    public var weight: Double
    public var weightSource: WeightSource

    public init(exerciseKey: String, performedAt: Date, weight: Double, weightSource: WeightSource = .measured) {
        self.exerciseKey = exerciseKey; self.performedAt = performedAt; self.weight = weight; self.weightSource = weightSource
    }
}

public struct RebaselineChange: Sendable, Hashable {
    public let exerciseKey: String
    public let from: Double
    public let to: Double
    public let growth: Double
}

/// §4.4: transfer relative growth within a strength cluster to stale exercises. Monotonic upward.
public struct Rebaseliner: Sendable {
    let catalog: Catalog
    let config: EngineConfig

    public init(catalog: Catalog, config: EngineConfig = .default) {
        self.catalog = catalog; self.config = config
    }

    public func run(states: [String: ExerciseState], history: [WorkingSetRecord], location: LocationInventory,
                    now: Date = Date()) -> (states: [String: ExerciseState], changes: [RebaselineChange]) {
        var out = states
        var changes: [RebaselineChange] = []
        let day: TimeInterval = 86_400

        for (key, e) in states {
            guard let ex = catalog.exercises[key], ex.loadable, let w = e.workingWeight, w > 0,
                  let last = e.lastPerformedAt, now.timeIntervalSince(last) > Double(config.rebaselineStaleDays) * day,
                  e.lastRebaselinedAt.map({ now.timeIntervalSince($0) > Double(config.rebaselineMinIntervalDays) * day }) ?? true,
                  let cluster = catalog.cluster(of: ex)
            else { continue }

            var ratios: [Double] = []
            for (aKey, a) in states where aKey != key {
                guard let aEx = catalog.exercises[aKey], catalog.cluster(of: aEx) == cluster,
                      a.weightSource == .measured, let aw = a.workingWeight,
                      let aLast = a.lastPerformedAt, aLast > last else { continue }
                let then = history.filter { $0.exerciseKey == aKey && $0.weightSource == .measured && $0.performedAt <= last }
                    .map(\.weight).max()
                guard let then, then > 0 else { continue }
                ratios.append(aw / then - 1)
            }
            guard !ratios.isEmpty else { continue }
            let growth = median(ratios)
            guard growth > 0 else { continue }
            let adjusted = min(growth * config.rebaselineDamping, config.rebaselineCap)
            let inc = ex.dumbbellBased ? config.dumbbellIncrement : location.plateIncrement
            let newWeight = Rounding.down(w * (1 + adjusted), to: inc)
            guard newWeight > w else { continue }
            var ns = e
            ns.preRebaselineWeight = w
            ns.workingWeight = newWeight
            ns.weightSource = .rebaselined
            ns.lastRebaselinedAt = now
            out[key] = ns
            changes.append(RebaselineChange(exerciseKey: key, from: w, to: newWeight, growth: growth))
        }
        return (out, changes.sorted { $0.exerciseKey < $1.exerciseKey })
    }

    func median(_ xs: [Double]) -> Double {
        let s = xs.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}
