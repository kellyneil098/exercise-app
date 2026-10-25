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

    /// Closing Today's plan with its X soft-deletes the unstarted session, so a relaunch goes to Home rather than
    /// resuming it; an open deck is still what resumes. Mirrors `AppModel.cancel` and `restoreActiveSession`.
    func testCancelledUnstartedSessionDoesNotResume() throws {
        let store = try WorkoutStore.inMemory()
        let catalog = try SeedLoader.loadBundled()
        let inventory = LocationInventory(locationKey: "crunch_union_square", name: "Crunch", available: Set(catalog.equipmentTypes.map(\.key)), dumbbellMaxWeight: nil, plateIncrement: 2.5)
        let plan = Planner(catalog: catalog).generate(PlannerInput(dayType: .push, durationMinutes: 60, location: inventory, heavyRotation: HeavyRotation(sequence: ["horizontal_press"])))
        var cancelled = SessionRow(userId: "u1", dayType: .push, locationId: "loc", durationMin: 60, plan: plan)
        try store.save(cancelled)
        let resumable = { try store.db.read {
            try SessionRow.filter(Column("userId") == "u1" && Column("completedAt") == nil && Column("abandoned") == false && Column("deleted") == false)
                .order(Column("startedAt").desc).fetchOne($0)
        } }
        XCTAssertEqual(try resumable()?.id, cancelled.id)

        cancelled.deleted = true
        try store.save(cancelled)
        XCTAssertNil(try resumable(), "a cancelled deck is not resumed")
        let ops = try store.db.read { try Row.fetchAll($0, sql: "SELECT op FROM outbox WHERE id = ?", arguments: [cancelled.id]) }
        XCTAssertEqual(ops.count, 1, "the tombstone still syncs")

        let open = SessionRow(userId: "u1", dayType: .pull, locationId: "loc", durationMin: 45, startedAt: Date().addingTimeInterval(60), plan: plan)
        try store.save(open)
        XCTAssertEqual(try resumable()?.id, open.id)
    }
}
