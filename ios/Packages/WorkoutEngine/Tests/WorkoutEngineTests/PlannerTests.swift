import XCTest
@testable import WorkoutEngine

final class PlannerTests: XCTestCase {
    let planner = Planner(catalog: Fixtures.catalog)

    func input(_ day: DayType, _ minutes: Int, _ loc: LocationInventory, position: Int = 0,
               states: [String: ExerciseState] = Fixtures.baseline, recent: [RecentSession] = []) -> PlannerInput {
        PlannerInput(dayType: day, durationMinutes: minutes, location: loc, heavyRotation: Fixtures.rotation(day, position: position),
                     states: states, recentSessions: recent, now: Date(timeIntervalSince1970: 1_800_000_000))
    }

    // §4.1: every slot fillable at every location, for every rotation position (mirrors validate_seed.py coverage).
    func testEverySlotFillableEverywhere() {
        for day in DayType.allCases {
            let seq = Fixtures.catalog.heavyRotationDefaults[day]!
            for pos in seq.indices {
                for loc in [Fixtures.commercial, Fixtures.building] {
                    let inp = input(day, 90, loc, position: pos, states: [:])
                    for slot in planner.resolvedSlots(dayType: day, heavyRotation: inp.heavyRotation) {
                        let c = planner.candidates(pattern: slot.pattern, slot: slot, input: inp)
                        XCTAssertTrue(c.first?.isAvailable == true, "\(day) pos \(pos) slot \(slot.slot) \(slot.pattern) unfillable at \(loc.locationKey)")
                    }
                }
            }
        }
    }

    func testHeavySlotIsAlwaysFirstAndLoadable() {
        for day in DayType.allCases {
            for loc in [Fixtures.commercial, Fixtures.building] {
                let plan = planner.generate(input(day, 60, loc))
                XCTAssertEqual(plan.blocks.first?.band, .heavy, "\(day) at \(loc.locationKey): \(plan.rendered)")
                XCTAssertEqual(plan.blocks.first?.slot, 1)
                XCTAssertTrue(Fixtures.catalog.exercises[plan.blocks.first!.exerciseKey]!.loadable)
                XCTAssertEqual(plan.blocks.filter { $0.band == .heavy }.count, 1)
            }
        }
    }

    func testPullOmitsRowSlotWhenHeavyIsRow() {
        let seq = Fixtures.catalog.heavyRotationDefaults[.pull]!
        let rowPos = seq.firstIndex(of: "horizontal_row")!
        let slots = planner.resolvedSlots(dayType: .pull, heavyRotation: Fixtures.rotation(.pull, position: rowPos))
        XCTAssertEqual(slots.filter { $0.pattern == "horizontal_row" }.count, 1)
        let other = planner.resolvedSlots(dayType: .pull, heavyRotation: Fixtures.rotation(.pull, position: (rowPos + 1) % seq.count))
        XCTAssertEqual(other.filter { $0.pattern == "horizontal_row" }.count, 1)
        XCTAssertGreaterThan(other.count, slots.count)
    }

    func testLegsFlipsSlot2ToSquatWhenHeavyIsHinge() {
        let seq = Fixtures.catalog.heavyRotationDefaults[.legs]!
        let hingePos = seq.firstIndex(of: "hinge")!
        let slots = planner.resolvedSlots(dayType: .legs, heavyRotation: Fixtures.rotation(.legs, position: hingePos))
        XCTAssertEqual(slots[0].pattern, "hinge")
        XCTAssertEqual(slots[1].pattern, "squat")
        XCTAssertEqual(slots.filter { $0.pattern == "hinge" }.count, 1)
    }

    func testPushOmitsVerticalPressWhenHeavyIsVerticalPress() {
        let seq = Fixtures.catalog.heavyRotationDefaults[.push]!
        let pos = seq.firstIndex(of: "vertical_press")!
        let slots = planner.resolvedSlots(dayType: .push, heavyRotation: Fixtures.rotation(.push, position: pos))
        XCTAssertEqual(slots.filter { $0.pattern == "vertical_press" }.count, 1)
    }

    func testPlansFitBudgetAndGrowWithDuration() {
        for day in DayType.allCases {
            var prev = -1
            for minutes in EngineConfig.default.durationBuckets {
                let plan = planner.generate(input(day, minutes, Fixtures.commercial))
                XCTAssertLessThanOrEqual(plan.estimatedSeconds, Double(minutes * 60), "\(day) \(minutes)")
                let work = plan.blocks.reduce(0) { $0 + $1.sets }
                XCTAssertGreaterThanOrEqual(work, prev, "\(day) \(minutes) shrank")
                prev = work
                XCTAssertFalse(plan.blocks.isEmpty)
            }
        }
    }

    // §4.1 trim loop must `continue`: a 30-min plan keeps core even if a pricier mid slot doesn't fit.
    func testShortPlanKeepsCore() {
        for day in DayType.allCases {
            let plan = planner.generate(input(day, 30, Fixtures.commercial))
            XCTAssertTrue(plan.blocks.contains { $0.pattern == "core" }, "\(day) 30min dropped core: \(plan.rendered)")
        }
    }

