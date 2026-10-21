import SwiftUI
import WorkoutEngine
import WorkoutStore
import WorkoutUI

struct DeckView: View {
    @Bindable var session: ActiveSession
    @Environment(AppModel.self) private var model
    @State private var swapTarget: PlanBlock?
    @State private var confirmAbandon = false

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                header
                if session.isFinished {
                    FinishView(session: session)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: Theme.Spacing.m) {
                                ForEach(session.orderedBlocks) { block in
                                    BlockCard(session: session, block: block, isCurrent: block.id == session.currentBlock?.id,
                                              onSwap: { swapTarget = block })
                                        .id(block.id)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.m)
                            .padding(.bottom, 120)
                        }
                        .onChange(of: session.currentBlock?.id) { _, id in
                            if let id { withAnimation(Theme.Motion.spring) { proxy.scrollTo(id, anchor: .top) } }
                        }
                    }
                }
            }
            .overlay(alignment: .bottom) { RestBar(session: session) }
        }
        .sheet(item: $swapTarget) { block in SwapSheet(session: session, block: block) }
        .confirmationDialog("End this workout?", isPresented: $confirmAbandon, titleVisibility: .visible) {
            Button("Finish and save progress") { session.finish() }
            Button("Discard", role: .destructive) { session.abandon() }
            Button("Keep going", role: .cancel) {}
        }
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
            Button("End") { confirmAbandon = true }.font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.l).padding(.vertical, Theme.Spacing.m)
    }
}

struct BlockCard: View {
    let session: ActiveSession
    let block: PlanBlock
    let isCurrent: Bool
    let onSwap: () -> Void
    @State private var reps: Int = 0
    @State private var weight: Double = 0
    @State private var offset: CGFloat = 0

    var done: Int { session.workingSetsDone(block) }
    var complete: Bool { session.isComplete(block) }

    var body: some View {
        Card(raised: isCurrent) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Overline(block.band == .heavy ? "Heavy" : block.isSupersetted ? "Superset" : block.pattern.replacingOccurrences(of: "_", with: " "))
                            if block.isEstimate { Overline("· est") }
                        }
                        Text(block.exerciseName).font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textPrimary)
                    }
                    Spacer()
                    if complete { Image(systemName: "checkmark").foregroundStyle(Theme.Colors.brass) }
                }

                HStack(alignment: .lastTextBaseline, spacing: Theme.Spacing.m) {
                    if let w = block.weight {
                        Text(w.formatted(.number.precision(.fractionLength(0...1)))).font(Theme.Fonts.numeral).foregroundStyle(Theme.Colors.textPrimary)
                        Text("lb").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Text("\(block.sets) × \(repRange)").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text("\(block.restSeconds)s rest").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                }

                if isCurrent && !complete { controls }
                if done > 0 || !block.warmups.isEmpty { setDots }
            }
        }
        .opacity(complete && !isCurrent ? 0.55 : 1)
        .offset(x: offset)
        .gesture(
            DragGesture(minimumDistance: 24)
                .onChanged { v in if v.translation.width < 0 { offset = max(v.translation.width, -96) } }
                .onEnded { v in
                    withAnimation(Theme.Motion.spring) { offset = 0 }
                    if v.translation.width < -72 { Haptics.play(.swap); onSwap() }
                }
        )
        .contextMenu {
            Button("Swap exercise", systemImage: "arrow.left.arrow.right") { onSwap() }
            Button("Do later", systemImage: "arrow.down.to.line") { session.defer_(block) }
            Button("Skip", systemImage: "forward.end") { session.skip(block) }
            if done > 0 { Button("Undo last set", systemImage: "arrow.uturn.backward") { session.undoLast(block: block) } }
        }
        .onAppear { reset() }
        .onChange(of: block.exerciseKey) { _, _ in reset() }
    }

    var repRange: String {
        block.measure == .seconds ? "\(block.repLow)–\(block.repHigh)s" : "\(block.repLow)–\(block.repHigh)"
    }

    func reset() {
        reps = block.measure == .seconds ? block.repHigh : block.repHigh
        weight = block.weight ?? 0
    }

    var warmupsPending: Bool { block.band == .heavy && session.logs(for: block).filter(\.isWarmup).count < block.warmups.count }

    @ViewBuilder var controls: some View {
        if warmupsPending {
            let i = session.logs(for: block).filter(\.isWarmup).count
            let w = block.warmups[i]
            HStack {
                Text("Warm-up \(i + 1): \(w.weight.formatted()) × \(w.reps)").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Button("Done") { session.log(block: block, reps: w.reps, weight: w.weight, effort: nil, isWarmup: true); Haptics.play(.setLogged) }
                    .font(Theme.Fonts.bodyMedium).foregroundStyle(Theme.Colors.brass)
            }
        } else {
            VStack(spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.m) {
                    Stepper("\(reps) \(block.measure == .seconds ? "sec" : "reps")", value: $reps, in: 0...200, step: block.measure == .seconds ? 5 : 1)
                        .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textPrimary)
                    if block.weight != nil {
                        Stepper("\(weight.formatted()) lb", value: $weight, in: 0...1000, step: session.input.location.plateIncrement)
                            .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
                HStack(spacing: Theme.Spacing.s) {
                    ForEach([EffortRating.easy, .good, .didNotFinish], id: \.rawValue) { e in
                        Button(e.rawValue.capitalized) { log(effort: e) }
                            .font(Theme.Fonts.caption).padding(.vertical, 12).frame(maxWidth: .infinity)
                            .background(Theme.Colors.cardRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                            .foregroundStyle(Theme.Colors.textPrimary).buttonStyle(PressStyle())
                    }
                }
                PillButton("Log set \(done + 1)") { log(effort: nil) }
            }
        }
    }

    func log(effort: EffortRating?) {
        session.log(block: block, reps: reps, weight: block.weight == nil ? nil : weight, effort: effort)
        Haptics.play(session.isComplete(block) ? .exerciseDone : .setLogged)
    }

    var setDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<block.sets, id: \.self) { i in
                Circle().fill(i < done ? Theme.Colors.brass : Theme.Colors.hairline).frame(width: 6, height: 6)
            }
            if done > block.sets { Text("+\(done - block.sets)").font(Theme.Fonts.overline).foregroundStyle(Theme.Colors.textTertiary) }
        }
    }
}

