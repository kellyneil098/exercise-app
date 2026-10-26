import GRDB
import SwiftUI
import WorkoutEngine
import WorkoutStore
import WorkoutUI

/// This week's runs as cards, shown inline on Home when Running is selected; logging a run writes a `RunRow`.
/// Week rollover advances the plan (§6).
/// Run accents: Piglet pink in the storybook, the classic pull-blue otherwise.
var runTint: Color { Theme.storybook ? Theme.Colors.pigletDeep : Theme.Colors.pull }
var runWash: Color { Theme.storybook ? Theme.Colors.piglet : Theme.Colors.pull }

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
                Group {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        if Theme.storybook {
                            // Pooh and Piglet tracking the Woozle, with a trail of prints walking across the page under them.
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                        Text("Off for a walk").font(Theme.Fonts.titleSmall).foregroundStyle(Theme.Colors.ink)
                                        Quip(state.isDeloadWeek ? "A lighter week, for resting and humming." : "Piglet keeps up. So will you.")
                                    }
                                    .layoutPriority(1)
                                    Spacer(minLength: Theme.Spacing.s)
                                    Illustration(.tracking, wash: Theme.Colors.piglet, washOpacity: 0.45)
                                        .frame(maxWidth: 156, maxHeight: 104)
                                }
                                WalkingFootprints(tint: Theme.Colors.pigletDeep).frame(height: 36)
                            }
                        } else {
                            HStack(spacing: Theme.Spacing.sm) {
                                Glyph("figure.run", tint: Theme.Colors.pull, width: 20)
                                Overline("This week", tint: Theme.Colors.textSecondary)
                                Spacer()
                                if state.isDeloadWeek {
                                    Text("Lighter week").font(Theme.Fonts.captionBold).foregroundStyle(Theme.Colors.pull)
                                        .padding(.horizontal, Theme.Spacing.s).frame(height: 24).background(Theme.Colors.pull.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                        Hairline()
                        HStack(alignment: .top) {
                            Stat(state.weeklyVolumeMi.formatted(), unit: "mi", label: "planned", tint: Theme.Colors.textPrimary)
                            Spacer()
                            Stat(done.reduce(0) { $0 + ($1.distanceMi ?? 0) }.formatted(.number.precision(.fractionLength(0...1))), unit: "mi", label: "run so far", tint: runTint)
                            Spacer()
                            Stat("\(done.count)", unit: "of \(runs.count)", label: "runs done")
                        }
                        if Theme.storybook {
                            Footprints(count: max(runs.count * 3, 6), progress: Double(done.count) / Double(max(1, runs.count)), tint: Theme.Colors.pigletDeep)
                                .frame(height: 26)
                                .animation(Theme.Motion.spring, value: done.count)
                        } else {
                            ProgressBar(Double(done.count) / Double(max(1, runs.count)), tint: Theme.Colors.pull)
                        }
                    }
                }
                ForEach(runs) { run in
                    RunCard(run: run, state: state, planned: plannedRun(run, state: state), onStart: { starting = run }, onLog: { logging = run })
                }
            } else {
                Group {
                    HStack(spacing: Theme.Spacing.m) {
                        if Theme.storybook {
                            Illustration(.eeyoreLying, wash: Theme.Colors.eeyore, washOpacity: 0.3).frame(width: 96, height: 48)
                            Quip("No running plan yet. Thanks for noticing.")
                        } else {
                            Glyph("figure.run", tint: Theme.Colors.textTertiary)
                            Text("No running plan yet.").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                        }
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
        Card(raised: !done, plate: !done) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.m) {
                    IconTile(done ? "checkmark" : symbol, tint: done ? Theme.Colors.brass : runWash, size: 44)
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
                                Circle().fill(Theme.storybook ? Theme.Colors.piglet : Theme.Colors.pull.opacity(0.6)).frame(width: Theme.storybook ? 8 : 6, height: Theme.storybook ? 8 : 6)
                                    .overlay(Circle().strokeBorder(Theme.Colors.ink.opacity(Theme.storybook ? 0.5 : 0), lineWidth: 1))
                                Text(segmentText(seg)).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                    .padding(.leading, Theme.Spacing.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !done {
                    HStack(spacing: Theme.Spacing.s) {
                        PillButton("Start run", icon: "play.fill", action: onStart)
                        Button(action: onLog) {
                            Image(systemName: "square.and.pencil").font(.system(size: 17, weight: .bold))
                                .frame(width: 56, height: 56)
                                .background(Theme.storybook ? Theme.Colors.paper : Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                                .inkOutline(Theme.Radius.control, opacity: 0.45)
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
                    if Theme.storybook { IconTile("square.and.pencil", tint: Theme.Colors.piglet, size: 40) } else { Glyph("square.and.pencil", tint: Theme.Colors.pull) }
                    VStack(alignment: .leading, spacing: 2) {
                        Overline("Log run")
                        Text(run.runType.capitalized).font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textPrimary)
                    }
                    Spacer()
                    if distance > 0, minutes > 0 {
                        Stat(formatPace(Double(minutes * 60) / distance), unit: "/mi", label: "pace", tint: Theme.Colors.honeyInk)
                    }
                }
                let adjusters = VStack(spacing: Theme.Spacing.m) {
                    Adjuster("\(distance.formatted()) mi", value: $distance, in: 0...50, step: 0.1)
                    Hairline()
                    Adjuster("\(minutes) min", value: $minutes.asDouble, in: 0...600)
                }
                if Theme.storybook { Card(padding: Theme.Spacing.m) { adjusters } } else { adjusters }
                HStack(spacing: Theme.Spacing.l) {
                    ForEach([EffortRating.easy, .good, .didNotFinish], id: \.rawValue) { e in
                        TextOption(e.label, selected: e == effort) { effort = e }
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
