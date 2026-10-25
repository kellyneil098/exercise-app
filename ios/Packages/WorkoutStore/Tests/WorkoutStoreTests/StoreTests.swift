import Foundation
import GRDB
import WorkoutEngine
import WorkoutStore
import XCTest

final class StoreTests: XCTestCase {
    func testUUIDv7IsTimeOrdered() {
        let a = UUIDv7.generate(now: Date(timeIntervalSince1970: 1_700_000_000))
        let b = UUIDv7.generate(now: Date(timeIntervalSince1970: 1_700_000_001))
        XCTAssertLessThan(a, b)
        XCTAssertEqual(a.count, 36)
        XCTAssertEqual(a[a.index(a.startIndex, offsetBy: 14)], "7")
    }

    func testSaveEnqueuesOutboxAndDeleteIsTombstone() throws {
        let store = try WorkoutStore.inMemory()
        let loc = Location(userId: "u1", name: "Building gym", dumbbellMaxWeight: 50)
        try store.save(loc)
        var pending = try store.db.read { try Row.fetchAll($0, sql: "SELECT op, tableName FROM outbox") }
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0]["op"] as String, "upsert")
        XCTAssertEqual(pending[0]["tableName"] as String, "location")

        try store.delete(loc)
        pending = try store.db.read { try Row.fetchAll($0, sql: "SELECT op FROM outbox") }
        XCTAssertEqual(pending.count, 1, "one outbox row per id; later write replaces")
        XCTAssertEqual(pending[0]["op"] as String, "delete")
        let stored = try store.db.read { try Location.fetchOne($0, key: loc.id) }
        XCTAssertEqual(stored?.deleted, true)
    }

    func testExerciseStateRoundTrip() throws {
        let store = try WorkoutStore.inMemory()
        let s = ExerciseState(exerciseKey: "bench_press", workingWeight: 185, weightSource: .measured, consecutiveFailures: 1)
        let row = ExerciseStateRow(userId: "u1", state: s)
        try store.save(row)
        let back = try store.db.read { try ExerciseStateRow.fetchOne($0, key: row.id) }!.engineState
        XCTAssertEqual(back.workingWeight, 185)
        XCTAssertEqual(back.consecutiveFailures, 1)
        XCTAssertEqual(back.weightSource, .measured)
    }

    func testPulledRecordLWW() throws {
        let store = try WorkoutStore.inMemory()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let loc = Location(userId: "u1", name: "Old", updatedAt: t0)
        try store.save(loc, now: t0)

        // Older pulled row loses.
        var older = loc; older.name = "Stale"
        let olderPayload = try JSONEncoder.store.encode(older)
        try store.applyForTesting(id: loc.id, userId: "u1", table: "location", payload: olderPayload, updatedAt: t0.addingTimeInterval(-10), deleted: false)
        XCTAssertEqual(try store.db.read { try Location.fetchOne($0, key: loc.id)?.name }, "Old")

        // Newer pulled row wins and does not touch the outbox.
        var newer = loc; newer.name = "Fresh"
        let newerPayload = try JSONEncoder.store.encode(newer)
        try store.applyForTesting(id: loc.id, userId: "u1", table: "location", payload: newerPayload, updatedAt: t0.addingTimeInterval(10), deleted: false)
        XCTAssertEqual(try store.db.read { try Location.fetchOne($0, key: loc.id)?.name }, "Fresh")
        XCTAssertEqual(try store.db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM outbox") }, 1)

        // Partner rows land under their own userId.
        let partner = Location(id: UUIDv7.generate(), userId: "u2", name: "Nat gym", updatedAt: t0)
        try store.applyForTesting(id: partner.id, userId: "u2", table: "location", payload: try JSONEncoder.store.encode(partner), updatedAt: t0, deleted: false)
        XCTAssertEqual(try store.db.read { try Location.filter(Column("userId") == "u2").fetchCount($0) }, 1)
    }

    func testSessionPlanRoundTrip() throws {
        let catalog = try SeedLoader.loadBundled()
        let planner = Planner(catalog: catalog)
        let inventory = LocationInventory(locationKey: "crunch_union_square", name: "Crunch", available: Set(catalog.equipmentTypes.map(\.key)), dumbbellMaxWeight: nil, plateIncrement: 2.5)
        let plan = planner.generate(PlannerInput(dayType: .push, durationMinutes: 60, location: inventory, heavyRotation: HeavyRotation(sequence: ["horizontal_press"])))
        let row = SessionRow(userId: "u1", dayType: .push, locationId: "loc", durationMin: 60, plan: plan)
        let store = try WorkoutStore.inMemory()
        try store.save(row)
        let back = try store.db.read { try SessionRow.fetchOne($0, key: row.id) }
        XCTAssertEqual(back?.plan?.blocks.count, plan.blocks.count)
    }

    func testReconcileRenamesFormerSeedNamesAndKeepsUserNames() throws {
        let seeds = try SeedLoader.loadBundled().seededLocations
        let stamped = Location(userId: "u1", name: "Crunch Union Square", seedKey: "crunch_union_square", sortOrder: 1)
        let legacy = Location(userId: "u1", name: "Building Gym", sortOrder: 0)
        var (changed, missing, renames) = Location.reconcile([legacy, stamped], with: seeds)
        XCTAssertTrue(missing.isEmpty)
        XCTAssertEqual(Set(changed.map(\.id)), [stamped.id, legacy.id])
        XCTAssertEqual(changed.first { $0.id == stamped.id }?.name, "Crunch USQ")
        XCTAssertEqual(changed.first { $0.id == legacy.id }?.name, "The Victoria")
        XCTAssertEqual(changed.first { $0.id == legacy.id }?.seedKey, "building_gym")
        XCTAssertEqual(renames, ["crunch_union_square:Crunch Union Square", "building_gym:Building Gym"])

        // Once applied, a user who deliberately picks the old name keeps it.
        (changed, missing, _) = Location.reconcile([stamped], with: seeds, appliedRenames: renames)
        XCTAssertTrue(changed.isEmpty)
        XCTAssertEqual(missing.map(\.key), ["building_gym"])

        // An unstamped legacy row (e.g. pulled after an account switch) is still recognised, never duplicated.
        let legacyCrunch = Location(userId: "u2", name: "Crunch Union Square")
        (changed, missing, _) = Location.reconcile([legacyCrunch], with: seeds, appliedRenames: renames)
        XCTAssertEqual(changed.map(\.id), [legacyCrunch.id])
        XCTAssertEqual(changed.first?.seedKey, "crunch_union_square")
        XCTAssertEqual(changed.first?.name, "Crunch Union Square")
        XCTAssertEqual(missing.map(\.key), ["building_gym"])

        // A name the user chose stays, and already-current rows need no write.
        let custom = Location(userId: "u1", name: "Crunch 14th St", seedKey: "crunch_union_square")
        let current = Location(userId: "u1", name: "The Victoria", seedKey: "building_gym")
        (changed, missing, _) = Location.reconcile([current, custom], with: seeds)
        XCTAssertTrue(changed.isEmpty)
        XCTAssertTrue(missing.isEmpty)

        // Seeds with no row are reported for insertion; an unrelated gym is left alone.
        (changed, missing, _) = Location.reconcile([Location(userId: "u1", name: "Hotel gym")], with: seeds)
        XCTAssertTrue(changed.isEmpty)
        XCTAssertEqual(missing.map(\.key), ["building_gym", "crunch_union_square"])
    }

    func testAppliedSeedRenamesPersist() throws {
        let store = try WorkoutStore.inMemory()
        XCTAssertEqual(store.appliedSeedRenames, [])
        try store.setAppliedSeedRenames(["crunch_union_square:Crunch Union Square"])
        XCTAssertEqual(store.appliedSeedRenames, ["crunch_union_square:Crunch Union Square"])
        XCTAssertEqual(try store.db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM outbox") }, 0)
    }

    // MARK: Gym equipment

    func outboxOps(_ store: WorkoutStore, table: String) throws -> [String] {
        try store.db.read { try String.fetchAll($0, sql: "SELECT op FROM outbox WHERE tableName = ? ORDER BY createdAt, id", arguments: [table]) }
    }

    func testToggleEquipmentPersistsPerGymWithoutTouchingAnotherGym() throws {
        let store = try WorkoutStore.inMemory()
        let victoria = Location(userId: "u1", name: "The Victoria", seedKey: "building_gym")
        let crunch = Location(userId: "u1", name: "Crunch USQ", seedKey: "crunch_union_square", sortOrder: 1)
        try store.save([victoria, crunch])
        try store.save(["bodyweight", "dumbbells"].map { LocationEquipment(userId: "u1", locationId: victoria.id, equipmentType: $0) })
        try store.save(["bodyweight", "dumbbells", "barbell"].map { LocationEquipment(userId: "u1", locationId: crunch.id, equipmentType: $0) })

        try store.setEquipment("barbell", available: true, forLocation: victoria.id, userId: "u1")
        XCTAssertEqual(try store.equipment(forLocation: victoria.id), ["bodyweight", "dumbbells", "barbell"])
        try store.setEquipment("dumbbells", available: false, forLocation: victoria.id, userId: "u1")
        XCTAssertEqual(try store.equipment(forLocation: victoria.id), ["bodyweight", "barbell"])
        XCTAssertEqual(try store.equipment(forLocation: crunch.id), ["bodyweight", "dumbbells", "barbell"], "the other gym is untouched")

        // Removal is a tombstone (synced as a delete); re-adding revives the same row instead of growing a new one.
        let victoriaRows = try store.db.read { try LocationEquipment.filter(Column("locationId") == victoria.id).fetchAll($0) }
        XCTAssertEqual(victoriaRows.count, 3)
        XCTAssertEqual(victoriaRows.first { $0.equipmentType == "dumbbells" }?.deleted, true)
        try store.setEquipment("dumbbells", available: true, forLocation: victoria.id, userId: "u1")
        XCTAssertEqual(try store.db.read { try LocationEquipment.filter(Column("locationId") == victoria.id).fetchCount($0) }, 3)
        XCTAssertEqual(try store.equipment(forLocation: victoria.id), ["bodyweight", "dumbbells", "barbell"])

        // Idempotent: adding what is there / removing what is not writes nothing.
        let before = try store.db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM outbox") }
        try store.setEquipment("barbell", available: true, forLocation: victoria.id, userId: "u1")
        try store.setEquipment("leg_press", available: false, forLocation: victoria.id, userId: "u1")
        XCTAssertEqual(try store.db.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM outbox") }, before)

        // Every toggle is queued for sync (one outbox row per record id, latest op wins).
        let ops = try store.db.read {
            try Row.fetchAll($0, sql: "SELECT op, payload FROM outbox WHERE tableName = 'location_equipment'")
        }
        XCTAssertEqual(ops.count, 6)
        XCTAssertTrue(ops.allSatisfy { ($0["op"] as String) == "upsert" }, "the revived row's pending op is the upsert, not the earlier delete")
    }

    func testToggleEquipmentOfflineQueuesForLaterSync() throws {
        let store = try WorkoutStore.inMemory()
        let gym = Location(userId: "u1", name: "Hotel gym")
        try store.save(gym)
        try store.setEquipment("kettlebell", available: true, forLocation: gym.id, userId: "u1")
        try store.setEquipment("kettlebell", available: false, forLocation: gym.id, userId: "u1")
        XCTAssertEqual(try outboxOps(store, table: "location_equipment"), ["delete"])
        let row = try store.db.read { try LocationEquipment.filter(Column("locationId") == gym.id).fetchOne($0) }
        XCTAssertEqual(row?.deleted, true)
        XCTAssertEqual(row?.userId, "u1")
    }

    // MARK: Deleting gyms

    func testSeededGymsArePermanentWhateverTheyAreCalled() throws {
        let store = try WorkoutStore.inMemory()
        let renamed = Location(userId: "u1", name: "My favourite Crunch", seedKey: "crunch_union_square")
        let victoria = Location(userId: "u1", name: "The Victoria", seedKey: "building_gym")
        try store.save([renamed, victoria])
        XCTAssertTrue(renamed.isSeeded)
        XCTAssertFalse(Location(userId: "u1", name: "Crunch USQ").isSeeded, "protection is by seed identity, not by name")
        XCTAssertThrowsError(try store.deleteLocation(renamed)) { XCTAssertEqual($0 as? LocationError, .seededLocationIsPermanent("crunch_union_square")) }
        XCTAssertThrowsError(try store.deleteLocation(victoria))
        XCTAssertEqual(try store.db.read { try Location.filter(Column("deleted") == false).fetchCount($0) }, 2)
    }

    func testDeleteCustomGymTombstonesItAndItsEquipmentOnly() throws {
        let store = try WorkoutStore.inMemory()
        let keep = Location(userId: "u1", name: "The Victoria", seedKey: "building_gym", sortOrder: 0)
        let gone = Location(userId: "u1", name: "Hotel gym", sortOrder: 1)
        try store.save([keep, gone])
        try store.save(["bodyweight", "dumbbells"].map { LocationEquipment(userId: "u1", locationId: keep.id, equipmentType: $0) })
        try store.save(["bodyweight", "kettlebell"].map { LocationEquipment(userId: "u1", locationId: gone.id, equipmentType: $0) })
        let catalog = try SeedLoader.loadBundled()
        let inventory = LocationInventory(locationKey: gone.id, name: gone.name, available: ["kettlebell"], dumbbellMaxWeight: nil, plateIncrement: 5)
        let plan = Planner(catalog: catalog).generate(PlannerInput(dayType: .push, durationMinutes: 45, location: inventory, heavyRotation: HeavyRotation(sequence: ["horizontal_press"])))
        let session = SessionRow(userId: "u1", dayType: .push, locationId: gone.id, durationMin: 45, plan: plan)
        try store.save(session)
        try store.db.write { try $0.execute(sql: "DELETE FROM outbox") }

        try store.deleteLocation(gone)

        XCTAssertEqual(try store.db.read { try Location.fetchOne($0, key: gone.id)?.deleted }, true)
        XCTAssertEqual(try store.db.read { try Location.fetchOne($0, key: keep.id)?.deleted }, false)
        XCTAssertEqual(try store.equipment(forLocation: gone.id), [])
        XCTAssertEqual(try store.equipment(forLocation: keep.id), ["bodyweight", "dumbbells"])
        XCTAssertEqual(try store.db.read { try LocationEquipment.filter(Column("locationId") == gone.id).fetchCount($0) }, 2, "tombstoned, not purged")
        // History is preserved: the session still points at the deleted gym.
        let kept = try store.db.read { try SessionRow.fetchOne($0, key: session.id) }
        XCTAssertEqual(kept?.locationId, gone.id)
        XCTAssertEqual(kept?.deleted, false)
        // Everything the delete touched is queued as a tombstone.
        XCTAssertEqual(try outboxOps(store, table: "location"), ["delete"])
        XCTAssertEqual(try outboxOps(store, table: "location_equipment"), ["delete", "delete"])
        XCTAssertEqual(try outboxOps(store, table: "session"), [])
    }

    func testDeletedGymKeepsItsInventoryForAWorkoutStillRunningThere() throws {
        let store = try WorkoutStore.inMemory()
        let gym = Location(userId: "u1", name: "Hotel gym")
        try store.save(gym)
        try store.save(["bodyweight", "kettlebell", "dumbbells", "treadmill"].map { LocationEquipment(userId: "u1", locationId: gym.id, equipmentType: $0) })
        try store.setEquipment("treadmill", available: false, forLocation: gym.id, userId: "u1", now: Date(timeIntervalSince1970: 1_000))

        try store.deleteLocation(gym, now: Date(timeIntervalSince1970: 2_000))

        let deleted = try XCTUnwrap(store.db.read { try Location.fetchOne($0, key: gym.id) })
        XCTAssertTrue(deleted.deleted)
        XCTAssertEqual(try store.equipment(for: deleted), ["bodyweight", "kettlebell", "dumbbells"], "what the gym had when it was deleted, not what was unchecked earlier")
        XCTAssertEqual(try store.equipment(forLocation: gym.id), [], "the gym itself no longer offers anything")
        XCTAssertEqual(try store.equipment(for: gym), ["bodyweight", "kettlebell", "dumbbells"], "a live snapshot reads live rows")
    }

    func testDeleteGymMovesTheDefaultLocationToTheNextGym() throws {
        let store = try WorkoutStore.inMemory()
        let first = Location(userId: "u1", name: "The Victoria", seedKey: "building_gym", sortOrder: 0)
        let chosen = Location(userId: "u1", name: "Hotel gym", sortOrder: 1)
        let other = Location(userId: "u1", name: "Office gym", sortOrder: 2)
        try store.save([first, chosen, other])
        var split = SplitStateRow(userId: "u1")
        split.defaultLocationId = chosen.id
        try store.save(split)

        try store.deleteLocation(chosen)
        var stored = try store.db.read { try SplitStateRow.fetchOne($0, key: split.id) }
        XCTAssertEqual(stored?.defaultLocationId, first.id, "falls back to the first remaining gym by sort order")

        // A default pointing elsewhere is left alone.
        try store.deleteLocation(other)
        stored = try store.db.read { try SplitStateRow.fetchOne($0, key: split.id) }
        XCTAssertEqual(stored?.defaultLocationId, first.id)
        XCTAssertEqual(try outboxOps(store, table: "split_state"), ["upsert"])

        // Deleting the last deletable gym clears the default rather than pointing at a tombstone.
        let only = Location(userId: "u2", name: "Garage")
        try store.save(only)
        var s2 = SplitStateRow(userId: "u2"); s2.defaultLocationId = only.id
        try store.save(s2)
        try store.deleteLocation(only)
        XCTAssertNil(try store.db.read { try SplitStateRow.fetchOne($0, key: s2.id)?.defaultLocationId })
    }
}
