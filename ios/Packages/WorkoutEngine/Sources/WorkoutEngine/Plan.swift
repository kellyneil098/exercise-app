import Foundation

public struct WarmupSet: Codable, Sendable, Hashable {
    public let weight: Double
    public let reps: Int
}

/// One exercise's worth of work in a generated plan.
public struct PlanBlock: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var slot: Int
    public var pattern: String
    public var exerciseKey: String
    public var exerciseName: String
    public var band: Band
    /// Sets actually in the plan (template + padding).
    public var sets: Int
    /// Sets the progression test looks at (§5.1) — the template's count.
    public var prescribedSets: Int
    public var repLow: Int
    public var repHigh: Int
    public var measure: Measure
    public var restSeconds: Int
    public var weight: Double?
    public var weightSource: WeightSource?
    public var warmups: [WarmupSet]
    /// Set when this block is supersetted into another block's rest periods.
    public var supersetHostID: UUID?
    public var estimatedSeconds: Double
    public var isCustomAdded: Bool = false

    public var isSupersetted: Bool { supersetHostID != nil }
    public var isEstimate: Bool { weightSource != nil && weightSource != .measured }
}

public struct Plan: Codable, Sendable, Hashable {
    public var dayType: DayType
    public var durationMinutes: Int
    public var locationKey: String
    public var blocks: [PlanBlock]

    public var estimatedSeconds: Double { blocks.reduce(0) { $0 + $1.estimatedSeconds } }
    public var heavyBlock: PlanBlock? { blocks.first { $0.band == .heavy } }
    public func host(of block: PlanBlock) -> PlanBlock? {
        guard let h = block.supersetHostID else { return nil }
        return blocks.first { $0.id == h }
    }
    public func supersetPartner(of host: PlanBlock) -> PlanBlock? {
        blocks.first { $0.supersetHostID == host.id }
    }
}
