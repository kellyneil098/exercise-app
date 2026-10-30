import SwiftUI
import WorkoutEngine
import WorkoutStore
import WorkoutUI

/// The zoomed-out deck: the whole workout at once. Drag to reorder; swipe a row left to delete it, right to swap
/// it; tap a row to edit weight / sets / reps or undo a set; `+` adds an exercise. Exercises skipped in the deck
/// collect under "Skipped" and deleted ones under "Deleted" — both swipe right to come back, so nothing is lost
/// for the session. Ending the workout lives here.
struct DeckOverview: View {
    @Bindable var session: ActiveSession
    /// Shown full-screen between Home and the deck: confirm the exercises, then Start workout.
    var confirming = false
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: UUID?
    @State private var picker: PickerMode?
    @State private var confirmEnd = false

    enum PickerMode: Identifiable {
        case add, swap(PlanBlock)
        var id: String { switch self { case .add: "add"; case .swap(let b): b.id.uuidString } }
        var block: PlanBlock? { if case .swap(let b) = self { b } else { nil } }
    }

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                        Illustration(.poohWithPot, wash: Theme.Colors.day(session.plan.dayType), washOpacity: 0.32)
                            .frame(width: 44, height: 68)
                            .storybookOnly()
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            if Theme.storybook {
                                Text(confirming ? "Today's plan" : "The deck").font(Theme.Fonts.titleSmall).foregroundStyle(Theme.Colors.textPrimary)
                            } else {
                                Overline(confirming ? "Today's plan" : "Deck")
                            }
                            HStack(alignment: .lastTextBaseline, spacing: Theme.Spacing.xs) {
                                Text("\(session.remainingCount)").font(Theme.Fonts.numeral).foregroundStyle(Theme.storybook ? Theme.Colors.honeyInk : Theme.Colors.textPrimary)
                                Text("\(confirming ? "exercises" : "left") · ~\(remainingMinutes) min").font(Theme.storybook ? Theme.Fonts.quip : Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                        Spacer()
                        IconButton("plus", label: "Add exercise", tint: Theme.storybook ? Theme.Colors.ink : Theme.Colors.brass) { picker = .add }
                        if confirming {
                            // This screen replaces Home at the root (not pushed, not a sheet), so it closes the way the
                            // live run does: an X in the top corner. Nothing is logged yet, so no confirmation.
                            IconButton("xmark", label: "Back to Home", tint: Theme.Colors.textSecondary) { session.cancel() }
                        } else {
                            Button { dismiss() } label: {
                                Text("Done").font(Theme.Fonts.captionBold).foregroundStyle(Theme.storybook ? Theme.Colors.ink : Theme.Colors.canvas)
                                    .padding(.horizontal, Theme.Spacing.m).frame(height: 44)
                                    .background(Theme.Colors.brass, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Theme.Colors.ink.opacity(Theme.storybook ? 0.7 : 0), lineWidth: Theme.Stroke.outline))
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                    if !confirming {
                        ProgressBar(Double(session.completedCount) / Double(max(1, session.deckCount)), tint: Theme.Colors.day(session.plan.dayType))
                    }
                }
                .padding(.horizontal, Theme.Spacing.l).padding(.top, Theme.Spacing.l).padding(.bottom, Theme.Spacing.m)

                List {
                    ForEach(Array(session.activeBlocks.enumerated()), id: \.element.id) { i, b in
                        SwipeRow(leading: .swap, trailing: .delete, onLeading: { beginSwap(b) }, onTrailing: { delete(b) }) {
                            row(b, index: i)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Theme.Colors.hairline)
                        .listRowInsets(rowInsets)
                    }
                    .onMove { session.move(fromOffsets: $0, toOffset: $1) }

                    if !session.skippedBlocks.isEmpty {
                        sectionHeader("Skipped", hint: "tap or swipe right to bring back")
                        ForEach(session.skippedBlocks) { b in
                            SwipeRow(leading: .restore, trailing: .delete, onLeading: { restore(b) }, onTrailing: { delete(b) }) {
                                skippedRow(b)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Theme.Colors.hairline)
                            .listRowInsets(rowInsets)
                        }
                    }

                    if !session.deletedBlocks.isEmpty {
                        sectionHeader("Deleted", hint: "swipe right to bring back")
                        ForEach(session.deletedBlocks) { b in
                            SwipeRow(leading: .restore, onLeading: { restore(b) }) {
                                deletedRow(b)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Theme.Colors.hairline)
                            .listRowInsets(rowInsets)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 1)

                if confirming {
                    PillButton("Start workout", icon: "play.fill") { session.start() }
                        .padding(.horizontal, Theme.Spacing.l).padding(.top, Theme.Spacing.s).padding(.bottom, Theme.Spacing.m)
                } else {
                    PillButton("End workout", icon: "stop.fill", style: .quiet) { confirmEnd = true }
                        .padding(Theme.Spacing.l)
                }
            }
        }
        .sheet(item: $picker) { mode in ExercisePicker(session: session, replacing: mode.block) }
        // Live user testing: the system alert's three equal buttons buried "Finish" and put Discard beside it. The X
        // is the way back to the workout; finishing leads; discard is small and set apart at the bottom.
        .fittedSheet(isPresented: $confirmEnd) {
            DecisionSheet(
                title: "End this workout?", message: endMessage, closeLabel: "Keep going",
                primary: .init("Finish and save progress", icon: "checkmark",
                               hint: "Ends the workout, keeps your logged sets and updates your next targets.") { dismiss(); session.finish() },
                destructive: .init("Discard this workout", icon: "trash",
                                   hint: "Ends the workout and deletes this session's logged sets. Your targets stay the same.") { dismiss(); session.abandon() }
            ) { confirmEnd = false }
        }
        .presentationBackground(Theme.Colors.canvas)
    }

    private var rowInsets: EdgeInsets { EdgeInsets(top: 0, leading: Theme.Spacing.l, bottom: 0, trailing: Theme.Spacing.l) }

    var endMessage: String {
        let sets = session.logs.filter { !$0.deleted }.count
        if sets == 0 { return "Nothing logged yet. Saving still moves you on to your next day; discarding deletes this session." }
        return "Saving keeps the \(sets) \(sets == 1 ? "set" : "sets") you logged and updates your next targets. Discarding deletes \(sets == 1 ? "it" : "them")."
    }

    var remainingMinutes: Int {
        let secs = session.activeBlocks.filter { !session.isComplete($0) }.reduce(0.0) { acc, b in
            let fraction = 1 - Double(session.workingSetsDone(b)) / Double(max(1, b.sets))
            return acc + b.estimatedSeconds * fraction
        }
        return Int((secs / 60).rounded())
    }

    // MARK: Actions (shared by the swipes and their accessibility actions)

    func beginSwap(_ b: PlanBlock) { picker = .swap(b) }

    func delete(_ b: PlanBlock) {
        withAnimation(Theme.Motion.quick) {
            if expanded == b.id { expanded = nil }
            session.delete(b)
        }
    }

    func restore(_ b: PlanBlock) {
        Haptics.play(.swap)
        withAnimation(Theme.Motion.quick) { session.restore(b) }
    }

    func sectionHeader(_ title: String, hint: String) -> some View {
        HStack {
            Overline(title)
            Spacer()
            Text(hint).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.top, Theme.Spacing.xl).padding(.bottom, Theme.Spacing.xs)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(rowInsets)
    }

    // MARK: Row

    func row(_ b: PlanBlock, index: Int) -> some View {
        let done = session.workingSetsDone(b)
        // Before Start workout nothing is in progress, so no row is marked current.
        let isCurrent = !confirming && session.currentBlock?.id == b.id
        let complete = session.isComplete(b)
        let linked = session.isSupersetLinked(b)
        let tint = Theme.Colors.day(session.plan.dayType)
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                Group {
                    if Theme.storybook {
                        PotNumber(index: index, complete: complete, current: isCurrent, linked: linked, tint: tint)
                    } else if complete {
                        IconTile("checkmark", tint: Theme.Colors.brass, size: 40)
                    } else if isCurrent {
                        IconTile("play.fill", tint: tint, size: 40)
                    } else {
                        IconTile(linked ? "link" : "\(min(index + 1, 50)).circle", tint: tint, size: 40)
                            .opacity(0.7)
                    }
                }
                .padding(.leading, linked ? Theme.Spacing.m : 0)
                VStack(alignment: .leading, spacing: 3) {
                    if b.band == .heavy || linked {
                        Overline(b.band == .heavy ? "Heavy" : "Superset", tint: Theme.Colors.dayInk(session.plan.dayType))
                    }
                    Text(b.exerciseName).font(Theme.Fonts.bodyMedium).lineLimit(2).minimumScaleFactor(0.85)
                        .foregroundStyle(complete ? Theme.Colors.textTertiary : isCurrent && !Theme.storybook ? Theme.Colors.brass : Theme.Colors.textPrimary)
                    Text(summary(b, done: done)).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: Theme.Spacing.s)
                SetDots(done: done, total: b.sets)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.Colors.textTertiary)
                    .rotationEffect(.degrees(expanded == b.id ? 180 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Theme.Motion.quick) { expanded = expanded == b.id ? nil : b.id } }
            // Swap and delete are swipes; these give them to anyone who can't swipe (VoiceOver, Switch Control, Voice Control).
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(b.band == .heavy ? "Heavy, " : "")\(b.exerciseName), \(summary(b, done: done))")
            .accessibilityHint(expanded == b.id ? "Hides the editors" : "Shows weight, sets and reps editors")
            .accessibilityAction(named: "Swap exercise") { beginSwap(b) }
            .accessibilityAction(named: "Delete exercise") { delete(b) }

            if expanded == b.id { editors(b, done: done) }
        }
        .padding(.vertical, Theme.Spacing.m)
    }

    /// A skipped exercise: dimmed, with its logged sets, and a restore control. The whole row restores on tap.
    func skippedRow(_ b: PlanBlock) -> some View {
        let done = session.workingSetsDone(b)
        return HStack(spacing: Theme.Spacing.m) {
            IconTile("forward.end", tint: Theme.Colors.textTertiary, size: 40).opacity(0.6)
            VStack(alignment: .leading, spacing: 3) {
                Text(b.exerciseName).font(Theme.Fonts.bodyMedium).foregroundStyle(Theme.Colors.textTertiary)
                Text(done > 0 ? "\(done) of \(b.sets) done · \(summary(b, done: done))" : summary(b, done: done))
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
            }
            Spacer()
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 13, weight: .bold))
                Text("Restore").font(Theme.Fonts.captionBold)
            }
            .foregroundStyle(Theme.storybook ? Theme.Colors.ink : Theme.Colors.brass)
            .padding(.horizontal, Theme.Spacing.sm).frame(height: 36)
            .background(Theme.storybook ? Theme.Colors.honey : Theme.Colors.brassDim, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.storybook ? Theme.Colors.ink.opacity(0.6) : Theme.Colors.brass.opacity(0.3), lineWidth: 1))
        }
        .padding(.vertical, Theme.Spacing.m)
        .contentShape(Rectangle())
        .onTapGesture { restore(b) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Restore \(b.exerciseName)")
        .accessibilityAction(named: "Delete exercise") { delete(b) }
    }

    /// A deleted exercise: dimmed and struck through, kept here so a mis-swipe isn't final. Swipe right to restore.
    func deletedRow(_ b: PlanBlock) -> some View {
        let done = session.workingSetsDone(b)
        return HStack(spacing: Theme.Spacing.m) {
            IconTile("trash", tint: Theme.Colors.textTertiary, size: 40).opacity(0.6)
            VStack(alignment: .leading, spacing: 3) {
                Text(b.exerciseName).font(Theme.Fonts.bodyMedium).foregroundStyle(Theme.Colors.textTertiary).strikethrough()
                Text(done > 0 ? "\(done) of \(b.sets) done · \(summary(b, done: done))" : summary(b, done: done))
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
            }
            Spacer()
            Image(systemName: "arrow.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.vertical, Theme.Spacing.m)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(b.exerciseName), deleted")
        .accessibilityHint("Swipe right to restore")
        .accessibilityAction(named: "Restore exercise") { restore(b) }
    }

    func summary(_ b: PlanBlock, done: Int) -> String {
        let range = b.measure == .seconds ? "\(b.repLow)–\(b.repHigh)s" : "\(b.repLow)–\(b.repHigh)"
        let load = b.weight.map { "\($0.formatted()) lb · " } ?? ""
        return "\(load)\(b.sets) × \(range) · \(session.restSeconds(for: b))s rest"
    }

    /// Weight / sets / reps, plus undo for a logged set. Swap and delete are swipes on the row, not buttons here.
    @ViewBuilder func editors(_ b: PlanBlock, done: Int) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            if b.weight != nil {
                Adjuster("\((b.weight ?? 0).formatted()) lb",
                         value: Binding(get: { b.weight ?? 0 }, set: { session.setWeight(b, $0) }),
                         in: 0...1000, step: session.increment(for: b))
            }
            Adjuster("\(b.sets) sets",
                     value: Binding(get: { Double(b.sets) }, set: { session.setSets(b, Int($0)) }),
                     in: 1...10)
            Adjuster("\(b.repLow)–\(b.repHigh) \(b.measure == .seconds ? "sec" : "reps")",
                     value: Binding(get: { Double(b.repLow) }, set: { session.shiftReps(b, by: Int($0) - b.repLow) }),
                     in: 1...300, step: b.measure == .seconds ? 5 : 1)
            restAdjuster(b)
            if done > 0 {
                HStack(spacing: Theme.Spacing.s) {
                    IconControl("arrow.uturn.backward", label: "Undo last set") { session.undoLast(block: b) }
                    Spacer()
                }
            }
        }
    }
}

