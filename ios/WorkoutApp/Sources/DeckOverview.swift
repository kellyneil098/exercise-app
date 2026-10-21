import SwiftUI
import WorkoutEngine
import WorkoutStore
import WorkoutUI

/// The zoomed-out deck: the whole workout at once. Long-press-drag to reorder; tap a row to edit
/// weight / sets / reps or swap, defer, skip, undo. Ending the workout lives here, out of the way.
struct DeckOverview: View {
    @Bindable var session: ActiveSession
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: UUID?
    @State private var swapTarget: PlanBlock?
    @State private var confirmEnd = false

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Overline("Deck")
                        Text("\(session.remainingCount) left · ~\(remainingMinutes) min").font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textPrimary)
                    }
                    Spacer()
                    Button("Done") { dismiss() }.font(Theme.Fonts.bodyMedium).foregroundStyle(Theme.Colors.brass)
                }
                .padding(Theme.Spacing.l)

                List {
                    ForEach(session.orderedBlocks) { b in
                        row(b)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Theme.Colors.hairline)
                            .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.l, bottom: 0, trailing: Theme.Spacing.l))
                    }
                    .onMove { session.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 1)

                PillButton("End workout", style: .quiet) { confirmEnd = true }
                    .padding(Theme.Spacing.l)
            }
        }
        .sheet(item: $swapTarget) { block in SwapSheet(session: session, block: block) }
        .alert("End this workout?", isPresented: $confirmEnd) {
            Button("Finish and save progress") { dismiss(); session.finish() }
            Button("Discard", role: .destructive) { dismiss(); session.abandon() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Finishing applies progression to what you logged. Discarding drops this session's sets.")
        }
        .presentationBackground(Theme.Colors.canvas)
    }

    var remainingMinutes: Int {
        let secs = session.plan.blocks.filter { !session.isComplete($0) }.reduce(0.0) { acc, b in
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
                if session.skipped.contains(b.id) {
                    Overline("Skipped")
                } else if session.deferred.contains(b.id) {
                    Overline("Later")
                } else if complete {
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
                Chip("Swap", selected: false) { swapTarget = b }
                if session.skipped.contains(b.id) || session.deferred.contains(b.id) {
                    Chip("Restore", selected: false) { session.unskip(b) }
                } else {
                    Chip("Later", selected: false) { session.defer_(b) }
                    Chip("Skip", selected: false) { session.skip(b) }
                }
                if done > 0 { Chip("Undo set", selected: false) { session.undoLast(block: b) } }
                Spacer()
            }
        }
    }
}