struct RestBar: View {
    let session: ActiveSession
    var body: some View {
        if let end = session.restEndsAt {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let remaining = max(0, end.timeIntervalSince(ctx.date))
                HStack {
                    Text(remaining == 0 ? "Go" : "\(Int(remaining.rounded(.up)))s").font(Theme.Fonts.numeral).foregroundStyle(remaining == 0 ? Theme.Colors.brass : Theme.Colors.textPrimary)
                    Spacer()
                    Button("Skip rest") { session.skipRest() }.font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.horizontal, Theme.Spacing.l).padding(.vertical, Theme.Spacing.m)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(alignment: .bottom) {
                    GeometryReader { g in
                        Rectangle().fill(Theme.Colors.brass).frame(width: g.size.width * (1 - remaining / max(1, session.restTotal)), height: 2)
                    }.frame(height: 2)
                }
                .padding(Theme.Spacing.m)
                .onChange(of: remaining == 0) { _, z in if z { Haptics.play(.warning) } }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct SwapSheet: View {
    let session: ActiveSession
    let block: PlanBlock
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Overline("Swap \(block.exerciseName)")
                    ForEach(session.candidates(for: block), id: \.exercise.key) { c in
                        Button {
                            session.swap(block, to: c.exercise); Haptics.play(.swap); dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.exercise.name).font(Theme.Fonts.body).foregroundStyle(c.isAvailable ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                                    if let why = reason(c.exclusion) { Text(why).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary) }
                                }
                                Spacer()
                                if let e = c.estimate { Text("\(e.weight.formatted()) lb").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary) }
                            }
                            .padding(.vertical, 12)
                        }
                        .disabled(!c.isAvailable)
                        Hairline()
                    }
                }
                .padding(Theme.Spacing.l)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Theme.Colors.canvas)
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
            Text("\(session.plan.blocks.count)").font(Theme.Fonts.display).foregroundStyle(Theme.Colors.textPrimary)
            Text("exercises done").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            PillButton("Finish") { Haptics.play(.sessionDone); session.finish() }.padding(.horizontal, Theme.Spacing.l)
        }
        .padding(.bottom, Theme.Spacing.xxl)
    }
}