/// What a swipe on a `SwipeRow` does: the stamp it shows and whether the row leaves when it lands.
struct SwipeRowAction {
    let label: String
    let icon: String
    let color: Color
    /// Whether the row leaves the screen when the swipe lands (delete, restore) or springs back (swap).
    let flies: Bool

    static let delete = SwipeRowAction(label: "Delete", icon: "trash", color: Theme.Colors.swipeSkip, flies: true)
    static let swap = SwipeRowAction(label: "Swap", icon: "arrow.triangle.2.circlepath", color: Theme.Colors.swipeRate, flies: false)
    static var restore: SwipeRowAction { SwipeRowAction(label: "Restore", icon: "arrow.uturn.backward", color: Theme.storybook ? Theme.Colors.honeyDeep : Theme.Colors.brass, flies: true) }
}

/// A list row that acts on a sideways swipe, with the deck cards' tint-and-stamp feedback (`SwipeFeedback`).
/// Right reveals `leading`, left reveals `trailing`; a direction with no action only rubber-bands. The row commits
/// at `RowSwipe`'s threshold (a flick counts a little momentum), flying off for an action that removes it from this
/// section and springing back otherwise. Vertical and diagonal drags are left to the list, so scrolling and
/// long-press reorder keep working.
struct SwipeRow<Content: View>: View {
    let leading: SwipeRowAction?
    let trailing: SwipeRowAction?
    let onLeading: () -> Void
    let onTrailing: () -> Void
    @ViewBuilder let content: () -> Content

