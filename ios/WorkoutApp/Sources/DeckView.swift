import SwiftUI
import WorkoutEngine
import WorkoutStore
import WorkoutUI

/// The minimal workout view: one card at a time. Swipe right = set done (→ rest → next card),
/// swipe left = rate the set (weight adjusts itself from the rating). Everything else lives in `DeckOverview`.
struct DeckView: View {
    @Bindable var session: ActiveSession
    @Environment(AppModel.self) private var model
    @State private var showOverview = false

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                header
                if session.isFinished {
                    FinishView(session: session)
                } else {
                    stack
                    hint
                }
            }
        }
        .sheet(isPresented: $showOverview) { DeckOverview(session: session) }
        #if os(iOS)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = model.settings?.keepScreenAwake ?? true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
    }

    var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                DayTag(session.plan.dayType)
                Text("\(session.completedCount) of \(session.plan.blocks.count)").font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textPrimary)
            }
            Spacer()
            Button { showOverview = true } label: {
                Image(systemName: "rectangle.stack").font(.system(size: 20, weight: .regular))
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .accessibilityLabel("Deck overview")
        }
        .padding(.horizontal, Theme.Spacing.l).padding(.vertical, Theme.Spacing.m)
    }

    // MARK: Stack

    /// Cards behind the top one are scaled about their bottom edge so a strip of each stays visible below it.
    var stack: some View {
        ZStack {
            ForEach(Array(session.upcoming(limit: 2).enumerated().reversed()), id: \.element.id) { i, b in
                PeekCard(block: b)
                    .scaleEffect(1 - CGFloat(i + 1) * 0.05, anchor: .bottom)
                    .offset(y: CGFloat(i + 1) * 18)
                    .opacity(0.7 - Double(i) * 0.25)
            }
            if let end = session.restEndsAt {
                RestCard(session: session, endsAt: end)
                    .transition(.opacity)
            } else if let step = session.currentStep {
                // Keyed by step so each card owns its drag/rating state; the old card leaves instantly
                // (it has already flown off-screen) instead of lingering through a fade.
                StepCard(step: step, session: session)
                    .id(step.id)
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.s)
        .frame(maxHeight: .infinity)
        .animation(Theme.Motion.spring, value: session.currentStep?.id)
        .animation(Theme.Motion.spring, value: session.restEndsAt)
    }

    @ViewBuilder var hint: some View {
        HStack {
            if session.restEndsAt != nil {
                Spacer(); Overline("Tap to skip rest"); Spacer()
            } else {
                Overline("← Rate"); Spacer(); Overline("Done →")
            }
        }
        .padding(.horizontal, Theme.Spacing.xl).padding(.vertical, Theme.Spacing.l)
    }
}

/// The card in hand: a set card that flips to a rating card on swipe-left. Owns its own gesture state.
struct StepCard: View {
    let step: DeckStep
    let session: ActiveSession
    @State private var rating = false
    @State private var drag: CGSize = .zero

    private enum Direction { case left, right }
    private let threshold: CGFloat = 110

    var body: some View {
        Group {
            if rating {
                RateCard(step: step) { e in
                    Haptics.play(.setLogged)
                    fly(.left) { session.complete(effort: e) }
                }
            } else {
                SetCard(step: step, session: session)
            }
        }
        .overlay(alignment: .top) { swipeLabel }
        .offset(drag)
        .rotationEffect(.degrees(Double(drag.width / 24)))
        .gesture(dragGesture)
    }

    @ViewBuilder var swipeLabel: some View {
        let strength = min(1, abs(drag.width) / threshold)
        if drag.width > 30 {
            Overline(rating ? "Back" : "Done").foregroundStyle(Theme.Colors.brass).opacity(strength).padding(.top, Theme.Spacing.m)
        } else if drag.width < -30, !rating {
            Overline("Rate").foregroundStyle(Theme.Colors.textSecondary).opacity(strength).padding(.top, Theme.Spacing.m)
        }
    }

    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in drag = CGSize(width: v.translation.width, height: v.translation.height * 0.15) }
            .onEnded { v in
                let x = v.translation.width + (v.predictedEndTranslation.width - v.translation.width) * 0.3
                if x > threshold {
                    if rating {
                        withAnimation(Theme.Motion.spring) { drag = .zero; rating = false }
                    } else {
                        Haptics.play(.setLogged)
                        fly(.right) { session.complete(effort: nil) }
                    }
                } else if x < -threshold, !rating {
                    Haptics.play(.swap)
                    fly(.left) {
                        var t = Transaction(); t.disablesAnimations = true
                        withTransaction(t) { drag = .zero; rating = true }
                    }
                } else {
                    withAnimation(Theme.Motion.spring) { drag = .zero }
                }
            }
    }

    /// Throw the card off-screen, then run `action` (which usually replaces this card entirely).
    private func fly(_ dir: Direction, then action: @escaping () -> Void) {
        withAnimation(.easeOut(duration: 0.22)) {
            drag = CGSize(width: dir == .right ? 640 : -640, height: drag.height)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) { action() }
    }
}