    func testCoreIsSupersettedIntoMediumHost() {
        let plan = planner.generate(input(.push, 60, Fixtures.commercial))
        let core = plan.blocks.first { $0.pattern == "core" }!
        let host = plan.host(of: core)!
        XCTAssertEqual(host.band, .medium)
        XCTAssertNotEqual(host.slot, 1)
        XCTAssertGreaterThanOrEqual(host.restSeconds, 90)
        XCTAssertEqual(core.estimatedSeconds, 60)
    }

    func testPaddingNeverTouchesHeavyOrSuperset() {
        let plan = planner.generate(input(.pull, 90, Fixtures.commercial))
        let templates = Fixtures.catalog.slotTemplates[.pull]!
        for b in plan.blocks {
            let t = templates.first { $0.slot == b.slot }!
            if b.band == .heavy || b.isSupersetted { XCTAssertEqual(b.sets, t.sets, b.exerciseName) }
            XCTAssertLessThanOrEqual(b.sets, t.sets + 1, "at most one padding set per block: \(b.exerciseName)")
        }
    }

    func testWeightsAndWarmups() {
        let plan = planner.generate(input(.push, 60, Fixtures.commercial))
        let bench = plan.blocks.first!
        XCTAssertEqual(bench.exerciseKey, "barbell_bench_press")
        XCTAssertEqual(bench.weight, 185)
        XCTAssertEqual(bench.weightSource, .measured)
        XCTAssertEqual(bench.warmups, [WarmupSet(weight: 92.5, reps: 8), WarmupSet(weight: 137.5, reps: 5)])
        // Estimated via ratio table, rounded down to the plate increment, flagged as estimate.
        let incline = plan.blocks.first { $0.exerciseKey == "incline_dumbbell_press" }
        if let incline { XCTAssertEqual(incline.weightSource, .estimated); XCTAssertEqual(incline.weight!.truncatingRemainder(dividingBy: 5), 0) }
    }

    func testLightBarbellGetsBarOnlyWarmup() {
        var states = Fixtures.baseline
        states["barbell_bench_press"]?.workingWeight = 85
        let plan = planner.generate(input(.push, 60, Fixtures.commercial, states: states))
        XCTAssertEqual(plan.blocks.first?.warmups, [WarmupSet(weight: 45, reps: 8)])
    }

    func testDumbbellMaxGate() {
        var states = Fixtures.baseline
        states["dumbbell_bench_press"] = ExerciseState(exerciseKey: "dumbbell_bench_press", workingWeight: 70, weightSource: .measured)
        let slot = planner.resolvedSlots(dayType: .push, heavyRotation: Fixtures.rotation(.push))[0]
        let c = planner.candidates(pattern: "horizontal_press", slot: slot, input: input(.push, 60, Fixtures.building, states: states))
        let db = c.first { $0.exercise.key == "dumbbell_bench_press" }!
        XCTAssertEqual(db.exclusion, .overDumbbellMax(needed: 70, max: 50))
        if case .missingEquipment(let m)? = c.first(where: { $0.exercise.key == "barbell_bench_press" })?.exclusion { XCTAssertTrue(m.contains("barbell")) } else { XCTFail("barbell bench should be excluded at building gym") }
        XCTAssertEqual(c.first { $0.exercise.key == "push_up" }?.exclusion, .notLoadableForHeavySlot)
    }

    func testStableSlotsRepeatAndVolumeSlotsRotate() {
        let first = planner.generate(input(.push, 60, Fixtures.commercial))
        let recent = [RecentSession(dayType: .push, performedAt: Date(), exerciseKeys: first.blocks.map(\.exerciseKey))]
        let second = planner.generate(input(.push, 60, Fixtures.commercial, recent: recent))
        for (a, b) in zip(first.blocks, second.blocks) where a.slot == b.slot {
            switch a.band {
            case .heavy, .medium: XCTAssertEqual(a.exerciseKey, b.exerciseKey, "stable slot \(a.slot) changed")
            case .volume:
                let alternatives = planner.candidates(pattern: a.pattern, slot: Fixtures.catalog.slotTemplates[.push]!.first { $0.slot == a.slot }!, input: input(.push, 60, Fixtures.commercial)).filter(\.isAvailable)
                if alternatives.count > 1 { XCTAssertNotEqual(a.exerciseKey, b.exerciseKey, "volume slot \(a.slot) did not rotate") }
            }
        }
    }

    func testSwapKeepsSlotAndSuperset() {
        let inp = input(.push, 60, Fixtures.commercial)
        let plan = planner.generate(inp)
        let host = plan.blocks.first { plan.supersetPartner(of: $0) != nil }!
        let alt = planner.candidates(pattern: host.pattern, slot: Fixtures.catalog.slotTemplates[.push]!.first { $0.slot == host.slot }!, input: inp)
            .filter(\.isAvailable).first { $0.exercise.key != host.exerciseKey }!
        let swapped = planner.swap(block: host, to: alt.exercise, in: plan, input: inp)
        let nb = swapped.blocks.first { $0.id == host.id }!
        XCTAssertEqual(nb.exerciseKey, alt.exercise.key)
        XCTAssertEqual(nb.slot, host.slot)
        XCTAssertNotNil(swapped.supersetPartner(of: nb))
    }

