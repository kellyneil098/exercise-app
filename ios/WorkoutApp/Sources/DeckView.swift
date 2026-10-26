import SwiftUI
import WorkoutEngine
import WorkoutStore
import WorkoutUI

/// The minimal workout view: one card at a time. Swipe right = set done (→ rest → next card), swipe left = skip
/// the exercise (restorable from the overview), swipe up = rate the set (weight adjusts itself from the rating).
/// Everything else lives in `DeckOverview`.
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

    /// Day, exercises done, elapsed time, undo for the last swipe, and a momentum bar.
    var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    DayTag(session.plan.dayType)
                    HStack(alignment: .lastTextBaseline, spacing: Theme.Spacing.xs) {
                        Text("\(session.completedCount)").font(Theme.Fonts.numeral).foregroundStyle(Theme.storybook ? Theme.Colors.honeyInk : Theme.Colors.textPrimary)
                            .contentTransition(.numericText())
                        Text("of \(session.deckCount)").font(Theme.storybook ? Theme.Fonts.quip : Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "timer").font(.system(size: 12, weight: .bold))
                        Text(formatElapsed(ctx.date.timeIntervalSince(session.row.startedAt))).font(Theme.Fonts.captionBold)
                    }
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.trailing, Theme.Spacing.sm)
                }
                if session.lastAction != nil {
                    IconButton("arrow.uturn.backward", label: "Undo") {
                        Haptics.play(.swap)
                        withAnimation(Theme.Motion.spring) { session.undo() }
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                IconButton("rectangle.stack", label: "Deck overview") { showOverview = true }
            }
            ProgressBar(Double(session.completedCount) / Double(max(1, session.deckCount)), tint: Theme.storybook ? Theme.Colors.honey : Theme.Colors.day(session.plan.dayType))
        }
        .padding(.horizontal, Theme.Spacing.l).padding(.top, Theme.Spacing.s).padding(.bottom, Theme.Spacing.m)
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
        .padding(.bottom, Theme.Spacing.xl + Theme.Spacing.s)
        .frame(maxHeight: .infinity)
        .animation(Theme.Motion.spring, value: session.currentStep?.id)
        .animation(Theme.Motion.spring, value: session.restEndsAt)
    }

    /// Gesture legend, colour-matched to the swipe cues the card shows mid-drag.
    @ViewBuilder var hint: some View {
        HStack(spacing: Theme.Spacing.s) {
            if session.restEndsAt != nil {
                Spacer()
                cue("arrow.left.and.right", "Swipe to skip rest", Theme.Colors.swipeSkip)
                Spacer()
            } else {
                cue("arrow.left", "Skip", Theme.Colors.swipeSkip)
                Spacer()
                cue("arrow.up", "Rate", Theme.Colors.swipeRate)
                Spacer()
                cue("arrow.right", "Done", Theme.Colors.swipeDone)
            }
        }
        .padding(.horizontal, Theme.Spacing.l).padding(.vertical, Theme.Spacing.m)
    }

    func cue(_ icon: String, _ text: String, _ tint: Color) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold))
            Text(text).font(Theme.Fonts.captionBold)
        }
        .foregroundStyle(Theme.storybook ? Theme.Colors.ink : tint)
        .padding(.horizontal, Theme.Spacing.sm).frame(height: 32)
        .background(tint.opacity(Theme.storybook ? 0.22 : 0.1), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.storybook ? Theme.Colors.ink.opacity(0.35) : tint.opacity(0.2), lineWidth: 1))
    }
}

/// The card in hand: a set card that flips to a rating card on swipe-up. Owns its own gesture state.
/// Right = done, left = skip, up = rate; the card tints and stamps the pending action as the drag grows (Tinder-style).
struct StepCard: View {
    let step: DeckStep
    let session: ActiveSession
    @State private var rating = false
    @State private var drag: CGSize = .zero
    @State private var axis: Axis?
    @State private var armed = false

    private enum Direction { case left, right, up }
    private enum SwipeAction { case done, skip, rate, back }
    private let threshold: CGFloat = 110
    /// How far an up-swipe lifts the card before rubber-banding (≈ a third of the card).
    private let liftCap: CGFloat = 150

