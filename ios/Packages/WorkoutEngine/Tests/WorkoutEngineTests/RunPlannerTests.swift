import XCTest
@testable import WorkoutEngine

final class RunPlannerTests: XCTestCase {
    let rp = RunPlanner()

    func testThreeRunWeekSplitAndPaces() {
        let s = RunPlanState(runsPerWeek: 3, easyPaceSecPerMi: 600, weeklyVolumeMi: 12)
        let week = rp.week(s)
        XCTAssertEqual(week.map(\.runType), [.easy, .tempo, .long])
        XCTAssertEqual(week.map(\.targetDistanceMi), [4.0, 3.0, 5.0])
        XCTAssertEqual(week.map(\.targetPaceSecPerMi), [600, 530, 615])
        XCTAssertEqual(s.targetWeeklyVolumeMi, 18)
    }

    func testTwoRunWeek() {
        let week = rp.week(RunPlanState(runsPerWeek: 2, easyPaceSecPerMi: 600, weeklyVolumeMi: 10))
        XCTAssertEqual(week.map(\.runType), [.easy, .long])
        XCTAssertEqual(week.map(\.targetDistanceMi), [4.5, 5.5])
    }

    func testProgressionDeloadsAndPlateaus() {
        var s = RunPlanState(runsPerWeek: 3, easyPaceSecPerMi: 600, weeklyVolumeMi: 10, targetWeeklyVolumeMi: 13)
        var volumes: [Double] = []
        for _ in 0..<10 { volumes.append(s.weeklyVolumeMi); s = rp.advanceWeek(s) }
        XCTAssertEqual(volumes, [10, 11, 12, 9, 13, 13, 13, 9, 13, 13])
    }

    func testPaceNudge() {
        let s = RunPlanState(runsPerWeek: 3, easyPaceSecPerMi: 600, weeklyVolumeMi: 10)
        XCTAssertEqual(rp.nudgedPace(s, recentEasyPaces: [(575, 600), (578, 600), (570, 600)]).easyPaceSecPerMi, 590)
        XCTAssertEqual(rp.nudgedPace(s, recentEasyPaces: [(575, 600), (590, 600), (570, 600)]).easyPaceSecPerMi, 600)
        XCTAssertEqual(rp.nudgedPace(s, recentEasyPaces: [(575, 600), (578, 600)]).easyPaceSecPerMi, 600)
    }

    func testSegmentsAndPaceFormat() {
        let s = RunPlanState(runsPerWeek: 3, easyPaceSecPerMi: 512, weeklyVolumeMi: 10)
        let segs = rp.segments(for: rp.week(s)[1], state: s)
        XCTAssertEqual(segs.map(\.kind), [.warmup, .main, .cooldown])
        XCTAssertEqual(segs[1].targetPaceSecPerMi, 442)
        XCTAssertEqual(Pace.format(512), "8:32")
    }
}