    /// The list row's horizontal inset: the revealed gap starts at the screen edge, not at the row content.
    private let revealInset: CGFloat = Theme.Spacing.l
    @State private var travel: CGFloat = 0
    @State private var lock: RowSwipe.Lock?
    @State private var armed = false
    @State private var flying = false
    private let swipe = RowSwipe()

    init(leading: SwipeRowAction? = nil, trailing: SwipeRowAction? = nil, onLeading: @escaping () -> Void = {}, onTrailing: @escaping () -> Void = {},
         @ViewBuilder content: @escaping () -> Content) {
        self.leading = leading; self.trailing = trailing; self.onLeading = onLeading; self.onTrailing = onTrailing; self.content = content
    }

    private var allowed: Set<RowSwipe.Direction> {
        var d = Set<RowSwipe.Direction>()
        if leading != nil { d.insert(.right) }
        if trailing != nil { d.insert(.left) }
        return d
    }

    private func action(_ direction: RowSwipe.Direction) -> SwipeRowAction? { direction == .right ? leading : trailing }

    var body: some View {
        let pending = swipe.pending(width: Double(travel), allowing: allowed)
        content()
            .overlay {
                if let p = pending, let a = action(p.direction) {
                    SwipeFeedback(label: a.label, icon: a.icon, color: a.color, strength: p.strength,
                                  placement: p.direction == .right ? .leading : .trailing, compact: true, showsStamp: false)
                }
            }
            .offset(x: travel)
            .background {
                if let p = pending, let a = action(p.direction) { revealedStamp(a, strength: p.strength, direction: p.direction) }
            }
            .gesture(drag)
    }

