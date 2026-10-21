import XCTest
@testable import WorkoutEngine

final class CatalogTests: XCTestCase {
    let c = Fixtures.catalog

    func testSeedLoads() {
        XCTAssertGreaterThan(c.exercises.count, 40)
        XCTAssertEqual(c.slotTemplates.count, 4)
        XCTAssertEqual(c.seededLocations.map(\.key).sorted(), ["building_gym", "crunch_union_square"])
        XCTAssertEqual(c.progressionSteps.heavyLower, 10)
    }

    func testEveryExercisePatternAndEquipmentIsKnown() {
        let eq = Set(c.equipmentTypes.map(\.key))
        for e in c.exercises.values {
            XCTAssertNotNil(c.patterns[e.movementPattern], e.key)
            for r in e.requiredEquipment { XCTAssertTrue(eq.contains(r), "\(e.key) requires unknown \(r)") }
            if e.measure == .seconds { XCTAssertNotNil(e.rangeLow, e.key); XCTAssertNotNil(e.rangeHigh, e.key) }
        }
    }

    func testTemplatesReferenceKnownPatterns() {
        for (day, slots) in c.slotTemplates {
            XCTAssertEqual(slots.first?.pattern, "heavy_rotation", "\(day)")
            XCTAssertEqual(slots.first?.band, .heavy)
            XCTAssertEqual(slots.filter { $0.band == .heavy }.count, 1, "\(day): exactly one heavy slot")
            for s in slots.dropFirst() {
                XCTAssertNotNil(c.patterns[s.pattern], "\(day) slot \(s.slot) \(s.pattern)")
                for alt in s.altPatternIfSlot1Pattern?.values ?? [:].values { XCTAssertNotNil(c.patterns[alt]) }
            }
            XCTAssertTrue(slots.contains { $0.pattern == "core" && $0.isSuperset }, "\(day): core supersetted")
        }
    }

    func testCommentsStripped() throws {
        let data = #"{"a": 1, "$comment": "x", "b": {"$c": 2, "d": [ {"$e": 1, "f": 2} ]}}"#.data(using: .utf8)!
        let out = try JSONSerialization.jsonObject(with: try SeedLoader.stripComments(data)) as! [String: Any]
        XCTAssertNil(out["$comment"])
        let b = out["b"] as! [String: Any]
        XCTAssertNil(b["$c"])
        XCTAssertEqual(((b["d"] as! [[String: Any]])[0])["f"] as? Int, 2)
    }
}