// MARK: Cards

private let cardMinHeight: CGFloat = 440

struct SetCard: View {
    let step: DeckStep
    let session: ActiveSession
    var b: PlanBlock { step.block }

    var body: some View {
        Card(raised: true) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ExerciseArt(exerciseKey: b.exerciseKey, pattern: b.pattern)
                    .frame(maxHeight: 150)
                    .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    Overline(kind)
                    if b.isEstimate { Overline("· est") }
                    Spacer()
                }
                .padding(.top, Theme.Spacing.s)
                Text(b.exerciseName).font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Spacing.m)
                if let w = step.warmup {
                    weight(w.weight)
                    Text("Warm-up \(step.index + 1) of \(b.warmups.count) · \(w.reps) reps")
                        .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    if let w = b.weight { weight(w) } else {
                        Text("Bodyweight").font(Theme.Fonts.numeral).foregroundStyle(Theme.Colors.textPrimary)
                    }
                    Text("Set \(step.index + 1) of \(b.sets) · \(repRange)")
                        .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: Theme.Spacing.l)
                SetDots(done: session.workingSetsDone(b), total: b.sets)
            }
            .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    var kind: String {
        if step.isWarmup { return "Warm-up" }
        if b.band == .heavy { return "Heavy" }
        if b.isSupersetted { return "Superset" }
        return b.pattern.replacingOccurrences(of: "_", with: " ")
    }

    var repRange: String {
        b.measure == .seconds ? "\(b.repLow)–\(b.repHigh) sec" : "\(b.repLow)–\(b.repHigh) reps"
    }

    func weight(_ w: Double) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(w.formatted(.number.precision(.fractionLength(0...1)))).font(Theme.Fonts.display).foregroundStyle(Theme.Colors.textPrimary)
            Text("lb").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

struct RateCard: View {
    let step: DeckStep
    let onRate: (EffortRating) -> Void

    var body: some View {
        Card(raised: true) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Overline("How was that set?")
                Text(step.block.exerciseName).font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: Theme.Spacing.m)
                ForEach([EffortRating.easy, .good, .hard], id: \.rawValue) { e in
                    Button { onRate(e) } label: {
                        HStack {
                            Text(e.label).font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            Text(note(e)).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .padding(.horizontal, Theme.Spacing.l).padding(.vertical, Theme.Spacing.m)
                        .frame(maxWidth: .infinity)
                        .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    }
                    .buttonStyle(PressStyle())
                }
                Spacer(minLength: Theme.Spacing.m)
                Button("Didn't finish the set") { onRate(.didNotFinish) }
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                Overline("Swipe right to go back").frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    func note(_ e: EffortRating) -> String {
        switch e { case .easy: "weight goes up faster"; case .good: "on plan"; case .hard: "hold the weight"; case .didNotFinish: "" }
    }
}

/// Countdown between sets. Auto-advances to the next card at zero; tap or swipe right to skip.
struct RestCard: View {
    let session: ActiveSession
    let endsAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let remaining = max(0, endsAt.timeIntervalSince(ctx.date))
            Card(raised: true) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Overline("Rest")
                    Spacer(minLength: Theme.Spacing.m)
                    CountdownRing(progress: remaining / max(1, session.restTotal)) {
                        Text(clock(remaining)).font(Theme.Fonts.display).monospacedDigit().foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    Spacer(minLength: Theme.Spacing.m)
                    if let next = session.currentStep {
                        Overline("Up next")
                        Text(next.block.exerciseName).font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textPrimary)
                        Text(detail(next)).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture { session.skipRest() }
            .gesture(DragGesture(minimumDistance: 24).onEnded { v in if v.translation.width > 80 { session.skipRest() } })
            .onChange(of: remaining <= 0) { _, zero in
                if zero { Haptics.play(.warning); withAnimation(Theme.Motion.spring) { session.skipRest() } }
            }
            .onAppear { if remaining <= 0 { session.skipRest() } }
        }
    }

    func clock(_ t: TimeInterval) -> String {
        let n = Int(t.rounded(.up))
        return n >= 60 ? String(format: "%d:%02d", n / 60, n % 60) : "\(n)"
    }

    func detail(_ s: DeckStep) -> String {
        let b = s.block
        if let w = s.warmup { return "Warm-up · \(w.weight.formatted()) lb × \(w.reps)" }
        let range = b.measure == .seconds ? "\(b.repLow)–\(b.repHigh) sec" : "\(b.repLow)–\(b.repHigh) reps"
        let load = b.weight.map { "\($0.formatted()) lb · " } ?? ""
        return "\(load)set \(s.index + 1) of \(b.sets) · \(range)"
    }
}

struct PeekCard: View {
    let block: PlanBlock
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Overline(block.isSupersetted ? "Superset" : "Next")
                Text(block.exerciseName).font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: cardMinHeight, alignment: .leading)
        }
    }
}

