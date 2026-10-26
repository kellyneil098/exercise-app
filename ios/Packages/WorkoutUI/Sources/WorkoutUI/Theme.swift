import SwiftUI
import WorkoutEngine
#if os(iOS)
import UIKit
#endif

// MARK: - Themes

/// The design systems the app can wear. `classic` is the original near-black canvas with a brass accent;
/// `hundredAcreWood` is the light "Winnie the Pooh" storybook. Adding a theme is one more case plus its `ThemeSpec`.
public enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case classic, hundredAcreWood

    public var id: String { rawValue }
    public var displayName: String {
        switch self { case .classic: "Default"; case .hundredAcreWood: "Winnie the Pooh" }
    }
    public var subtitle: String {
        switch self { case .classic: "Dark, brass, matter-of-fact"; case .hundredAcreWood: "A storybook in your pocket" }
    }
    /// Alternate app icon that goes with the theme (`nil` = the primary icon).
    public var alternateIconName: String? {
        switch self { case .classic: nil; case .hundredAcreWood: "AppIcon-Hunny" }
    }
    public var spec: ThemeSpec {
        switch self { case .classic: .classic; case .hundredAcreWood: .hundredAcreWood }
    }

    public static let defaultsKey = "appTheme"
    /// Existing users keep `classic` until they pick something else.
    public static func load(from defaults: UserDefaults = .standard) -> AppTheme {
        defaults.string(forKey: defaultsKey).flatMap(AppTheme.init(rawValue:)) ?? .classic
    }
    public func save(to defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.defaultsKey) }
}

/// Everything a theme decides: colour scheme, tokens, and whether the storybook decorations (bees, balloons, honey
/// pots, Shepard plates, rubber stamps) are drawn.
public struct ThemeSpec: Sendable {
    public let id: AppTheme
    public let colorScheme: ColorScheme
    public let storybook: Bool
    public let colors: ThemeColors
    public let fonts: ThemeFonts
    public let radius: ThemeRadius

    public static let classic = ThemeSpec(id: .classic, colorScheme: .dark, storybook: false, colors: .classic, fonts: .classic, radius: .classic)
    public static let hundredAcreWood = ThemeSpec(id: .hundredAcreWood, colorScheme: .light, storybook: true, colors: .hundredAcreWood, fonts: .hundredAcreWood, radius: .hundredAcreWood)
}

public struct ThemeColors: Sendable {
    // Surfaces
    public let canvas, card, cardRaised, surface, hairline: Color
    // Text: one neutral at 100 / 70 / 45.
    public let textPrimary, textSecondary, textTertiary: Color
    // Accent (brass in classic, honey in the storybook)
    public let brass, brassDeep, brassLight, brassSoft, brassBorder, brassDim, accentText, shadow: Color
    public let tint: Color
    // Day types and roles
    public let partner, push, pull, legs, fullBody, run, destructive: Color
    public let swipeDone, swipeSkip, swipeRate: Color
    // Washes (storybook); mapped to the nearest classic tint so nothing is hard-wired to one theme.
    public let leaf, moss, sky, skyDeep, piglet, pigletDeep, eeyore, carrot, bark, balloon, jam: Color

    /// Every token, for the completeness test.
    public var all: [Color] {
        [canvas, card, cardRaised, surface, hairline, textPrimary, textSecondary, textTertiary, brass, brassDeep, brassLight, brassSoft,
         brassBorder, brassDim, accentText, shadow, tint, partner, push, pull, legs, fullBody, run, destructive, swipeDone, swipeSkip,
         swipeRate, leaf, moss, sky, skyDeep, piglet, pigletDeep, eeyore, carrot, bark, balloon, jam]
    }

    public static let classic: ThemeColors = {
        let text = Color(hex: 0xF5F5F7), brass = Color(hex: 0xD4B275)
        let push = Color(hex: 0xC98B7A), pull = Color(hex: 0x7A9FC9), legs = Color(hex: 0x8BB088), full = Color(hex: 0xAB98BA), run = Color(hex: 0xC2B47A)
        let partner = Color(hex: 0x8FA3B8), destructive = Color(hex: 0xC9706A)
        return ThemeColors(
            canvas: Color(hex: 0x0B0B0C), card: Color(hex: 0x151517), cardRaised: Color(hex: 0x1D1D21),
            surface: Color.white.opacity(0.05), hairline: Color.white.opacity(0.08),
            textPrimary: text, textSecondary: text.opacity(0.7), textTertiary: text.opacity(0.45),
            brass: brass, brassDeep: Color(hex: 0xB08E4C), brassLight: Color(hex: 0xE8CFA0), brassSoft: brass.opacity(0.06),
            brassBorder: brass.opacity(0.14), brassDim: brass.opacity(0.18), accentText: brass, shadow: Color(hex: 0x0E0A04).opacity(0.6), tint: brass,
            partner: partner, push: push, pull: pull, legs: legs, fullBody: full, run: run, destructive: destructive,
            swipeDone: Color(hex: 0x5FAE7A), swipeSkip: Color(hex: 0xC9625C), swipeRate: Color(hex: 0x5F8FD6),
            leaf: legs, moss: legs, sky: pull, skyDeep: pull, piglet: run, pigletDeep: run, eeyore: partner, carrot: push,
            bark: Color(hex: 0xB08E4C), balloon: destructive, jam: destructive)
    }()

