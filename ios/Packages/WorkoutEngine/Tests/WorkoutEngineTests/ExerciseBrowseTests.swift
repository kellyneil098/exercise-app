import XCTest
@testable import WorkoutEngine

final class ExerciseBrowseTests: XCTestCase {
    let c = Fixtures.catalog

    func testGroupsFollowPatternDayType() {
        XCTAssertEqual(c.group(ofExercise: "barbell_bench_press"), .day(.push))
        XCTAssertEqual(c.group(ofExercise: "barbell_row"), .day(.pull))
        XCTAssertEqual(c.group(ofExercise: "back_squat"), .day(.legs))
        XCTAssertEqual(c.group(ofExercise: "plank"), .pattern("core"))
        XCTAssertEqual(c.group(ofExercise: "not_a_real_exercise"), .uncategorized)
    }

    func testEverySeedExerciseLandsInADayOrPatternSection() {
        for e in c.exercises.values { XCTAssertNotEqual(c.group(ofExercise: e.key), .uncategorized, e.key) }
    }

    func testSectionOrderAndAlphabeticalEntries() {
        let sections = c.browseSections(keys: Array(c.exercises.keys) + ["mystery_lift"])
        XCTAssertEqual(sections.map(\.title), ["Push", "Pull", "Legs", "Core", "Other"])
        for s in sections {
            let names = s.entries.map(\.name)
            XCTAssertEqual(names, names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, s.title)
        }
        XCTAssertEqual(sections.reduce(0) { $0 + $1.entries.count }, c.exercises.count + 1)
        XCTAssertEqual(sections.last?.entries.map(\.name), ["Mystery Lift"])
        XCTAssertEqual(sections.last?.entries.first?.detail, "Not in catalog")
    }

    func testOnlyRequestedKeysAppearAndDuplicatesCollapse() {
        let sections = c.browseSections(keys: ["deadlift", "barbell_bench_press", "deadlift"])
        XCTAssertEqual(sections.map(\.title), ["Push", "Legs"])
        XCTAssertEqual(sections.flatMap(\.entries).map(\.key), ["barbell_bench_press", "deadlift"])
    }

    func testDetailShowsPatternUnlessItRepeatsTheSectionTitle() {
        XCTAssertEqual(c.browseEntry(forExercise: "barbell_bench_press").detail, "Horizontal Press")
        XCTAssertNil(c.browseEntry(forExercise: "plank").detail)
    }

    func testSearchMatchesNamePatternOrSection() {
        let all = Array(c.exercises.keys)
        let byName = c.browseSections(keys: all, query: "  BENCH ").flatMap(\.entries).map(\.key)
        XCTAssertTrue(byName.contains("barbell_bench_press"))
        XCTAssertTrue(byName.allSatisfy { c.exercises[$0]!.name.localizedCaseInsensitiveContains("bench") })

        let byPattern = c.browseSections(keys: all, query: "hinge").flatMap(\.entries).map(\.key)
        XCTAssertEqual(Set(byPattern), Set(c.exercises(withPattern: "hinge").map(\.key)))

        let core = c.browseSections(keys: all, query: "core")
        XCTAssertEqual(core.map(\.title), ["Core"])
        XCTAssertEqual(core.first?.entries.count, c.exercises(withPattern: "core").count)

        XCTAssertTrue(c.browseSections(keys: all, query: "zzzz").isEmpty)
    }

    func testCustomExercisesAreGroupedByTheirPattern() {
        let custom = Exercise(key: "custom_landmine_press", name: "Landmine Press", movementPattern: "vertical_press",
                              requiredEquipment: ["barbell"], isCustom: true)
        let merged = c.adding(custom: [custom])
        XCTAssertEqual(merged.group(ofExercise: custom.key), .day(.push))
        XCTAssertEqual(merged.browseEntry(forExercise: custom.key).detail, "Custom · Vertical Press")
    }
}
