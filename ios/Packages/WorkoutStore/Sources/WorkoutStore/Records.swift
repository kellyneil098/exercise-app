import Foundation
import GRDB
import WorkoutEngine

/// Every synced table shares this envelope (§9). `updatedAt` drives last-writer-wins on both ends.
public protocol SyncedRecord: Codable, Sendable, FetchableRecord, PersistableRecord, Identifiable where ID == String {
    static var tableName: String { get }
    var id: String { get }
    var userId: String { get set }
    var updatedAt: Date { get set }
    var deleted: Bool { get set }
}

extension SyncedRecord {
    public static var databaseTableName: String { tableName }
}

public struct Location: SyncedRecord {
    public static let tableName = "location"
    public var id: String
    public var userId: String
    public var name: String
    public var dumbbellMaxWeight: Double?
    public var dumbbellIncrement: Double
    public var barbellIncrement: Double
    public var sortOrder: Int
    public var updatedAt: Date
    public var deleted: Bool = false

    public init(id: String = UUIDv7.generate(), userId: String, name: String, dumbbellMaxWeight: Double? = nil,
                dumbbellIncrement: Double = 5, barbellIncrement: Double = 5, sortOrder: Int = 0, updatedAt: Date = Date()) {
        self.id = id; self.userId = userId; self.name = name; self.dumbbellMaxWeight = dumbbellMaxWeight
        self.dumbbellIncrement = dumbbellIncrement; self.barbellIncrement = barbellIncrement
        self.sortOrder = sortOrder; self.updatedAt = updatedAt
    }
}

public struct LocationEquipment: SyncedRecord {
    public static let tableName = "location_equipment"
    public var id: String
    public var userId: String
    public var locationId: String
    public var equipmentType: String
    public var updatedAt: Date
    public var deleted: Bool = false
    public init(id: String = UUIDv7.generate(), userId: String, locationId: String, equipmentType: String, updatedAt: Date = Date()) {
        self.id = id; self.userId = userId; self.locationId = locationId; self.equipmentType = equipmentType; self.updatedAt = updatedAt
    }
}

/// Per-exercise working state (§4.3 / §5). Unique on (userId, exerciseKey).
public struct ExerciseStateRow: SyncedRecord {
    public static let tableName = "exercise_state"
    public var id: String
    public var userId: String
    public var exerciseKey: String
    public var workingWeight: Double?
    public var weightSource: String
    public var consecutiveFailures: Int
    public var preRebaselineWeight: Double?
    public var setCount: Int?
    public var lastPerformedAt: Date?
    public var lastRebaselinedAt: Date?
    public var updatedAt: Date
    public var deleted: Bool = false

    public init(id: String = UUIDv7.generate(), userId: String, state: ExerciseState, updatedAt: Date = Date()) {
        self.id = id; self.userId = userId; exerciseKey = state.exerciseKey
        workingWeight = state.workingWeight; weightSource = state.weightSource.rawValue
        consecutiveFailures = state.consecutiveFailures; preRebaselineWeight = state.preRebaselineWeight
        setCount = state.setCount; lastPerformedAt = state.lastPerformedAt; lastRebaselinedAt = state.lastRebaselinedAt
        self.updatedAt = updatedAt
    }

    public var engineState: ExerciseState {
        ExerciseState(exerciseKey: exerciseKey, workingWeight: workingWeight,
                      weightSource: WeightSource(rawValue: weightSource) ?? .estimated,
                      consecutiveFailures: consecutiveFailures, lastPerformedAt: lastPerformedAt,
                      lastRebaselinedAt: lastRebaselinedAt, preRebaselineWeight: preRebaselineWeight, setCount: setCount)
    }

    public mutating func apply(_ state: ExerciseState, now: Date = Date()) {
        workingWeight = state.workingWeight; weightSource = state.weightSource.rawValue
        consecutiveFailures = state.consecutiveFailures; preRebaselineWeight = state.preRebaselineWeight
        setCount = state.setCount; lastPerformedAt = state.lastPerformedAt; lastRebaselinedAt = state.lastRebaselinedAt
        updatedAt = now
    }
}

