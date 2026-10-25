import SwiftUI
import WorkoutEngine
import WorkoutUI

/// Technique sheet opened by tapping the pictogram on a set card: a large staged demonstration of the movement,
/// the stages as a tappable strip with one cue each, then the written set-up / execution / faults / breathing
/// cues. Reads top to bottom with hairline-ruled sections on the canvas, no nested cards.
///
/// Motion: the demonstration loops on its own; tapping a stage freezes the figure in that position (tap again to
/// resume). With Reduce Motion on it starts frozen on the first stage and the user steps through by tapping.
struct ExerciseGuideView: View {
    let guide: ExerciseGuide
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frozenStage: Int?
    private let timeline: GuideTimeline
    private let renderer: FigureRenderer

    init(block: PlanBlock) {
        self.init(guide: ExerciseGuide.for(exerciseKey: block.exerciseKey, exerciseName: block.exerciseName, pattern: block.pattern))
    }

    init(guide: ExerciseGuide) {
        self.guide = guide
        timeline = GuideTimeline(guide)
        let demo = guide.demonstration
        var r = FigureRenderer(keyframes: demo.keyframes, anchor: demo.anchor, armsXY: demo.armsXY)
        var d = FigureRenderer.Detail()
        d.joints = demo.overlays.contains(.joints)
        d.midfoot = demo.overlays.contains(.midfoot)
        d.maxScale = 2.4
        if demo.overlays.contains(.path) {
            let path = r.trace(order: guide.loopOrder)
            let xs = path.map(\.x), ys = path.map(\.y)
            if let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max(), max(x1 - x0, y1 - y0) > 2.5 { d.path = path }
        }
        r.detail = d
        renderer = r
    }

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    HStack(alignment: .center) {
                        IconButton("xmark", label: "Close") { dismiss() }
                        Spacer()
                        Overline(guide.familyName)
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(guide.exerciseName).font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(scopeLine).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                    }
                    demonstration
                    Hairline()
                    cueSection("Set up", guide.cues.setUp)
                    cueSection("Execute", guide.cues.execute)
                    cueSection("Avoid", guide.cues.avoid)
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        Glyph("wind", tint: Theme.Colors.textTertiary, width: 20)
                        Text(guide.cues.breathing).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Hairline()
                    Text("General technique guidance, not medical advice. Work within the range you control and stop if something hurts.")
                        .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, Theme.Spacing.l).padding(.top, Theme.Spacing.m).padding(.bottom, Theme.Spacing.xl)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.Colors.canvas)
        .presentationDragIndicator(.hidden)
        .onAppear { if reduceMotion, frozenStage == nil { frozenStage = 0 } }
    }

    /// Side-view figure walking the stages, with the stage strip and the active cue beneath it.
    var demonstration: some View {
        TimelineView(.animation(paused: frozenStage != nil)) { context in
            let sample = timeline.at(context.date.timeIntervalSinceReferenceDate)
            let stage = frozenStage ?? sample.stage
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Canvas(rendersAsynchronously: true) { ctx, size in
                    if let frozen = frozenStage {
                        let f = timeline.end(of: frozen, in: guide)
                        renderer.draw(in: &ctx, size: size, from: f, to: f, t: 0)
                    } else {
                        renderer.draw(in: &ctx, size: size, from: sample.from, to: sample.to, t: sample.t)
                    }
                }
                .padding(Theme.Spacing.m)
                .aspectRatio(100.0 / 68.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(Theme.Colors.card))
                .accessibilityElement()
                .accessibilityLabel("\(guide.exerciseName) demonstration, \(guide.stages.count) stages")
                .accessibilityValue(guide.stages[stage].name)
                .accessibilityAddTraits(.isImage)

                HStack(spacing: Theme.Spacing.m) {
                    ForEach(Array(guide.stages.enumerated()), id: \.offset) { i, s in
                        stageTab(i, s, active: i == stage)
                    }
                    Spacer(minLength: 0)
                    if frozenStage != nil {
                        IconButton("play.fill", label: "Resume demonstration") { frozenStage = nil }
                    }
                }
                .frame(minHeight: 44)
                .animation(Theme.Motion.quick, value: frozenStage)

                Text(guide.stages[stage].cue)
                    .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 48, alignment: .topLeading)
                    .id(stage)
                    .transition(.opacity)
                    .animation(reduceMotion ? nil : Theme.Motion.quick, value: stage)
            }
        }
    }

    /// Stage name with a 2-pt brass bar when active; tap to freeze the figure there, tap again to resume.
    func stageTab(_ i: Int, _ s: ExerciseGuide.Stage, active: Bool) -> some View {
        Button {
            Haptics.play(.swap)
            frozenStage = (frozenStage == i) ? nil : i
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text("\(i + 1)").font(Theme.Fonts.captionBold).foregroundStyle(active ? Theme.Colors.brass : Theme.Colors.textTertiary)
                    Text(s.name).font(active ? Theme.Fonts.bodyMedium : Theme.Fonts.body).lineLimit(1)
                        .foregroundStyle(active ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                }
                Capsule().fill(active ? Theme.Colors.brass : Theme.Colors.hairline).frame(height: 2)
                    .shadow(color: active ? Theme.Colors.brass.opacity(0.6) : .clear, radius: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Stage \(i + 1), \(s.name)")
        .accessibilityHint(frozenStage == i ? "Resumes the demonstration" : "Shows this position")
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    func cueSection(_ title: String, _ lines: [String]) -> some View {
        FlatSection(title) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        Circle().fill(Theme.Colors.brass).frame(width: 5, height: 5).offset(y: -3)
                        Text(line).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, Theme.Spacing.xs)
        }
    }

    /// Says plainly how specific this content is, instead of implying every exercise has its own write-up.
    var scopeLine: String {
        let family = guide.familyName.lowercased()
        switch (guide.cuesScope, guide.demonstration.motionScope) {
        case (.exercise, .exercise): return "Technique for the \(guide.exerciseName.lowercased())."
        case (.exercise, .family): return "Technique for the \(guide.exerciseName.lowercased()); the figure shows the standard \(family) movement."
        case (.family, _): return "General guidance for \(family) exercises; your setup may differ."
        }
    }
}
