import SwiftUI
import WorkoutEngine
import WorkoutStore
import WorkoutUI

/// Name → gym(s) → optional lifting/running baselines. Everything else has defaults.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var selectedSeeds: Set<String> = []
    @State private var step = 0
    @State private var baselines: [String: Double] = [:]
    @State private var runs = 3
    @State private var easyPace = 10.0
    @State private var weeklyMiles = 6.0

    var body: some View {
        Screen {
            // Scrolls (rather than squeezing) when the keyboard is up, so the heading and Continue stay reachable.
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    stepBar
                    switch step {
                    case 0: nameAndGyms
                    case 1: lifting
                    default: running
                    }
                }
                .padding(.horizontal, Theme.Spacing.l).padding(.top, Theme.Spacing.m).padding(.bottom, Theme.Spacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                PillButton(step == 2 ? "Begin" : "Continue", icon: step == 2 ? "play.fill" : "arrow.right") { next() }
                    .disabled(step == 0 && (name.isEmpty || selectedSeeds.isEmpty))
                    .padding(.horizontal, Theme.Spacing.l).padding(.top, Theme.Spacing.m).padding(.bottom, Theme.Spacing.s)
                    .background(
                        LinearGradient(colors: [Theme.Colors.canvas.opacity(0), Theme.Colors.canvas, Theme.Colors.canvas],
                                       startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                    )
            }
        }
    }

    /// Three segments, the current one brass: where you are without a word of explanation.
    var stepBar: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(i <= step ? Theme.Colors.brass : Theme.Colors.surface).frame(height: 4)
                    .animation(Theme.Motion.spring, value: step)
            }
            Spacer(minLength: Theme.Spacing.l)
            Overline("Step \(step + 1) of 3")
        }
    }

    var nameAndGyms: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Hello.").font(Theme.Fonts.display).heroTracking().foregroundStyle(Theme.Colors.textPrimary)
                Text("Two things, then we lift.").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Overline("Your name")
                TextField("First name", text: $name).font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                    .textInputAutocapitalization(.words).submitLabel(.done)
                Hairline()
            }
            VStack(alignment: .leading, spacing: 0) {
            Overline("Where do you train?").padding(.bottom, Theme.Spacing.s)
            ForEach(model.catalog.seededLocations, id: \.key) { loc in
                let on = selectedSeeds.contains(loc.key)
                Button {
                    Haptics.play(.swap)
                    withAnimation(Theme.Motion.quick) { if on { selectedSeeds.remove(loc.key) } else { selectedSeeds.insert(loc.key) } }
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Glyph(loc.kind == "home_gym" ? "house" : "building.2", tint: on ? Theme.Colors.brass : Theme.Colors.textSecondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.name).font(Theme.Fonts.bodyMedium).foregroundStyle(Theme.Colors.textPrimary)
                            Text(loc.kind == "home_gym" ? "Building gym · limited equipment" : "Commercial gym · everything available")
                                .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                        }
                        Spacer()
                        Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 24))
                            .foregroundStyle(on ? Theme.Colors.brass : Theme.Colors.textTertiary)
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
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Working weights").font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                Text("Optional. A weight you can do for 5–8 reps. Everything else is estimated from these and corrected as you lift.").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
            }
            Group {
                VStack(spacing: 0) {
                    Hairline()
                    ForEach(Array(anchorKeys.enumerated()), id: \.element) { i, key in
                        HStack(spacing: Theme.Spacing.m) {
                            Glyph("scalemass", tint: (baselines[key] ?? 0) > 0 ? Theme.Colors.brass : Theme.Colors.textTertiary)
                            Text(model.catalog.exercises[key]?.name ?? key).font(Theme.Fonts.bodyMedium).foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            TextField("—", value: Binding(get: { baselines[key] }, set: { baselines[key] = $0 }), format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                                .font(Theme.Fonts.numeral).foregroundStyle(Theme.Colors.brass)
                            Text("lb").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .padding(.horizontal, Theme.Spacing.s).frame(minHeight: 56)
                        Hairline()
                    }
                }
            }
        }
    }

    var running: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Running").font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                Text("A starting point. The plan adapts from here.").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
            }
            Group {
                VStack(spacing: Theme.Spacing.m) {
                    Adjuster("\(runs) runs a week", value: $runs.asDouble, in: 2...3)
                    Hairline()
                    Adjuster("Easy pace \(Int(easyPace)):\(String(format: "%02d", Int((easyPace * 60).truncatingRemainder(dividingBy: 60)))) /mi", value: $easyPace, in: 6...16, step: 0.25)
                    Hairline()
                    Adjuster("\(weeklyMiles.formatted()) miles this week", value: $weeklyMiles, in: 2...40, step: 0.5)
                }
            }
            Text("Volume grows 10% a week toward 1.5× this, with every fourth week lighter.").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    func next() {
        if step < 2 { withAnimation(Theme.Motion.spring) { step += 1 }; return }
        let uid = model.userId
        try? model.store.save(SettingsRow(userId: uid, displayName: name))
        for (i, key) in selectedSeeds.sorted().enumerated() {
            guard let seed = model.catalog.seededLocations.first(where: { $0.key == key }) else { continue }
            let loc = Location(userId: uid, name: seed.name, seedKey: seed.key, dumbbellMaxWeight: seed.dumbbellMaxWeight,
                               dumbbellIncrement: 5, barbellIncrement: seed.plateIncrement, sortOrder: i)
            try? model.store.save(loc)
            let equipment = seed.defaultAvailable ? model.catalog.equipmentTypes.map(\.key) : AppModel.homeGymEquipment
            try? model.store.save(equipment.map { LocationEquipment(userId: uid, locationId: loc.id, equipmentType: $0) })
        }
        for (key, w) in baselines where w > 0 {
            try? model.store.save(ExerciseStateRow(userId: uid, state: ExerciseState(exerciseKey: key, workingWeight: w, weightSource: .measured)))
        }
        let state = RunPlanState(runsPerWeek: runs, easyPaceSecPerMi: easyPace * 60, weeklyVolumeMi: weeklyMiles)
        try? model.store.save(RunPlanRow(userId: uid, state: state, weekStart: Date.startOfWeek))
        _ = model.splitState
    }
}

extension Date {
    static var startOfWeek: Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)) ?? .now
    }
}
