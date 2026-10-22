import SwiftUI
import WorkoutEngine
import WorkoutStore
import WorkoutUI

/// The zoomed-out deck: the whole workout at once. Drag to reorder, swipe a row away to delete, tap a row to
/// edit weight / sets / reps or swap / skip / delete / undo; `+` adds an exercise. Exercises swiped away in the
/// deck collect under "Skipped" with a one-tap restore. Ending the workout lives here.
struct DeckOverview: View {
    @Bindable var session: ActiveSession
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
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Overline("Deck")
                        Text("\(session.remainingCount) left · ~\(remainingMinutes) min").font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textPrimary)
                    }
                    Spacer()
                    Button { picker = .add } label: { Image(systemName: "plus").font(.system(size: 20, weight: .medium)) }
                        .foregroundStyle(Theme.Colors.brass)
                        .accessibilityLabel("Add exercise")
                        .padding(.trailing, Theme.Spacing.m)
                    Button("Done") { dismiss() }.font(Theme.Fonts.bodyMedium).foregroundStyle(Theme.Colors.brass)
                }
                .padding(Theme.Spacing.l)

                List {
                    ForEach(session.activeBlocks) { b in
                        row(b)
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

                PillButton("End workout", style: .quiet) { confirmEnd = true }
                    .padding(Theme.Spacing.l)
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

    func row(_ b: PlanBlock) -> some View {
        let done = session.workingSetsDone(b)
        let isCurrent = session.currentBlock?.id == b.id
        let complete = session.isComplete(b)
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: 3) {
                    if b.band == .heavy || b.isSupersetted {
                        Overline(b.band == .heavy ? "Heavy" : "Superset")
                    }
                    Text(b.exerciseName).font(Theme.Fonts.body)
                        .foregroundStyle(complete ? Theme.Colors.textTertiary : isCurrent ? Theme.Colors.brass : Theme.Colors.textPrimary)
                    Text(summary(b, done: done)).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.leading, b.isSupersetted ? Theme.Spacing.m : 0)
                Spacer()
                if complete {
                    Image(systemName: "checkmark").foregroundStyle(Theme.Colors.brass)
                } else {
                    SetDots(done: done, total: b.sets)
                }
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
            VStack(alignment: .leading, spacing: 3) {
                Text(b.exerciseName).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textTertiary)
                Text(done > 0 ? "\(done) of \(b.sets) done · \(summary(b, done: done))" : summary(b, done: done))
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 13, weight: .semibold))
                Text("Restore").font(Theme.Fonts.caption)
            }
            .foregroundStyle(Theme.Colors.brass)
            .padding(.horizontal, 12).frame(height: 36)
            .background(Theme.Colors.brassDim, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
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
                IconControl("forward.end", label: "Skip") {
                    withAnimation(Theme.Motion.quick) { expanded = nil; session.skip(b) }
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
        Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
            .frame(width: 48, height: 36)
            .background(Theme.Colors.cardRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous).strokeBorder(Theme.Colors.hairline, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(label)
    }
}
