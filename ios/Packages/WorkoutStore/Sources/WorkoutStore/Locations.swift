import Foundation
import GRDB

public enum LocationError: Error, Equatable, CustomStringConvertible {
    /// Gyms that came from the seed (`Location.seedKey` set) are permanent.
    case seededLocationIsPermanent(String)

    public var description: String {
        switch self {
        case .seededLocationIsPermanent(let key): "seeded location \(key) cannot be deleted"
        }
    }
}

extension Location {
    /// Came from seed/equipment_types.json (stamped by `Location.reconcile`), so it is permanent whatever it is called now.
    public var isSeeded: Bool { seedKey != nil }
}

extension WorkoutStore {
    /// Equipment keys currently available at a location (live rows only).
    public func equipment(forLocation locationId: String) throws -> Set<String> {
        let rows = try db.read {
            try LocationEquipment.filter(Column("locationId") == locationId && Column("deleted") == false).fetchAll($0)
        }
        return Set(rows.map(\.equipmentType))
    }

    /// Equipment available at a location as the app should see it: live rows for a live gym; for a deleted gym, the rows
    /// `deleteLocation` tombstoned with it (they share its `updatedAt`), so a workout still running there keeps its inventory.
    /// Equipment the user had unchecked before the deletion stays out.
    public func equipment(for location: Location) throws -> Set<String> {
        guard location.deleted else { return try equipment(forLocation: location.id) }
        let rows = try db.read {
            try LocationEquipment.filter(Column("locationId") == location.id && Column("deleted") == true && Column("updatedAt") == location.updatedAt).fetchAll($0)
        }
        return Set(rows.map(\.equipmentType))
    }

    /// Marks one equipment type available or not at one location, persisting and enqueueing in a single transaction.
    /// Re-adding revives that location's tombstoned row rather than growing a new one; removing tombstones every live row
    /// for the key. Other locations are never touched.
    public func setEquipment(_ key: String, available: Bool, forLocation locationId: String, userId: String, now: Date = Date()) throws {
        try db.write { db in
            let rows = try LocationEquipment.filter(Column("locationId") == locationId && Column("equipmentType") == key).fetchAll(db)
            if available {
                guard !rows.contains(where: { !$0.deleted }) else { return }
                var row = rows.max { $0.updatedAt < $1.updatedAt } ?? LocationEquipment(userId: userId, locationId: locationId, equipmentType: key)
                row.deleted = false
                row.updatedAt = now
                try Self.saveAndEnqueue(row, in: db)
            } else {
                for var row in rows where !row.deleted {
                    row.deleted = true
                    row.updatedAt = now
                    try Self.saveAndEnqueue(row, in: db)
                }
            }
        }
    }

    /// Deletes a user-created gym: tombstones the location and its equipment rows in one transaction (each enqueued for
    /// sync), and moves the user's default location off it. Sessions logged there keep their `locationId`; history is
    /// never cascaded. Throws for seeded gyms, which are permanent.
    public func deleteLocation(_ location: Location, now: Date = Date()) throws {
        if let key = location.seedKey { throw LocationError.seededLocationIsPermanent(key) }
        try db.write { db in
            var loc = location
            loc.deleted = true
            loc.updatedAt = now
            try Self.saveAndEnqueue(loc, in: db)
            for var row in try LocationEquipment.filter(Column("locationId") == location.id && Column("deleted") == false).fetchAll(db) {
                row.deleted = true
                row.updatedAt = now
                try Self.saveAndEnqueue(row, in: db)
            }
            if var split = try SplitStateRow.filter(Column("userId") == location.userId).fetchOne(db), split.defaultLocationId == location.id {
                split.defaultLocationId = try Location
                    .filter(Column("userId") == location.userId && Column("deleted") == false && Column("id") != location.id)
                    .order(Column("sortOrder")).fetchOne(db)?.id
                split.updatedAt = now
                try Self.saveAndEnqueue(split, in: db)
            }
        }
    }
}