    public static let hundredAcreWood: ThemeColors = {
        let ink = Color(hex: 0x3B2A1A), honey = Color(hex: 0xF2B134), honeyDeep = Color(hex: 0xE59A1C), honeyLight = Color(hex: 0xFFD56B)
        let honeyInk = Color(hex: 0x9C6410), leaf = Color(hex: 0x8FAE6B), sky = Color(hex: 0xA9D3EA), piglet = Color(hex: 0xF2B7C4)
        let eeyore = Color(hex: 0x9BA7B4), carrot = Color(hex: 0xE8894A), jam = Color(hex: 0xD2614F)
        return ThemeColors(
            canvas: Color(hex: 0xFBF3E1), card: Color(hex: 0xFFFBF2), cardRaised: Color(hex: 0xF3E6C8),
            surface: ink.opacity(0.05), hairline: ink.opacity(0.2),
            textPrimary: ink, textSecondary: ink.opacity(0.7), textTertiary: ink.opacity(0.45),
            brass: honey, brassDeep: honeyDeep, brassLight: honeyLight, brassSoft: honey.opacity(0.16),
            brassBorder: ink.opacity(0.35), brassDim: honey.opacity(0.32), accentText: honeyInk, shadow: Color(hex: 0xB37A12).opacity(0.18), tint: honeyInk,
            partner: eeyore, push: honey, pull: carrot, legs: leaf, fullBody: sky, run: piglet, destructive: jam,
            swipeDone: Color(hex: 0x6FA866), swipeSkip: jam, swipeRate: Color(hex: 0x5B9BD5),
            leaf: leaf, moss: Color(hex: 0x5E7F49), sky: sky, skyDeep: Color(hex: 0x5B9BD5), piglet: piglet, pigletDeep: Color(hex: 0xD2778E),
            eeyore: eeyore, carrot: carrot, bark: Color(hex: 0x8B5E3C), balloon: Color(hex: 0xD9534F), jam: jam)
    }()
}

public struct ThemeFonts: Sendable {
    public let hero, display, title, titleSmall, greeting, numeral, heading, quip, quipSmall, stamp, body, bodyMedium, caption, captionBold, overline: Font
    public var all: [Font] { [hero, display, title, titleSmall, greeting, numeral, heading, quip, quipSmall, stamp, body, bodyMedium, caption, captionBold, overline] }

    /// Four sizes (56 / 28 / 17 / 13), two weights (regular / bold). Numbers are always monospaced.
    public static let classic = ThemeFonts(
        hero: Font.system(size: 56, weight: .bold).monospacedDigit(),
        display: Font.system(size: 56, weight: .bold).monospacedDigit(),
        title: Font.system(size: 28, weight: .bold),
        titleSmall: Font.system(size: 28, weight: .bold),
        greeting: Font.system(size: 28, weight: .bold),
        numeral: Font.system(size: 28, weight: .bold).monospacedDigit(),
        heading: Font.system(size: 17, weight: .bold),
        quip: Font.system(size: 13, weight: .regular),
        quipSmall: Font.system(size: 13, weight: .regular),
        stamp: Font.system(size: 24, weight: .bold),
        body: Font.system(size: 17, weight: .regular),
        bodyMedium: Font.system(size: 17, weight: .bold),
        caption: Font.system(size: 13, weight: .regular),
        captionBold: Font.system(size: 13, weight: .bold).monospacedDigit(),
        overline: Font.system(size: 13, weight: .bold))

    /// Serif (New York) for headlines and quips, rounded for body, big rounded monospaced digits for numbers.
    public static let hundredAcreWood = ThemeFonts(
        hero: Font.system(size: 72, weight: .heavy, design: .rounded).monospacedDigit(),
        display: Font.system(size: 60, weight: .heavy, design: .rounded).monospacedDigit(),
        title: Font.system(size: 30, weight: .bold, design: .serif),
        titleSmall: Font.system(size: 24, weight: .bold, design: .serif),
        greeting: Font.system(size: 32, weight: .semibold, design: .serif).italic(),
        numeral: Font.system(size: 28, weight: .bold, design: .rounded).monospacedDigit(),
        heading: Font.system(size: 19, weight: .bold, design: .serif),
        quip: Font.system(size: 17, weight: .regular, design: .serif).italic(),
        quipSmall: Font.system(size: 14, weight: .regular, design: .serif).italic(),
        stamp: Font.system(size: 30, weight: .black, design: .serif).italic(),
        body: Font.system(size: 17, weight: .regular, design: .rounded),
        bodyMedium: Font.system(size: 17, weight: .semibold, design: .rounded),
        caption: Font.system(size: 13, weight: .regular, design: .rounded),
        captionBold: Font.system(size: 13, weight: .bold, design: .rounded).monospacedDigit(),
        overline: Font.system(size: 12, weight: .bold, design: .rounded))
}