/// One row per user: split position, heavy rotation, run target. Small enough to be a single row.
public struct SplitStateRow: SyncedRecord {
    public static let tableName = "split_state"
    public var id: String
    public var userId: String
    public var nextDayIndex: Int
    public var heavyRotationJSON: String
    public var defaultDurationMin: Int
    public var defaultLocationId: String?
    public var updatedAt: Date
    public var deleted: Bool = false

    public init(id: String = UUIDv7.generate(), userId: String, updatedAt: Date = Date()) {
        self.id = id; self.userId = userId
        nextDayIndex = 0; heavyRotationJSON = "{}"; defaultDurationMin = 60; defaultLocationId = nil; self.updatedAt = updatedAt
    }

    public var heavyRotations: [DayType: HeavyRotation] {
        get {
            let raw = (try? JSONDecoder.store.decode([String: HeavyRotation].self, from: Data(heavyRotationJSON.utf8))) ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in DayType(rawValue: k).map { ($0, v) } })
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) })
            heavyRotationJSON = (try? String(decoding: JSONEncoder.store.encode(raw), as: UTF8.self)) ?? "{}"
        }
    }
}

public struct SessionRow: SyncedRecord {
    public static let tableName = "session"
    public var id: String
    public var userId: String
    public var dayType: String
    public var locationId: String
    public var durationMin: Int
    public var startedAt: Date
    public var completedAt: Date?
    public var abandoned: Bool
    public var planJSON: String
    public var updatedAt: Date
    public var deleted: Bool = false

    public init(id: String = UUIDv7.generate(), userId: String, dayType: DayType, locationId: String, durationMin: Int,
                startedAt: Date = Date(), plan: Plan, updatedAt: Date = Date()) {
        self.id = id; self.userId = userId; self.dayType = dayType.rawValue; self.locationId = locationId
        self.durationMin = durationMin; self.startedAt = startedAt; completedAt = nil; abandoned = false
        planJSON = (try? String(decoding: JSONEncoder.store.encode(plan), as: UTF8.self)) ?? "{}"
        self.updatedAt = updatedAt
    }

    public var plan: Plan? { try? JSONDecoder.store.decode(Plan.self, from: Data(planJSON.utf8)) }
}

public struct SetLog: SyncedRecord {
    public static let tableName = "set_log"
    public var id: String
    public var userId: String
    public var sessionId: String
    public var exerciseKey: String
    public var slot: Int
    public var setIndex: Int
    public var isPadding: Bool
    public var isWarmup: Bool
    public var weight: Double?
    public var targetReps: Int
    public var repsDone: Int
    public var effort: String?
    public var completedAt: Date
    public var updatedAt: Date
    public var deleted: Bool = false

    public init(id: String = UUIDv7.generate(), userId: String, sessionId: String, exerciseKey: String, slot: Int, setIndex: Int,
                isPadding: Bool = false, isWarmup: Bool = false, weight: Double?, targetReps: Int, repsDone: Int,
                effort: EffortRating? = nil, completedAt: Date = Date()) {
        self.id = id; self.userId = userId; self.sessionId = sessionId; self.exerciseKey = exerciseKey; self.slot = slot
        self.setIndex = setIndex; self.isPadding = isPadding; self.isWarmup = isWarmup; self.weight = weight
        self.targetReps = targetReps; self.repsDone = repsDone; self.effort = effort?.rawValue
        self.completedAt = completedAt; updatedAt = completedAt
    }
}

public struct RunPlanRow: SyncedRecord {
    public static let tableName = "run_plan"
    public var id: String
    public var userId: String
    public var runsPerWeek: Int
    public var peakWeeklyVolumeMi: Double
    public var targetWeeklyVolumeMi: Double
    public var easyPaceSecPerMi: Double
    public var weekIndex: Int
    public var weekStart: Date
    public var updatedAt: Date
    public var deleted: Bool = false

