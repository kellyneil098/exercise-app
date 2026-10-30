import Foundation

/// The overview's edits to a deck, kept apart from the plan itself: a manual order plus the blocks set aside.
/// Skipped blocks were swiped away mid-workout; deleted blocks were swiped out of the overview. Both stay in the
/// plan and come back with `restore`, so nothing the user takes out is lost until the session ends.
public struct DeckEdits: Equatable, Sendable {
    /// Manual deck order; empty means slot order.
    public var order: [UUID]
    public var skipped: Set<UUID>
    public var deleted: Set<UUID>

    public init(order: [UUID] = [], skipped: Set<UUID> = [], deleted: Set<UUID> = []) {
        self.order = order; self.skipped = skipped; self.deleted = deleted
    }

    public func isSkipped(_ id: UUID) -> Bool { skipped.contains(id) }
    public func isDeleted(_ id: UUID) -> Bool { deleted.contains(id) }
    /// Out of the active deck for either reason.
    public func isSetAside(_ id: UUID) -> Bool { skipped.contains(id) || deleted.contains(id) }

    // `ordered` is the whole deck in deck order; these split it into the overview's sections.

    public func active(_ ordered: [PlanBlock]) -> [PlanBlock] { ordered.filter { !isSetAside($0.id) } }
    public func skippedBlocks(_ ordered: [PlanBlock]) -> [PlanBlock] { ordered.filter { skipped.contains($0.id) } }
    public func deletedBlocks(_ ordered: [PlanBlock]) -> [PlanBlock] { ordered.filter { deleted.contains($0.id) } }

    /// Reorders within the active deck; set-aside blocks keep their place behind it.
    public mutating func move(fromOffsets: IndexSet, toOffset: Int, in ordered: [PlanBlock]) {
        // Same semantics as SwiftUI's `move(fromOffsets:toOffset:)` (which isn't in Foundation): `toOffset` indexes
        // the list before anything is lifted out.
        let ids = active(ordered).map(\.id)
        let moving = fromOffsets.sorted().map { ids[$0] }
        let staying = ids.indices.filter { !fromOffsets.contains($0) }
        let before = staying.filter { $0 < toOffset }.map { ids[$0] }
        let after = staying.filter { $0 >= toOffset }.map { ids[$0] }
        order = before + moving + after + setAside(ordered)
    }

    /// A block just added to the plan: once there is a manual order it joins the end of the active deck, but ahead of
    /// a cooldown sitting last, so the stretch stays the final card. (Without a manual order, slot order already does this.)
    public mutating func add(_ id: UUID, in ordered: [PlanBlock]) {
        guard !order.isEmpty else { return }
        let active = active(ordered).filter { $0.id != id }
        var ids = active.map(\.id)
        ids.insert(id, at: active.last?.isCooldown == true ? ids.count - 1 : ids.count)
        order = ids + setAside(ordered)
    }

    public mutating func skip(_ id: UUID) {
        deleted.remove(id)
        skipped.insert(id)
    }

    /// Works on an active or a skipped block.
    public mutating func delete(_ id: UUID) {
        skipped.remove(id)
        deleted.insert(id)
    }

    /// Back into the deck at the end of what's left, so it never jumps ahead of the block in hand.
    public mutating func restore(_ id: UUID, in ordered: [PlanBlock]) {
        skipped.remove(id)
        deleted.remove(id)
        var ids = active(ordered).map(\.id).filter { $0 != id }
        ids.append(id)
        order = ids + setAside(ordered)
    }

    private func setAside(_ ordered: [PlanBlock]) -> [UUID] { ordered.filter { isSetAside($0.id) }.map(\.id) }
}