    var body: some View {
        Group {
            if rating {
                RateCard(step: step) { e in
                    Haptics.play(.setLogged)
                    fly(.up) { session.complete(effort: e) }
                }
            } else {
                SetCard(step: step, session: session)
            }
        }
        .overlay { if let p = pending { SwipeFeedback(label: label(p.action), color: color(p.action), strength: p.strength, placement: placement(p.action)) } }
        .offset(drag)
        .rotationEffect(.degrees(Double(drag.width / 24)))
        .gesture(dragGesture)
    }

    /// What letting go now would do, and how committed the drag is (0…1 at the threshold).
    private var pending: (action: SwipeAction, strength: Double)? {
        guard let axis else { return nil }
        if axis == .horizontal, drag.width > 20 {
            return (rating ? .back : .done, min(1, Double((drag.width - 20) / (threshold - 20))))
        }
        if axis == .horizontal, drag.width < -20, !rating {
            return (.skip, min(1, Double((-drag.width - 20) / (threshold - 20))))
        }
        if axis == .vertical, drag.height < -20, !rating {
            return (.rate, min(1, Double((-drag.height - 20) / (threshold - 20))))
        }
        return nil
    }

    private func color(_ a: SwipeAction) -> Color {
        switch a {
        case .done: Theme.Colors.swipeDone
        case .skip: Theme.Colors.swipeSkip
        case .rate: Theme.Colors.swipeRate
        case .back: Theme.storybook ? Theme.Colors.honeyDeep : Theme.Colors.brass
        }
    }

    /// What the stamp says: Pooh's own words for each of the three swipes.
    private func label(_ a: SwipeAction) -> String {
        if Theme.storybook {
            switch a { case .done: return "Hooray!"; case .skip: return "Oh, bother"; case .rate: return "Think, think"; case .back: return "Back" }
        }
        switch a { case .done: return "Done"; case .skip: return "Skip"; case .rate: return "Rate"; case .back: return "Back" }
    }

    /// Done sits top-left (the card is moving right), skip top-right, rate in the middle of the card (the card is
    /// moving up, so the top edge is the first thing to leave the screen).
    private func placement(_ a: SwipeAction) -> SwipeFeedback.Placement {
        switch a { case .done, .back: .leading; case .skip: .trailing; case .rate: .center }
    }

