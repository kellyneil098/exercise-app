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
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Overline("Step \(step + 1) of 3")
                switch step {
                case 0: nameAndGyms
                case 1: lifting
                default: running
                }
                Spacer()
                PillButton(step == 2 ? "Begin" : "Continue") { next() }
                    .disabled(step == 0 && (name.isEmpty || selectedSeeds.isEmpty))
            }
            .padding(Theme.Spacing.l)
        }
    }

    var nameAndGyms: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("Hello.").font(Theme.Fonts.display).foregroundStyle(Theme.Colors.textPrimary)
            TextField("Your name", text: $name).font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                .textInputAutocapitalization(.words)
            Hairline()
            Overline("Where do you train?")
            ForEach(model.catalog.seededLocations, id: \.key) { loc in
                Button {
                    if selectedSeeds.contains(loc.key) { selectedSeeds.remove(loc.key) } else { selectedSeeds.insert(loc.key) }
                } label: {
                    HStack {
                        Text(loc.name).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Image(systemName: selectedSeeds.contains(loc.key) ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.Colors.brass)
                    }
                    .padding(.vertical, 12)
                }
            }
            Text("You can add gyms and edit equipment later.").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    var anchorKeys: [String] { ["barbell_bench_press", "back_squat", "deadlift", "overhead_press"].filter { model.catalog.exercises[$0] != nil } }

    var lifting: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("Working weights").font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
            Text("Optional. A weight you can do for 5–8 reps. Everything else is estimated from these and corrected as you lift.").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
            ForEach(anchorKeys, id: \.self) { key in
                HStack {
                    Text(model.catalog.exercises[key]?.name ?? key).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    TextField("—", value: Binding(get: { baselines[key] }, set: { baselines[key] = $0 }), format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                        .font(Theme.Fonts.numeral).foregroundStyle(Theme.Colors.brass)
                    Text("lb").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                }
                Hairline()
            }
        }
    }

    var running: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("Running").font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
            Adjuster("\(runs) runs a week", value: $runs.asDouble, in: 2...3)
            Adjuster("Easy pace \(Int(easyPace)):\(String(format: "%02d", Int((easyPace * 60).truncatingRemainder(dividingBy: 60)))) /mi", value: $easyPace, in: 6...16, step: 0.25)
            Adjuster("\(weeklyMiles.formatted()) miles this week", value: $weeklyMiles, in: 2...40, step: 0.5)
            Text("Volume grows 10% a week toward 1.5× this, with every fourth week lighter.").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    func next() {
        if step < 2 { withAnimation(Theme.Motion.spring) { step += 1 }; return }
        let uid = model.userId
        try? model.store.save(SettingsRow(userId: uid, displayName: name))
        for (i, key) in selectedSeeds.sorted().enumerated() {
            guard let seed = model.catalog.seededLocations.first(where: { $0.key == key }) else { continue }
            let loc = Location(userId: uid, name: seed.name, dumbbellMaxWeight: seed.dumbbellMaxWeight,
                               dumbbellIncrement: 5, barbellIncrement: seed.plateIncrement, sortOrder: i)
            try? model.store.save(loc)
            let equipment = seed.defaultAvailable ? model.catalog.equipmentTypes.map(\.key) : ["bodyweight", "dumbbells", "bench_adjustable", "bench_flat", "cable_machine", "treadmill"]
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
