import GRDB
import SwiftUI
import WorkoutEngine
import WorkoutStore
import WorkoutUI

/// This week's runs as cards; logging a run writes a `RunRow`. Week rollover advances the plan (§6).
struct RunView: View {
    @Environment(AppModel.self) private var model
    @State private var plan: RunPlanRow?
    @State private var runs: [RunRow] = []
    @State private var logging: RunRow?

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Overline("This week")
                    if let plan {
                        let state = plan.engineState
                        weekHeader(state)
                        ForEach(runs) { run in
                            RunCard(run: run, state: state, planned: plannedRun(run, state: state), onLog: { logging = run })
                        }
                    } else {
                        Text("No running plan yet.").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .padding(Theme.Spacing.l)
            }
        }
        .presentationBackground(Theme.Colors.canvas)
        .onAppear(perform: load)
        .sheet(item: $logging) { run in LogRunSheet(run: run) { load() } }
    }

    @ViewBuilder func weekHeader(_ state: RunPlanState) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(state.weeklyVolumeMi.formatted()).font(Theme.Fonts.display).foregroundStyle(Theme.Colors.textPrimary)
            Text("mi").font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textSecondary)
        }
        if state.isDeloadWeek { Text("Lighter week.").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary) }
    }

    func plannedRun(_ r: RunRow, state: RunPlanState) -> PlannedRun? {
        model.runPlanner.week(state).first { $0.runType.rawValue == r.runType }
    }
}

struct RunCard: View {
    let run: RunRow
    let state: RunPlanState
    let planned: PlannedRun?
    let onLog: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
                            Card(raised: run.completedAt == nil) {
                                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                                    HStack {
                                        Overline(run.runType.capitalized)
                                        Spacer()
                                        if run.completedAt != nil { Image(systemName: "checkmark").foregroundStyle(Theme.Colors.brass) }
                                    }
                                    HStack(alignment: .lastTextBaseline) {
                                        Text("\(run.targetDistanceMi.formatted()) mi").font(Theme.Fonts.numeral).foregroundStyle(Theme.Colors.textPrimary)
                                        Text("@ \(formatPace(run.targetPaceSecPerMi))").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                                    }
                                    if let planned {
                                        ForEach(Array(model.runPlanner.segments(for: planned, state: state).enumerated()), id: \.offset) { _, seg in
                                            Text(segmentText(seg)).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                                        }
                                    }
                                    if run.completedAt == nil {
                                        PillButton("Log run", style: .quiet) { onLog() }
                                    } else if let d = run.distanceMi, let p = run.paceSecPerMi {
                                        Text("\(d.formatted()) mi at \(formatPace(p))").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                                    }
                                }
                            }
    }

    func segmentText(_ s: RunSegment) -> String {
        var parts = [s.kind.rawValue.capitalized]
        if let d = s.distanceMi { parts.append("\(d.formatted()) mi") }
        if let t = s.durationSec { parts.append("\(Int(t / 60)) min") }
        if let p = s.targetPaceSecPerMi { parts.append("@ \(formatPace(p))") }
        return parts.joined(separator: " · ")
    }

}

extension RunView {
    /// Ensure the plan row is on the current week, then ensure this week's runs exist.
    func load() {
        let uid = model.userId
        guard var row = try? model.store.db.read({ try RunPlanRow.filter(Column("userId") == uid && Column("deleted") == false).fetchOne($0) }) else { return }
        let weekStart = Date.startOfWeek
        var state = row.engineState
        var changed = false
        while row.weekStart < weekStart.addingTimeInterval(-1) {
            state = model.runPlanner.advanceWeek(state)
            row.weekStart = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: row.weekStart) ?? weekStart
            changed = true
        }
        if changed {
            row = RunPlanRow(id: row.id, userId: uid, state: state, weekStart: row.weekStart)
            try? model.store.save(row)
        }
        var weekRuns = (try? model.store.db.read {
            try RunRow.filter(Column("userId") == uid && Column("deleted") == false && Column("weekStart") >= row.weekStart).order(Column("id")).fetchAll($0)
        }) ?? []
        if weekRuns.isEmpty {
            weekRuns = model.runPlanner.week(state).map { RunRow(userId: uid, planned: $0, weekStart: row.weekStart) }
            try? model.store.save(weekRuns)
        }
        plan = row
        runs = weekRuns
    }
}

func formatPace(_ secPerMi: Double) -> String {
    let s = Int(secPerMi.rounded())
    return "\(s / 60):\(String(format: "%02d", s % 60))"
}

struct LogRunSheet: View {
    let run: RunRow
    let onDone: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var distance: Double = 0
    @State private var minutes: Int = 0
    @State private var effort: EffortRating = .good

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Overline("Log \(run.runType)")
                Adjuster("\(distance.formatted()) mi", value: $distance, in: 0...50, step: 0.1)
                Adjuster("\(minutes) min", value: $minutes.asDouble, in: 0...600)
                if distance > 0, minutes > 0 {
                    Text(formatPace(Double(minutes * 60) / distance) + " /mi").font(Theme.Fonts.numeral).foregroundStyle(Theme.Colors.brass)
                }
                HStack(spacing: Theme.Spacing.s) {
                    ForEach([EffortRating.easy, .good, .didNotFinish], id: \.rawValue) { e in
                        Chip(e.label, selected: e == effort) { effort = e }
                    }
                }
                Spacer()
                PillButton("Save") {
                    var r = run
                    r.distanceMi = distance; r.durationSec = minutes * 60; r.effort = effort.rawValue; r.completedAt = Date()
                    try? model.store.save(r)
                    Haptics.play(.sessionDone)
                    onDone(); dismiss()
                }
                .disabled(distance <= 0 || minutes <= 0)
            }
            .padding(Theme.Spacing.l)
        }
        .presentationDetents([.medium])
        .presentationBackground(Theme.Colors.canvas)
        .onAppear { distance = run.targetDistanceMi; minutes = Int(run.targetDistanceMi * run.targetPaceSecPerMi / 60) }
    }
}
