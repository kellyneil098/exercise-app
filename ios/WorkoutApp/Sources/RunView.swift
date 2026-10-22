import GRDB
import SwiftUI
import WorkoutEngine
import WorkoutStore
import WorkoutUI

/// This week's runs as cards, shown inline on Home when Running is selected; logging a run writes a `RunRow`.
/// Week rollover advances the plan (§6).
struct RunContent: View {
    @Environment(AppModel.self) private var model
    @State private var plan: RunPlanRow?
    @State private var runs: [RunRow] = []
    @State private var logging: RunRow?
    @State private var starting: RunRow?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if let plan {
                let state = plan.engineState
                let done = runs.filter { $0.completedAt != nil }
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        HStack(spacing: Theme.Spacing.sm) {
                            IconTile("figure.run", tint: Theme.Colors.pull, size: 32)
                            Overline("This week", tint: Theme.Colors.textSecondary)
                            Spacer()
                            if state.isDeloadWeek {
                                Text("Lighter week").font(Theme.Fonts.captionBold).foregroundStyle(Theme.Colors.pull)
                                    .padding(.horizontal, Theme.Spacing.s).frame(height: 24).background(Theme.Colors.pull.opacity(0.12), in: Capsule())
                            }
                        }
                        HStack(alignment: .top) {
                            Stat(state.weeklyVolumeMi.formatted(), unit: "mi", label: "planned", tint: Theme.Colors.textPrimary)
                            Spacer()
                            Stat(done.reduce(0) { $0 + ($1.distanceMi ?? 0) }.formatted(.number.precision(.fractionLength(0...1))), unit: "mi", label: "run so far", tint: Theme.Colors.pull)
                            Spacer()
                            Stat("\(done.count)", unit: "of \(runs.count)", label: "runs done")
                        }
                        ProgressBar(Double(done.count) / Double(max(1, runs.count)), tint: Theme.Colors.pull)
                    }
                }
                ForEach(runs) { run in
                    RunCard(run: run, state: state, planned: plannedRun(run, state: state), onStart: { starting = run }, onLog: { logging = run })
                }
            } else {
                Card {
                    HStack(spacing: Theme.Spacing.m) {
                        IconTile("figure.run", tint: Theme.Colors.textTertiary, size: 44)
                        Text("No running plan yet.").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .onAppear(perform: load)
        .sheet(item: $logging) { run in LogRunSheet(run: run) { load() } }
        .fullScreenCover(item: $starting) { run in
            ActiveRunView(run: run, state: plan?.engineState, planned: plan.flatMap { plannedRun(run, state: $0.engineState) }) { load() }
        }
        .onAppear {
            // Resume a run that was in progress when the app was killed.
            if starting == nil, let id = ActiveRunClock.resumableRunID(), let run = runs.first(where: { $0.id == id && $0.completedAt == nil }) { starting = run }
        }
    }

    func plannedRun(_ r: RunRow, state: RunPlanState) -> PlannedRun? {
        model.runPlanner.week(state).first { $0.runType.rawValue == r.runType }
    }
}

struct RunCard: View {
    let run: RunRow
    let state: RunPlanState
    let planned: PlannedRun?
    let onStart: () -> Void
    let onLog: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let done = run.completedAt != nil
        Card(raised: !done) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.m) {
                    IconTile(done ? "checkmark" : symbol, tint: done ? Theme.Colors.brass : Theme.Colors.pull, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(run.runType.capitalized).font(Theme.Fonts.heading).foregroundStyle(done ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                        if done, let d = run.distanceMi, let p = run.paceSecPerMi {
                            Text("\(d.formatted()) mi at \(formatPace(p)) /mi").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                        } else {
                            Text("Target").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    Spacer()
                    HStack(alignment: .lastTextBaseline, spacing: Theme.Spacing.xs) {
                        Text(run.targetDistanceMi.formatted()).font(Theme.Fonts.numeral).foregroundStyle(done ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                        Text("mi").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                if let planned, !done {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        ForEach(Array(model.runPlanner.segments(for: planned, state: state).enumerated()), id: \.offset) { _, seg in
                            HStack(spacing: Theme.Spacing.s) {
                                Circle().fill(Theme.Colors.pull.opacity(0.6)).frame(width: 6, height: 6)
                                Text(segmentText(seg)).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                    .padding(Theme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                if !done {
                    HStack(spacing: Theme.Spacing.s) {
                        PillButton("Start run", icon: "play.fill", action: onStart)
                        Button(action: onLog) {
                            Image(systemName: "square.and.pencil").font(.system(size: 17, weight: .bold))
                                .frame(width: 56, height: 56)
                                .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(Theme.Colors.brassBorder, lineWidth: 1))
                        }
                        .foregroundStyle(Theme.Colors.textPrimary).buttonStyle(PressStyle())
                        .accessibilityLabel("Log run manually")
                    }
                }
            }
        }
    }

    var symbol: String {
        switch run.runType {
        case "long": "arrow.right.to.line"
        case "tempo", "intervals", "quality": "bolt"
        default: "figure.run"
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

extension RunContent {
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
                HStack(spacing: Theme.Spacing.m) {
                    IconTile("square.and.pencil", tint: Theme.Colors.pull, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Overline("Log run")
                        Text(run.runType.capitalized).font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textPrimary)
                    }
                    Spacer()
                    if distance > 0, minutes > 0 {
                        Stat(formatPace(Double(minutes * 60) / distance), unit: "/mi", label: "pace", tint: Theme.Colors.brass)
                    }
                }
                Card {
                    VStack(spacing: Theme.Spacing.m) {
                        Adjuster("\(distance.formatted()) mi", value: $distance, in: 0...50, step: 0.1)
                        Hairline()
                        Adjuster("\(minutes) min", value: $minutes.asDouble, in: 0...600)
                    }
                }
                HStack(spacing: Theme.Spacing.s) {
                    ForEach([EffortRating.easy, .good, .didNotFinish], id: \.rawValue) { e in
                        Chip(e.label, selected: e == effort) { effort = e }
                    }
                }
                Spacer()
                PillButton("Save run", icon: "checkmark") {
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