    public init(id: String = UUIDv7.generate(), userId: String, state: RunPlanState, weekStart: Date, updatedAt: Date = Date()) {
        self.id = id; self.userId = userId; runsPerWeek = state.runsPerWeek; peakWeeklyVolumeMi = state.peakWeeklyVolumeMi
        targetWeeklyVolumeMi = state.targetWeeklyVolumeMi; easyPaceSecPerMi = state.easyPaceSecPerMi
        weekIndex = state.weekIndex; self.weekStart = weekStart; self.updatedAt = updatedAt
    }

    public var engineState: RunPlanState {
        RunPlanState(runsPerWeek: runsPerWeek, easyPaceSecPerMi: easyPaceSecPerMi, weeklyVolumeMi: peakWeeklyVolumeMi,
                     targetWeeklyVolumeMi: targetWeeklyVolumeMi, weekIndex: weekIndex)
    }
}

public struct RunRow: SyncedRecord {
    public static let tableName = "run"
    public var id: String
    public var userId: String
    public var runType: String
    public var targetDistanceMi: Double
    public var targetPaceSecPerMi: Double
    public var distanceMi: Double?
    public var durationSec: Int?
    public var effort: String?
    public var completedAt: Date?
    public var weekStart: Date
    public var updatedAt: Date
    public var deleted: Bool = false

    public init(id: String = UUIDv7.generate(), userId: String, planned: PlannedRun, weekStart: Date, updatedAt: Date = Date()) {
        self.id = id; self.userId = userId; runType = planned.runType.rawValue; targetDistanceMi = planned.targetDistanceMi
        targetPaceSecPerMi = planned.targetPaceSecPerMi; self.weekStart = weekStart; self.updatedAt = updatedAt
    }

    public var paceSecPerMi: Double? {
        guard let d = distanceMi, d > 0, let s = durationSec else { return nil }
        return Double(s) / d
    }
}

public struct SettingsRow: SyncedRecord {
    public static let tableName = "settings"
    public var id: String
    public var userId: String
    public var displayName: String
    public var restTimerSoundOn: Bool
    public var keepScreenAwake: Bool
    public var updatedAt: Date
    public var deleted: Bool = false
    public init(id: String = UUIDv7.generate(), userId: String, displayName: String = "", updatedAt: Date = Date()) {
        self.id = id; self.userId = userId; self.displayName = displayName; restTimerSoundOn = true; keepScreenAwake = true
        self.updatedAt = updatedAt
    }
}

public struct UserExercise: SyncedRecord {
    public static let tableName = "user_exercise"
    public var id: String
    public var userId: String
    public var key: String
    public var name: String
    public var pattern: String
    public var equipmentJSON: String
    public var loadable: Bool
    public var dumbbellBased: Bool
    public var updatedAt: Date
    public var deleted: Bool = false
    public init(id: String = UUIDv7.generate(), userId: String, key: String, name: String, pattern: String,
                equipment: [String], loadable: Bool, dumbbellBased: Bool, updatedAt: Date = Date()) {
        self.id = id; self.userId = userId; self.key = key; self.name = name; self.pattern = pattern
        equipmentJSON = (try? String(decoding: JSONEncoder.store.encode(equipment), as: UTF8.self)) ?? "[]"
        self.loadable = loadable; self.dumbbellBased = dumbbellBased; self.updatedAt = updatedAt
    }

    public var equipment: [String] { (try? JSONDecoder().decode([String].self, from: Data(equipmentJSON.utf8))) ?? [] }
}

extension JSONEncoder {
    public static let store: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer(); try c.encode(ISO8601Fractional.formatter.string(from: date))
        }
        return e
    }()
}

extension JSONDecoder {
    public static let store: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            if let date = ISO8601Fractional.formatter.date(from: s) ?? ISO8601Fractional.plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
        }
        return d
    }()
}

/// Wire timestamps keep milliseconds so two edits within one second still order under LWW.
enum ISO8601Fractional {
    static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
}

/// Local-only tables.
struct OutboxRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "outbox"
    var id: String
    var tableName: String
    var op: String
    var payload: String
    var createdAt: Date
}

struct SyncMeta: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sync_meta"
    var key: String
    var value: String
}
