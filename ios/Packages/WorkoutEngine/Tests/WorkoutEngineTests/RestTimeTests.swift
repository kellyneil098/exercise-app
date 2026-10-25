import XCTest
@testable import WorkoutEngine

/// Plan-editor rest stepper: 10 s per tap, clamped, and it changes the rest the deck actually runs.
final class RestTimeTests: XCTestCase {
    let planner = Planner(catalog: Fixtures.catalog)
    let config = EngineConfig.default

    func plan(_ day: DayType = .push) -> Plan {
        planner.generate(PlannerInput(dayType: day, durationMinutes: 60, location: Fixtures.commercial,
                                      heavyRotation: Fixtures.rotation(day), states: Fixtures.baseline,
                                      now: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    func standalone(_ p: Plan) -> PlanBlock { p.blocks.first { !$0.isSupersetted && p.supersetPartner(of: $0) == nil }! }

    func testEachTapMovesExactlyTenSeconds() {
        var p = plan()
        let b = standalone(p)
        let start = p.restSeconds(for: b)
        XCTAssertEqual(config.restStepSeconds, 10)
        p.stepRest(of: b, by: 1)
        XCTAssertEqual(p.restSeconds(for: b), start + 10)
        p.stepRest(of: b, by: 1)
        XCTAssertEqual(p.restSeconds(for: b), start + 20)
        p.stepRest(of: b, by: -1)
        p.stepRest(of: b, by: -1)
        p.stepRest(of: b, by: -1)
        XCTAssertEqual(p.restSeconds(for: b), start - 10)
    }

    func testBoundsClampAtTenSecondsAndTenMinutes() {
        var p = plan()
        let b = standalone(p)
        for _ in 0..<200 { p.stepRest(of: b, by: -1) }
        XCTAssertEqual(p.restSeconds(for: b), 10)
        p.stepRest(of: b, by: -1)
        XCTAssertEqual(p.restSeconds(for: b), 10, "never zero or negative")
        for _ in 0..<200 { p.stepRest(of: b, by: 1) }
        XCTAssertEqual(p.restSeconds(for: b), 600)
        p.setRest(of: b, to: 10_000)
        XCTAssertEqual(p.restSeconds(for: b), 600)
        p.setRest(of: b, to: -30)
        XCTAssertEqual(p.restSeconds(for: b), 10)
        // An off-grid seed value (75 s) still steps by 10 and only the last tap is clamped.
        p.setRest(of: b, to: 75)
        p.stepRest(of: b, by: -1)
        XCTAssertEqual(p.restSeconds(for: b), 65)
        p.setRest(of: b, to: 15)
        p.stepRest(of: b, by: -1)
        XCTAssertEqual(p.restSeconds(for: b), 10)
    }

    func testOnlyRestAndEstimateChange() {
        let before = plan()
        var p = before
        let b = standalone(p)
        p.stepRest(of: b, by: 1)
        let i = p.blocks.firstIndex { $0.id == b.id }!
        XCTAssertEqual(p.blocks[i].restSeconds, b.restSeconds + 10)
        XCTAssertEqual(p.blocks[i].estimatedSeconds, b.estimatedSeconds + Double((b.sets - 1) * 10), accuracy: 0.001)
        var reverted = p.blocks[i]
        reverted.restSeconds = b.restSeconds
        reverted.estimatedSeconds = b.estimatedSeconds
        XCTAssertEqual(reverted, b, "weight, sets, reps, warm-ups untouched")
        for (old, new) in zip(before.blocks, p.blocks) where old.id != b.id { XCTAssertEqual(old, new) }
        XCTAssertEqual(p.dayType, before.dayType)
        XCTAssertEqual(p.durationMinutes, before.durationMinutes)
    }

    func testSupersetPartnerEditsTheHostRestItRunsOn() {
        var p = plan()
        let core = p.blocks.first { $0.pattern == "core" && $0.isSupersetted }!
        let host = p.host(of: core)!
        XCTAssertEqual(p.restSeconds(for: core), host.restSeconds)
        p.stepRest(of: core, by: 1)
        XCTAssertEqual(p.host(of: core)!.restSeconds, host.restSeconds + 10)
        XCTAssertEqual(p.restSeconds(for: core), host.restSeconds + 10)
        XCTAssertEqual(p.blocks.first { $0.id == core.id }, core, "partner block itself unchanged")
    }

    func testEditedRestSurvivesPlanEncoding() throws {
        var p = plan()
        let b = standalone(p)
        p.setRest(of: b, to: 130)
        let back = try JSONDecoder().decode(Plan.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back.restSeconds(for: b), 130)
        XCTAssertEqual(back, p)
    }

    func testUnknownBlockIsANoOp() {
        var p = plan()
        let before = p
        var stray = standalone(p)
        stray.id = UUID()
        p.stepRest(of: stray, by: 1)
        XCTAssertEqual(p, before)
    }
}
