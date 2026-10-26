import SwiftUI
import WorkoutEngine
import WorkoutStore
import WorkoutUI

/// Name → gym(s) → optional lifting/running baselines. Everything else has defaults.
/// Three pages of a picture book: the doormat welcome, the balloon, and Pooh and Piglet walking off to begin.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Bindable var draft: OnboardingDraft

    var body: some View {
        Screen {
            // Scrolls (rather than squeezing) when the keyboard is up, so the heading and Continue stay reachable.
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    stepBar
                    switch draft.step {
                    case 0: nameAndGyms
                    case 1: lifting
                    default: running
                    }
                }
                .padding(.horizontal, Theme.Spacing.l).padding(.top, Theme.Spacing.m).padding(.bottom, Theme.Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if draft.step == 2, Theme.storybook {
                        Footprints(count: 9).frame(height: 28).padding(.horizontal, Theme.Spacing.xxl).padding(.bottom, Theme.Spacing.xs)
                    }
                    PillButton(draft.step == 2 ? "Begin" : "Continue", icon: draft.step == 2 ? "play.fill" : "arrow.right") { next() }
                        .disabled(draft.step == 0 && (draft.name.isEmpty || draft.selectedSeeds.isEmpty))
                }
                .padding(.horizontal, Theme.Spacing.l).padding(.top, Theme.Spacing.m).padding(.bottom, Theme.Spacing.s)
                .background(
                    LinearGradient(colors: [Theme.Colors.canvas.opacity(0), Theme.Colors.canvas, Theme.Colors.canvas],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                )
            }
        }
    }

    /// Three honeycomb cells, filled as far as you've come, and the chapter number.
    var stepBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            if Theme.storybook {
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { i in
                        HexCell().fill(i <= draft.step ? Theme.Colors.honey : Theme.Colors.paper)
                            .overlay(HexCell().stroke(Theme.Colors.ink.opacity(0.6), lineWidth: 1))
                            .frame(width: 18, height: 16)
                            .animation(Theme.Motion.spring, value: draft.step)
                    }
                }
                Spacer(minLength: Theme.Spacing.l)
                Text("Chapter \(["One", "Two", "Three"][draft.step]) of Three").font(Theme.Fonts.quip).foregroundStyle(Theme.Colors.textTertiary)
            } else {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(i <= draft.step ? Theme.Colors.brass : Theme.Colors.surface).frame(height: 4)
                        .animation(Theme.Motion.spring, value: draft.step)
                }
                Spacer(minLength: Theme.Spacing.l)
                Overline("Step \(draft.step + 1) of 3")
            }
        }
    }

    var nameAndGyms: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if Theme.storybook {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(alignment: .bottom, spacing: Theme.Spacing.m) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            Text("Hello there.").font(Theme.Fonts.greeting).foregroundStyle(Theme.Colors.textPrimary)
                            Text("In which we are introduced, and the lifting begins.")
                                .font(Theme.Fonts.quip).foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Balloon(width: 34).padding(.trailing, Theme.Spacing.s)
                    }
                    Illustration(.doormat, wash: Theme.Colors.honey, washOpacity: 0.22)
                        .frame(maxWidth: .infinity).frame(height: 104)
                        .padding(.top, Theme.Spacing.xs)
                }
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Hello.").font(Theme.Fonts.display).heroTracking().foregroundStyle(Theme.Colors.textPrimary)
                    Text("Three things, then we lift.").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            // Re-themes onboarding live; the draft lives on AppModel so nothing typed is lost when the tree rebuilds.
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Overline("Your look")
                ThemeCards()
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Overline("Your name")
                TextField("First name", text: $draft.name).font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                    .textInputAutocapitalization(.words).submitLabel(.done)
                Hairline()
            }
            VStack(alignment: .leading, spacing: 0) {
            Overline("Where do you train?").padding(.bottom, Theme.Spacing.s)
            ForEach(model.catalog.seededLocations, id: \.key) { loc in
                let on = draft.selectedSeeds.contains(loc.key)
                Button {
                    Haptics.play(.swap)
                    withAnimation(Theme.Motion.quick) { if on { draft.selectedSeeds.remove(loc.key) } else { draft.selectedSeeds.insert(loc.key) } }
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        if Theme.storybook {
                            IconTile(loc.kind == "home_gym" ? "house" : "building.2", tint: on ? Theme.Colors.honey : Theme.Colors.aged, size: 36)
                        } else {
                            Glyph(loc.kind == "home_gym" ? "house" : "building.2", tint: on ? Theme.Colors.brass : Theme.Colors.textSecondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.name).font(Theme.Fonts.bodyMedium).foregroundStyle(Theme.Colors.textPrimary)
                            Text(loc.kind == "home_gym" ? "Building gym · limited equipment" : "Commercial gym · everything available")
                                .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                        }
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 24))
                            .foregroundStyle(on ? Theme.Colors.honeyInk : Theme.Colors.textTertiary)
                    }
                    .padding(.vertical, Theme.Spacing.sm)
                    .frame(minHeight: 56)
                    .overlay(alignment: .bottom) { Hairline() }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            }
            Text("You can add gyms and edit equipment later.").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    var anchorKeys: [String] { ["barbell_bench_press", "back_squat", "deadlift", "overhead_press"].filter { model.catalog.exercises[$0] != nil } }

    var lifting: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Working weights").font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                    Text("Optional. A weight you can do for 5–8 reps. Everything else is estimated from these and corrected as you lift.").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                }
                Illustration(.balloonBoy, wash: Theme.Colors.sky, washOpacity: 0.3).frame(width: 84, height: 112).storybookOnly()
            }
            if Theme.storybook {
                Card(padding: Theme.Spacing.s) {
                    VStack(spacing: 0) {
                        ForEach(Array(anchorKeys.enumerated()), id: \.element) { i, key in
                            weightRow(key)
                            if i < anchorKeys.count - 1 { Hairline() }
                        }
                    }
                }
            } else {
                VStack(spacing: 0) {
                    Hairline()
                    ForEach(anchorKeys, id: \.self) { key in
                        weightRow(key)
                        Hairline()
                    }
                }
            }
        }
    }

    func weightRow(_ key: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            if Theme.storybook {
                HoneyPot(fill: (draft.baselines[key] ?? 0) > 0 ? 0.8 : 0, drip: false, label: nil).frame(width: 28, height: 28)
            } else {
                Glyph("scalemass", tint: (draft.baselines[key] ?? 0) > 0 ? Theme.Colors.brass : Theme.Colors.textTertiary)
            }
            Text(model.catalog.exercises[key]?.name ?? key).font(Theme.Fonts.bodyMedium).foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            TextField("—", value: Binding(get: { draft.baselines[key] }, set: { draft.baselines[key] = $0 }), format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                .font(Theme.Fonts.numeral).foregroundStyle(Theme.Colors.honeyInk)
            Text("lb").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.horizontal, Theme.Spacing.s).frame(minHeight: 56)
    }

    var running: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Running").font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                Text("A starting point. The plan adapts from here.").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
            }
            let adjusters = VStack(spacing: Theme.Spacing.m) {
                Adjuster("\(draft.runs) runs a week", value: $draft.runs.asDouble, in: 2...3)
                Hairline()
                Adjuster("Easy pace \(Int(draft.easyPace)):\(String(format: "%02d", Int((draft.easyPace * 60).truncatingRemainder(dividingBy: 60)))) /mi", value: $draft.easyPace, in: 6...16, step: 0.25)
                Hairline()
                Adjuster("\(draft.weeklyMiles.formatted()) miles this week", value: $draft.weeklyMiles, in: 2...40, step: 0.5)
            }
            if Theme.storybook { Card(padding: Theme.Spacing.m) { adjusters } } else { adjusters }
            Text("Volume grows 10% a week toward 1.5× this, with every fourth week lighter.").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
            if Theme.storybook {
                Illustration(.walkingOff, wash: Theme.Colors.leaf, washOpacity: 0.22)
                    .frame(maxWidth: .infinity).frame(height: 150)
                    .padding(.top, Theme.Spacing.s)
                Quip("“We’ll be friends forever, won’t we?” asked Piglet. “Even longer,” said Pooh.")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
        }
    }

    func next() {
        if draft.step < 2 { withAnimation(Theme.Motion.spring) { draft.step += 1 }; return }
        let uid = model.userId
        try? model.store.save(SettingsRow(userId: uid, displayName: draft.name))
        for (i, key) in draft.selectedSeeds.sorted().enumerated() {
            guard let seed = model.catalog.seededLocations.first(where: { $0.key == key }) else { continue }
            let loc = Location(userId: uid, name: seed.name, seedKey: seed.key, dumbbellMaxWeight: seed.dumbbellMaxWeight,
                               dumbbellIncrement: 5, barbellIncrement: seed.plateIncrement, sortOrder: i)
            try? model.store.save(loc)
            try? model.store.save(model.catalog.defaultEquipment(for: seed).map { LocationEquipment(userId: uid, locationId: loc.id, equipmentType: $0) })
        }
        for (key, w) in draft.baselines where w > 0 {
            try? model.store.save(ExerciseStateRow(userId: uid, state: ExerciseState(exerciseKey: key, workingWeight: w, weightSource: .measured)))
        }
        let state = RunPlanState(runsPerWeek: draft.runs, easyPaceSecPerMi: draft.easyPace * 60, weeklyVolumeMi: draft.weeklyMiles)
        try? model.store.save(RunPlanRow(userId: uid, state: state, weekStart: Date.startOfWeek))
        _ = model.splitState
    }
}

/// Onboarding's answers so far; owned by `AppModel` so a theme switch mid-onboarding keeps them.
@Observable @MainActor
final class OnboardingDraft {
    var name = ""
    var selectedSeeds: Set<String> = []
    var step = 0
    var baselines: [String: Double] = [:]
    var runs = 3
    var easyPace = 10.0
    var weeklyMiles = 6.0
}

extension Date {
    static var startOfWeek: Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)) ?? .now
    }
}