public struct ThemeRadius: Sendable {
    public let card, control, chip: CGFloat
    public static let classic = ThemeRadius(card: 24, control: 16, chip: 12)
    public static let hundredAcreWood = ThemeRadius(card: 24, control: 20, chip: 14)
}

private struct ThemeKey: EnvironmentKey { static let defaultValue: ThemeSpec = .classic }
public extension EnvironmentValues {
    /// The active design system. Primitives read it; the root re-identifies its subtree when it changes so the
    /// static `Theme.*` tokens (which resolve through `Theme.current`) are re-read everywhere.
    var theme: ThemeSpec {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

// MARK: - Static tokens

/// Static access to the active theme's tokens, so call sites stay `Theme.Colors.brass` whatever the look.
public enum Theme {
    nonisolated(unsafe) public static var current: ThemeSpec = .classic

    public enum Colors {
        public static var canvas: Color { Theme.current.colors.canvas }
        public static var card: Color { Theme.current.colors.card }
        public static var cardRaised: Color { Theme.current.colors.cardRaised }
        public static var surface: Color { Theme.current.colors.surface }
        public static var hairline: Color { Theme.current.colors.hairline }
        public static var textPrimary: Color { Theme.current.colors.textPrimary }
        public static var textSecondary: Color { Theme.current.colors.textSecondary }
        public static var textTertiary: Color { Theme.current.colors.textTertiary }
        public static var brass: Color { Theme.current.colors.brass }
        public static var brassDeep: Color { Theme.current.colors.brassDeep }
        public static var brassSoft: Color { Theme.current.colors.brassSoft }
        public static var brassBorder: Color { Theme.current.colors.brassBorder }
        public static var brassDim: Color { Theme.current.colors.brassDim }
        public static var shadow: Color { Theme.current.colors.shadow }
        public static var partner: Color { Theme.current.colors.partner }
        public static var push: Color { Theme.current.colors.push }
        public static var pull: Color { Theme.current.colors.pull }
        public static var legs: Color { Theme.current.colors.legs }
        public static var fullBody: Color { Theme.current.colors.fullBody }
        public static var run: Color { Theme.current.colors.run }
        public static var destructive: Color { Theme.current.colors.destructive }
        public static var swipeDone: Color { Theme.current.colors.swipeDone }
        public static var swipeSkip: Color { Theme.current.colors.swipeSkip }
        public static var swipeRate: Color { Theme.current.colors.swipeRate }
        // Storybook names
        public static var parchment: Color { Theme.current.colors.canvas }
        public static var paper: Color { Theme.current.colors.card }
        public static var aged: Color { Theme.current.colors.cardRaised }
        public static var ink: Color { Theme.current.colors.textPrimary }
        public static var honey: Color { Theme.current.colors.brass }
        public static var honeyDeep: Color { Theme.current.colors.brassDeep }
        public static var honeyLight: Color { Theme.current.colors.brassLight }
        public static var honeyInk: Color { Theme.current.colors.accentText }
        public static var accentText: Color { Theme.current.colors.accentText }
        public static var leaf: Color { Theme.current.colors.leaf }
        public static var moss: Color { Theme.current.colors.moss }
        public static var sky: Color { Theme.current.colors.sky }
        public static var skyDeep: Color { Theme.current.colors.skyDeep }
        public static var piglet: Color { Theme.current.colors.piglet }
        public static var pigletDeep: Color { Theme.current.colors.pigletDeep }
        public static var eeyore: Color { Theme.current.colors.eeyore }
        public static var carrot: Color { Theme.current.colors.carrot }
        public static var bark: Color { Theme.current.colors.bark }
        public static var balloon: Color { Theme.current.colors.balloon }
        public static var jam: Color { Theme.current.colors.jam }

        public static func day(_ d: DayType) -> Color {
            switch d { case .push: push; case .pull: pull; case .legs: legs; case .fullBody: fullBody }
        }
        /// A darker companion for text or strokes on top of the day wash (the day colour itself in classic).
        public static func dayInk(_ d: DayType) -> Color {
            guard Theme.current.storybook else { return day(d) }
            switch d { case .push: return honeyInk; case .pull: return Color(hex: 0xA8531C); case .legs: return moss; case .fullBody: return skyDeep }
        }
    }

    public enum Fonts {
        public static var hero: Font { Theme.current.fonts.hero }
        public static var display: Font { Theme.current.fonts.display }
        public static var title: Font { Theme.current.fonts.title }
        public static var titleSmall: Font { Theme.current.fonts.titleSmall }
        public static var greeting: Font { Theme.current.fonts.greeting }
        public static var numeral: Font { Theme.current.fonts.numeral }
        public static var heading: Font { Theme.current.fonts.heading }
        public static var quip: Font { Theme.current.fonts.quip }
        public static var quipSmall: Font { Theme.current.fonts.quipSmall }
        public static var stamp: Font { Theme.current.fonts.stamp }
        public static var body: Font { Theme.current.fonts.body }
        public static var bodyMedium: Font { Theme.current.fonts.bodyMedium }
        public static var caption: Font { Theme.current.fonts.caption }
        public static var captionBold: Font { Theme.current.fonts.captionBold }
        public static var overline: Font { Theme.current.fonts.overline }
    }

    /// 8-pt grid; 4 and 12 only inside compound controls.
    public enum Spacing {
        public static let xs: CGFloat = 4, s: CGFloat = 8, sm: CGFloat = 12, m: CGFloat = 16, l: CGFloat = 24, xl: CGFloat = 32, xxl: CGFloat = 48
    }

    public enum Radius {
        public static var card: CGFloat { Theme.current.radius.card }
        public static var control: CGFloat { Theme.current.radius.control }
        public static var chip: CGFloat { Theme.current.radius.chip }
    }

    public enum Motion {
        public static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)
        public static let quick = Animation.spring(response: 0.25, dampingFraction: 0.9)
        public static let celebrate = Animation.spring(response: 0.6, dampingFraction: 0.7)
        public static let bob = Animation.easeInOut(duration: 3).repeatForever(autoreverses: true)
    }

    public enum Stroke {
        public static let outline: CGFloat = 1.5
        public static let dashed = StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 5])
    }

    /// Whether the storybook decorations are drawn.
    public static var storybook: Bool { current.storybook }
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

    /// Ink outline on a continuous-corner shape, the storybook equivalent of a border; the classic brass border otherwise.
    func inkOutline(_ radius: CGFloat, opacity: Double = 0.35, lineWidth: CGFloat = Theme.Stroke.outline) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(Theme.storybook ? Theme.Colors.ink.opacity(opacity) : Theme.Colors.brassBorder, lineWidth: Theme.storybook ? lineWidth : 1))
    }

    /// Irregular watercolour blob behind an illustration so it feels printed on the page (nothing in classic).
    func wash(_ color: Color, opacity: Double = 0.2, scale: CGFloat = 1.1) -> some View {
        background(WashBlob(color: color, opacity: opacity).scaleEffect(scale).allowsHitTesting(false))
    }

    /// Only in the storybook theme.
    @ViewBuilder func storybookOnly() -> some View {
        if Theme.storybook { self }
    }
}

