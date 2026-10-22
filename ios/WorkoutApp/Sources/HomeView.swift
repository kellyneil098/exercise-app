import SwiftUI
import WorkoutEngine
import WorkoutStore
import WorkoutUI

/// What Home can start: a strength day or the week's running.
enum HomeMode: Hashable {
    case strength(DayType), running
    static let all: [HomeMode] = DayType.allCases.map { .strength($0) } + [.running]
    var label: String { switch self { case .strength(let d): d.label; case .running: "Run" } }
}

/// Cold open → workout in ≤3 taps: Start is the primary action, duration/location are one tap each.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var mode: HomeMode = .strength(.push)
    @State private var duration: Int = 60
    @State private var location: Location?
    @State private var showProgress = false
    @State private var showSettings = false

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    HStack(spacing: Theme.Spacing.m) {
                        Overline(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                        Spacer()
                        headerButton("chart.xyaxis.line", label: "Progress") { showProgress = true }
                        headerButton("person", label: "Profile") { showSettings = true }
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.trailing, -Theme.Spacing.s)

                    Text(mode.label).font(Theme.Fonts.display).foregroundStyle(Theme.Colors.textPrimary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.s) {
                            ForEach(HomeMode.all, id: \.self) { m in
                                Chip(m.label, selected: m == mode) { withAnimation(Theme.Motion.quick) { mode = m } }
                            }
                        }
                    }
                    .scrollClipDisabled()

                    switch mode {
                    case .strength(let dayType): strength(dayType)
                    case .running: RunContent()
                    }
                }
                .padding(Theme.Spacing.l)
            }
        }
        .onAppear {
            mode = ActiveRunClock.resumableRunID() != nil ? .running : .strength(model.nextDayType)
            let split = model.splitState
            duration = split.defaultDurationMin
            model.ensureSeededLocations()
            location = model.locations.first { $0.id == split.defaultLocationId } ?? model.locations.first
            model.restoreActiveSession()
        }
        .sheet(isPresented: $showProgress) { ProgressScreen() }
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    /// Full 44-pt targets with a gap between them, so analytics and profile can't be mis-tapped for each other.
    func headerButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .regular))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }

    @ViewBuilder func strength(_ dayType: DayType) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Overline("Time")
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(EngineConfig.default.durationBuckets, id: \.self) { m in
                        Chip("\(m)", selected: m == duration) { duration = m }
                    }
                }
                Hairline()
                Overline("Where")
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(model.locations) { l in
                        Chip(l.name, selected: l.id == location?.id) { location = l }
                    }
                }
            }
        }

        if let location {
            PlanPreview(plan: model.preview(dayType: dayType, duration: duration, location: location))
        }

        PillButton("Start") {
            if let location { model.startSession(dayType: dayType, duration: duration, location: location) }
        }
        .disabled(location == nil)
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    init(_ title: String, selected: Bool, action: @escaping () -> Void) { self.title = title; self.selected = selected; self.action = action }
    var body: some View {
        Button(action: action) {
            Text(title).font(Theme.Fonts.caption).padding(.horizontal, 14).padding(.vertical, 10)
                .background(selected ? Theme.Colors.brassDim : Theme.Colors.cardRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                .foregroundStyle(selected ? Theme.Colors.brass : Theme.Colors.textSecondary)
        }
        .buttonStyle(PressStyle())
    }
}

struct PlanPreview: View {
    let plan: Plan
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    Overline("Plan")
                    Spacer()
                    Text("~\(Int(plan.estimatedSeconds / 60)) min").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                }
                ForEach(plan.blocks.sorted { $0.slot < $1.slot }) { b in
                    HStack {
                        Text(b.exerciseName).font(Theme.Fonts.body).foregroundStyle(b.isSupersetted ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                            .padding(.leading, b.isSupersetted ? Theme.Spacing.m : 0)
                        Spacer()
                        Text(b.weight.map { "\($0.formatted()) · " } ?? "").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                        + Text("\(b.sets)×\(b.repLow)–\(b.repHigh)").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
        }
    }
}