    /// The stamp sits in the gap the row opens (row inset included), hugging the row's moving edge so it slides in
    /// with the row and flies off with it; it is never drawn over the row's own content.
    private func revealedStamp(_ a: SwipeRowAction, strength: Double, direction: RowSwipe.Direction) -> some View {
        let towardRow: Alignment = direction == .right ? .trailing : .leading
        let screenEdge: Alignment = direction == .right ? .leading : .trailing
        return SwipeStamp(label: a.label, icon: a.icon, color: a.color, strength: strength, compact: true)
            .fixedSize()
            .padding(direction == .right ? .trailing : .leading, Theme.Spacing.s)
            .frame(width: max(0, abs(travel) + revealInset), alignment: towardRow)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: screenEdge)
            .padding(.horizontal, -revealInset)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { v in
                guard !flying else { return }
                let w = Double(v.translation.width), h = Double(v.translation.height)
                if lock == nil { lock = swipe.lock(width: w, height: h) }
                guard lock == .horizontal else { return }
                travel = CGFloat(swipe.travel(width: w, allowing: allowed))
                let crossed = (swipe.pending(width: Double(travel), allowing: allowed)?.strength ?? 0) >= 1
                if crossed != armed {
                    armed = crossed
                    if crossed { Haptics.play(.swap) }
                }
            }
            .onEnded { v in
                let ended = lock
                lock = nil; armed = false
                guard !flying, ended == .horizontal,
                      let direction = swipe.resolve(width: Double(v.translation.width), predictedWidth: Double(v.predictedEndTranslation.width), allowing: allowed),
                      let a = action(direction)
                else {
                    withAnimation(Theme.Motion.spring) { travel = 0 }
                    return
                }
                let perform = direction == .right ? onLeading : onTrailing
                if a.flies {
                    flying = true
                    Haptics.play(.exerciseDone)
                    withAnimation(.easeOut(duration: 0.22)) { travel = direction == .right ? 640 : -640 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
                        perform()
                        travel = 0
                        flying = false
                    }
                } else {
                    Haptics.play(.swap)
                    withAnimation(Theme.Motion.spring) { travel = 0 }
                    perform()
                }
            }
    }
}