/// A blurred, slightly lopsided ellipse: the watercolour wash under line art. Draws nothing in classic.
public struct WashBlob: View {
    let color: Color
    var opacity: Double = 0.2
    public init(color: Color, opacity: Double = 0.2) { self.color = color; self.opacity = opacity }
    public var body: some View {
        if Theme.storybook {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                Path { p in
                    p.move(to: CGPoint(x: w * 0.08, y: h * 0.5))
                    p.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.04), control1: CGPoint(x: w * 0.05, y: h * 0.12), control2: CGPoint(x: w * 0.3, y: h * -0.02))
                    p.addCurve(to: CGPoint(x: w * 0.95, y: h * 0.42), control1: CGPoint(x: w * 0.75, y: h * 0.08), control2: CGPoint(x: w * 1.02, y: h * 0.18))
                    p.addCurve(to: CGPoint(x: w * 0.55, y: h * 0.97), control1: CGPoint(x: w * 0.9, y: h * 0.75), control2: CGPoint(x: w * 0.8, y: h * 1.02))
                    p.addCurve(to: CGPoint(x: w * 0.08, y: h * 0.5), control1: CGPoint(x: w * 0.25, y: h * 0.92), control2: CGPoint(x: w * 0.1, y: h * 0.8))
                }
                .fill(color.opacity(opacity))
                .blur(radius: 1.5)
            }
        }
    }
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
        Text(text.uppercased()).font(Theme.Fonts.overline).tracking(Theme.storybook ? 1.6 : 1.2).foregroundStyle(tint)
    }
}

/// Serif italic aside, the book's narrator voice; a caption in classic.
public struct Quip: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text).font(Theme.Fonts.quip).foregroundStyle(Theme.Colors.textSecondary)
    }
}

/// A small label beside or above content: the narrator's aside in the storybook, an overline in classic.
public struct Aside: View {
    let text: String
    var tint: Color?
    public init(_ text: String, tint: Color? = nil) { self.text = text; self.tint = tint }
    public var body: some View {
        if Theme.storybook {
            Text(text).font(Theme.Fonts.quip).foregroundStyle(tint ?? Theme.Colors.textSecondary)
        } else {
            Overline(text, tint: tint ?? Theme.Colors.textTertiary)
        }
    }
}

