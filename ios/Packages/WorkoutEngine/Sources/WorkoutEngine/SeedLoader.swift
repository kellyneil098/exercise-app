import Foundation

public enum SeedError: Error, CustomStringConvertible {
    case missingResource(String)
    case malformed(String)

    public var description: String {
        switch self {
        case .missingResource(let n): return "seed resource missing: \(n)"
        case .malformed(let m): return "seed malformed: \(m)"
        }
    }
}

/// Loads the authored seed JSON (shipped in the package bundle) into a `Catalog`.
public enum SeedLoader {
    /// Bump when the seed files change in a way the local store should re-import.
    public static let seedVersion = 3

    public static func loadBundled() throws -> Catalog {
        try load(
            exercises: try data("exercises"),
            movementPatterns: try data("movement_patterns"),
            equipmentTypes: try data("equipment_types")
        )
    }

    public static func load(exercises: Data, movementPatterns: Data, equipmentTypes: Data) throws -> Catalog {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let ex = try decoder.decode(ExercisesFile.self, from: stripComments(exercises))
        let mp = try decoder.decode(MovementPatternsFile.self, from: stripComments(movementPatterns))
        let eq = try decoder.decode(EquipmentFile.self, from: stripComments(equipmentTypes))

        var templates: [DayType: [SlotTemplate]] = [:]
        for (day, slots) in mp.slotTemplates {
            guard let d = DayType(rawValue: day) else { throw SeedError.malformed("unknown day type \(day)") }
            templates[d] = slots.sorted { $0.slot < $1.slot }
        }
        var rotations: [DayType: [String]] = [:]
        for (day, seq) in mp.heavyRotationDefaults {
            guard let d = DayType(rawValue: day) else { throw SeedError.malformed("unknown day type \(day)") }
            rotations[d] = seq
        }

        return Catalog(
            exercises: ex.exercises, patterns: mp.movementPatterns, slotTemplates: templates,
            heavyRotationDefaults: rotations, progressionSteps: mp.progressionStepsLb,
            ratioTable: mp.ratioTable, equipmentTypes: eq.equipmentTypes, seededLocations: eq.locations
        )
    }

    private static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Seed")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        else { throw SeedError.missingResource(name) }
        return try Data(contentsOf: url)
    }

    /// The seed files carry `$comment` keys for human readers. Remove any key starting with `$` so
    /// strict Codable models don't have to know about them.
    static func stripComments(_ data: Data) throws -> Data {
        let obj = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(withJSONObject: strip(obj))
    }

    private static func strip(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict where !k.hasPrefix("$") { out[k] = strip(v) }
            return out
        }
        if let arr = value as? [Any] { return arr.map(strip) }
        return value
    }

    private struct ExercisesFile: Decodable { let exercises: [Exercise] }
    private struct EquipmentFile: Decodable {
        let equipmentTypes: [EquipmentType]
        let locations: [SeededLocation]
    }
    private struct MovementPatternsFile: Decodable {
        let movementPatterns: [MovementPattern]
        let slotTemplates: [String: [SlotTemplate]]
        let heavyRotationDefaults: [String: [String]]
        let progressionStepsLb: ProgressionSteps
        let ratioTable: [String: [String: Double]]
    }
}