    var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                let w = v.translation.width, h = v.translation.height
                if axis == nil { axis = abs(w) >= abs(h) ? .horizontal : .vertical }
                if axis == .horizontal {
                    drag = CGSize(width: w, height: h * 0.15)
                } else {
                    // Up follows the finger to `liftCap` (past the threshold), then rubber-bands so the card and its
                    // stamp stay on screen; down only rubber-bands.
                    let lift = -h
                    let up = lift <= liftCap ? lift : liftCap + (lift - liftCap) * 0.18
                    drag = CGSize(width: w * 0.15, height: h < 0 ? -up : h * 0.25)
                }
                let crossed = (pending?.strength ?? 0) >= 1
                if crossed != armed {
                    armed = crossed
                    if crossed { Haptics.play(.swap) }
                }
            }
            .onEnded { v in
                let endedAxis = axis
                axis = nil; armed = false
                let x = v.translation.width + (v.predictedEndTranslation.width - v.translation.width) * 0.3
                let y = v.translation.height + (v.predictedEndTranslation.height - v.translation.height) * 0.3
                if endedAxis == .horizontal, x > threshold {
                    if rating {
                        withAnimation(Theme.Motion.spring) { drag = .zero; rating = false }
                    } else {
                        Haptics.play(.setLogged)
                        fly(.right) { session.complete(effort: nil) }
                    }
                } else if endedAxis == .horizontal, x < -threshold, !rating {
                    Haptics.play(.exerciseDone)
                    fly(.left) { session.skip(step.block) }
                } else if endedAxis == .vertical, y < -threshold, !rating {
                    Haptics.play(.swap)
                    fly(.up) {
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
            drag = switch dir {
            case .right: CGSize(width: 640, height: drag.height)
            case .left: CGSize(width: -640, height: drag.height)
            case .up: CGSize(width: drag.width, height: -900)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) { action() }
    }
}

/// Mid-drag feedback shared by every swipeable card and overview row: a wash in the action's colour, deepening
/// toward the threshold, plus a stamp naming what letting go will do. `strength` is 0…1 at the threshold.
/// `compact` is the row-sized variant: a smaller stamp with its icon, level and vertically centred on the side
/// the row is moving toward, instead of tilted in a top corner. `showsStamp: false` draws only the wash, for a row
/// that puts its `SwipeStamp` in the space it reveals instead.
struct SwipeFeedback: View {
    enum Placement { case leading, trailing, top, center }
    let label: String
    var icon: String? = nil
    let color: Color
    let strength: Double
    let placement: Placement
    var compact = false
    var showsStamp = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: compact ? Theme.Radius.control : Theme.Radius.card, style: .continuous)
        let alignment: Alignment = switch placement {
        case .leading: compact ? .leading : .topLeading
        case .trailing: compact ? .trailing : .topTrailing
        case .top: .top
        case .center: .center
        }
        let tilt: Double = switch placement { case .leading: compact ? 0 : -12; case .trailing: compact ? 0 : 12; case .top, .center: 0 }
        shape.fill(color.opacity(0.08 + 0.14 * strength))
            .overlay(shape.strokeBorder(color.opacity(0.35 + 0.65 * strength), lineWidth: 1.5))
            .overlay(alignment: alignment) {
                if showsStamp {
                    SwipeStamp(label: label, icon: icon, color: color, strength: strength, compact: compact)
                        .rotationEffect(.degrees(tilt))
                        .padding(compact ? Theme.Spacing.m : Theme.Spacing.l)
                }
            }
            .allowsHitTesting(false)
    }
}

/// The outlined label inside `SwipeFeedback`: icon + uppercased action, growing and firming up toward the threshold.
struct SwipeStamp: View {
    let label: String
    var icon: String? = nil
    let color: Color
    let strength: Double
    var compact = false

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: compact ? 14 : 22, weight: .bold)) }
            Text(label.uppercased())
                .font(Theme.storybook ? .system(size: compact ? 13 : 26, weight: .black, design: .serif).italic() : .system(size: compact ? 13 : 24, weight: .bold))
                .tracking(compact ? 1.5 : (Theme.storybook ? 2 : 3))
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 10 : 14).padding(.vertical, compact ? 6 : 8)
        .background(Theme.storybook ? Theme.Colors.paper.opacity(0.9) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(color, lineWidth: compact ? 2 : (Theme.storybook ? 3.5 : 3)))
        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(color.opacity(0.6), lineWidth: compact || !Theme.storybook ? 0 : 1).padding(4))
        .scaleEffect((compact || !Theme.storybook ? 0.85 : 0.7) + (compact || !Theme.storybook ? 0.15 : 0.3) * strength)
        .opacity(0.45 + 0.55 * strength)
        .allowsHitTesting(false)
    }
}

// MARK: Cards

/// Cards fill the height the stack gives them (so the hero element can sit low enough to read from the floor)
/// and never shrink below this, which still fits an iPhone SE with the peek strips showing.
private let cardMinHeight: CGFloat = 400

