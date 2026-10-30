import Foundation

public enum DayType: String, Codable, CaseIterable, Sendable, Hashable {
    case push, pull, legs
    /// Standalone program: repeats itself instead of rotating through push/pull/legs.
    case fullBody = "full_body"

    public var next: DayType {
        switch self {
        case .push: return .pull
        case .pull: return .legs
        case .legs: return .push
        case .fullBody: return .fullBody
        }
    }

    public var label: String { self == .fullBody ? "Full body" : rawValue.capitalized }
}

public enum Band: String, Codable, Sendable, Hashable {
    case heavy, medium, volume
}

public enum Measure: String, Codable, Sendable, Hashable {
    case reps, seconds
}

/// One entry of the equipment vocabulary (seed/equipment_types.json): the master catalog every gym selects from.
public struct EquipmentType: Codable, Hashable, Sendable {
    public let key: String
    /// Grouping for the gym equipment editor ("Free weights", "Machines", ...). Categories are ordered by first appearance in the seed.
    public let category: String
    public let label: String
    /// Developer note from the seed; never shown to users.
    public let note: String?
    /// Optional short user-facing subtitle for the gym equipment editor.
    public let hint: String?

    /// The one piece of equipment every location has; never gates an exercise and cannot be unchecked.
    public static let bodyweightKey = "bodyweight"

    public init(key: String, category: String, label: String, note: String? = nil, hint: String? = nil) {
        self.key = key; self.category = category; self.label = label; self.note = note; self.hint = hint
    }
}

public struct SeededLocation: Codable, Hashable, Sendable {
    /// Stable id stamped on the user's row (`Location.seedKey`); never changes when the display name does.
    public let key: String
    public let name: String
    /// Names this seed shipped with before; rows still carrying one are renamed to `name` on launch.
    public let previousNames: [String]?
    public let kind: String
    public let defaultAvailable: Bool
    /// Starting equipment for a gym that does not default to everything (`default_available: false`).
    /// A seeding template only; the gym still chooses from the whole catalog.
    public let defaultEquipment: [String]?
    public let dumbbellMaxWeight: Double?
    public let plateIncrement: Double
}

public struct MovementPattern: Codable, Hashable, Sendable {
    public let key: String
    /// "push" | "pull" | "legs" | "any" — the pattern's home day, not a restriction.
    public let dayType: String
    public let cluster: String
}

public struct SlotTemplate: Codable, Hashable, Sendable {
    public let slot: Int
    /// A movement-pattern key, or the literal "heavy_rotation".
    public let pattern: String
    public let sets: Int
    public let repLow: Int
    public let repHigh: Int
    public let restSeconds: Int
    public let band: Band
    public let warmupSets: Int
    public let superset: Bool?
    public let omitIfSlot1Pattern: String?
    public let altPatternIfSlot1Pattern: [String: String]?

    public var isSuperset: Bool { superset ?? false }
}

