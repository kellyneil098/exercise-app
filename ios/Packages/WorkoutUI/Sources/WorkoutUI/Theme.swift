import SwiftUI
import WorkoutEngine

/// Design tokens. 60/30/10: a near-black canvas (60%), one neutral ramp for surfaces and type (30%), brass
/// for the primary action, live state and the user's own data (10%). Four type sizes, two weights, an 8-pt grid,
/// soft shadows tinted to the canvas, and a quiet glow behind the one element each screen is about.
public enum Theme {
    public enum Colors {
        public static let canvas = Color(hex: 0x0B0B0C)
        public static let card = Color(hex: 0x151517)
        public static let cardRaised = Color(hex: 0x1D1D21)
        /// Translucent neutral for inputs and unselected chips.
        public static let surface = Color.white.opacity(0.05)
        public static let hairline = Color.white.opacity(0.08)
        /// One neutral, three opacities: 100 / 70 / 45.
        public static let textPrimary = Color(hex: 0xF5F5F7)
        public static let textSecondary = Color(hex: 0xF5F5F7).opacity(0.7)
        public static let textTertiary = Color(hex: 0xF5F5F7).opacity(0.45)
        public static let brass = Color(hex: 0xD4B275)
        public static let brassDeep = Color(hex: 0xB08E4C)
        /// Accent at 5–6% for secondary buttons and card highlights, ~10% for their borders.
        public static let brassSoft = Color(hex: 0xD4B275).opacity(0.06)
        public static let brassBorder = Color(hex: 0xD4B275).opacity(0.14)
        public static let brassDim = Color(hex: 0xD4B275).opacity(0.18)
        /// Shadows are tinted toward the canvas's warm black, never flat grey.
        public static let shadow = Color(hex: 0x0E0A04).opacity(0.6)
        public static let partner = Color(hex: 0x8FA3B8)
        public static let push = Color(hex: 0xC98B7A)
        public static let pull = Color(hex: 0x7A9FC9)
        public static let legs = Color(hex: 0x8BB088)
        public static let fullBody = Color(hex: 0xAB98BA)
        public static let run = Color(hex: 0xC2B47A)
        public static let destructive = Color(hex: 0xC9706A)
        /// Swipe cues on the set card (§7): the one place the app uses green / red / blue.
        public static let swipeDone = Color(hex: 0x5FAE7A)
        public static let swipeSkip = Color(hex: 0xC9625C)
        public static let swipeRate = Color(hex: 0x5F8FD6)

        public static func day(_ d: DayType) -> Color {
            switch d { case .push: push; case .pull: pull; case .legs: legs; case .fullBody: fullBody }
        }
    }

    /// Four sizes (56 / 28 / 17 / 13), two weights (regular / bold). Numbers are always monospaced.
    public enum Fonts {
        public static let display = Font.system(size: 56, weight: .bold).monospacedDigit()
        public static let title = Font.system(size: 28, weight: .bold)
        public static let numeral = Font.system(size: 28, weight: .bold).monospacedDigit()
        public static let heading = Font.system(size: 17, weight: .bold)
        public static let body = Font.system(size: 17, weight: .regular)
        public static let bodyMedium = Font.system(size: 17, weight: .bold)
        public static let caption = Font.system(size: 13, weight: .regular)
        public static let captionBold = Font.system(size: 13, weight: .bold).monospacedDigit()
        public static let overline = Font.system(size: 13, weight: .bold)
    }

    /// 8-pt grid; 4 and 12 only inside compound controls.
    public enum Spacing {
        public static let xs: CGFloat = 4, s: CGFloat = 8, sm: CGFloat = 12, m: CGFloat = 16, l: CGFloat = 24, xl: CGFloat = 32, xxl: CGFloat = 48
    }

    public enum Radius {
        public static let card: CGFloat = 24
        public static let control: CGFloat = 16
        public static let chip: CGFloat = 12
    }

    public enum Motion {
        public static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)
        public static let quick = Animation.spring(response: 0.25, dampingFraction: 0.9)
        public static let celebrate = Animation.spring(response: 0.6, dampingFraction: 0.7)
    }
}

public extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}

// MARK: - Modifiers

public extension View {
    /// Soft, canvas-tinted drop shadow.
    func softShadow(_ radius: CGFloat = 24, y: CGFloat = 12) -> some View {
        shadow(color: Theme.Colors.shadow, radius: radius, x: 0, y: y)
    }

    /// Blurred colour wash behind the element: the screen's one focal point.
    func glow(_ color: Color = Theme.Colors.brass, radius: CGFloat = 48, opacity: Double = 0.35) -> some View {
        background(
            Circle().fill(color.opacity(opacity)).blur(radius: radius).padding(-radius / 2)
                .allowsHitTesting(false)
        )
    }

    /// Hero numbers: tight tracking so the digits read as one object.
    func heroTracking() -> some View { tracking(-1.5) }
}