/// Section title: serif heading in the storybook, the classic overline otherwise.
public struct SectionTitle: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        if Theme.storybook {
            Text(text).font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textPrimary)
        } else {
            Overline(text, tint: Theme.Colors.textSecondary)
        }
    }
}

// MARK: - Surfaces

/// The only container in the app. Classic: continuous-corner surface with a soft tinted shadow and a top-edge light.
/// Storybook: a page of paper with an ink outline; `plate` adds the dashed inner border of an illustration plate.
public struct Card<Content: View>: View {
    let raised: Bool
    let plate: Bool
    let padding: CGFloat
    let content: Content
    @Environment(\.theme) private var theme
    public init(raised: Bool = false, plate: Bool = false, padding: CGFloat = Theme.Spacing.l, @ViewBuilder content: () -> Content) {
        self.raised = raised; self.plate = plate; self.padding = padding; self.content = content()
    }
    public var body: some View {
        if theme.storybook {
            content
                .padding(padding)
                .background(Theme.Colors.paper, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay {
                    if plate {
                        RoundedRectangle(cornerRadius: Theme.Radius.card - 8, style: .continuous)
                            .strokeBorder(Theme.Colors.ink.opacity(0.25), style: Theme.Stroke.dashed)
                            .padding(8)
                            .allowsHitTesting(false)
                    }
                }
                .inkOutline(Theme.Radius.card, opacity: raised ? 0.55 : 0.35)
                .softShadow(raised ? 24 : 14, y: raised ? 12 : 6)
        } else {
            content
                .padding(padding)
                .background(raised ? Theme.Colors.cardRaised : Theme.Colors.card, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay(EdgeLight(radius: Theme.Radius.card, strength: raised ? 1 : 0.7))
                .softShadow(raised ? 32 : 20, y: raised ? 16 : 10)
        }
    }
}

/// Divider: a hairline in classic, a hand-drawn dashed ink line in the storybook.
public struct Hairline: View {
    public init() {}
    public var body: some View {
        if Theme.storybook {
            Line().stroke(Theme.Colors.ink.opacity(0.3), style: Theme.Stroke.dashed).frame(height: 1)
        } else {
            Rectangle().fill(Theme.Colors.hairline).frame(height: 1)
        }
    }
    struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path(); p.move(to: CGPoint(x: 0, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)); return p
        }
    }
}

/// Canvas with the theme's warm light at the top, so every screen shares it.
public struct Screen<Content: View>: View {
    let content: Content
    @Environment(\.theme) private var theme
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        ZStack(alignment: .top) {
            Theme.Colors.canvas.ignoresSafeArea()
            LinearGradient(colors: [theme.storybook ? Theme.Colors.honeyLight.opacity(0.28) : Theme.Colors.brass.opacity(0.09), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: theme.storybook ? 320 : 360)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            content
        }
        .preferredColorScheme(theme.colorScheme)
        .tint(theme.colors.tint)
    }
}

// MARK: - Controls

