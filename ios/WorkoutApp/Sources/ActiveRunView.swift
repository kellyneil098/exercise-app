import SwiftUI
import WorkoutEngine
import WorkoutStore
import WorkoutUI

/// Wall-clock based run timer that survives backgrounding and relaunch: only the start instant and any paused
/// time are stored, so elapsed is always derived.
enum ActiveRunClock {
    private static let runKey = "activeRun.id", startKey = "activeRun.startedAt", pausedKey = "activeRun.pausedSeconds", pauseStartKey = "activeRun.pauseStartedAt"

    static func start(_ id: String) {
        let d = UserDefaults.standard
        guard d.string(forKey: runKey) != id else { return }
        d.set(id, forKey: runKey); d.set(Date(), forKey: startKey); d.set(0.0, forKey: pausedKey); d.removeObject(forKey: pauseStartKey)
    }
    static func resumableRunID() -> String? { UserDefaults.standard.string(forKey: runKey) }
    static var isPaused: Bool { UserDefaults.standard.object(forKey: pauseStartKey) != nil }
    static func pause() { if !isPaused { UserDefaults.standard.set(Date(), forKey: pauseStartKey) } }
    static func resume() {
        let d = UserDefaults.standard
        if let p = d.object(forKey: pauseStartKey) as? Date { d.set(d.double(forKey: pausedKey) + Date().timeIntervalSince(p), forKey: pausedKey) }
        d.removeObject(forKey: pauseStartKey)
    }
    static func elapsed(at now: Date = Date()) -> TimeInterval {
        let d = UserDefaults.standard
        guard let start = d.object(forKey: startKey) as? Date else { return 0 }
        let pausedNow = (d.object(forKey: pauseStartKey) as? Date).map { now.timeIntervalSince($0) } ?? 0
        return max(0, now.timeIntervalSince(start) - d.double(forKey: pausedKey) - pausedNow)
    }
    static func clear() {
        let d = UserDefaults.standard
        for k in [runKey, startKey, pausedKey, pauseStartKey] { d.removeObject(forKey: k) }
    }
}

/// The run in progress: one big elapsed number, the target underneath, the segments to follow. Pause / Finish
/// only. Finishing asks for the distance (prefilled with the target), derives pace from the clock, and saves.
struct ActiveRunView: View {
    let run: RunRow
    let state: RunPlanState?
    let planned: PlannedRun?
    let onDone: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var paused = ActiveRunClock.isPaused
    @State private var finishing = false
    @State private var confirmDiscard = false
    @State private var distance: Double = 0
    @State private var effort: EffortRating = .good

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack {
                    Overline(run.runType.capitalized)
                    Spacer()
                    Button { confirmDiscard = true } label: { Image(systemName: "xmark") }
                        .foregroundStyle(Theme.Colors.textSecondary).accessibilityLabel("Discard run")
                }
                if finishing { finish } else { live }
            }
            .padding(Theme.Spacing.l)
        }
        .onAppear { ActiveRunClock.start(run.id); paused = ActiveRunClock.isPaused }
        #if os(iOS)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
        .alert("Discard this run?", isPresented: $confirmDiscard) {
            Button("Discard", role: .destructive) { ActiveRunClock.clear(); dismiss() }
            Button("Keep going", role: .cancel) {}
        }
    }

    // MARK: Live

    var live: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let t = ActiveRunClock.elapsed(at: ctx.date)
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(formatElapsed(t)).font(Theme.Fonts.display).foregroundStyle(paused ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                        .contentTransition(.numericText())
                    Text("\(run.targetDistanceMi.formatted()) mi @ \(formatPace(run.targetPaceSecPerMi)) · ~\(formatElapsed(run.targetDistanceMi * run.targetPaceSecPerMi))")
                        .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            if let planned, let state {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Overline("Segments")
                        ForEach(Array(model.runPlanner.segments(for: planned, state: state).enumerated()), id: \.offset) { _, seg in
                            Text(segmentText(seg)).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textPrimary)
                        }
                    }
                }
            }
            Spacer()
            HStack(spacing: Theme.Spacing.s) {
                PillButton(paused ? "Resume" : "Pause", style: .quiet) {
                    if paused { ActiveRunClock.resume() } else { ActiveRunClock.pause() }
                    paused.toggle(); Haptics.play(.setLogged)
                }
                PillButton("Finish") {
                    if !paused { ActiveRunClock.pause(); paused = true }
                    distance = run.targetDistanceMi
                    withAnimation(Theme.Motion.quick) { finishing = true }
                }
            }
        }
    }

    // MARK: Finish

    var finish: some View {
        let seconds = Int(ActiveRunClock.elapsed().rounded())
        return VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text(formatElapsed(TimeInterval(seconds))).font(Theme.Fonts.display).foregroundStyle(Theme.Colors.textPrimary)
            Adjuster("\(distance.formatted()) mi", value: $distance, in: 0...50, step: 0.1)
            if distance > 0, seconds > 0 {
                Text(formatPace(Double(seconds) / distance) + " /mi").font(Theme.Fonts.numeral).foregroundStyle(Theme.Colors.brass)
            }
            HStack(spacing: Theme.Spacing.s) {
                ForEach([EffortRating.easy, .good, .didNotFinish], id: \.rawValue) { e in
                    Chip(e.label, selected: e == effort) { effort = e }
                }
            }
            Spacer()
            HStack(spacing: Theme.Spacing.s) {
                PillButton("Back", style: .quiet) { withAnimation(Theme.Motion.quick) { finishing = false } }
                PillButton("Save") {
                    var r = run
                    r.distanceMi = distance; r.durationSec = seconds; r.effort = effort.rawValue; r.completedAt = Date()
                    try? model.store.save(r)
                    ActiveRunClock.clear()
                    Haptics.play(.sessionDone)
                    onDone(); dismiss()
                }
                .disabled(distance <= 0 || seconds <= 0)
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

func formatElapsed(_ t: TimeInterval) -> String {
    let s = Int(t.rounded())
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}