/// Top-edge light: a thin gradient stroke that fades from white to the accent, standing in for an inner shadow.
struct EdgeLight: View {
    let radius: CGFloat
    var strength: Double = 1
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
                LinearGradient(colors: [Color.white.opacity(0.14 * strength), Theme.Colors.brassBorder.opacity(strength)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
    }
}

// MARK: - Text

public struct Overline: View {
    let text: String
    var tint: Color = Theme.Colors.textTertiary
    public init(_ text: String, tint: Color = Theme.Colors.textTertiary) { self.text = text; self.tint = tint }
    public var body: some View {
        Text(text.uppercased()).font(Theme.Fonts.overline).tracking(1.2).foregroundStyle(tint)
    }
}

// MARK: - Surfaces

/// Continuous-corner card surface, the only container in the app. Depth from a soft tinted shadow and a
/// top-edge light, not from borders.
public struct Card<Content: View>: View {
    let raised: Bool
    let padding: CGFloat
    let content: Content
    public init(raised: Bool = false, padding: CGFloat = Theme.Spacing.l, @ViewBuilder content: () -> Content) {
        self.raised = raised; self.padding = padding; self.content = content()
    }
    public var body: some View {
        content
            .padding(padding)
            .background(raised ? Theme.Colors.cardRaised : Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(EdgeLight(radius: Theme.Radius.card, strength: raised ? 1 : 0.7))
            .softShadow(raised ? 32 : 20, y: raised ? 16 : 10)
    }
}

public struct Hairline: View {
    public init() {}
    public var body: some View { Rectangle().fill(Theme.Colors.hairline).frame(height: 1) }
}

/// Canvas with a faint brass wash at the top, so every screen shares the same warm light.
public struct Screen<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        ZStack(alignment: .top) {
            Theme.Colors.canvas.ignoresSafeArea()
            LinearGradient(colors: [Theme.Colors.brass.opacity(0.09), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 360)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            content
        }
        .preferredColorScheme(.dark)
        .tint(Theme.Colors.brass)
    }
}

// MARK: - Controls

/// Single accent button. Filled brass with a top light for the one primary action per screen; `quiet` is the
/// accent at 5% with a 10% border; `destructive` is reserved for throwing work away.
public struct PillButton: View {
    public enum Style { case primary, quiet, destructive }
    let title: String
    let icon: String?
    let style: Style
    let action: () -> Void
    public init(_ title: String, icon: String? = nil, style: Style = .primary, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.style = style; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                if let icon { Image(systemName: icon).font(.system(size: 16, weight: .bold)) }
                Text(title).font(Theme.Fonts.bodyMedium)
            }
            .frame(maxWidth: .infinity).frame(height: 56)
        }
        .foregroundStyle(foreground)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                .strokeBorder(border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .shadow(color: style == .primary ? Theme.Colors.brass.opacity(0.3) : .clear, radius: 20, y: 8)
        .buttonStyle(PressStyle())
    }
    var foreground: Color {
        switch style { case .primary: Theme.Colors.canvas; case .quiet: Theme.Colors.textPrimary; case .destructive: Theme.Colors.destructive }
    }
    @ViewBuilder var background: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        switch style {
        case .primary:
            shape.fill(LinearGradient(colors: [Theme.Colors.brass, Theme.Colors.brassDeep], startPoint: .top, endPoint: .bottom))
        case .quiet: shape.fill(Theme.Colors.brassSoft)
        case .destructive: shape.fill(Theme.Colors.destructive.opacity(0.1))
        }
    }
    var border: LinearGradient {
        switch style {
        case .primary: LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0)], startPoint: .top, endPoint: .bottom)
        case .quiet: LinearGradient(colors: [Theme.Colors.brassBorder], startPoint: .top, endPoint: .bottom)
        case .destructive: LinearGradient(colors: [Theme.Colors.destructive.opacity(0.2)], startPoint: .top, endPoint: .bottom)
        }
    }
}

public struct PressStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

