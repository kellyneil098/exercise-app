import Foundation

public struct PlannerInput: Sendable {
    public var dayType: DayType
    public var durationMinutes: Int
    public var location: LocationInventory
    public var heavyRotation: HeavyRotation
    public var states: [String: ExerciseState]
    /// Newest first.
    public var recentSessions: [RecentSession]
    public var now: Date

    public init(
        dayType: DayType, durationMinutes: Int, location: LocationInventory, heavyRotation: HeavyRotation,
        states: [String: ExerciseState] = [:], recentSessions: [RecentSession] = [], now: Date = Date()
    ) {
        self.dayType = dayType; self.durationMinutes = durationMinutes; self.location = location
        self.heavyRotation = heavyRotation; self.states = states; self.recentSessions = recentSessions; self.now = now
    }
}

/// Why an exercise is *not* offered — surfaced in the swap sheet (§3.1 "make the gate legible").
public enum Exclusion: Sendable, Hashable {
    case missingEquipment([String])
    case overDumbbellMax(needed: Double, max: Double)
    case notLoadableForHeavySlot
}

public struct Candidate: Sendable, Hashable {
    public let exercise: Exercise
    public let estimate: WeightEstimate?
    public let exclusion: Exclusion?
    public var isAvailable: Bool { exclusion == nil }
}

/// §4.1. Given (user state, location, duration, day type) → ordered, time-boxed plan.
public struct Planner: Sendable {
    public let catalog: Catalog
    public let config: EngineConfig
    let estimator: WeightEstimator
    let timer: TimeEstimator

    public init(catalog: Catalog, config: EngineConfig = .default) {
        self.catalog = catalog; self.config = config
        self.estimator = WeightEstimator(catalog: catalog, config: config)
        self.timer = TimeEstimator(config: config)
    }

    // MARK: Slot resolution (§4.1 steps 1-2)

    public func resolvedSlots(dayType: DayType, heavyRotation: HeavyRotation) -> [SlotTemplate] {
        guard var slots = catalog.slotTemplates[dayType], let first = slots.first else { return [] }
        let heavyPattern = heavyRotation.current ?? catalog.heavyRotationDefaults[dayType]?.first ?? first.pattern
        slots[0] = first.with(pattern: heavyPattern)
        var out: [SlotTemplate] = [slots[0]]
        for s in slots.dropFirst() {
            if s.omitIfSlot1Pattern == heavyPattern { continue }
            if let alt = s.altPatternIfSlot1Pattern?[heavyPattern] { out.append(s.with(pattern: alt)); continue }
            out.append(s)
        }
        return out
    }

    // MARK: Candidates (§4.1 step 3)

    /// Every exercise for the pattern, with availability verdicts. Ranked, available first.
    public func candidates(
        pattern: String, slot: SlotTemplate, input: PlannerInput, excluding: Set<String> = []
    ) -> [Candidate] {
        let pool = catalog.exercises(withPattern: pattern).filter { !excluding.contains($0.key) }
        var out: [Candidate] = []
        for ex in pool {
            let est = estimator.estimate(ex, states: input.states, location: input.location)
            var exclusion: Exclusion?
            let missing = ex.requiredEquipment.filter { !input.location.available.contains($0) }
            if !missing.isEmpty {
                exclusion = .missingEquipment(missing)
            } else if ex.dumbbellBased, let max = input.location.dumbbellMaxWeight, let w = est?.weight, w > max {
                exclusion = .overDumbbellMax(needed: w, max: max)
            } else if slot.band == .heavy, !ex.loadable {
                exclusion = .notLoadableForHeavySlot
            }
            out.append(Candidate(exercise: ex, estimate: est, exclusion: exclusion))
        }
        return out.sorted { a, b in
            if a.isAvailable != b.isAvailable { return a.isAvailable }
            let sa = score(a.exercise, slot: slot, input: input), sb = score(b.exercise, slot: slot, input: input)
            if sa != sb { return sa > sb }
            return a.exercise.name < b.exercise.name
        }
    }

