import XCTest
@testable import WorkoutEngine

final class RebaselineTests: XCTestCase {
    let r = Rebaseliner(catalog: Fixtures.catalog)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func days(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }

    func testTransfersDampedCappedGrowth() {
        // Machine chest press last done 60 days ago at 150. Bench went 185 → 205 since (+10.8%).
        let states: [String: ExerciseState] = [
            "machine_chest_press": ExerciseState(exerciseKey: "machine_chest_press", workingWeight: 150, weightSource: .measured, lastPerformedAt: days(60)),
            "barbell_bench_press": ExerciseState(exerciseKey: "barbell_bench_press", workingWeight: 205, weightSource: .measured, lastPerformedAt: days(2)),
        ]
        let history = [WorkingSetRecord(exerciseKey: "barbell_bench_press", performedAt: days(61), weight: 185),
                       WorkingSetRecord(exerciseKey: "barbell_bench_press", performedAt: days(2), weight: 205)]
        let out = r.run(states: states, history: history, location: Fixtures.commercial, now: now)
        XCTAssertEqual(out.changes.count, 1)
        let c = out.changes[0]
        XCTAssertEqual(c.exerciseKey, "machine_chest_press")
        XCTAssertEqual(c.to, 157.5)   // 150 × (1 + 0.108/2) = 158.1 → 157.5
        let s = out.states["machine_chest_press"]!
        XCTAssertEqual(s.weightSource, .rebaselined); XCTAssertEqual(s.preRebaselineWeight, 150); XCTAssertEqual(s.lastRebaselinedAt, now)
    }

    func testNeverDowngradesAndIgnoresNonMeasuredAnchors() {
        let states: [String: ExerciseState] = [
            "machine_chest_press": ExerciseState(exerciseKey: "machine_chest_press", workingWeight: 150, weightSource: .measured, lastPerformedAt: days(60)),
            "barbell_bench_press": ExerciseState(exerciseKey: "barbell_bench_press", workingWeight: 175, weightSource: .measured, lastPerformedAt: days(2)),
            "dumbbell_bench_press": ExerciseState(exerciseKey: "dumbbell_bench_press", workingWeight: 90, weightSource: .rebaselined, lastPerformedAt: days(1)),
        ]
        let history = [WorkingSetRecord(exerciseKey: "barbell_bench_press", performedAt: days(61), weight: 185),
                       WorkingSetRecord(exerciseKey: "dumbbell_bench_press", performedAt: days(61), weight: 60)]
        let out = r.run(states: states, history: history, location: Fixtures.commercial, now: now)
        XCTAssertTrue(out.changes.isEmpty)
        XCTAssertEqual(out.states["machine_chest_press"]?.workingWeight, 150)
    }

    func testRespectsStalenessAndIntervalAndCluster() {
        var fresh = ExerciseState(exerciseKey: "machine_chest_press", workingWeight: 150, weightSource: .measured, lastPerformedAt: days(10))
        let bench = ExerciseState(exerciseKey: "barbell_bench_press", workingWeight: 230, weightSource: .measured, lastPerformedAt: days(2))
        let ohp = ExerciseState(exerciseKey: "overhead_press", workingWeight: 100, weightSource: .measured, lastPerformedAt: days(60))
        let history = [WorkingSetRecord(exerciseKey: "barbell_bench_press", performedAt: days(61), weight: 185)]
        XCTAssertTrue(r.run(states: ["machine_chest_press": fresh, "barbell_bench_press": bench], history: history, location: Fixtures.commercial, now: now).changes.isEmpty)
        fresh.lastPerformedAt = days(60); fresh.lastRebaselinedAt = days(5)
        XCTAssertTrue(r.run(states: ["machine_chest_press": fresh, "barbell_bench_press": bench], history: history, location: Fixtures.commercial, now: now).changes.isEmpty)
        // Bench does not inform overhead press (different cluster).
        XCTAssertTrue(r.run(states: ["overhead_press": ohp, "barbell_bench_press": bench], history: history, location: Fixtures.commercial, now: now).changes.isEmpty)
        // Cap at +10% even with +24% growth.
        fresh.lastRebaselinedAt = nil
        let out = r.run(states: ["machine_chest_press": fresh, "barbell_bench_press": bench], history: history, location: Fixtures.commercial, now: now)
        XCTAssertEqual(out.changes.first?.to, 165)
    }
}
