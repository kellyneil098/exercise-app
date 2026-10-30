import SwiftUI
import WorkoutEngine

/// Screen-top header: date overline, time-of-day greeting, and trailing controls (Progress, profile avatar).
///
/// The layout adapts to the name and the text size with no width thresholds: `ViewThatFits` picks the first
/// arrangement whose natural width fits.
/// 1. **Inline** — "Good morning, Neil" on one title line beside the controls, whenever it fits at full size.
/// 2. **Split** — the phrase drops to a smaller secondary line tucked under the date, the name stays title-size,
///    still beside the controls (typical on 375–390-pt phones, where the controls leave the greeting ~230 pt). A name
///    too long for the line eases down to 80% and then truncates (VoiceOver still reads it whole), so even a
///    pathological name costs no extra height at ordinary text sizes.
/// 3. **Stacked** — when even the phrase can't sit beside the controls (accessibility text sizes): the controls share
///    the date's row and the greeting gets the full width, the name wrapping over up to two lines.
///
/// The header owns the space below it so the split form can pay for its extra line: inline keeps `spacingBelow`, the
/// fallbacks use `compactSpacingBelow`. With Home's 32/8 that puts the content below exactly where the one-line
/// header left it.
/// VoiceOver always reads the whole greeting as one heading, whichever layout is on screen.
public struct GreetingHeader<Trailing: View>: View {
    let overline: String
    let greeting: Greeting
    let spacingBelow: CGFloat
    let compactSpacingBelow: CGFloat
    let trailing: Trailing

    public init(overline: String, greeting: Greeting, spacingBelow: CGFloat = Theme.Spacing.xl,
                compactSpacingBelow: CGFloat = Theme.Spacing.s, @ViewBuilder trailing: () -> Trailing) {
        self.overline = overline; self.greeting = greeting
        self.spacingBelow = spacingBelow; self.compactSpacingBelow = compactSpacingBelow
        self.trailing = trailing()
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            besideControls(spacing: Theme.Spacing.xs) { inlineGreeting }
                .padding(.bottom, spacingBelow)
            besideControls(spacing: 0) { splitGreeting(nameLines: 1) }
                .padding(.bottom, compactSpacingBelow)
            stacked
                .padding(.bottom, compactSpacingBelow)
        }
    }

    /// Same row as before the adaptive header: text column (taking all the width the controls leave), controls.
    func besideControls<G: View>(spacing: CGFloat, @ViewBuilder _ greetingView: () -> G) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: spacing) {
                date
                greetingView()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
    }

    var stacked: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                date
                trailing
            }
            splitGreeting(nameLines: 2)
        }
    }

    /// Ideal width 0 so a long date (or locale) never decides the layout: it wraps within whatever the greeting
    /// leaves, as it did before.
    var date: some View {
        Overline(overline).frame(idealWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    var inlineGreeting: some View {
        Text(greeting.inline).font(Self.titleFont).foregroundStyle(Theme.Colors.textPrimary)
            .lineLimit(1)
            .greetingElement(greeting)
    }

    @ViewBuilder func splitGreeting(nameLines: Int) -> some View {
        if let name = greeting.name {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(greeting.phrase),").font(Self.phraseFont).foregroundStyle(Theme.Colors.textSecondary)
                if nameLines == 1 {
                    // Ideal width 0: only the phrase decides whether this arrangement fits; the name takes what's left.
                    // The hidden line keeps the full title height when a long name is scaled down.
                    ZStack(alignment: .leading) {
                        Text(verbatim: " ").font(Self.titleFont).hidden()
                        Text(name).font(Self.titleFont).foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.8).truncationMode(.tail)
                    }
                    .frame(idealWidth: 0, alignment: .leading)
                } else {
                    Text(name).font(Self.titleFont).foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(nameLines).truncationMode(.tail)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .greetingElement(greeting)
        } else {
            Text(greeting.phrase).font(Self.titleFont).foregroundStyle(Theme.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .greetingElement(greeting)
        }
    }

    /// `Theme.Fonts.title` / `.heading` at the default text size, but following Dynamic Type (capped at AX3 below, so
    /// a word like "afternoon," still fits a 375-pt phone's width without breaking mid-word).
    static var titleFont: Font { Theme.storybook ? .system(.title, design: .serif, weight: .semibold).italic() : .system(.title, weight: .bold) }
    static var phraseFont: Font { Theme.storybook ? .system(.headline, design: .serif, weight: .regular).italic() : .system(.headline, weight: .bold) }
}

private extension View {
    /// One VoiceOver heading with the full greeting, and the Dynamic Type cap noted on `titleFont`.
    func greetingElement(_ greeting: Greeting) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(greeting.inline)
            .accessibilityAddTraits(.isHeader)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

// MARK: - Previews

#if DEBUG
private struct GreetingHeaderPreview: View {
    let name: String
    var dayPart: Greeting.DayPart = .afternoon
    /// Home's content width on a phone of this width (24-pt side margins).
    var phoneWidth: CGFloat = 390

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GreetingHeader(overline: "Wednesday, Sep 30", greeting: Greeting(dayPart: dayPart, displayName: name)) {
                IconButton("chart.xyaxis.line", label: "Progress") {}
                Avatar(name: name)
            }
            Stat("3", label: "sessions this week", tint: Theme.Colors.brass)
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(width: phoneWidth, alignment: .leading)
        .background(Theme.Colors.canvas)
        .preferredColorScheme(Theme.current.colorScheme)
    }
}

private let previewNames = ["Neil", "Bartholomew", "Anna-Katharina von Hohenzollern", "Wolfeschlegelsteinhausenbergerdorff",
                            "José 💪🏽", "王小明", "محمد علي", ""]

#Preview("iPhone 12 width · names") {
    VStack(alignment: .leading, spacing: Theme.Spacing.m) { ForEach(previewNames, id: \.self) { GreetingHeaderPreview(name: $0) } }
}

#Preview("SE width · names") {
    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
        ForEach(previewNames, id: \.self) { GreetingHeaderPreview(name: $0, phoneWidth: 375) }
    }
}

#Preview("Morning / afternoon / evening") {
    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
        ForEach(Greeting.DayPart.allCases, id: \.self) { GreetingHeaderPreview(name: "Neil", dayPart: $0) }
        ForEach(Greeting.DayPart.allCases, id: \.self) { GreetingHeaderPreview(name: "Maximiliano", dayPart: $0) }
    }
}

#Preview("Large text") {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            GreetingHeaderPreview(name: "Neil").dynamicTypeSize(.xxxLarge)
            GreetingHeaderPreview(name: "Neil", phoneWidth: 375).dynamicTypeSize(.accessibility3)
            GreetingHeaderPreview(name: "Bartholomew", phoneWidth: 375).dynamicTypeSize(.accessibility5)
            GreetingHeaderPreview(name: "Wolfeschlegelsteinhausenbergerdorff", phoneWidth: 375).dynamicTypeSize(.accessibility5)
        }
    }
}
#endif