struct SetDots: View {
    let done: Int
    let total: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(total, 0), id: \.self) { i in
                Circle().fill(i < done ? Theme.Colors.brass : Theme.Colors.hairline).frame(width: 6, height: 6)
            }
            if done > total { Text("+\(done - total)").font(Theme.Fonts.overline).foregroundStyle(Theme.Colors.textTertiary) }
        }
    }
}

/// One picker for swap and add: a search field, the suggestions for this day/slot first, then the whole catalog.
struct ExercisePicker: View {
    let session: ActiveSession
    /// `nil` adds a new exercise to the deck.
    let replacing: PlanBlock?
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var creating = false

    var body: some View {
        let sections = session.pickerSections(replacing: replacing)
        let suggested = filtered(sections.suggested)
        let all = filtered(sections.all)
        Screen {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Overline(replacing.map { "Swap \($0.exerciseName)" } ?? "Add exercise")
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.Colors.textTertiary)
                    TextField("Search exercises", text: $query)
                        .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textPrimary)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .foregroundStyle(Theme.Colors.textTertiary).accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Theme.Colors.cardRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous).strokeBorder(Theme.Colors.hairline, lineWidth: 1))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !suggested.isEmpty {
                            Overline("Suggested").padding(.top, Theme.Spacing.s).padding(.bottom, Theme.Spacing.xs)
                            ForEach(suggested, id: \.exercise.key) { row($0) }
                        }
                        Overline(suggested.isEmpty ? "Exercises" : "All exercises").padding(.top, Theme.Spacing.l).padding(.bottom, Theme.Spacing.xs)
                        if all.isEmpty {
                            Text("No matches").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textTertiary).padding(.vertical, 12)
                        }
                        ForEach(all, id: \.exercise.key) { row($0) }
                        newExerciseRow
                    }
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .padding(Theme.Spacing.l)
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.Colors.canvas)
        .sheet(isPresented: $creating) {
            NewExerciseSheet(initialName: query) { exercise in pick(exercise) }
        }
    }

    /// Always at the end of the list, so a failed search leads straight to creating the exercise.
    var newExerciseRow: some View {
        Button { creating = true } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "plus.circle").font(.system(size: 20, weight: .regular)).foregroundStyle(Theme.Colors.brass)
                VStack(alignment: .leading, spacing: 2) {
                    Text(query.trimmingCharacters(in: .whitespaces).isEmpty ? "New exercise" : "New exercise “\(query.trimmingCharacters(in: .whitespaces))”")
                        .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textPrimary)
                    Text("Yours, synced, picked like any other").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer()
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("New exercise")
    }

    func pick(_ exercise: Exercise) {
        if let replacing { session.swap(replacing, to: exercise) } else { session.add(exercise) }
        Haptics.play(.swap); dismiss()
    }

    func filtered(_ c: [Candidate]) -> [Candidate] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return c }
        return c.filter { $0.exercise.name.localizedCaseInsensitiveContains(q) || patternLabel($0.exercise).localizedCaseInsensitiveContains(q) }
    }

    func patternLabel(_ e: Exercise) -> String {
        e.movementPattern.replacingOccurrences(of: "_", with: " ").capitalized
    }

    func row(_ c: Candidate) -> some View {
        Button { pick(c.exercise) } label: {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.exercise.name).font(Theme.Fonts.body).foregroundStyle(c.isAvailable ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        Text(reason(c.exclusion) ?? patternLabel(c.exercise)).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                    }
                    Spacer()
                    if let e = c.estimate, c.isAvailable { Text("\(e.weight.formatted()) lb").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary) }
                }
                .padding(.vertical, 12)
                Hairline()
            }
        }
        .buttonStyle(PressStyle())
        .disabled(!c.isAvailable)
    }

    func reason(_ e: Exclusion?) -> String? {
        switch e {
        case nil: nil
        case .missingEquipment(let eq): "Needs \(eq.joined(separator: ", ").replacingOccurrences(of: "_", with: " "))"
        case .overDumbbellMax(let needed, let max): "Needs \(needed.formatted()) lb dumbbells, rack tops out at \(max.formatted())"
        case .notLoadableForHeavySlot: "Can't be loaded for the heavy slot"
        }
    }
}

struct FinishView: View {
    let session: ActiveSession
    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            Text("\(session.completedCount)").font(Theme.Fonts.display).foregroundStyle(Theme.Colors.textPrimary)
            Text(session.completedCount == 1 ? "exercise done" : "exercises done").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            PillButton("Finish") { Haptics.play(.sessionDone); session.finish() }.padding(.horizontal, Theme.Spacing.l)
        }
        .padding(.bottom, Theme.Spacing.xxl)
    }
}

/// Stopwatch-style ring: a hairline track with the remaining fraction drawn in brass, draining clockwise from 12 o'clock.
struct CountdownRing<Label: View>: View {
    let progress: Double
    @ViewBuilder let label: () -> Label

    var body: some View {
        ZStack {
            Circle().stroke(Theme.Colors.hairline, lineWidth: 6)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(Theme.Colors.brass, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)
            label()
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Rest remaining")
    }
}
