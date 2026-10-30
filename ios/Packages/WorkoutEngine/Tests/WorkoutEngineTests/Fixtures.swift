import Foundation
@testable import WorkoutEngine

enum Fixtures {
    static let catalog: Catalog = try! SeedLoader.loadBundled()

    static func inventory(_ key: String) -> LocationInventory {
        let loc = catalog.seededLocations.first { $0.key == key }!
        let available: Set<String>
        switch key {
        case "building_gym":
            available = ["dumbbells", "bench_flat", "bench_adjustable", "cable_machine", "treadmill", "bodyweight"]
        default:
            available = Set(catalog.equipmentTypes.map(\.key))
        }
        return LocationInventory(locationKey: key, name: loc.name, available: available,
                                 dumbbellMaxWeight: loc.dumbbellMaxWeight ?? (key == "building_gym" ? 50 : nil), plateIncrement: loc.plateIncrement)
    }

    static let commercial = inventory("crunch_union_square")
    static let building = inventory("building_gym")

    static func rotation(_ day: DayType, position: Int = 0) -> HeavyRotation {
        HeavyRotation(sequence: catalog.heavyRotationDefaults[day]!, position: position)
    }

    static let baseline: [String: ExerciseState] = [
        "barbell_bench_press": ExerciseState(exerciseKey: "barbell_bench_press", workingWeight: 185, weightSource: .measured),
        "back_squat": ExerciseState(exerciseKey: "back_squat", workingWeight: 225, weightSource: .measured),
        "deadlift": ExerciseState(exerciseKey: "deadlift", workingWeight: 275, weightSource: .measured),
        "overhead_press": ExerciseState(exerciseKey: "overhead_press", workingWeight: 115, weightSource: .measured),
        "barbell_row": ExerciseState(exerciseKey: "barbell_row", workingWeight: 155, weightSource: .measured),
    ]
}

extension Plan {
    /// Human-readable rendering for snapshot files.
    var rendered: String {
        var lines = ["\(dayType.rawValue) \(durationMinutes)min @\(locationKey)  est \(Int(estimatedSeconds / 60))min"]
        for b in blocks {
            if b.isCooldown {
                lines.append("  \(b.slot). \(b.exerciseName) [cooldown] \(Int(b.estimatedSeconds / 60))min")
                continue
            }
            var s = "  \(b.slot). \(b.exerciseName) [\(b.pattern)/\(b.band.rawValue)] \(b.sets)x\(b.repLow)-\(b.repHigh)\(b.measure == .seconds ? "s" : "")"
            if let w = b.weight { s += " @\(Int(w))\(b.weightSource == .measured ? "" : "~")" }
            if !b.warmups.isEmpty { s += " wu:" + b.warmups.map { "\(Int($0.weight))x\($0.reps)" }.joined(separator: ",") }
            if let h = host(of: b) { s += " ⤷ superset w/ \(h.exerciseName)" }
            lines.append(s)
        }
        return lines.joined(separator: "\n")
    }
}
