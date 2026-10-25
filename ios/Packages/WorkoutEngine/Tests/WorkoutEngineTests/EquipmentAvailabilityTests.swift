import XCTest
@testable import WorkoutEngine

final class EquipmentAvailabilityTests: XCTestCase {
    let c = Fixtures.catalog

    /// What each seeded gym stores before the user touches it.
    var seededStores: [String: Set<String>] {
        Dictionary(uniqueKeysWithValues: c.seededLocations.map { ($0.key, Set(c.defaultEquipment(for: $0))) })
    }

    func testEverySeedEquipmentTypeHasACategoryAndCategoriesKeepSeedOrder() {
        XCTAssertEqual(c.equipmentTypes.count, 27)
        for e in c.equipmentTypes { XCTAssertFalse(e.category.trimmingCharacters(in: .whitespaces).isEmpty, e.key) }
        XCTAssertEqual(c.equipmentCategories, ["Bodyweight", "Free weights", "Racks & benches", "Cables", "Machines", "Cardio"])
        XCTAssertEqual(Set(c.equipmentCategories), Set(c.equipmentTypes.map(\.category)))
    }

    func testEveryGymSeesTheSameMasterKeys() {
        let stores = seededStores
        XCTAssertNotEqual(stores["building_gym"], stores["crunch_union_square"], "the gyms differ in what they have ...")
        var unions: Set<Set<String>> = []
        for (_, available) in stores {
            let p = c.equipmentPartition(available: available)
            unions.insert(Set(p.selectedKeys + p.unselectedKeys))
        }
        XCTAssertEqual(unions, [c.equipmentKeys], "... but not in what they can choose from")
        XCTAssertEqual(c.equipmentPartition(available: ["not_in_catalog"]).totalCount, c.equipmentTypes.count, "unknown stored keys never widen the list")
    }

    func testPartitionIsCompleteAndDisjoint() {
        let cases: [Set<String>] = [[], seededStores["building_gym"]!, c.equipmentKeys, ["barbell", "ghost_machine"], ["bodyweight"]]
        for available in cases {
            let p = c.equipmentPartition(available: available)
            let selected = Set(p.selectedKeys), unselected = Set(p.unselectedKeys)
            XCTAssertEqual(selected.union(unselected), c.equipmentKeys, "\(available)")
            XCTAssertTrue(selected.isDisjoint(with: unselected), "\(available)")
            XCTAssertEqual(p.selectedKeys.count, selected.count, "no duplicates: \(available)")
            XCTAssertEqual(selected, available.intersection(c.equipmentKeys).union(["bodyweight"]), "\(available)")
            XCTAssertEqual(p.totalCount, c.equipmentTypes.count)
        }
    }

    func testBodyweightIsAlwaysSelected() {
        let p = c.equipmentPartition(available: [])
        XCTAssertEqual(p.selectedKeys, ["bodyweight"])
        XCTAssertEqual(p.selected.map(\.category), ["Bodyweight"])
        XCTAssertFalse(p.unselectedKeys.contains("bodyweight"))
    }

    func testEmptyStates() {
        XCTAssertTrue(c.equipmentPartition(available: c.equipmentKeys).unselected.isEmpty, "everything selected → nothing to add")
        XCTAssertEqual(c.equipmentPartition(available: []).selectedCount, 1, "nothing selected → only bodyweight")
    }

    func testSectionsFollowSeedCategoryOrderWithLabelsAToZ() {
        let p = c.equipmentPartition(available: c.equipmentKeys)
        let order = c.equipmentCategories
        XCTAssertEqual(p.selected.map(\.category), order)
        for s in p.selected {
            let labels = s.items.map(\.label)
            XCTAssertEqual(labels, labels.sorted { $0.localizedStandardCompare($1) == .orderedAscending }, s.category)
            XCTAssertTrue(s.items.allSatisfy { $0.category == s.category })
        }
        // A sparse selection keeps the same relative order and drops empty categories.
        let sparse = c.equipmentPartition(available: ["treadmill", "barbell", "leg_press"])
        XCTAssertEqual(sparse.selected.map(\.category), ["Bodyweight", "Free weights", "Machines", "Cardio"])
        XCTAssertEqual(sparse.selectedKeys, ["bodyweight", "barbell", "leg_press", "treadmill"])
    }

    func testNewCatalogItemAppearsUnselectedForEveryGym() {
        let grown = Catalog(
            exercises: Array(c.exercises.values), patterns: Array(c.patterns.values), slotTemplates: c.slotTemplates,
            heavyRotationDefaults: c.heavyRotationDefaults, progressionSteps: c.progressionSteps, ratioTable: c.ratioTable,
            equipmentTypes: c.equipmentTypes + [EquipmentType(key: "rowing_erg", category: "Cardio", label: "Rowing erg")],
            seededLocations: c.seededLocations
        )
        for (key, available) in seededStores {
            let p = grown.equipmentPartition(available: available)
            XCTAssertTrue(p.unselectedKeys.contains("rowing_erg"), key)
            XCTAssertFalse(p.selectedKeys.contains("rowing_erg"), key)
            XCTAssertEqual(Set(p.selectedKeys + p.unselectedKeys), grown.equipmentKeys, key)
        }
        // Crunch had "everything"; the new item is the only thing left to add.
        XCTAssertEqual(grown.equipmentPartition(available: seededStores["crunch_union_square"]!).unselectedKeys, ["rowing_erg"])
    }

    func testDefaultEquipmentIsATemplateNotTheCatalog() {
        let victoria = c.seededLocations.first { $0.key == "building_gym" }!
        let crunch = c.seededLocations.first { $0.key == "crunch_union_square" }!
        XCTAssertEqual(Set(c.defaultEquipment(for: victoria)), ["bodyweight", "dumbbells", "bench_adjustable", "bench_flat", "cable_machine", "treadmill"])
        XCTAssertEqual(Set(c.defaultEquipment(for: crunch)), c.equipmentKeys)
        XCTAssertNil(crunch.defaultEquipment)
        XCTAssertTrue(Set(c.defaultEquipment(for: victoria)).isSubset(of: c.equipmentKeys))
    }
}
