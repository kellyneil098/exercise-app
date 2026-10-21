import Foundation

public enum RunType: String, Codable, Sendable, Hashable, CaseIterable {
    case easy, tempo, long
}

/// §6 run_plan. `peakWeeklyVolumeMi` is the non-deload volume the progression climbs; the
/// displayed week volume dips to 70% of it on deload weeks.
public struct RunPlanState: Codable, Sendable, Hashable {
    public var runsPerWeek: Int
    public var easyPaceSecPerMi: Double
    public var peakWeeklyVolumeMi: Double
    public var targetWeeklyVolumeMi: Double
    public var weekIndex: Int

    public init(runsPerWeek: Int, easyPaceSecPerMi: Double, weeklyVolumeMi: Double,
                targetWeeklyVolumeMi: Double? = nil, weekIndex: Int = 0) {
        self.runsPerWeek = max(2, min(3, runsPerWeek))
        self.easyPaceSecPerMi = easyPaceSecPerMi
        self.peakWeeklyVolumeMi = weeklyVolumeMi
        self.targetWeeklyVolumeMi = targetWeeklyVolumeMi ?? RunPlanner.roundHalf(weeklyVolumeMi * 1.5)
        self.weekIndex = weekIndex
    }

    public var isDeloadWeek: Bool { weekIndex % 4 == 3 }
    public var weeklyVolumeMi: Double {
        RunPlanner.roundHalf(isDeloadWeek ? peakWeeklyVolumeMi * 0.7 : peakWeeklyVolumeMi)
    }
}

public struct PlannedRun: Codable, Sendable, Hashable {
    public var runType: RunType
    public var targetDistanceMi: Double
    public var targetPaceSecPerMi: Double
}

public struct RunSegment: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case warmup, main, cooldown }
    public var kind: Kind
    public var distanceMi: Double?
    public var durationSec: Double?
    public var targetPaceSecPerMi: Double?
}

public struct RunPlanner: Sendable {
    public var tempoOffset: Double = -70
    public var longOffset: Double = 15
    public var warmupSeconds: Double = 5 * 60
    public var cooldownSeconds: Double = 5 * 60
    public var paceNudgeThreshold: Double = 20
    public var paceNudgeStep: Double = 10
    public var paceNudgeRuns: Int = 3

    public init() {}

    static func roundHalf(_ x: Double) -> Double { (x * 2).rounded() / 2 }

    public func pace(_ type: RunType, state: RunPlanState) -> Double {
        switch type {
        case .easy: return state.easyPaceSecPerMi
        case .tempo: return state.easyPaceSecPerMi + tempoOffset
        case .long: return state.easyPaceSecPerMi + longOffset
        }
    }

    /// The week's runs, in the order they should be done (easy, [tempo], long).
    public func week(_ state: RunPlanState) -> [PlannedRun] {
        let v = state.weeklyVolumeMi
        let split: [(RunType, Double)] = state.runsPerWeek >= 3
            ? [(.easy, 0.35), (.tempo, 0.25), (.long, 0.40)]
            : [(.easy, 0.45), (.long, 0.55)]
        return split.map { PlannedRun(runType: $0.0, targetDistanceMi: max(0.5, Self.roundHalf(v * $0.1)), targetPaceSecPerMi: pace($0.0, state: state)) }
    }

    /// §6 progression: +10%/week to the target, deload every 4th week, then hold.
    public func advanceWeek(_ state: RunPlanState) -> RunPlanState {
        var s = state
        s.weekIndex += 1
        if !state.isDeloadWeek {
            s.peakWeeklyVolumeMi = min(Self.roundHalf(state.peakWeeklyVolumeMi * 1.1), state.targetWeeklyVolumeMi)
        }
        return s
    }

    /// If actual easy pace beat target by ≥ 20 s/mi for 3 consecutive easy runs, drop easy pace 10 s/mi.
    /// `recentEasyPaces` newest first, as (actual, target).
    public func nudgedPace(_ state: RunPlanState, recentEasyPaces: [(actual: Double, target: Double)]) -> RunPlanState {
        guard recentEasyPaces.count >= paceNudgeRuns,
              recentEasyPaces.prefix(paceNudgeRuns).allSatisfy({ $0.target - $0.actual >= paceNudgeThreshold })
        else { return state }
        var s = state
        s.easyPaceSecPerMi -= paceNudgeStep
        return s
    }

    public func segments(for run: PlannedRun, state: RunPlanState) -> [RunSegment] {
        let easy = state.easyPaceSecPerMi
        return [
            RunSegment(kind: .warmup, distanceMi: nil, durationSec: warmupSeconds, targetPaceSecPerMi: easy + 60),
            RunSegment(kind: .main, distanceMi: run.targetDistanceMi, durationSec: run.targetDistanceMi * run.targetPaceSecPerMi, targetPaceSecPerMi: run.targetPaceSecPerMi),
            RunSegment(kind: .cooldown, distanceMi: nil, durationSec: cooldownSeconds, targetPaceSecPerMi: easy + 60),
        ]
    }
}

public enum Pace {
    /// 8:32 style formatting for seconds per mile.
    public static func format(_ secPerMi: Double) -> String {
        let s = Int(secPerMi.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