    /// §4.1 rank(): one scoring function with a sign flip on the recency term.
    func score(_ ex: Exercise, slot: SlotTemplate, input: PlannerInput) -> Double {
        let rotate = slot.band == .volume
        var s = Double(ex.rankHint)
        if rotate {
            let recent = input.recentSessions.filter { $0.dayType == input.dayType }
                .prefix(config.rotateSlotLookbackSessions)
            if recent.contains(where: { $0.exerciseKeys.contains(ex.key) }) { s -= 1000 }
        } else if lastPerformed(pattern: ex.movementPattern, input: input) == ex.key {
            s += 1000
        }
        return s
    }

    func lastPerformed(pattern: String, input: PlannerInput) -> String? {
        for session in input.recentSessions {
            for key in session.exerciseKeys where catalog.exercises[key]?.movementPattern == pattern { return key }
        }
        return input.states.values
            .filter { catalog.exercises[$0.exerciseKey]?.movementPattern == pattern && $0.lastPerformedAt != nil }
            .max { ($0.lastPerformedAt ?? .distantPast) < ($1.lastPerformedAt ?? .distantPast) }?.exerciseKey
    }

    // MARK: Generate (§4.1 steps 4-7)

    public func generate(_ input: PlannerInput) -> Plan {
        let slots = resolvedSlots(dayType: input.dayType, heavyRotation: input.heavyRotation)
        let budget = Double(input.durationMinutes) * 60

        struct Chosen { let slot: SlotTemplate; let exercise: Exercise; let estimate: WeightEstimate? }
        var chosen: [Chosen] = []
        for slot in slots {
            let c = candidates(pattern: slot.pattern, slot: slot, input: input)
            if let best = c.first, best.isAvailable {
                chosen.append(Chosen(slot: slot, exercise: best.exercise, estimate: best.estimate))
            } else if slot.band == .heavy,
                      let capped = c.first(where: { if case .overDumbbellMax = $0.exclusion { return true } else { return false } }),
                      let max = input.location.dumbbellMaxWeight {
                // The heavy slot never silently disappears: use the heaviest dumbbell available.
                chosen.append(Chosen(slot: slot, exercise: capped.exercise, estimate: WeightEstimate(weight: max, source: .estimated)))
            }
        }

        var blocks: [PlanBlock] = []
        var spent: Double = 0
        for c in chosen {
            let sets = prescribedSets(for: c.exercise, slot: c.slot, states: input.states)
            let cost = timer.blockSeconds(exercise: c.exercise, slot: c.slot, sets: sets, supersetted: c.slot.isSuperset)
            guard spent + cost <= budget else { continue }   // continue, not break (§4.1)
            spent += cost
            blocks.append(makeBlock(c.exercise, slot: c.slot, sets: sets, estimate: c.estimate, cost: cost, location: input.location))
        }

        // Step 5: resolve superset hosts.
        for i in blocks.indices where slotTemplate(blocks[i], slots).isSuperset {
            if let host = blocks.last(where: { $0.slot != 1 && $0.band == .medium && $0.restSeconds >= config.minSupersetHostRest && !slotTemplate($0, slots).isSuperset }) {
                blocks[i].supersetHostID = host.id
            } else {
                let slot = slotTemplate(blocks[i], slots)
                let standalone = timer.blockSeconds(exercise: catalog.exercises[blocks[i].exerciseKey]!, slot: slot, sets: blocks[i].sets, supersetted: false)
                if spent - blocks[i].estimatedSeconds + standalone <= budget {
                    spent += standalone - blocks[i].estimatedSeconds
                    blocks[i].estimatedSeconds = standalone
                } else {
                    spent -= blocks[i].estimatedSeconds
                    blocks[i].estimatedSeconds = -1   // mark for removal
                }
            }
        }
        blocks.removeAll { $0.estimatedSeconds < 0 }

        // Step 6: pad slack. Never slot 1, never supersets; slots 2-4 first.
        var padded = Set<UUID>()
        while budget - spent >= config.paddingSlackThreshold {
            let order = blocks.filter { $0.band != .heavy && !$0.isSupersetted && !padded.contains($0.id) }
                .sorted { ($0.band == .medium ? 0 : 1, $0.slot) < ($1.band == .medium ? 0 : 1, $1.slot) }
            guard let target = order.first, let idx = blocks.firstIndex(where: { $0.id == target.id }) else { break }
            let extra = timer.extraSetSeconds(exercise: catalog.exercises[target.exerciseKey]!, slot: slotTemplate(target, slots))
            padded.insert(target.id)
            guard spent + extra <= budget else { continue }
            blocks[idx].sets += 1
            blocks[idx].estimatedSeconds += extra
            spent += extra
        }

        return Plan(dayType: input.dayType, durationMinutes: input.durationMinutes, locationKey: input.location.locationKey, blocks: blocks)
    }

