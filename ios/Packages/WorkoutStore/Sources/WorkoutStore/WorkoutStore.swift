import Foundation
import GRDB
import WorkoutEngine

/// Local-first SQLite store (§9). Every write lands in SQLite immediately and appends an outbox row;
/// `SyncClient` drains the outbox and applies pulled rows with last-writer-wins on `updatedAt`.
public final class WorkoutStore: Sendable {
    public let db: DatabaseWriter

    public init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        db = try DatabasePool(path: path, configuration: config)
        try Self.migrator.migrate(db)
    }

    public static func inMemory() throws -> WorkoutStore {
        let store = WorkoutStore(writer: try DatabaseQueue())
        try migrator.migrate(store.db)
        return store
    }

    private init(writer: DatabaseWriter) { db = writer }

    public static let allTables: [any SyncedRecord.Type] = [
        Location.self, LocationEquipment.self, UserExercise.self, ExerciseStateRow.self, SplitStateRow.self,
        SessionRow.self, SetLog.self, RunPlanRow.self, RunRow.self, SettingsRow.self,
    ]

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            func synced(_ name: String, _ body: (TableDefinition) -> Void) throws {
                try db.create(table: name) { t in
                    t.primaryKey("id", .text)
                    t.column("userId", .text).notNull().indexed()
                    t.column("updatedAt", .datetime).notNull()
                    t.column("deleted", .boolean).notNull().defaults(to: false)
                    body(t)
                }
            }
            try synced("location") { t in
                t.column("name", .text).notNull()
                t.column("dumbbellMaxWeight", .double)
                t.column("dumbbellIncrement", .double).notNull()
                t.column("barbellIncrement", .double).notNull()
                t.column("sortOrder", .integer).notNull()
            }
            try synced("location_equipment") { t in
                t.column("locationId", .text).notNull().indexed()
                t.column("equipmentType", .text).notNull()
            }
            try synced("user_exercise") { t in
                t.column("key", .text).notNull()
                t.column("name", .text).notNull()
                t.column("pattern", .text).notNull()
                t.column("equipmentJSON", .text).notNull()
                t.column("loadable", .boolean).notNull()
                t.column("dumbbellBased", .boolean).notNull()
            }
            try synced("exercise_state") { t in
                t.column("exerciseKey", .text).notNull()
                t.column("workingWeight", .double)
                t.column("weightSource", .text).notNull()
                t.column("consecutiveFailures", .integer).notNull()
                t.column("preRebaselineWeight", .double)
                t.column("setCount", .integer)
                t.column("lastPerformedAt", .datetime)
                t.column("lastRebaselinedAt", .datetime)
            }
            try db.create(index: "exercise_state_user_key", on: "exercise_state", columns: ["userId", "exerciseKey"], unique: true)
            try synced("split_state") { t in
                t.column("nextDayIndex", .integer).notNull()
                t.column("heavyRotationJSON", .text).notNull()
                t.column("defaultDurationMin", .integer).notNull()
                t.column("defaultLocationId", .text)
            }
            try synced("session") { t in
                t.column("dayType", .text).notNull()
                t.column("locationId", .text).notNull()
                t.column("durationMin", .integer).notNull()
                t.column("startedAt", .datetime).notNull().indexed()
                t.column("completedAt", .datetime)
                t.column("abandoned", .boolean).notNull()
                t.column("planJSON", .text).notNull()
            }
            try synced("set_log") { t in
                t.column("sessionId", .text).notNull().indexed()
                t.column("exerciseKey", .text).notNull().indexed()
                t.column("slot", .integer).notNull()
                t.column("setIndex", .integer).notNull()
                t.column("isPadding", .boolean).notNull()
                t.column("isWarmup", .boolean).notNull()
                t.column("weight", .double)
                t.column("targetReps", .integer).notNull()
                t.column("repsDone", .integer).notNull()
                t.column("effort", .text)
                t.column("completedAt", .datetime).notNull().indexed()
            }
            try synced("run_plan") { t in
                t.column("runsPerWeek", .integer).notNull()
                t.column("peakWeeklyVolumeMi", .double).notNull()
                t.column("targetWeeklyVolumeMi", .double).notNull()
                t.column("easyPaceSecPerMi", .double).notNull()
                t.column("weekIndex", .integer).notNull()
                t.column("weekStart", .datetime).notNull()
            }
            try synced("run") { t in
                t.column("runType", .text).notNull()
                t.column("targetDistanceMi", .double).notNull()
                t.column("targetPaceSecPerMi", .double).notNull()
                t.column("distanceMi", .double)
                t.column("durationSec", .integer)
                t.column("effort", .text)
                t.column("completedAt", .datetime)
                t.column("weekStart", .datetime).notNull().indexed()
            }
            try synced("settings") { t in
                t.column("displayName", .text).notNull()
                t.column("restTimerSoundOn", .boolean).notNull()
                t.column("keepScreenAwake", .boolean).notNull()
            }
            try db.create(table: "outbox") { t in
                t.primaryKey("id", .text)
                t.column("tableName", .text).notNull()
                t.column("op", .text).notNull()
                t.column("payload", .text).notNull()
                t.column("createdAt", .datetime).notNull().indexed()
            }
            try db.create(table: "sync_meta") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }
        m.registerMigration("v2-location-seedKey") { db in
            try db.alter(table: "location") { $0.add(column: "seedKey", .text) }
        }
        return m
    }

    // MARK: Writes

    /// Local-first write: persist + enqueue for sync in one transaction.
    public func save<R: SyncedRecord>(_ record: R, now: Date = Date()) throws {
        var r = record
        r.updatedAt = now
        try db.write { db in try Self.saveAndEnqueue(r, in: db) }
    }

    public func save<R: SyncedRecord>(_ records: [R], now: Date = Date()) throws {
        try db.write { db in
            for var r in records {
                r.updatedAt = now
                try Self.saveAndEnqueue(r, in: db)
            }
        }
    }

    /// Soft delete (§9 tombstones). Row stays locally with `deleted = true`.
    public func delete<R: SyncedRecord>(_ record: R, now: Date = Date()) throws {
        var r = record
        r.deleted = true
        r.updatedAt = now
        try db.write { db in try Self.saveAndEnqueue(r, in: db) }
    }

    static func saveAndEnqueue<R: SyncedRecord>(_ r: R, in db: Database) throws {
        try r.save(db)
        let payload = String(decoding: try JSONEncoder.store.encode(r), as: UTF8.self)
        // One outbox row per record id: a later local write replaces the pending one.
        try OutboxRow(id: r.id, tableName: R.tableName, op: r.deleted ? "delete" : "upsert",
                      payload: payload, createdAt: r.updatedAt).save(db)
    }

    // MARK: Sync plumbing

    func pendingOutbox(limit: Int) throws -> [OutboxRow] {
        try db.read { db in try OutboxRow.order(Column("createdAt")).limit(limit).fetchAll(db) }
    }

    /// Removes only the exact snapshots that were sent; a newer local write that replaced one stays queued.
    func clearOutbox(sent: [OutboxRow]) throws {
        try db.write { db in
            for row in sent {
                _ = try OutboxRow.filter(Column("id") == row.id && Column("createdAt") == row.createdAt).deleteAll(db)
            }
        }
    }

    /// Drops rows owned by users we can no longer see (share revoked). Local-only; nothing is enqueued.
    public func purgeRows(notOwnedBy visible: [String]) throws {
        try db.write { db in
            for t in Self.allTables {
                try db.execute(sql: "DELETE FROM \(t.tableName) WHERE userId NOT IN (\(visible.map { _ in "?" }.joined(separator: ",")))",
                               arguments: StatementArguments(visible))
            }
        }
    }

    public var pullCursor: Int {
        get { (try? db.read { try SyncMeta.fetchOne($0, key: "pull_cursor")?.value }).flatMap { Int($0) } ?? 0 }
    }

    public func setPullCursor(_ c: Int) throws {
        try db.write { try SyncMeta(key: "pull_cursor", value: String(c)).save($0) }
    }

    /// Apply a pulled record: LWW on updatedAt; never enqueues (it came from the server).
    func apply(pulled: PulledRecord) throws {
        guard let type = Self.allTables.first(where: { $0.tableName == pulled.table }) else { return }
        try db.write { db in try type.applyPulled(pulled, in: db) }
    }
}

extension SyncedRecord {
    static func applyPulled(_ pulled: PulledRecord, in db: Database) throws {
        let existing = try Self.fetchOne(db, key: pulled.id)
        if let existing, existing.updatedAt >= pulled.updatedAt { return }
        if pulled.deleted {
            if var existing {
                existing.deleted = true
                existing.updatedAt = pulled.updatedAt
                try existing.save(db)
            }
            return
        }
        var incoming = try JSONDecoder.store.decode(Self.self, from: pulled.payload)
        incoming.updatedAt = pulled.updatedAt
        incoming.userId = pulled.userId
        try incoming.save(db)
    }
}

public struct PulledRecord: Sendable {
    public var id: String
    public var userId: String
    public var table: String
    public var payload: Data
    public var updatedAt: Date
    public var deleted: Bool
    public var seq: Int
}