extension DeckOverview {
    /// Rest time, after Weight / Sets / Reps. Each tap is one engine step (10 s); the engine clamps and, for a
    /// superset partner, edits the host's rest it actually runs on.
    func restAdjuster(_ b: PlanBlock) -> some View {
        let config = EngineConfig.default
        let rest = session.restSeconds(for: b)
        return Adjuster("\(rest)s rest",
                        value: Binding(get: { Double(rest) }, set: { new in
                            // Direction only: the Adjuster may pre-clamp a partial step (15 → 10); the engine re-clamps.
                            if new != Double(rest) { session.stepRest(b, by: new > Double(rest) ? 1 : -1) }
                        }),
                        in: Double(config.restSecondsRange.lowerBound)...Double(config.restSecondsRange.upperBound),
                        step: Double(config.restStepSeconds), name: "rest time")
    }
}

/// The row's number on a little honey pot: full and ticked when the exercise is done, honey-washed while current,
/// a chain link for the second half of a superset.
struct PotNumber: View {
    let index: Int
    let complete: Bool
    let current: Bool
    let linked: Bool
    let tint: Color
    var body: some View {
        ZStack {
            HoneyPot(fill: complete ? 1 : current ? 0.55 : 0, drip: complete, label: nil)
                .frame(width: 44, height: 44)
            if complete {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.Colors.ink).offset(y: 6)
            } else if linked {
                Image(systemName: "link").font(.system(size: 11, weight: .heavy)).foregroundStyle(Theme.Colors.ink).offset(y: 6)
            } else {
                Text("\(min(index + 1, 50))").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Theme.Colors.ink).offset(y: 6)
            }
        }
        .background(WashBlob(color: tint, opacity: current ? 0.45 : 0.18).scaleEffect(1.25))
        .opacity(complete ? 0.75 : 1)
        .accessibilityHidden(true)
    }
}

/// Icon-only control. A tap gesture on a shaped view rather than a `Button`, which can lose taps to a
/// reorderable `List` row's own gestures.
struct IconControl: View {
    let icon: String
    let label: String
    var tint: Color = Theme.Colors.textPrimary
    let action: () -> Void
    init(_ icon: String, label: String, tint: Color = Theme.Colors.textPrimary, action: @escaping () -> Void) {
        self.icon = icon; self.label = label; self.tint = tint; self.action = action
    }
    var body: some View {
        Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(tint)
            .frame(width: 52, height: 44)
            .background(Theme.storybook ? Theme.Colors.paper : Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            .inkOutline(Theme.Radius.chip, opacity: 0.4, lineWidth: 1)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
    }
}