/// Single accent button for the one primary action per screen. Classic: filled brass with a top light; `quiet` is the
/// accent at 5% with a 10% border. Storybook: honey pill with an ink outline; `quiet` is paper with an ink outline.
public struct PillButton: View {
    public enum Style { case primary, quiet, destructive }
    let title: String
    let icon: String?
    let style: Style
    let action: () -> Void
    @Environment(\.theme) private var theme
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
            .foregroundStyle(foreground)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(border, lineWidth: theme.storybook ? Theme.Stroke.outline : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .shadow(color: shadowColor, radius: theme.storybook ? (style == .primary ? 14 : 8) : 20, y: theme.storybook ? 6 : 8)
        }
        .buttonStyle(PressStyle())
    }
    var shadowColor: Color {
        if theme.storybook { return style == .primary ? Theme.Colors.honeyDeep.opacity(0.35) : Theme.Colors.shadow }
        return style == .primary ? Theme.Colors.brass.opacity(0.3) : .clear
    }
    var foreground: Color {
        if theme.storybook {
            switch style { case .primary, .quiet: return Theme.Colors.ink; case .destructive: return Theme.Colors.jam }
        }
        switch style { case .primary: return Theme.Colors.canvas; case .quiet: return Theme.Colors.textPrimary; case .destructive: return Theme.Colors.destructive }
    }
    @ViewBuilder var background: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
        switch style {
        case .primary:
            shape.fill(LinearGradient(colors: theme.storybook ? [Theme.Colors.honeyLight, Theme.Colors.honey] : [Theme.Colors.brass, Theme.Colors.brassDeep], startPoint: .top, endPoint: .bottom))
        case .quiet: shape.fill(theme.storybook ? Theme.Colors.paper : Theme.Colors.brassSoft)
        case .destructive: shape.fill(Theme.Colors.destructive.opacity(theme.storybook ? 0.08 : 0.1))
        }
    }
    var border: LinearGradient {
        if theme.storybook {
            let c: Color = switch style { case .primary: Theme.Colors.ink.opacity(0.8); case .quiet: Theme.Colors.ink.opacity(0.45); case .destructive: Theme.Colors.jam.opacity(0.5) }
            return LinearGradient(colors: [c], startPoint: .top, endPoint: .bottom)
        }
        switch style {
        case .primary: return LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0)], startPoint: .top, endPoint: .bottom)
        case .quiet: return LinearGradient(colors: [Theme.Colors.brassBorder], startPoint: .top, endPoint: .bottom)
        case .destructive: return LinearGradient(colors: [Theme.Colors.destructive.opacity(0.2)], startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Press = a gentle scale; the storybook adds a squash and a tiny tilt, like pushing a rubber stamp.
public struct PressStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? (theme.storybook ? 0.96 : 0.97) : 1)
            .rotationEffect(.degrees(configuration.isPressed && theme.storybook ? -0.8 : 0))
            .opacity(configuration.isPressed ? (theme.storybook ? 0.9 : 0.85) : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

/// Selectable chip: optional leading symbol or tint dot. Classic selects in the accent; the storybook puts a honey
/// drop behind ink text.
public struct Chip: View {
    let title: String
    let icon: String?
    let dot: Color?
    let selected: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme
    public init(_ title: String, icon: String? = nil, dot: Color? = nil, selected: Bool, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.dot = dot; self.selected = selected; self.action = action
    }
    public var body: some View {
        let sb = theme.storybook
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                if let dot {
                    Circle().fill(dot).frame(width: sb ? 9 : 8, height: sb ? 9 : 8)
                        .overlay(Circle().strokeBorder(Theme.Colors.ink.opacity(sb ? 0.5 : 0), lineWidth: 1))
                }
                if let icon { Image(systemName: icon).font(.system(size: 13, weight: .bold)) }
                Text(title).font(selected ? Theme.Fonts.captionBold : Theme.Fonts.caption).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, Theme.Spacing.m).frame(height: 40)
            .background(sb ? (selected ? Theme.Colors.honey : Theme.Colors.paper.opacity(0.6)) : (selected ? Theme.Colors.brassDim : Theme.Colors.surface),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .strokeBorder(sb ? Theme.Colors.ink.opacity(selected ? 0.7 : 0.3) : (selected ? Theme.Colors.brass.opacity(0.5) : Theme.Colors.hairline),
                              lineWidth: sb && selected ? Theme.Stroke.outline : 1))
            .foregroundStyle(sb ? (selected ? Theme.Colors.ink : Theme.Colors.textSecondary) : (selected ? Theme.Colors.brass : Theme.Colors.textSecondary))
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Text-only option for dense rows. Classic: brass when selected, no box. Storybook: ink on a honey drop.
public struct TextOption: View {
    let title: String
    let icon: String?
    let selected: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme
    public init(_ title: String, icon: String? = nil, selected: Bool, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.selected = selected; self.action = action
    }
    public var body: some View {
        let sb = theme.storybook
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .bold)) }
                Text(title).font(selected ? Theme.Fonts.bodyMedium : Theme.Fonts.body).lineLimit(1).fixedSize()
            }
            .foregroundStyle(selected ? (sb ? Theme.Colors.ink : Theme.Colors.brass) : Theme.Colors.textTertiary)
            .padding(.horizontal, sb ? Theme.Spacing.sm : 0)
            .frame(minHeight: sb ? 36 : 44)
            .background(sb && selected ? Theme.Colors.honey : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.Colors.ink.opacity(sb && selected ? 0.6 : 0), lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Underlined tab: label with a tint bar beneath when selected. For switching modes without chips.
public struct TabItem: View {
    let title: String
    let icon: String?
    let tint: Color
    let selected: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme
    public init(_ title: String, icon: String? = nil, tint: Color = Theme.Colors.brass, selected: Bool, action: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.tint = tint; self.selected = selected; self.action = action
    }
    public var body: some View {
        let sb = theme.storybook
        Button(action: action) {
            VStack(spacing: Theme.Spacing.s) {
                HStack(spacing: Theme.Spacing.xs) {
                    if let icon { Image(systemName: icon).font(.system(size: 13, weight: .bold)) }
                    Text(title).font(sb && selected ? Theme.Fonts.heading : Theme.Fonts.bodyMedium).lineLimit(1).fixedSize()
                }
                .foregroundStyle(selected ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                Capsule().fill(selected ? tint : .clear).frame(height: sb ? 4 : 2)
                    .shadow(color: selected && !sb ? tint.opacity(0.6) : .clear, radius: 4)
                    .overlay(Capsule().strokeBorder(Theme.Colors.ink.opacity(sb && selected ? 0.5 : 0), lineWidth: 1))
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Plain tinted symbol in a fixed column, for list rows that don't need a tile behind the glyph.
public struct Glyph: View {
    let icon: String
    let tint: Color?
    var width: CGFloat = 28
    public init(_ icon: String, tint: Color? = nil, width: CGFloat = 28) { self.icon = icon; self.tint = tint; self.width = width }
    public var body: some View {
        Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint ?? Theme.Colors.accentText)
            .frame(width: width, alignment: .leading)
    }
}

/// Section on the canvas: title, optional trailing detail, rule, content. The flat alternative to a Card.
public struct FlatSection<Content: View>: View {
    let title: String
    let detail: String?
    let content: Content
    public init(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.detail = detail; self.content = content()
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(title)
                Spacer()
                if let detail { Text(detail).font(Theme.Fonts.quip).foregroundStyle(Theme.Colors.textTertiary) }
            }
            Hairline()
            content
        }
    }
}

/// Round icon button for headers and toolbars: a 44-pt target on a soft surface (paper with an ink rim in the storybook).
public struct IconButton: View {
    let icon: String
    let label: String
    var tint: Color = Theme.Colors.textPrimary
    let action: () -> Void
    @Environment(\.theme) private var theme
    public init(_ icon: String, label: String, tint: Color = Theme.Colors.textPrimary, action: @escaping () -> Void) {
        self.icon = icon; self.label = label; self.tint = tint; self.action = action
    }
    public var body: some View {
        let sb = theme.storybook
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(sb ? Theme.Colors.paper : Theme.Colors.surface, in: Circle())
                .overlay(Circle().strokeBorder(sb ? Theme.Colors.ink.opacity(0.4) : Theme.Colors.hairline, lineWidth: sb ? Theme.Stroke.outline : 1))
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
    @Environment(\.theme) private var theme
    public init(_ icon: String, tint: Color = Theme.Colors.brass, size: CGFloat = 40) { self.icon = icon; self.tint = tint; self.size = size }
    public var body: some View {
        let sb = theme.storybook
        Image(systemName: icon).font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(sb ? Theme.Colors.ink : tint)
            .frame(width: size, height: size)
            .background(tint.opacity(sb ? 0.35 : 0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(Theme.Colors.ink.opacity(sb ? 0.3 : 0), lineWidth: 1))
    }
}

/// Initials on the accent disc: the user, not a generic person glyph. A round honey badge with an ink rim in the storybook.
public struct Avatar: View {
    let name: String
    var size: CGFloat = 44
    @Environment(\.theme) private var theme
    public init(name: String, size: CGFloat = 44) { self.name = name; self.size = size }
    var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap(\.first)
        return parts.isEmpty ? "?" : String(parts).uppercased()
    }
    public var body: some View {
        if theme.storybook {
            Text(initials).font(.system(size: size * 0.36, weight: .bold, design: .serif)).foregroundStyle(Theme.Colors.ink)
                .frame(width: size, height: size)
                .background(
                    ZStack {
                        Circle().fill(RadialGradient(colors: [Theme.Colors.honeyLight, Theme.Colors.honey], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
                        Circle().strokeBorder(Theme.Colors.paper.opacity(0.8), lineWidth: size * 0.06).padding(size * 0.08)
                    }
                )
                .overlay(Circle().strokeBorder(Theme.Colors.ink.opacity(0.7), lineWidth: Theme.Stroke.outline))
                .softShadow(8, y: 3)
                .accessibilityLabel(name)
        } else {
            Text(initials).font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(Theme.Colors.canvas)
                .frame(width: size, height: size)
                .background(LinearGradient(colors: [Theme.Colors.brass, Theme.Colors.brassDeep], startPoint: .top, endPoint: .bottom), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .accessibilityLabel(name)
        }
    }
}

/// Thin momentum bar: how far through the thing you are. In the storybook it is honey that ends in a drip.
public struct ProgressBar: View {
    let progress: Double
    var tint: Color = Theme.Colors.brass
    var height: CGFloat?
    @Environment(\.theme) private var theme
    public init(_ progress: Double, tint: Color = Theme.Colors.brass, height: CGFloat? = nil) { self.progress = progress; self.tint = tint; self.height = height }
    public var body: some View {
        let sb = theme.storybook
        let h = height ?? (sb ? 8 : 6)
        GeometryReader { geo in
            let w = max(h, geo.size.width * max(0, min(1, progress)))
            ZStack(alignment: .leading) {
                if sb {
                    Capsule().fill(Theme.Colors.aged)
                    Capsule().strokeBorder(Theme.Colors.ink.opacity(0.25), lineWidth: 1)
                    HoneyBarShape().fill(tint)
                        .overlay(HoneyBarShape().stroke(Theme.Colors.ink.opacity(0.45), lineWidth: 1))
                        .frame(width: w, height: h * 1.9)
                        .offset(y: h * 0.1)
                } else {
                    Capsule().fill(Theme.Colors.surface)
                    Capsule().fill(tint)
                        .frame(width: w)
                        .shadow(color: tint.opacity(0.5), radius: 6)
                }
            }
        }
        .frame(height: h)
        .animation(Theme.Motion.spring, value: progress)
    }
}

/// A capsule whose trailing end sags into a honey drip. Drawn in a frame ~1.9× taller than the bar so the drip
/// hangs below.
public struct HoneyBarShape: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        let barH = rect.height / 1.9
        let r = barH / 2
        let bar = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: barH)
        var p = Path(roundedRect: bar, cornerRadius: r)
        if rect.width > barH * 2 {
            let dripR = barH * 0.42
            let cx = rect.maxX - r - dripR * 0.4
            p.addEllipse(in: CGRect(x: cx - dripR, y: rect.minY + barH - dripR * 0.9, width: dripR * 2, height: dripR * 2))
            p.addRect(CGRect(x: cx - dripR * 0.6, y: rect.minY + barH * 0.6, width: dripR * 1.2, height: barH * 0.5))
        }
        return p
    }
}

/// Segmented momentum indicator: one pill per step, filled as they're done; honeycomb cells in the storybook.
public struct Segments: View {
    let done: Int
    let total: Int
    var tint: Color = Theme.Colors.brass
    @Environment(\.theme) private var theme
    public init(done: Int, total: Int, tint: Color = Theme.Colors.brass) { self.done = done; self.total = total; self.tint = tint }
    public var body: some View {
        let sb = theme.storybook
        HStack(spacing: sb ? 3 : Theme.Spacing.xs) {
            ForEach(0..<max(total, 0), id: \.self) { i in
                if sb {
                    HexCell().fill(i < done ? tint : Theme.Colors.paper)
                        .overlay(HexCell().stroke(Theme.Colors.ink.opacity(i < done ? 0.6 : 0.3), lineWidth: 1))
                        .frame(width: 14, height: 12)
                } else {
                    Capsule().fill(i < done ? tint : Theme.Colors.surface).frame(height: 6)
                        .shadow(color: i < done ? tint.opacity(0.5) : .clear, radius: 4)
                }
            }
            if done > total { Text("+\(done - total)").font(Theme.Fonts.captionBold).foregroundStyle(Theme.Colors.textTertiary) }
        }
        .animation(Theme.Motion.spring, value: done)
    }
}

/// Flat-topped hexagon.
public struct HexCell: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        let w = rect.width
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + w * 0.25, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.75, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.75, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.25, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.closeSubpath()
        return p
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
            Text(label).font(Theme.Fonts.quipSmall).foregroundStyle(Theme.Colors.textTertiary)
        }
    }
}

/// Small day-type tint dot + label; the only place colour names a day.
public struct DayTag: View {
    let day: DayType
    public init(_ day: DayType) { self.day = day }
    public var body: some View {
        let sb = Theme.storybook
        HStack(spacing: 6) {
            Circle().fill(Theme.Colors.day(day)).frame(width: sb ? 10 : 8, height: sb ? 10 : 8)
                .shadow(color: sb ? .clear : Theme.Colors.day(day).opacity(0.7), radius: 4)
                .overlay(Circle().strokeBorder(Theme.Colors.ink.opacity(sb ? 0.5 : 0), lineWidth: 1))
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
    /// What the value is, for VoiceOver ("Decrease rest time"); `nil` keeps the plain "Decrease" / "Increase".
    let name: String?
    @Environment(\.theme) private var theme
    public init(_ label: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 1, name: String? = nil) {
        self.label = label; _value = value; self.range = range; self.step = step; self.name = name
    }
    public var body: some View {
        let sb = theme.storybook
        HStack {
            Text(label).font(Theme.Fonts.body).monospacedDigit().foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            HStack(spacing: 0) {
                button("minus") { value = max(range.lowerBound, value - step) }
                Rectangle().fill(sb ? Theme.Colors.ink.opacity(0.3) : Theme.Colors.hairline).frame(width: 1, height: 20)
                button("plus") { value = min(range.upperBound, value + step) }
            }
            .background(sb ? Theme.Colors.paper : Theme.Colors.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .strokeBorder(sb ? Theme.Colors.ink.opacity(0.4) : Theme.Colors.brassBorder, lineWidth: 1))
        }
    }
    /// Plain tap targets rather than `Button`s: inside a `List` row (with `.onMove`) sibling buttons
    /// can lose taps to the row's own gestures; a tap gesture on a shaped view does not.
    func button(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(theme.storybook ? Theme.Colors.ink : Theme.Colors.brass)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel([icon == "minus" ? "Decrease" : "Increase", name].compactMap { $0 }.joined(separator: " "))
    }
}

public extension Binding where Value == Int {
    var asDouble: Binding<Double> { Binding<Double>(get: { Double(wrappedValue) }, set: { wrappedValue = Int($0) }) }
}