    // MARK: Helpers

    func prescribedSets(for exercise: Exercise, slot: SlotTemplate, states: [String: ExerciseState]) -> Int {
        guard !exercise.loadable, let n = states[exercise.key]?.setCount else { return slot.sets }
        return min(max(n, slot.sets), config.nonLoadableMaxSets)
    }

    func slotTemplate(_ block: PlanBlock, _ slots: [SlotTemplate]) -> SlotTemplate {
        slots.first { $0.slot == block.slot } ?? slots[0]
    }

    public func makeBlock(
        _ exercise: Exercise, slot: SlotTemplate, sets: Int, estimate: WeightEstimate?, cost: Double, location: LocationInventory
    ) -> PlanBlock {
        let (low, high) = exercise.measure == .seconds
            ? (exercise.rangeLow ?? slot.repLow, exercise.rangeHigh ?? slot.repHigh)
            : (slot.repLow, slot.repHigh)
        return PlanBlock(
            id: UUID(), slot: slot.slot, pattern: slot.pattern, exerciseKey: exercise.key, exerciseName: exercise.name,
            band: slot.band, sets: sets, prescribedSets: sets, repLow: low, repHigh: high, measure: exercise.measure,
            restSeconds: slot.restSeconds, weight: estimate?.weight, weightSource: estimate?.source,
            warmups: warmups(exercise, slot: slot, weight: estimate?.weight, location: location),
            supersetHostID: nil, estimatedSeconds: cost
        )
    }

    /// §4.2 warm-up table: 50% × 8, 75% × 5; floor at the empty bar; bar-only if weight ≤ 2× bar.
    func warmups(_ exercise: Exercise, slot: SlotTemplate, weight: Double?, location: LocationInventory) -> [WarmupSet] {
        guard slot.warmupSets > 0, exercise.loadable, let w = weight, w > 0 else { return [] }
        let inc = estimator.increment(for: exercise, at: location)
        if exercise.usesBarbell && w <= config.barWeight * 2 {
            return [WarmupSet(weight: config.barWeight, reps: config.warmupReps[0])]
        }
        return (0..<min(slot.warmupSets, config.warmupFractions.count)).map { i in
            var load = Rounding.down(w * config.warmupFractions[i], to: inc)
            if exercise.usesBarbell { load = max(load, config.barWeight) }
            return WarmupSet(weight: load, reps: config.warmupReps[i])
        }
    }

    /// Rebuild a block in place with a substitute exercise (§7 swap). Keeps slot, sets, superset linkage.
    public func swap(block: PlanBlock, to exercise: Exercise, in plan: Plan, input: PlannerInput) -> Plan {
        guard let idx = plan.blocks.firstIndex(where: { $0.id == block.id }),
              let slot = resolvedSlots(dayType: plan.dayType, heavyRotation: input.heavyRotation).first(where: { $0.slot == block.slot })
                ?? catalog.slotTemplates[plan.dayType]?.first(where: { $0.slot == block.slot })
        else { return plan }
        let est = estimator.estimate(exercise, states: input.states, location: input.location)
        let cost = timer.blockSeconds(exercise: exercise, slot: slot, sets: block.sets, supersetted: block.isSupersetted)
        var nb = makeBlock(exercise, slot: slot.with(pattern: block.pattern), sets: block.sets, estimate: est, cost: cost, location: input.location)
        nb.id = block.id
        nb.supersetHostID = block.supersetHostID
        nb.prescribedSets = block.prescribedSets
        var p = plan
        p.blocks[idx] = nb
        return p
    }
}

extension SlotTemplate {
    func with(pattern: String) -> SlotTemplate {
        SlotTemplate(
            slot: slot, pattern: pattern, sets: sets, repLow: repLow, repHigh: repHigh, restSeconds: restSeconds,
            band: band, warmupSets: warmupSets, superset: superset, omitIfSlot1Pattern: omitIfSlot1Pattern,
            altPatternIfSlot1Pattern: altPatternIfSlot1Pattern
        )
    }
}