    // Building gym with heavy baselines: every squat option exceeds the 50 lb dumbbells, so the heavy
    // slot falls back to the best dumbbell-capped candidate rather than vanishing.
    func testHeavySlotFallsBackToCappedDumbbellWhenNothingFits() {
        let plan = planner.generate(input(.legs, 60, Fixtures.building))
        let heavy = plan.blocks.first!
        XCTAssertEqual(heavy.band, .heavy)
        XCTAssertEqual(heavy.weight, 50)
        XCTAssertEqual(heavy.weightSource, .estimated)
        let hinge = plan.blocks.first { $0.pattern == "hinge" }
        XCTAssertEqual(hinge?.weight, 50, "hinge slot should fall back to capped dumbbell RDL, not vanish")
    }

    func testRoundingDown() {
        XCTAssertEqual(Rounding.down(187, to: 5), 185)
        XCTAssertEqual(Rounding.down(0, to: 5), 0)
        XCTAssertEqual(Rounding.down(42.5, to: 5), 40)
    }

    func testAddedBlockTakesNextSlotAndPatternTemplate() {
        let planner = Planner(catalog: Fixtures.catalog)
        let input = PlannerInput(dayType: .push, durationMinutes: 60, location: Fixtures.commercial, heavyRotation: Fixtures.rotation(.push), states: Fixtures.baseline)
        let plan = planner.generate(input)
        let curl = Fixtures.catalog.exercises["dumbbell_curl"]!
        let b = planner.block(adding: curl, to: plan, input: input)
        XCTAssertEqual(b.slot, (plan.blocks.map(\.slot).max() ?? 0) + 1)
        XCTAssertEqual(b.pattern, "elbow_flexion")
        XCTAssertTrue(b.isCustomAdded)
        XCTAssertEqual(b.band, .medium)
        XCTAssertNil(b.supersetHostID)
    }

    func testSwapOfAddedBlockReplacesExercise() {
        let planner = Planner(catalog: Fixtures.catalog)
        let input = PlannerInput(dayType: .legs, durationMinutes: 30, location: Fixtures.building, heavyRotation: Fixtures.rotation(.legs), states: Fixtures.baseline)
        var plan = planner.generate(input)
        let added = planner.block(adding: Fixtures.catalog.exercises["dumbbell_curl"]!, to: plan, input: input)
        plan.blocks.append(added)
        let swapped = planner.swap(block: added, to: Fixtures.catalog.exercises["cable_curl"]!, in: plan, input: input)
        let nb = swapped.blocks.first { $0.id == added.id }!
        XCTAssertEqual(nb.exerciseKey, "cable_curl")
        XCTAssertEqual(nb.slot, added.slot)
        XCTAssertTrue(nb.isCustomAdded)
    }

    func testSwapOfMediumBlockInSlotOneAllowsBodyweight() {
        let planner = Planner(catalog: Fixtures.catalog)
        let input = PlannerInput(dayType: .push, durationMinutes: 60, location: Fixtures.commercial, heavyRotation: Fixtures.rotation(.push), states: Fixtures.baseline)
        var plan = planner.generate(input)
        plan.blocks.removeAll()
        let added = planner.block(adding: Fixtures.catalog.exercises["dumbbell_bench_press"]!, to: plan, input: input)
        plan.blocks.append(added)
        XCTAssertEqual(added.band, .medium)
        let pushUp = Fixtures.catalog.exercises["push_up"]!
        let cands = planner.candidates(pattern: "horizontal_press", replacing: added, in: plan, input: input)
        XCTAssertTrue(cands.first { $0.exercise.key == "push_up" }?.isAvailable ?? false)
        XCTAssertEqual(planner.swap(block: added, to: pushUp, in: plan, input: input).blocks.first?.exerciseKey, "push_up")
    }

    func testHeavySlotRefusesBodyweightSwap() {
        let planner = Planner(catalog: Fixtures.catalog)
        let input = PlannerInput(dayType: .push, durationMinutes: 60, location: Fixtures.commercial, heavyRotation: Fixtures.rotation(.push), states: Fixtures.baseline)
        let plan = planner.generate(input)
        let heavy = plan.blocks.first { $0.band == .heavy }!
        let pushUp = Fixtures.catalog.exercises["push_up"]!
        XCTAssertFalse(planner.candidates(pattern: "horizontal_press", replacing: heavy, in: plan, input: input).first { $0.exercise.key == "push_up" }?.isAvailable ?? true)
        XCTAssertEqual(planner.swap(block: heavy, to: pushUp, in: plan, input: input).blocks.first { $0.id == heavy.id }?.exerciseKey, heavy.exerciseKey)
    }
}