/// Selectable chip: optional leading symbol or tint dot, selected state in the accent.
public struct Chip: View {
    let title: String
    let icon: String?
    let dot: Color?
    let selected: Bool
    let action: () -> Void
    public init(_ title: String, icon: String? = nil, dot: Color? = nil, selected: Bool, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.dot = dot; self.selected = selected; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .bold)) }
                Text(title).font(selected ? Theme.Fonts.captionBold : Theme.Fonts.caption).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, Theme.Spacing.m).frame(height: 40)
            .background(selected ? Theme.Colors.brassDim : Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .strokeBorder(selected ? Theme.Colors.brass.opacity(0.5) : Theme.Colors.hairline, lineWidth: 1))
            .foregroundStyle(selected ? Theme.Colors.brass : Theme.Colors.textSecondary)
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Round icon button for headers and toolbars: a 44-pt target on a soft surface.
public struct IconButton: View {
    let icon: String
    let label: String
    var tint: Color = Theme.Colors.textPrimary
    let action: () -> Void
    public init(_ icon: String, label: String, tint: Color = Theme.Colors.textPrimary, action: @escaping () -> Void) {
        self.icon = icon; self.label = label; self.tint = tint; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(Theme.Colors.surface, in: Circle())
                .overlay(Circle().strokeBorder(Theme.Colors.hairline, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

/// Symbol on a soft colour-coded square: the visual cue in front of a row or category.
public struct IconTile: View {
    let icon: String
    let tint: Color
    var size: CGFloat = 40
    public init(_ icon: String, tint: Color = Theme.Colors.brass, size: CGFloat = 40) { self.icon = icon; self.tint = tint; self.size = size }
    public var body: some View {
        Image(systemName: icon).font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// Initials on a brass disc: the user, not a generic person glyph.
public struct Avatar: View {
    let name: String
    var size: CGFloat = 44
    public init(name: String, size: CGFloat = 44) { self.name = name; self.size = size }
    var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap(\.first)
        return parts.isEmpty ? "?" : String(parts).uppercased()
    }
    public var body: some View {
        Text(initials).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(Theme.Colors.canvas)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Theme.Colors.brass, Theme.Colors.brassDeep], startPoint: .top, endPoint: .bottom), in: Circle())
            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
            .accessibilityLabel(name)
    }
}

/// Thin momentum bar: how far through the thing you are.
public struct ProgressBar: View {
    let progress: Double
    var tint: Color = Theme.Colors.brass
    var height: CGFloat = 6
    public init(_ progress: Double, tint: Color = Theme.Colors.brass, height: CGFloat = 6) { self.progress = progress; self.tint = tint; self.height = height }
    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.surface)
                Capsule().fill(tint)
                    .frame(width: max(height, geo.size.width * max(0, min(1, progress))))
                    .shadow(color: tint.opacity(0.5), radius: 6)
            }
        }
        .frame(height: height)
        .animation(Theme.Motion.spring, value: progress)
    }
}

/// Segmented momentum indicator: one pill per step, filled as they're done.
public struct Segments: View {
    let done: Int
    let total: Int
    var tint: Color = Theme.Colors.brass
    public init(done: Int, total: Int, tint: Color = Theme.Colors.brass) { self.done = done; self.total = total; self.tint = tint }
    public var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(0..<max(total, 0), id: \.self) { i in
                Capsule().fill(i < done ? tint : Theme.Colors.surface).frame(height: 6)
                    .shadow(color: i < done ? tint.opacity(0.5) : .clear, radius: 4)
            }
            if done > total { Text("+\(done - total)").font(Theme.Fonts.captionBold).foregroundStyle(Theme.Colors.textTertiary) }
        }
        .animation(Theme.Motion.spring, value: done)
    }
}

/// Value first, label second: the number is what the user came for.
public struct Stat: View {
    let value: String
    let unit: String?
    let label: String
    var tint: Color = Theme.Colors.textPrimary
    public init(_ value: String, unit: String? = nil, label: String, tint: Color = Theme.Colors.textPrimary) {
        self.value = value; self.unit = unit; self.label = label; self.tint = tint
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .lastTextBaseline, spacing: Theme.Spacing.xs) {
                Text(value).font(Theme.Fonts.numeral).foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.7)
                if let unit { Text(unit).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary) }
            }
            Text(label).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
        }
    }
}

/// Small day-type tint dot + label; the only place colour names a day.
public struct DayTag: View {
    let day: DayType
    public init(_ day: DayType) { self.day = day }
    public var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.Colors.day(day)).frame(width: 8, height: 8)
                .shadow(color: Theme.Colors.day(day).opacity(0.7), radius: 4)
            Text(day.label).font(Theme.Fonts.captionBold).foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

public extension DayType {
    /// Symbol for each day, used wherever the day is a tappable option.
    var symbol: String {
        switch self { case .push: "arrow.up.right"; case .pull: "arrow.down.left"; case .legs: "figure.strengthtraining.functional"; case .fullBody: "figure.mixed.cardio" }
    }
}

public enum Haptics {
    public enum Kind { case setLogged, exerciseDone, sessionDone, swap, warning }
    @MainActor public static func play(_ kind: Kind) {
        #if os(iOS)
        switch kind {
        case .setLogged: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .exerciseDone: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .sessionDone: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .swap: UISelectionFeedbackGenerator().selectionChanged()
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        #endif
    }
}

/// Quiet numeric control replacing the stock Stepper: label left, −/+ right.
public struct Adjuster: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    public init(_ label: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 1) {
        self.label = label; _value = value; self.range = range; self.step = step
    }
    public var body: some View {
        HStack {
            Text(label).font(Theme.Fonts.body).monospacedDigit().foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            HStack(spacing: 0) {
                button("minus") { value = max(range.lowerBound, value - step) }
                Rectangle().fill(Theme.Colors.hairline).frame(width: 1, height: 20)
                button("plus") { value = min(range.upperBound, value + step) }
            }
            .background(Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous).strokeBorder(Theme.Colors.brassBorder, lineWidth: 1))
        }
    }
    /// Plain tap targets rather than `Button`s: inside a `List` row (with `.onMove`) sibling buttons
    /// can lose taps to the row's own gestures; a tap gesture on a shaped view does not.
    func button(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.Colors.brass)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(icon == "minus" ? "Decrease" : "Increase")
    }
}

public extension Binding where Value == Int {
    var asDouble: Binding<Double> { Binding<Double>(get: { Double(wrappedValue) }, set: { wrappedValue = Int($0) }) }
}
