import Foundation

extension WorkoutStore {
    /// Test seam for the pull path without a network.
    public func applyForTesting(id: String, userId: String, table: String, payload: Data, updatedAt: Date, deleted: Bool) throws {
        try apply(pulled: PulledRecord(id: id, userId: userId, table: table, payload: payload, updatedAt: updatedAt, deleted: deleted, seq: 0))
    }
}