private extension View {
    /// Shared card body frame: full width and height, content hanging from the top-left; each card
    /// distributes its own slack with spacers.
    func cardBody() -> some View {
        frame(maxWidth: .infinity, minHeight: cardMinHeight, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct SetCard: View {
    let step: DeckStep
    let session: ActiveSession
    @State private var showingGuide = false
    var b: PlanBlock { step.block }

    var body: some View {
        Card(raised: true, plate: true) {
            // Three groups, top to bottom: picture + name, the weight (hero, centred in the remaining space),
            // set dots pinned to the bottom edge. Spacing is tight inside a group and loose between groups.
            VStack(alignment: .leading, spacing: 0) {
                // Tapping the picture opens the technique sheet. A plain tap gesture (not a Button) so a swipe that
                // starts on the picture still reaches the card's drag gesture; a Button would swallow it.
                ExerciseArt(exerciseKey: b.exerciseKey, pattern: b.pattern)
                    .frame(maxHeight: 150)
                    .frame(maxWidth: .infinity)
                    .background {
                        if Theme.storybook {
                            WashBlob(color: tint, opacity: 0.32).scaleEffect(x: 0.92, y: 0.9)
                        } else {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(LinearGradient(colors: [tint.opacity(0.16), tint.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: "info.circle").font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textTertiary).padding(Theme.Spacing.sm)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Bee(size: 14).offset(x: 4, y: -6).storybookOnly()
                    }
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .onTapGesture { showingGuide = true }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(b.exerciseName) technique")
                    .accessibilityHint("Shows the demonstration and form cues")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { showingGuide = true }
                    .sheet(isPresented: $showingGuide) { ExerciseGuideView(block: b) }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    HStack(spacing: Theme.Spacing.s) {
                        Text(kind.uppercased()).font(Theme.Fonts.overline).tracking(1.2).foregroundStyle(Theme.storybook ? Theme.Colors.ink : tint)
                            .padding(.horizontal, Theme.Spacing.s).frame(height: 24)
                            .background(tint.opacity(Theme.storybook ? 0.4 : 0.12), in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.Colors.ink.opacity(Theme.storybook ? 0.4 : 0), lineWidth: 1))
                    }
                    Text(b.exerciseName).font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, Theme.Spacing.l)
                Spacer(minLength: Theme.Spacing.l)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if let w = step.warmup {
                        weight(w.weight)
                        Text("Warm-up \(step.index + 1) of \(b.warmups.count) · \(w.reps) reps")
                            .font(Theme.storybook ? Theme.Fonts.quip : Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                    } else {
                        if let w = b.weight { weight(w) } else {
                            Text("Bodyweight").font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary).glow(Theme.storybook ? Theme.Colors.honeyLight : tint, radius: 40, opacity: Theme.storybook ? 0.6 : 0.22)
                        }
                        Text("Set \(step.index + 1) of \(b.sets) · \(repRange)")
                            .font(Theme.storybook ? Theme.Fonts.quip : Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                Spacer(minLength: Theme.Spacing.l)
                Segments(done: session.workingSetsDone(b), total: b.sets)
            }
            .cardBody()
        }
        .contentShape(Rectangle())
    }

    /// Heavy lifts are honey; everything else takes the day's wash.
    var tint: Color { b.band == .heavy ? Theme.Colors.honey : Theme.Colors.day(session.plan.dayType) }

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
        HStack(alignment: .lastTextBaseline, spacing: Theme.Spacing.s) {
            Text(w.formatted(.number.precision(.fractionLength(0...1)))).font(Theme.Fonts.hero).heroTracking()
                .foregroundStyle(Theme.Colors.textPrimary)
                .glow(Theme.storybook ? Theme.Colors.honeyLight : tint, radius: Theme.storybook ? 36 : 40, opacity: Theme.storybook ? 0.7 : 0.22)
            Text("lb").font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

struct RateCard: View {
    let step: DeckStep
    let onRate: (EffortRating) -> Void

    var body: some View {
        Card(raised: true, plate: true) {
            VStack(alignment: .leading, spacing: 0) {
                if Theme.storybook {
                    HStack(alignment: .top, spacing: Theme.Spacing.m) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                            Text("Think, think, think.").font(Theme.Fonts.greeting).foregroundStyle(Theme.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("How was that set of \(step.block.exerciseName)?").font(Theme.Fonts.quip).foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Illustration(.poohThinking, wash: Theme.Colors.sky, washOpacity: 0.35).frame(width: 92, height: 96)
                    }
                } else {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Overline("How was that set?")
                        Text(step.block.exerciseName).font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
                Spacer(minLength: Theme.Spacing.l)
                VStack(spacing: Theme.Spacing.s) {
                    ForEach([EffortRating.easy, .good, .hard], id: \.rawValue) { e in
                        Button { onRate(e) } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                IconTile(symbol(e), tint: tint(e), size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.label).font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textPrimary)
                                    Text(note(e)).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .padding(Theme.Spacing.m)
                            .frame(maxWidth: .infinity)
                            .background(Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                            .inkOutline(Theme.Radius.control, opacity: 0.45)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                Spacer(minLength: Theme.Spacing.l)
                VStack(spacing: Theme.Spacing.m) {
                    Button("Didn't finish the set") { onRate(.didNotFinish) }
                        .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                    Aside("Swipe right to go back")
                }
                .frame(maxWidth: .infinity)
            }
            .cardBody()
        }
        .contentShape(Rectangle())
    }

    func symbol(_ e: EffortRating) -> String {
        switch e { case .easy: "wind"; case .good: "checkmark"; case .hard: "flame"; case .didNotFinish: "xmark" }
    }

    func tint(_ e: EffortRating) -> Color {
        if Theme.storybook {
            switch e { case .easy: return Theme.Colors.sky; case .good: return Theme.Colors.honey; case .hard: return Theme.Colors.carrot; case .didNotFinish: return Theme.Colors.eeyore }
        }
        switch e { case .easy: return Theme.Colors.pull; case .good: return Theme.Colors.brass; case .hard: return Theme.Colors.push; case .didNotFinish: return Theme.Colors.textTertiary }
    }

    func note(_ e: EffortRating) -> String {
        switch e { case .easy: "weight goes up faster"; case .good: "on plan"; case .hard: "hold the weight"; case .didNotFinish: "" }
    }
}

/// Countdown between sets. Auto-advances to the next card at zero; swipe it away (either side) to skip the rest.
/// Tapping the card does nothing — pause / −10 / +10 under the ring are the only tap targets. The remaining
/// time still derives from a stored end date (§7.4).
struct RestCard: View {
    let session: ActiveSession
    let endsAt: Date
    @State private var drag: CGSize = .zero
    @State private var axis: Axis?
    @State private var armed = false
    private let threshold: CGFloat = 110

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let remaining = session.restRemaining(at: ctx.date)
            let paused = session.isRestPaused
            let progress = min(1, max(0, remaining / max(1, session.restTotal)))
            Card(raised: true, plate: true) {
                // Label at the top, "up next" at the bottom, and Pooh on his balloon rising past the clock in the
                // middle of whatever is left, so the countdown sits at the card's centre rather than its top edge.
                VStack(alignment: .leading, spacing: 0) {
                    if Theme.storybook {
                        HStack {
                            Text(paused ? "A little rest · paused" : "A little rest").font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            Quip(paused ? "humming quietly" : "just a small smackerel")
                        }
                    } else {
                        Overline(paused ? "Rest · paused" : "Rest")
                    }
                    Spacer(minLength: Theme.Spacing.m)
                    if !Theme.storybook {
                        CountdownRing(progress: progress, dimmed: paused) {
                            Text(clock(remaining)).font(Theme.Fonts.display).heroTracking()
                                .foregroundStyle(paused ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                                .contentTransition(.numericText(countsDown: true))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .glow(Theme.Colors.brass, radius: 56, opacity: paused ? 0.08 : 0.28)
                        .animation(Theme.Motion.spring, value: paused)
                    } else {
                    ZStack(alignment: .leading) {
                        BeeSwarm(count: 3, beeSize: 13, speed: paused ? 0 : 1)
                            .frame(maxWidth: .infinity).frame(height: 190)
                            .opacity(0.9)
                        Illustration(.balloonHang, wash: Theme.Colors.sky, washOpacity: 0.3)
                            .frame(height: 170)
                            .offset(y: CGFloat(progress) * 44 - 22)
                            .saturation(paused ? 0.2 : 1)
                            .animation(.linear(duration: 0.5), value: progress)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(clock(remaining)).font(Theme.Fonts.hero).heroTracking()
                            .foregroundStyle(paused ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                            .contentTransition(.numericText(countsDown: true))
                            .glow(Theme.Colors.honeyLight, radius: 40, opacity: paused ? 0.2 : 0.7)
                            .padding(.leading, Theme.Spacing.xs)
                            .accessibilityLabel("Rest remaining")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .animation(Theme.Motion.spring, value: paused)
                    ProgressBar(progress, tint: paused ? Theme.Colors.eeyore : Theme.Colors.honey, height: 6)
                        .padding(.top, Theme.Spacing.s)
                    }
                    controls(paused: paused)
                        .padding(.top, Theme.Spacing.l)
                    Spacer(minLength: Theme.Spacing.m)
                    if let next = session.currentStep {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Aside("Up next").padding(.bottom, Theme.Spacing.xs)
                            Text(next.block.exerciseName).font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textPrimary)
                            Text(detail(next)).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
                .cardBody()
            }
            .overlay { if let s = strength { SwipeFeedback(label: Theme.storybook ? "Skip rest" : "Skip", color: Theme.Colors.swipeSkip, strength: s, placement: .top) } }
            .offset(drag)
            .rotationEffect(.degrees(Double(drag.width / 24)))
            .gesture(dragGesture)
            .onChange(of: remaining <= 0) { _, zero in
                if zero { Haptics.play(.warning); withAnimation(Theme.Motion.spring) { session.skipRest() } }
            }
            .onAppear { if remaining <= 0 { session.skipRest() } }
        }
    }

    /// How committed the horizontal drag is (0…1 at the threshold), either side; nil when nothing would happen.
    private var strength: Double? {
        guard axis == .horizontal, abs(drag.width) > 20 else { return nil }
        return min(1, Double((abs(drag.width) - 20) / (threshold - 20)))
    }

    /// Same feel as the set card: the card follows a horizontal drag and only rubber-bands vertically. The stamp
    /// sits top-centre for both directions so it never covers the "Rest" label in the top-left corner.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                let w = v.translation.width, h = v.translation.height
                if axis == nil { axis = abs(w) >= abs(h) ? .horizontal : .vertical }
                drag = axis == .horizontal ? CGSize(width: w, height: h * 0.15) : CGSize(width: w * 0.15, height: h * 0.25)
                let crossed = (strength ?? 0) >= 1
                if crossed != armed {
                    armed = crossed
                    if crossed { Haptics.play(.swap) }
                }
            }
            .onEnded { v in
                let endedAxis = axis
                axis = nil; armed = false
                let x = v.translation.width + (v.predictedEndTranslation.width - v.translation.width) * 0.3
                if endedAxis == .horizontal, abs(x) > threshold {
                    Haptics.play(.exerciseDone)
                    withAnimation(.easeOut(duration: 0.22)) { drag = CGSize(width: x > 0 ? 640 : -640, height: drag.height) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) { session.skipRest() }
                } else {
                    withAnimation(Theme.Motion.spring) { drag = .zero }
                }
            }
    }

    func controls(paused: Bool) -> some View {
        HStack(spacing: Theme.Spacing.l) {
            Spacer()
            TimerControl(label: "Ten seconds less") { session.adjustRest(by: -10) } content: {
                Text("−10").font(Theme.Fonts.caption).monospacedDigit()
            }
            TimerControl(label: paused ? "Resume rest" : "Pause rest", prominent: true) {
                if paused { session.resumeRest() } else { session.pauseRest() }
            } content: {
                Image(systemName: paused ? "play.fill" : "pause.fill").font(.system(size: 20, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
            }
            TimerControl(label: "Ten seconds more") { session.adjustRest(by: 10) } content: {
                Text("+10").font(Theme.Fonts.caption).monospacedDigit()
            }
            Spacer()
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

/// Round control under the rest ring. `prominent` is the pause/play button: larger, brass-washed.
struct TimerControl<Content: View>: View {
    let label: String
    var prominent = false
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    init(label: String, prominent: Bool = false, action: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.label = label; self.prominent = prominent; self.action = action; self.content = content
    }

    var body: some View {
        Button(action: action) {
            content()
                .foregroundStyle(Theme.storybook ? Theme.Colors.ink : (prominent ? Theme.Colors.brass : Theme.Colors.textPrimary))
                .frame(width: prominent ? 64 : 52, height: prominent ? 64 : 52)
                .background(Theme.storybook ? (prominent ? Theme.Colors.honey : Theme.Colors.paper) : (prominent ? Theme.Colors.brassDim : Theme.Colors.surface), in: Circle())
                .overlay(Circle().strokeBorder(Theme.storybook ? Theme.Colors.ink.opacity(prominent ? 0.75 : 0.45) : (prominent ? Theme.Colors.brass.opacity(0.4) : Theme.Colors.brassBorder),
                                               lineWidth: Theme.storybook ? Theme.Stroke.outline : 1))
                .softShadow(Theme.storybook ? (prominent ? 10 : 6) : 0, y: Theme.storybook ? 4 : 0)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

struct PeekCard: View {
    let block: PlanBlock
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Aside(block.isSupersetted ? "Superset" : (Theme.storybook ? "Next page" : "Next"))
                Text(block.exerciseName).font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
            }
            .cardBody()
        }
    }
}

/// Compact set progress for list rows: a short run of segments.
struct SetDots: View {
    let done: Int
    let total: Int
    var body: some View {
        Segments(done: done, total: total).frame(width: CGFloat(min(max(total, 1), 6)) * 14)
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
                if Theme.storybook {
                    Text(replacing.map { "Swap \($0.exerciseName)" } ?? "Add exercise").font(Theme.Fonts.title).foregroundStyle(Theme.Colors.ink)
                } else {
                    Overline(replacing.map { "Swap \($0.exerciseName)" } ?? "Add exercise")
                }
                ExerciseSearchField(text: $query)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !suggested.isEmpty {
                            ExercisePickerHeader(title: "Suggested", topPadding: Theme.Spacing.s)
                            ForEach(suggested, id: \.exercise.key) { row($0) }
                        }
                        ExercisePickerHeader(title: suggested.isEmpty ? "Exercises" : "All exercises")
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
                Image(systemName: "plus.circle").font(.system(size: 20, weight: .regular)).foregroundStyle(Theme.Colors.honeyInk)
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
        let label = e.movementPattern.replacingOccurrences(of: "_", with: " ").capitalized
        return e.isCustom ? "Custom · \(label)" : label
    }

    func row(_ c: Candidate) -> some View {
        ExercisePickerRow(name: c.exercise.name, detail: reason(c.exclusion) ?? patternLabel(c.exercise), dimmed: !c.isAvailable,
                          art: (c.exercise.key, c.exercise.movementPattern)) {
            pick(c.exercise)
        } trailing: {
            if let e = c.estimate, c.isAvailable { Text("\(e.weight.formatted()) lb").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary) }
        }
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

/// "A Very Grand Thing": Pooh at the signpost, bees and honey drops bursting, the session in honey-pot numbers,
/// and Finish in the thumb zone.
struct FinishView: View {
    let session: ActiveSession
    @Environment(AppModel.self) private var model
    @State private var shown = false

    var sets: [SetLog] { session.logs.filter { !$0.isWarmup } }
    var volume: Double { sets.reduce(0) { $0 + Double($1.repsDone) * ($1.weight ?? 0) } }
    var minutes: Int { Int(Date.now.timeIntervalSince(session.row.startedAt) / 60) }
    var name: String { model.settings?.displayName.split(separator: " ").first.map(String.init) ?? "" }

    var body: some View {
        if Theme.storybook { storybookBody } else { classicBody }
    }

    /// The original: a glowing check, the session in numbers, one line of calm affirmation, Finish in the thumb zone.
    var classicBody: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            Image(systemName: "checkmark").font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.Colors.canvas)
                .frame(width: 96, height: 96)
                .background(LinearGradient(colors: [Theme.Colors.brass, Theme.Colors.brassDeep], startPoint: .top, endPoint: .bottom), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1))
                .glow(Theme.Colors.brass, radius: 64, opacity: 0.45)
                .scaleEffect(shown ? 1 : 0.6)
                .opacity(shown ? 1 : 0)
            VStack(spacing: Theme.Spacing.s) {
                Text(name.isEmpty ? "Session complete." : "Strong session, \(name).").font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                Text("\(session.plan.dayType.label) day · \(session.row.startedAt.formatted(.dateTime.weekday(.wide)))")
                    .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
            }
            .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 12)
            Card {
                HStack(alignment: .top) {
                    Stat("\(session.completedCount)", label: session.completedCount == 1 ? "exercise" : "exercises", tint: Theme.Colors.brass)
                    Spacer()
                    Stat("\(sets.count)", label: "sets")
                    Spacer()
                    Stat(volume >= 1000 ? String(format: "%.1fk", volume / 1000) : volume.formatted(), unit: "lb", label: "volume")
                    Spacer()
                    Stat("\(minutes)", unit: "min", label: "time")
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 24)
            Spacer()
            Text("Progression is applied to everything you logged.").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
            PillButton("Finish", icon: "checkmark") { Haptics.play(.sessionDone); session.finish() }.padding(.horizontal, Theme.Spacing.l)
        }
        .padding(.bottom, Theme.Spacing.l)
        .onAppear { withAnimation(Theme.Motion.celebrate) { shown = true } }
    }

    var storybookBody: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer()
            Illustration(.signpost, wash: Theme.Colors.honey, washOpacity: 0.3)
                .frame(maxWidth: .infinity).frame(height: 190)
                .scaleEffect(shown ? 1 : 0.8)
                .opacity(shown ? 1 : 0)
            VStack(spacing: Theme.Spacing.s) {
                Text("A Very Grand Thing").font(Theme.Fonts.greeting).foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(name.isEmpty ? "Session complete." : "Strong session, \(name).").font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                Text("\(session.plan.dayType.label) day · \(session.row.startedAt.formatted(.dateTime.weekday(.wide)))")
                    .font(Theme.Fonts.quip).foregroundStyle(Theme.Colors.textSecondary)
            }
            .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 12)
            HStack(spacing: Theme.Spacing.s) {
                PotStat("\(session.completedCount)", label: session.completedCount == 1 ? "exercise" : "exercises")
                PotStat("\(sets.count)", label: "sets")
                PotStat(volume >= 1000 ? String(format: "%.1fk", volume / 1000) : volume.formatted(), unit: "lb", label: "volume")
                PotStat("\(minutes)", unit: "min", label: "time")
            }
            .padding(.horizontal, Theme.Spacing.l)
            .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 24)
            Spacer()
            Text("Progression is applied to everything you logged.").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
            PillButton("Finish", icon: "checkmark") { Haptics.play(.sessionDone); session.finish() }.padding(.horizontal, Theme.Spacing.l)
        }
        .padding(.bottom, Theme.Spacing.l)
        .overlay(alignment: .top) { HoneyBurst().frame(height: 420).padding(.top, Theme.Spacing.xxl) }
        .onAppear { withAnimation(Theme.Motion.celebrate) { shown = true } }
    }
}

/// A number on a little honey pot: the finish screen's stat tile.
struct PotStat: View {
    let value: String
    var unit: String? = nil
    let label: String
    init(_ value: String, unit: String? = nil, label: String) { self.value = value; self.unit = unit; self.label = label }
    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ZStack {
                HoneyPot(fill: 0.85, drip: true, label: nil).frame(width: 64, height: 64)
                VStack(spacing: -2) {
                    Text(value).font(.system(size: 17, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(Theme.Colors.ink)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let unit { Text(unit).font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(Theme.Colors.ink.opacity(0.8)) }
                }
                .offset(y: 9)
                .frame(width: 44)
            }
            Text(label).font(Theme.Fonts.quip).foregroundStyle(Theme.Colors.textSecondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(unit ?? "") \(label)")
    }
}

/// Stopwatch-style ring: a hairline track with the remaining fraction drawn in brass, draining clockwise from 12 o'clock.
struct CountdownRing<Label: View>: View {
    let progress: Double
    var dimmed = false
    @ViewBuilder let label: () -> Label

    var body: some View {
        ZStack {
            Circle().stroke(Theme.Colors.surface, lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(dimmed ? Theme.Colors.textTertiary : Theme.Colors.brass, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .shadow(color: dimmed ? .clear : Theme.Colors.brass.opacity(0.6), radius: 8)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)
            label()
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Rest remaining")
    }
}
