import SwiftUI
import WorkoutEngine
import WorkoutStore
import WorkoutUI

/// What Home can start: a strength day or the week's running.
enum HomeMode: Hashable {
    case strength(DayType), running
    static let all: [HomeMode] = DayType.allCases.map { .strength($0) } + [.running]
    var label: String { switch self { case .strength(let d): d.label; case .running: "Run" } }
    var symbol: String { switch self { case .strength(let d): d.symbol; case .running: "figure.run" } }
    var tint: Color { switch self { case .strength(let d): Theme.Colors.day(d); case .running: Theme.Colors.run } }
}

/// Cold open → workout in ≤3 taps. The greeting and this week's momentum sit at the top, the choices in the
/// middle, and Start lives in the thumb zone, pinned to the bottom edge.
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
                    header
                    momentum
                    modePicker
                    switch mode {
                    case .strength(let dayType): strength(dayType)
                    case .running: RunContent()
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.s)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                if case .strength(let dayType) = mode { startBar(dayType) }
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

    // MARK: Header

    var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Overline(Date.now.formatted(.dateTime.weekday(.wide).month().day()))
                Text(greeting).font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary).lineLimit(1).minimumScaleFactor(0.75)
            }
            Spacer()
            IconButton("chart.xyaxis.line", label: "Progress") { showProgress = true }
            Button { showSettings = true } label: { Avatar(name: model.settings?.displayName ?? "") }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Profile")
        }
    }

    /// "Today", "Yesterday", a weekday within the week, otherwise a short date.
    func dayLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: .now)).day, days < 7 {
            return d.formatted(.dateTime.weekday(.wide))
        }
        return d.formatted(.dateTime.day().month(.abbreviated))
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let name = model.settings?.displayName.split(separator: " ").first.map(String.init) ?? ""
        return name.isEmpty ? part : "\(part), \(name)"
    }

    /// This week at a glance. Returning users see their momentum; a new user sees where it will go.
    var momentum: some View {
        let week = model.recentSessions(limit: 30).filter { $0.performedAt >= Date.startOfWeek }
        let last = model.recentSessions(limit: 1).first
        return Card(padding: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                Stat("\(week.count)", label: week.count == 1 ? "session this week" : "sessions this week", tint: Theme.Colors.brass)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle().fill(Theme.Colors.hairline).frame(width: 1, height: 40)
                Group {
                    if let last {
                        Stat(dayLabel(last.performedAt), label: "last · \(last.dayType.label.lowercased())")
                    } else {
                        Stat("—", label: "no sessions yet")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(HomeMode.all, id: \.self) { m in
                    Chip(m.label, icon: m.symbol, dot: m == mode ? nil : m.tint, selected: m == mode) {
                        withAnimation(Theme.Motion.quick) { mode = m }
                    }
                }
            }
        }
        .scrollClipDisabled()
    }

    // MARK: Strength

    @ViewBuilder func strength(_ dayType: DayType) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.sm) {
                    IconTile("clock", tint: Theme.Colors.brass, size: 32)
                    Overline("Minutes", tint: Theme.Colors.textSecondary)
                }
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(EngineConfig.default.durationBuckets, id: \.self) { m in
                        Chip("\(m)", selected: m == duration) { duration = m }
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("\(m) minutes")
                    }
                }
                Hairline().padding(.vertical, Theme.Spacing.xs)
                HStack(spacing: Theme.Spacing.sm) {
                    IconTile("mappin", tint: Theme.Colors.day(dayType), size: 32)
                    Overline("Where", tint: Theme.Colors.textSecondary)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(model.locations) { l in
                            Chip(l.name, icon: model.catalog.seededLocations.first { $0.key == l.seedKey }?.kind == "home_gym" ? "house" : "building.2", selected: l.id == location?.id) { location = l }
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
            }
        }

        if let location {
            PlanPreview(plan: model.preview(dayType: dayType, duration: duration, location: location), dayType: dayType)
        }
    }

    /// Thumb-zone CTA over a fade so the plan can scroll underneath it.
    func startBar(_ dayType: DayType) -> some View {
        VStack(spacing: 0) {
            PillButton(startTitle(dayType), icon: "play.fill") {
                if let location { model.startSession(dayType: dayType, duration: duration, location: location) }
            }
            .disabled(location == nil)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.m)
            .padding(.bottom, Theme.Spacing.s)
        }
        .background(
            LinearGradient(colors: [Theme.Colors.canvas.opacity(0), Theme.Colors.canvas, Theme.Colors.canvas], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    func startTitle(_ dayType: DayType) -> String {
        guard let location else { return "Start" }
        let mins = Int(model.preview(dayType: dayType, duration: duration, location: location).estimatedSeconds / 60)
        return "Start \(dayType.label.lowercased()) · ~\(mins) min"
    }
}

/// The deck before it's dealt: each exercise with its load and volume, the heavy lift leading.
struct PlanPreview: View {
    let plan: Plan
    let dayType: DayType
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    Overline("Today's plan", tint: Theme.Colors.textSecondary)
                    Spacer()
                    Text("\(plan.blocks.count) exercises · ~\(Int(plan.estimatedSeconds / 60)) min").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                }
                VStack(spacing: 0) {
                    ForEach(Array(plan.blocks.sorted { $0.slot < $1.slot }.enumerated()), id: \.element.id) { i, b in
                        HStack(spacing: Theme.Spacing.sm) {
                            if b.isSupersetted {
                                Image(systemName: "arrow.turn.down.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.Colors.textTertiary)
                                    .frame(width: 32)
                            } else {
                                IconTile(b.band == .heavy ? "flame" : "dumbbell", tint: b.band == .heavy ? Theme.Colors.brass : Theme.Colors.day(dayType), size: 32)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.exerciseName).font(Theme.Fonts.body).foregroundStyle(b.isSupersetted ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                                    .lineLimit(2).minimumScaleFactor(0.85)
                                Text(b.band == .heavy ? "Heavy" : b.isSupersetted ? "Superset" : b.pattern.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(b.weight.map { "\($0.formatted()) lb" } ?? "Body").font(Theme.Fonts.captionBold).foregroundStyle(Theme.Colors.textPrimary)
                                Text("\(b.sets) × \(b.repLow)–\(b.repHigh)").font(Theme.Fonts.caption).monospacedDigit().foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                        .padding(.vertical, Theme.Spacing.sm)
                        if i < plan.blocks.count - 1 { Hairline() }
                    }
                }
            }
        }
    }
}
