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

    /// This week at a glance, set straight on the canvas: two numbers, no box.
    var momentum: some View {
        let week = model.completedSessions(since: Date.startOfWeek)
        let last = model.completedSessions().first
        return HStack(alignment: .top, spacing: Theme.Spacing.l) {
            Stat("\(week.count)", label: week.count == 1 ? "session this week" : "sessions this week", tint: Theme.Colors.brass)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let last {
                Stat(dayLabel(last.performedAt), label: "last · \(last.dayType.label.lowercased())")
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Stat("—", label: "no sessions yet")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Underlined tabs: the day colours do the labelling, nothing is boxed.
    var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.m) {
                ForEach(HomeMode.all, id: \.self) { m in
                    TabItem(m.label, icon: m.symbol, tint: m.tint, selected: m == mode) {
                        withAnimation(Theme.Motion.quick) { mode = m }
                    }
                }
            }
        }
        .scrollClipDisabled()
        .overlay(alignment: .bottom) { Hairline() }
    }

    // MARK: Strength

    @ViewBuilder func strength(_ dayType: DayType) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            optionRow("Minutes", icon: "clock") {
                ForEach(EngineConfig.default.durationBuckets, id: \.self) { m in
                    TextOption("\(m)", selected: m == duration) { duration = m }
                        .accessibilityLabel("\(m) minutes")
                }
            }
            Hairline()
            optionRow("Where", icon: "mappin") {
                ForEach(model.locations) { l in
                    TextOption(l.name, selected: l.id == location?.id) { location = l }
                }
            }
        }
    }

    /// Label on the left, text options trailing; options scroll if a gym name is long.
    func optionRow<Options: View>(_ label: String, icon: String, @ViewBuilder options: () -> Options) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                Glyph(icon, tint: Theme.Colors.textTertiary, width: 20)
                Overline(label, tint: Theme.Colors.textSecondary)
            }
            .frame(width: 104, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.l) { options() }
            }
        }
    }

    /// Thumb-zone CTA: hands the chosen type / minutes / gym to the deck overview for confirmation.
    func startBar(_ dayType: DayType) -> some View {
        VStack(spacing: 0) {
            PillButton(startTitle(dayType), icon: "rectangle.stack") {
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
        guard let location else { return "Build deck" }
        let plan = model.preview(dayType: dayType, duration: duration, location: location)
        return "Build \(dayType.label.lowercased()) deck · \(plan.blocks.count) exercises · ~\(Int(plan.estimatedSeconds / 60)) min"
    }
}
