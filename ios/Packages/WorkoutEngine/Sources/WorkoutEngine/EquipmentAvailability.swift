import Foundation

/// A titled run of equipment rows in the gym editor: one seed category, labels A–Z.
public struct EquipmentSection: Identifiable, Hashable, Sendable {
    public var id: String { category }
    public let category: String
    public let items: [EquipmentType]

    public var keys: [String] { items.map(\.key) }
}

/// A gym's view of the master equipment catalog: what it has (`selected`) and what it could add (`unselected`).
/// Together the two cover every catalog key exactly once, whatever the gym has stored.
public struct EquipmentPartition: Hashable, Sendable {
    public let selected: [EquipmentSection]
    public let unselected: [EquipmentSection]

    public var selectedKeys: [String] { selected.flatMap(\.keys) }
    public var unselectedKeys: [String] { unselected.flatMap(\.keys) }
    public var selectedCount: Int { selected.reduce(0) { $0 + $1.items.count } }
    public var totalCount: Int { selectedCount + unselected.reduce(0) { $0 + $1.items.count } }
}

extension Catalog {
    /// Every equipment key in the seed vocabulary. This is the one list every gym chooses from; nothing per-gym
    /// (defaults, stored rows, unknown keys) adds to or removes from it.
    public var equipmentKeys: Set<String> { Set(equipmentTypes.map(\.key)) }

    /// Seed categories in order of first appearance.
    public var equipmentCategories: [String] {
        var seen: [String] = []
        for e in equipmentTypes where !seen.contains(e.category) { seen.append(e.category) }
        return seen
    }

    /// Splits the master catalog by `available` (the gym's stored equipment keys). Bodyweight is always selected;
    /// keys the catalog doesn't know are ignored, so every gym sees the same choices.
    public func equipmentPartition(available: Set<String>) -> EquipmentPartition {
        let have = available.union([EquipmentType.bodyweightKey])
        return EquipmentPartition(
            selected: equipmentSections(equipmentTypes.filter { have.contains($0.key) }),
            unselected: equipmentSections(equipmentTypes.filter { !have.contains($0.key) })
        )
    }

    /// Groups `items` into sections by category (seed order), labels sorted A–Z within each; empty categories are dropped.
    public func equipmentSections(_ items: [EquipmentType]) -> [EquipmentSection] {
        equipmentCategories.compactMap { category in
            let members = items.filter { $0.category == category }.sorted {
                let order = $0.label.localizedStandardCompare($1.label)
                return order == .orderedSame ? $0.key < $1.key : order == .orderedAscending
            }
            return members.isEmpty ? nil : EquipmentSection(category: category, items: members)
        }
    }

    /// What a seeded gym starts with before the user edits it: everything for a commercial gym, the seed's
    /// `default_equipment` otherwise. A template for new rows only — never the list a gym can choose from.
    public func defaultEquipment(for seed: SeededLocation) -> [String] {
        if seed.defaultAvailable { return equipmentTypes.map(\.key) }
        return (seed.defaultEquipment ?? [EquipmentType.bodyweightKey]).filter(equipmentKeys.contains)
    }
}
