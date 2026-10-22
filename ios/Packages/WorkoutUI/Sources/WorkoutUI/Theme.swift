import SwiftUI
import WorkoutEngine

/// §8 design tokens. Dark-first, one warm metallic accent, muted day hues. No gamification.
public enum Theme {
    public enum Colors {
        public static let canvas = Color(hex: 0x0B0B0C)
        public static let card = Color(hex: 0x141416)
        public static let cardRaised = Color(hex: 0x1C1C1F)
        public static let hairline = Color.white.opacity(0.08)
        public static let textPrimary = Color(hex: 0xF5F5F7)
        public static let textSecondary = Color(hex: 0x9A9AA0)
        public static let textTertiary = Color(hex: 0x5E5E64)
        public static let brass = Color(hex: 0xC8A96A)
        public static let brassDim = Color(hex: 0xC8A96A).opacity(0.18)
        public static let partner = Color(hex: 0x8FA3B8)
        public static let push = Color(hex: 0xB07D6E)
        public static let pull = Color(hex: 0x6E8FA3)
        public static let legs = Color(hex: 0x7E9A7A)
        public static let fullBody = Color(hex: 0x9A8AA3)
        public static let run = Color(hex: 0xA39A6E)
        public static let destructive = Color(hex: 0xB5635E)

        public static func day(_ d: DayType) -> Color {
            switch d { case .push: push; case .pull: pull; case .legs: legs; case .fullBody: fullBody }
        }
    }

    public enum Fonts {
        /// One big number per screen.
        public static let display = Font.system(size: 64, weight: .light, design: .default).monospacedDigit()
        public static let title = Font.system(size: 28, weight: .semibold)
        public static let heading = Font.system(size: 20, weight: .semibold)
        public static let body = Font.system(size: 17, weight: .regular)
        public static let bodyMedium = Font.system(size: 17, weight: .medium)
        public static let caption = Font.system(size: 13, weight: .medium)
        public static let overline = Font.system(size: 11, weight: .semibold)
        public static let numeral = Font.system(size: 34, weight: .medium).monospacedDigit()
    }

    public enum Spacing {
        public static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 16, l: CGFloat = 24, xl: CGFloat = 32, xxl: CGFloat = 48
    }

    public enum Radius {
        public static let card: CGFloat = 28
        public static let control: CGFloat = 14
        public static let chip: CGFloat = 10
    }

    public enum Motion {
        public static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)
        public static let quick = Animation.spring(response: 0.25, dampingFraction: 0.9)
    }
}

public extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: 1)
    }
}

public struct Overline: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text.uppercased()).font(Theme.Fonts.overline).tracking(1.6).foregroundStyle(Theme.Colors.textTertiary)
    }
}

/// Continuous-corner card surface, the only container in the app.
public struct Card<Content: View>: View {
    let raised: Bool
    let content: Content
    public init(raised: Bool = false, @ViewBuilder content: () -> Content) { self.raised = raised; self.content = content() }
    public var body: some View {
        content
            .padding(Theme.Spacing.l)
            .background(raised ? Theme.Colors.cardRaised : Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.Colors.hairline, lineWidth: 1))
    }
}

public struct Hairline: View {
    public init() {}
    public var body: some View { Rectangle().fill(Theme.Colors.hairline).frame(height: 1) }
}

/// Single accent button. Filled brass for the one primary action per screen, else quiet.
public struct PillButton: View {
    public enum Style { case primary, quiet, destructive }
    let title: String
    let style: Style
    let action: () -> Void
    public init(_ title: String, style: Style = .primary, action: @escaping () -> Void) {
        self.title = title; self.style = style; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Text(title).font(Theme.Fonts.bodyMedium).frame(maxWidth: .infinity).padding(.vertical, 16)
        }
        .foregroundStyle(foreground)
        .background(background, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).strokeBorder(style == .quiet ? Theme.Colors.hairline : .clear, lineWidth: 1))
        .buttonStyle(PressStyle())
    }
    var foreground: Color {
        switch style { case .primary: Theme.Colors.canvas; case .quiet: Theme.Colors.textPrimary; case .destructive: Theme.Colors.destructive }
    }
    var background: Color {
        switch style { case .primary: Theme.Colors.brass; case .quiet: Theme.Colors.cardRaised; case .destructive: Theme.Colors.destructive.opacity(0.12) }
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

/// Small day-type tint dot + label; the only place colour names a day.
public struct DayTag: View {
    let day: DayType
    public init(_ day: DayType) { self.day = day }
    public var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.Colors.day(day)).frame(width: 6, height: 6)
            Text(day.label).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

public struct Screen<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        ZStack { Theme.Colors.canvas.ignoresSafeArea(); content }
            .preferredColorScheme(.dark)
            .tint(Theme.Colors.brass)
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
            Text(label).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            HStack(spacing: 0) {
                button("minus") { value = max(range.lowerBound, value - step) }
                Rectangle().fill(Theme.Colors.hairline).frame(width: 1, height: 20)
                button("plus") { value = min(range.upperBound, value + step) }
            }
            .background(Theme.Colors.cardRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous).strokeBorder(Theme.Colors.hairline, lineWidth: 1))
        }
    }
    /// Plain tap targets rather than `Button`s: inside a `List` row (with `.onMove`) sibling buttons
    /// can lose taps to the row's own gestures; a tap gesture on a shaped view does not.
    func button(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.Colors.textPrimary)
            .frame(width: 44, height: 36)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(icon == "minus" ? "Decrease" : "Increase")
    }
}

public extension Binding where Value == Int {
    var asDouble: Binding<Double> { Binding<Double>(get: { Double(wrappedValue) }, set: { wrappedValue = Int($0) }) }
}
