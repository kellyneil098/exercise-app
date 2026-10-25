import SwiftUI
import WorkoutEngine
import WorkoutStore
import WorkoutUI

/// The zoomed-out deck: the whole workout at once. Drag to reorder, swipe a row away to delete, tap a row to
/// edit weight / sets / reps or swap / skip / delete / undo; `+` adds an exercise. Exercises swiped away in the
/// deck collect under "Skipped" with a one-tap restore. Ending the workout lives here.
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
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Overline(confirming ? "Today's plan" : "Deck")
                            HStack(alignment: .lastTextBaseline, spacing: Theme.Spacing.xs) {
                                Text("\(session.remainingCount)").font(Theme.Fonts.numeral).foregroundStyle(Theme.Colors.textPrimary)
                                Text("\(confirming ? "exercises" : "left") · ~\(remainingMinutes) min").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                        Spacer()
                        IconButton("plus", label: "Add exercise", tint: Theme.Colors.brass) { picker = .add }
                        if !confirming {
                            Button { dismiss() } label: {
                                Text("Done").font(Theme.Fonts.captionBold).foregroundStyle(Theme.Colors.canvas)
                                    .padding(.horizontal, Theme.Spacing.m).frame(height: 44)
                                    .background(Theme.Colors.brass, in: Capsule())
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
                        row(b, index: i)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Theme.Colors.hairline)
                            .listRowInsets(rowInsets)
                    }
                    .onMove { session.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { offsets in
                        let blocks = session.activeBlocks
                        for i in offsets { session.remove(blocks[i]) }
                    }

                    if !session.skippedBlocks.isEmpty {
                        HStack {
                            Overline("Skipped")
                            Spacer()
                            Text("tap to bring back").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .padding(.top, Theme.Spacing.xl).padding(.bottom, Theme.Spacing.xs)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(rowInsets)
                        ForEach(session.skippedBlocks) { b in
                            skippedRow(b)
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(Theme.Colors.hairline)
                                .listRowInsets(rowInsets)
                        }
                        .onDelete { offsets in
                            let blocks = session.skippedBlocks
                            for i in offsets { session.remove(blocks[i]) }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 1)

                if confirming {
                    VStack(spacing: Theme.Spacing.xs) {
                        PillButton("Start workout", icon: "play.fill") { session.start() }
                        Button("Back") { session.cancel() }
                            .font(Theme.Fonts.captionBold).foregroundStyle(Theme.Colors.textSecondary).frame(minHeight: 44)
                    }
                    .padding(.horizontal, Theme.Spacing.l).padding(.top, Theme.Spacing.s).padding(.bottom, Theme.Spacing.s)
                } else {
                    PillButton("End workout", icon: "stop.fill", style: .quiet) { confirmEnd = true }
                        .padding(Theme.Spacing.l)
                }
            }
        }
        .sheet(item: $picker) { mode in ExercisePicker(session: session, replacing: mode.block) }
        .alert("End this workout?", isPresented: $confirmEnd) {
            Button("Finish and save progress") { dismiss(); session.finish() }
            Button("Discard", role: .destructive) { dismiss(); session.abandon() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Finishing applies progression to what you logged. Discarding drops this session's sets.")
        }
        .presentationBackground(Theme.Colors.canvas)
    }

    private var rowInsets: EdgeInsets { EdgeInsets(top: 0, leading: Theme.Spacing.l, bottom: 0, trailing: Theme.Spacing.l) }

    var remainingMinutes: Int {
        let secs = session.activeBlocks.filter { !session.isComplete($0) }.reduce(0.0) { acc, b in
            let fraction = 1 - Double(session.workingSetsDone(b)) / Double(max(1, b.sets))
            return acc + b.estimatedSeconds * fraction
        }
        return Int((secs / 60).rounded())
    }

    // MARK: Row

    func row(_ b: PlanBlock, index: Int) -> some View {
        let done = session.workingSetsDone(b)
        // Before Start workout nothing is in progress, so no row is marked current.
        let isCurrent = !confirming && session.currentBlock?.id == b.id
        let complete = session.isComplete(b)
        let tint = Theme.Colors.day(session.plan.dayType)
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                Group {
                    if complete {
                        IconTile("checkmark", tint: Theme.Colors.brass, size: 40)
                    } else if isCurrent {
                        IconTile("play.fill", tint: tint, size: 40)
                    } else {
                        IconTile(b.isSupersetted ? "link" : "\(min(index + 1, 50)).circle", tint: tint, size: 40)
                            .opacity(0.7)
                    }
                }
                .padding(.leading, b.isSupersetted ? Theme.Spacing.m : 0)
                VStack(alignment: .leading, spacing: 3) {
                    if b.band == .heavy || b.isSupersetted {
                        Overline(b.band == .heavy ? "Heavy" : "Superset", tint: tint)
                    }
                    Text(b.exerciseName).font(Theme.Fonts.bodyMedium).lineLimit(2).minimumScaleFactor(0.85)
                        .foregroundStyle(complete ? Theme.Colors.textTertiary : isCurrent ? Theme.Colors.brass : Theme.Colors.textPrimary)
                    Text(summary(b, done: done)).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: Theme.Spacing.s)
                SetDots(done: done, total: b.sets)
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.Colors.textTertiary)
                    .rotationEffect(.degrees(expanded == b.id ? 180 : 0))
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Theme.Motion.quick) { expanded = expanded == b.id ? nil : b.id } }

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
            .foregroundStyle(Theme.Colors.brass)
            .padding(.horizontal, Theme.Spacing.sm).frame(height: 36)
            .background(Theme.Colors.brassDim, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Colors.brass.opacity(0.3), lineWidth: 1))
        }
        .padding(.vertical, Theme.Spacing.m)
        .contentShape(Rectangle())
        .onTapGesture { Haptics.play(.swap); withAnimation(Theme.Motion.quick) { session.restore(b) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Restore \(b.exerciseName)")
    }

    func summary(_ b: PlanBlock, done: Int) -> String {
        let range = b.measure == .seconds ? "\(b.repLow)–\(b.repHigh)s" : "\(b.repLow)–\(b.repHigh)"
        let load = b.weight.map { "\($0.formatted()) lb · " } ?? ""
        return "\(load)\(b.sets) × \(range) · \(b.restSeconds)s rest"
    }

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
            HStack(spacing: Theme.Spacing.s) {
                IconControl("arrow.triangle.2.circlepath", label: "Swap") { picker = .swap(b) }
                if !session.isComplete(b) {
                    IconControl("forward.end", label: "Skip") {
                        withAnimation(Theme.Motion.quick) { expanded = nil; session.skip(b) }
                    }
                }
                if done > 0 { IconControl("arrow.uturn.backward", label: "Undo last set") { session.undoLast(block: b) } }
                Spacer()
                IconControl("trash", label: "Delete", tint: Theme.Colors.destructive) {
                    withAnimation(Theme.Motion.quick) { expanded = nil; session.remove(b) }
                }
            }
        }
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
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous).strokeBorder(Theme.Colors.brassBorder, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
    }
}
