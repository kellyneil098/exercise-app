import XCTest
@testable import WorkoutEngine

final class ProgressionTests: XCTestCase {
    let p = Progression(catalog: Fixtures.catalog)
    let loc = Fixtures.commercial
    var bench: Exercise { Fixtures.catalog.exercises["barbell_bench_press"]! }
    var squat: Exercise { Fixtures.catalog.exercises["back_squat"]! }
    var lateral: Exercise { Fixtures.catalog.exercises["dumbbell_lateral_raise"]! }
    var plank: Exercise { Fixtures.catalog.exercises["plank"]! }

    func result(_ reps: [Int], low: Int = 8, high: Int = 12, band: Band = .medium, rating: EffortRating = .good,
                completed: [Bool]? = nil, padding: Int = 0, weight: Double? = nil, prescribed: Int? = nil) -> ExerciseResult {
        var sets = reps.enumerated().map { SetResult(value: $0.element, weight: weight, completed: completed?[$0.offset] ?? true) }
        for _ in 0..<padding { sets.append(SetResult(value: high, weight: weight, isPadding: true)) }
        return ExerciseResult(exerciseKey: "x", band: band, repLow: low, repHigh: high, prescribedSets: prescribed ?? reps.count,
                              sets: sets, rating: rating)
    }

    func testLoggedWeightOverridesStoredWeight() {
        let o = p.apply(result([12, 12, 12, 12], weight: 120), to: state(100), exercise: bench, location: loc)
        XCTAssertEqual(o.state.workingWeight, 125) // progressed from the 120 actually lifted, not the stored 100
    }

    func testHardRatingHoldsEvenAtTopOfRange() {
        let o = p.apply(result([12, 12, 12, 12], rating: .hard), to: state(100), exercise: bench, location: loc)
        XCTAssertEqual(o.change, .hold)
        XCTAssertEqual(o.state.workingWeight, 100)
        XCTAssertEqual(o.state.consecutiveFailures, 0)
    }

    func testIncompleteSessionHolds() {
        let o = p.apply(result([12], prescribed: 4), to: state(100), exercise: bench, location: loc)
        XCTAssertEqual(o.change, .hold); XCTAssertEqual(o.state.workingWeight, 100); XCTAssertEqual(o.state.consecutiveFailures, 0)
    }

    func state(_ w: Double, source: WeightSource = .measured, failures: Int = 0, pre: Double? = nil) -> ExerciseState {
        ExerciseState(exerciseKey: "x", workingWeight: w, weightSource: source, consecutiveFailures: failures, preRebaselineWeight: pre)
    }

    func testAllTopIncreases() {
        let o = p.apply(result([12, 12, 12, 12]), to: state(100), exercise: bench, location: loc)
        XCTAssertEqual(o.change, .increase(by: 5)); XCTAssertEqual(o.state.workingWeight, 105)
    }

    func testPartialHolds() {
        let o = p.apply(result([12, 12, 11, 10]), to: state(100, failures: 1), exercise: bench, location: loc)
        XCTAssertEqual(o.change, .hold); XCTAssertEqual(o.state.consecutiveFailures, 0)
    }

    func testTwoBelowBottomDeloads() {
        let one = p.apply(result([12, 10, 8, 7]), to: state(100), exercise: bench, location: loc)
        XCTAssertEqual(one.change, .hold); XCTAssertEqual(one.state.consecutiveFailures, 1)
        let two = p.apply(result([12, 10, 8, 7]), to: one.state, exercise: bench, location: loc)
        XCTAssertEqual(two.change, .deload(to: 90)); XCTAssertEqual(two.state.consecutiveFailures, 0)
    }

    func testDeloadRoundsDownToIncrement() {
        let o = p.apply(result([5, 5, 5, 5], low: 8, high: 12), to: state(185, failures: 1), exercise: bench, location: Fixtures.building)
        XCTAssertEqual(o.state.workingWeight, 165) // 166.5 → 165 at 5 lb plates
    }

