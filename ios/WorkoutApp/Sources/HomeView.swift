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
    /// The character who stands for this kind of day: Pooh pushes, Rabbit pulls, Kanga and Roo hop, Christopher Robin
    /// does the whole thing, Piglet runs.
    var plate: Plate {
        switch self {
        case .strength(.push): .poohSmall
        case .strength(.pull): .rabbit
        case .strength(.legs): .kangaRoo
        case .strength(.fullBody): .balloonBoy
        case .running: .piglet
        }
    }
}

/// Cold open → workout in ≤3 taps. The greeting and this week's momentum sit at the top, the choices in the
/// middle, and Start lives in the thumb zone, pinned to the bottom edge.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var mode: HomeMode = .strength(.push)
    @State private var duration: Int = 60
    @State private var location: Location?
    @State private var showProgress = false

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    // The header sets its own gap to momentum (tighter when a long name takes two lines).
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        momentum
                    }
                    modePicker
                    switch mode {
                    case .strength(let dayType): strength(dayType)
                    case .running: RunContent()
                    }
                    if case .strength = mode, Theme.storybook { poohCorner }
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
            mode = ActiveRunClock.resumableRunID() != nil ? .running : .strength(model.resumeDayType ?? model.nextDayType)
            model.resumeDayType = nil
            let split = model.splitState
            duration = EngineConfig.default.durationBucket(nearest: split.defaultDurationMin)
            model.ensureSeededLocations()
            location = model.locations.first { $0.id == split.defaultLocationId } ?? model.locations.first
            model.restoreActiveSession()
        }
        .onChange(of: model.locations.map(\.id)) { _, ids in
            // The chosen gym was deleted in Settings: fall back to the default, then the first remaining gym.
            if let location, !ids.contains(location.id) {
                self.location = model.locations.first { $0.id == model.splitState.defaultLocationId } ?? model.locations.first
            }
        }
        .sheet(isPresented: $showProgress) { ProgressScreen() }
    }

    // MARK: Header

    var header: some View {
        GreetingHeader(overline: Date.now.formatted(.dateTime.weekday(.wide).month().day()),
                       greeting: Greeting(displayName: model.settings?.displayName ?? ""),
                       spacingBelow: Theme.Spacing.xl, compactSpacingBelow: Theme.Spacing.s) {
            IconButton("chart.xyaxis.line", label: "Progress") { showProgress = true }
            Button { model.showSettings = true } label: { Avatar(name: model.settings?.displayName ?? "") }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Profile")
        }
        .background(alignment: .topTrailing) {
            // A cloud drifting past behind the controls, the way the sky sits behind every page in the book.
            Cloud(width: 58, drift: 9).opacity(0.9).offset(x: -112, y: -10).storybookOnly()
        }
    }

    /// Pooh wandering in from the right-hand margin, footprints behind him, to see what we're up to.
    var poohCorner: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Footprints(count: 7).frame(height: 30).padding(.bottom, Theme.Spacing.s)
            Illustration(.poohStanding, wash: Theme.Colors.honey, washOpacity: 0.22).frame(height: 132)
                .padding(.trailing, Theme.Spacing.s)
        }
        .padding(.top, Theme.Spacing.s)
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

    /// This week at a glance, set straight on the canvas: two numbers, no box.
    var momentum: some View {
        let week = model.completedSessions(since: Date.startOfWeek)
        let last = model.completedSessions().first
        return HStack(alignment: .top, spacing: Theme.Spacing.l) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                HoneyPot(fill: min(1, Double(week.count) / 3), drip: week.count > 0, label: nil).frame(width: 30, height: 30).storybookOnly()
                Stat("\(week.count)", label: week.count == 1 ? "session this week" : "sessions this week", tint: Theme.Colors.honeyInk)
            }
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

    /// The day picker owns the middle of the screen: one tall row per day with what's heavy this time and when it
    /// was last done, so the choice is informed rather than a strip of tabs.
    var modePicker: some View {
        FlatSection("Workout", detail: Theme.storybook ? "pick a page" : nil) {
            VStack(spacing: 0) {
                ForEach(HomeMode.all, id: \.self) { m in
                    ModeRow(mode: m, subtitle: subtitle(m), isNext: m == .strength(model.nextDayType), selected: m == mode) {
                        withAnimation(Theme.Motion.quick) { mode = m }
                    }
                }
            }
        }
    }

    func subtitle(_ m: HomeMode) -> String {
        switch m {
        case .running:
            return "This week's plan"
        case .strength(let d):
            let heavy = (model.splitState.heavyRotations[d]?.current ?? model.catalog.heavyRotationDefaults[d]?.first)
                .map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
            let last = model.completedSessions().first { $0.dayType == d }.map { "last \(dayLabel($0.performedAt).lowercased())" } ?? "not yet done"
            return [heavy.map { "Heavy: \($0)" }, last].compactMap { $0 }.joined(separator: " · ")
        }
    }

    // MARK: Strength

    @ViewBuilder func strength(_ dayType: DayType) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
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
        let sb = Theme.storybook
        return HStack(alignment: .center, spacing: sb ? Theme.Spacing.sm : Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                Glyph(icon, tint: Theme.Colors.textTertiary, width: 20)
                Overline(label, tint: Theme.Colors.textSecondary)
            }
            .frame(width: sb ? 96 : 104, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: sb ? Theme.Spacing.sm : Theme.Spacing.l) { options() }
                    .padding(.trailing, sb ? Theme.Spacing.m : 0)
            }
            // The page edge fades the last chip so a long gym list reads as scrollable.
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: sb ? 18 : 0)
                }
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
        location == nil ? "Build deck" : "Build \(dayType.label.lowercased()) deck"
    }
}

/// One choice in Home's day list: a character vignette on its wash, name, what makes this one different, and a
/// honey check when chosen.
struct ModeRow: View {
    let mode: HomeMode
    let subtitle: String
    let isNext: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                if Theme.storybook {
                    Illustration(mode.plate)
                        .frame(width: 40, height: 40)
                        .padding(6)
                        .background(WashBlob(color: mode.tint, opacity: selected ? 0.55 : 0.25).scaleEffect(1.15))
                        .saturation(selected ? 1 : 0.6)
                        .opacity(selected ? 1 : 0.7)
                } else {
                    Image(systemName: mode.symbol).font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(selected ? mode.tint : Theme.Colors.textTertiary)
                        .frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Theme.Spacing.s) {
                        Text(mode.label).font(Theme.Fonts.heading)
                            .foregroundStyle(selected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        if isNext { Aside("up next", tint: Theme.Colors.honeyInk) }
                    }
                    Text(subtitle).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary).lineLimit(1)
                }
                Spacer()
                if Theme.storybook {
                    ZStack {
                        Circle().fill(Theme.Colors.honey).frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(Theme.Colors.ink.opacity(0.7), lineWidth: 1.2))
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.Colors.ink)
                    }
                    .opacity(selected ? 1 : 0)
                    .scaleEffect(selected ? 1 : 0.6)
                    .animation(Theme.Motion.quick, value: selected)
                } else {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.Colors.brass)
                        .opacity(selected ? 1 : 0)
                }
            }
            .frame(minHeight: Theme.storybook ? 68 : 64)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Hairline() }
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
