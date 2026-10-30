import Foundation

public struct WarmupSet: Codable, Sendable, Hashable {
    public let weight: Double
    public let reps: Int
}

/// What a block asks of the user. A cooldown is a timed placeholder (a reminder to stretch): no load, no set or rep
/// prescription, no superset or heavy role, and never part of progression.
public enum BlockKind: String, Codable, Sendable, Hashable {
    case exercise, cooldown
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
    /// Swiped out of the deck in the overview. The block stays in the plan (so it syncs and can be restored) but
    /// is out of play: not sequenced, not a superset host, not counted as performed.
    public var isDeleted: Bool = false
    public var kind: BlockKind = .exercise

    public var isSupersetted: Bool { supersetHostID != nil }
    public var isEstimate: Bool { weightSource != nil && weightSource != .measured }
    public var isCooldown: Bool { kind == .cooldown }
    /// Only real exercises feed progression, weight recommendations and the planner's rotation history.
    public var tracksProgression: Bool { kind == .exercise }
}

extension PlanBlock {
    /// Not a catalog exercise: it keys the cooldown's logged "set" so history and Progress can leave it out.
    public static let cooldownExerciseKey = "cooldown_stretch"

    /// The generic stretch placeholder appended to a new deck: one timed "set" lasting `seconds`.
    public static func cooldown(slot: Int, seconds: Int) -> PlanBlock {
        PlanBlock(
            id: UUID(), slot: slot, pattern: "cooldown", exerciseKey: cooldownExerciseKey, exerciseName: "Stretch",
            band: .volume, sets: 1, prescribedSets: 1, repLow: seconds, repHigh: seconds, measure: .seconds,
            restSeconds: 0, weight: nil, weightSource: nil, warmups: [], supersetHostID: nil,
            estimatedSeconds: Double(seconds), kind: .cooldown
        )
    }
}

// In an extension so the memberwise initializer the planner uses survives.
extension PlanBlock {
    // Plans saved before these flags existed decode with them off.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        slot = try c.decode(Int.self, forKey: .slot)
        pattern = try c.decode(String.self, forKey: .pattern)
        exerciseKey = try c.decode(String.self, forKey: .exerciseKey)
        exerciseName = try c.decode(String.self, forKey: .exerciseName)
        band = try c.decode(Band.self, forKey: .band)
        sets = try c.decode(Int.self, forKey: .sets)
        prescribedSets = try c.decode(Int.self, forKey: .prescribedSets)
        repLow = try c.decode(Int.self, forKey: .repLow)
        repHigh = try c.decode(Int.self, forKey: .repHigh)
        measure = try c.decode(Measure.self, forKey: .measure)
        restSeconds = try c.decode(Int.self, forKey: .restSeconds)
        weight = try c.decodeIfPresent(Double.self, forKey: .weight)
        weightSource = try c.decodeIfPresent(WeightSource.self, forKey: .weightSource)
        warmups = try c.decode([WarmupSet].self, forKey: .warmups)
        supersetHostID = try c.decodeIfPresent(UUID.self, forKey: .supersetHostID)
        estimatedSeconds = try c.decode(Double.self, forKey: .estimatedSeconds)
        isCustomAdded = try c.decodeIfPresent(Bool.self, forKey: .isCustomAdded) ?? false
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        kind = try c.decodeIfPresent(BlockKind.self, forKey: .kind) ?? .exercise
    }
}

public struct Plan: Codable, Sendable, Hashable {
    public var dayType: DayType
    public var durationMinutes: Int
    public var locationKey: String
    public var blocks: [PlanBlock]

    public var estimatedSeconds: Double { blocks.reduce(0) { $0 + $1.estimatedSeconds } }
    public var heavyBlock: PlanBlock? { blocks.first { $0.band == .heavy } }
    /// Blocks still in the workout.
    public var liveBlocks: [PlanBlock] { blocks.filter { !$0.isDeleted } }
    /// Live blocks that count as training: what progression is applied to and what the planner's history remembers.
    public var progressionBlocks: [PlanBlock] { liveBlocks.filter(\.tracksProgression) }
    /// Default deck order: slot order, with cooldowns after every exercise (even ones added later, which take higher slots).
    public var slotOrdered: [PlanBlock] { blocks.sorted { ($0.isCooldown ? 1 : 0, $0.slot) < ($1.isCooldown ? 1 : 0, $1.slot) } }
    /// A deleted host no longer pairs: its partner works (and rests) on its own until the host is restored.
    public func host(of block: PlanBlock) -> PlanBlock? {
        guard let h = block.supersetHostID else { return nil }
        return blocks.first { $0.id == h && !$0.isDeleted }
    }
    public func supersetPartner(of host: PlanBlock) -> PlanBlock? {
        guard !host.isDeleted else { return nil }
        return blocks.first { $0.supersetHostID == host.id && !$0.isDeleted }
    }

    /// Rest after a working set of `block`. A superset partner rests on its host's clock (host → partner → rest).
    public func restSeconds(for block: PlanBlock) -> Int {
        let current = blocks.first { $0.id == block.id } ?? block
        return host(of: current)?.restSeconds ?? current.restSeconds
    }

    /// Sets the rest that follows `block`'s sets (its host's, for a superset partner), clamped to
    /// `config.restSecondsRange`. Like the sets/reps edits, it leaves `estimatedSeconds` alone (§4.2: estimated once, at generation).
    public mutating func setRest(of block: PlanBlock, to seconds: Int, config: EngineConfig = .default) {
        guard let current = blocks.first(where: { $0.id == block.id }), !current.isCooldown else { return }
        let targetID = current.supersetHostID ?? current.id
        guard let i = blocks.firstIndex(where: { $0.id == targetID }) else { return }
        blocks[i].restSeconds = config.clampedRest(seconds)
    }

    /// One stepper tap: `steps` × `config.restStepSeconds` (−1 = minus, +1 = plus), clamped.
    public mutating func stepRest(of block: PlanBlock, by steps: Int, config: EngineConfig = .default) {
        setRest(of: block, to: restSeconds(for: block) + steps * config.restStepSeconds, config: config)
    }
}