    func testPaddingSetsIgnored() {
        let o = p.apply(result([12, 12, 12], padding: 1), to: state(100), exercise: bench, location: loc)
        XCTAssertEqual(o.change, .increase(by: 5))
        let r = result([12, 12, 12], padding: 1)
        XCTAssertEqual(r.workingSets.count, 3)
    }

    func testHeavyStepsByUpperLower() {
        XCTAssertEqual(p.step(for: bench, band: .heavy, location: loc), 5)
        XCTAssertEqual(p.step(for: squat, band: .heavy, location: loc), 10)
        XCTAssertEqual(p.step(for: lateral, band: .volume, location: loc), 5)   // dumbbells jump 5
        XCTAssertEqual(p.step(for: Fixtures.catalog.exercises["cable_lateral_raise"]!, band: .volume, location: loc), 2.5)
        XCTAssertEqual(p.step(for: Fixtures.catalog.exercises["cable_lateral_raise"]!, band: .volume, location: Fixtures.building), 5)
    }

    func testEasyDoublesStepAndResolvesEstimate() {
        let o = p.apply(result([12, 12, 12, 12], rating: .easy), to: state(100, source: .estimated), exercise: bench, location: loc)
        XCTAssertEqual(o.change, .increase(by: 10)); XCTAssertEqual(o.state.weightSource, .measured)
        let partial = p.apply(result([12, 11, 10, 9], rating: .easy), to: state(100), exercise: bench, location: loc)
        XCTAssertEqual(partial.change, .increase(by: 5))
    }

    func testDNFFirstSetOnEstimateReverts() {
        let o = p.apply(result([3, 0, 0, 0], rating: .didNotFinish, completed: [false, false, false, false]),
                        to: state(110, source: .rebaselined, pre: 100), exercise: bench, location: loc)
        XCTAssertEqual(o.change, .revert(to: 100)); XCTAssertEqual(o.state.weightSource, .measured); XCTAssertEqual(o.state.consecutiveFailures, 0)
        let cold = p.apply(result([3, 0, 0, 0], rating: .didNotFinish, completed: [false, false, false, false]),
                           to: state(100, source: .estimated), exercise: bench, location: loc)
        XCTAssertEqual(cold.change, .revert(to: 90))
    }

    func testDNFFirstSetOnMeasuredCountsAsFailure() {
        let o = p.apply(result([3, 0, 0, 0], rating: .didNotFinish, completed: [false, false, false, false]),
                        to: state(100, failures: 1), exercise: bench, location: loc)
        XCTAssertEqual(o.change, .deload(to: 90))
    }

    func testDNFLaterSetHolds() {
        let o = p.apply(result([12, 12, 4, 0], rating: .didNotFinish, completed: [true, true, false, false]),
                        to: state(110, source: .rebaselined, failures: 1, pre: 100), exercise: bench, location: loc)
        XCTAssertEqual(o.change, .hold); XCTAssertEqual(o.state.workingWeight, 110); XCTAssertEqual(o.state.consecutiveFailures, 1)
    }

    func testNonLoadableAddsSetsThenMaintains() {
        var s = ExerciseState(exerciseKey: "plank")
        let o1 = p.apply(result([45, 45, 45], low: 20, high: 45), to: s, exercise: plank, location: loc)
        XCTAssertEqual(o1.change, .addSet(to: 4)); s = o1.state
        let o2 = p.apply(result([45, 45, 45, 45], low: 20, high: 45), to: s, exercise: plank, location: loc)
        XCTAssertEqual(o2.change, .maintain); XCTAssertEqual(o2.state.setCount, 4)
        let hold = p.apply(result([45, 40, 30], low: 20, high: 45), to: ExerciseState(exerciseKey: "plank"), exercise: plank, location: loc)
        XCTAssertEqual(hold.change, .hold)
    }
}
