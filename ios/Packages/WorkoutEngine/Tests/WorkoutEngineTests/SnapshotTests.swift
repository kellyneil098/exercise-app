import XCTest
@testable import WorkoutEngine

/// Readable plan snapshots: run with `UPDATE_SNAPSHOTS=1 swift test` to regenerate.
final class SnapshotTests: XCTestCase {
    func testPlanSnapshots() throws {
        let planner = Planner(catalog: Fixtures.catalog)
        var out: [String] = []
        for day in DayType.allCases {
            for loc in [Fixtures.commercial, Fixtures.building] {
                for minutes in [30, 45, 60, 90] {
                    let inp = PlannerInput(dayType: day, durationMinutes: minutes, location: loc, heavyRotation: Fixtures.rotation(day),
                                           states: Fixtures.baseline, now: Date(timeIntervalSince1970: 1_800_000_000))
                    out.append(planner.generate(inp).rendered)
                }
            }
        }
        let text = out.joined(separator: "\n\n") + "\n"
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Snapshots/plans.txt")
        if ProcessInfo.processInfo.environment["UPDATE_SNAPSHOTS"] != nil || !FileManager.default.fileExists(atPath: url.path) {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        XCTAssertEqual(text, try String(contentsOf: url, encoding: .utf8), "plans changed; rerun with UPDATE_SNAPSHOTS=1 if intended")
    }
}