public struct Exercise: Codable, Hashable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let movementPattern: String
    public let requiredEquipment: [String]
    public let repSeconds: Double?
    public let measure: Measure
    public let rangeLow: Int?
    public let rangeHigh: Int?
    public let loadable: Bool
    public let dumbbellBased: Bool
    public let supersettable: Bool
    public let rankHint: Int
    public let note: String?
    public let isCustom: Bool

    public init(
        key: String, name: String, movementPattern: String, requiredEquipment: [String],
        repSeconds: Double? = nil, measure: Measure = .reps, rangeLow: Int? = nil, rangeHigh: Int? = nil,
        loadable: Bool = true, dumbbellBased: Bool = false, supersettable: Bool = false,
        rankHint: Int = 50, note: String? = nil, isCustom: Bool = false
    ) {
        self.key = key; self.name = name; self.movementPattern = movementPattern
        self.requiredEquipment = requiredEquipment; self.repSeconds = repSeconds; self.measure = measure
        self.rangeLow = rangeLow; self.rangeHigh = rangeHigh; self.loadable = loadable
        self.dumbbellBased = dumbbellBased; self.supersettable = supersettable; self.rankHint = rankHint
        self.note = note; self.isCustom = isCustom
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        name = try c.decode(String.self, forKey: .name)
        movementPattern = try c.decode(String.self, forKey: .movementPattern)
        requiredEquipment = try c.decode([String].self, forKey: .requiredEquipment)
        repSeconds = try c.decodeIfPresent(Double.self, forKey: .repSeconds)
        measure = try c.decodeIfPresent(Measure.self, forKey: .measure) ?? .reps
        rangeLow = try c.decodeIfPresent(Int.self, forKey: .rangeLow)
        rangeHigh = try c.decodeIfPresent(Int.self, forKey: .rangeHigh)
        loadable = try c.decodeIfPresent(Bool.self, forKey: .loadable) ?? true
        dumbbellBased = try c.decodeIfPresent(Bool.self, forKey: .dumbbellBased) ?? false
        supersettable = try c.decodeIfPresent(Bool.self, forKey: .supersettable) ?? false
        rankHint = try c.decodeIfPresent(Int.self, forKey: .rankHint) ?? 50
        note = try c.decodeIfPresent(String.self, forKey: .note)
        isCustom = try c.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
    }

    public var isBodyweightOnly: Bool { requiredEquipment == ["bodyweight"] }
    public var usesBarbell: Bool { requiredEquipment.contains("barbell") }
}

/// Progression increments (lb) keyed by band, from movement_patterns.json.
public struct ProgressionSteps: Codable, Hashable, Sendable {
    public let heavyUpper: Double
    public let heavyLower: Double
    public let medium: Double
    public let mediumDumbbellPerHand: Double
    public let volume: Double
    public let volumeFallback: Double
}

/// The authored reference data: exercises, patterns, templates, equipment vocabulary.
/// Immutable for the life of the process; user state lives elsewhere.
public struct Catalog: Sendable {
    public let exercises: [String: Exercise]
    public let patterns: [String: MovementPattern]
    public let slotTemplates: [DayType: [SlotTemplate]]
    public let heavyRotationDefaults: [DayType: [String]]
    public let progressionSteps: ProgressionSteps
    /// ratioTable[source][target] = multiplier (dumbbell targets are per hand).
    public let ratioTable: [String: [String: Double]]
    public let equipmentTypes: [EquipmentType]
    public let seededLocations: [SeededLocation]

    public init(
        exercises: [Exercise], patterns: [MovementPattern], slotTemplates: [DayType: [SlotTemplate]],
        heavyRotationDefaults: [DayType: [String]], progressionSteps: ProgressionSteps,
        ratioTable: [String: [String: Double]], equipmentTypes: [EquipmentType], seededLocations: [SeededLocation]
    ) {
        self.exercises = Dictionary(uniqueKeysWithValues: exercises.map { ($0.key, $0) })
        self.patterns = Dictionary(uniqueKeysWithValues: patterns.map { ($0.key, $0) })
        self.slotTemplates = slotTemplates
        self.heavyRotationDefaults = heavyRotationDefaults
        self.progressionSteps = progressionSteps
        self.ratioTable = ratioTable
        self.equipmentTypes = equipmentTypes
        self.seededLocations = seededLocations
    }

    public func exercises(withPattern pattern: String) -> [Exercise] {
        exercises.values.filter { $0.movementPattern == pattern }
    }

    public func cluster(of exercise: Exercise) -> String? {
        patterns[exercise.movementPattern]?.cluster
    }

    public func exercises(inCluster cluster: String) -> [Exercise] {
        exercises.values.filter { patterns[$0.movementPattern]?.cluster == cluster }
    }

    /// Returns a copy with user-created exercises merged in (custom keys override nothing seeded).
    public func adding(custom: [Exercise]) -> Catalog {
        var merged = exercises
        for e in custom where merged[e.key] == nil { merged[e.key] = e }
        return Catalog(
            exercises: Array(merged.values), patterns: Array(patterns.values), slotTemplates: slotTemplates,
            heavyRotationDefaults: heavyRotationDefaults, progressionSteps: progressionSteps,
            ratioTable: ratioTable, equipmentTypes: equipmentTypes, seededLocations: seededLocations
        )
    }
}
