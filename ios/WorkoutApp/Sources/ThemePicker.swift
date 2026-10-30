import SwiftUI
import WorkoutUI
#if os(iOS)
import UIKit
#endif

/// Profile → Appearance: one card per `AppTheme` (palette swatch + the app icon that goes with it). Picking one
/// switches the design system at once and swaps the home-screen icon to match. New themes only need a new case.
struct ThemePicker: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader("Appearance", icon: "paintpalette", tint: Theme.storybook ? Theme.Colors.piglet : Theme.Colors.fullBody)
            ThemeCards()
            Text("Changes the colours, type and illustrations everywhere, and the app icon on your home screen.")
                .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
        }
    }
}

/// The row of theme cards, one per `AppTheme`, all the same height. Shared by Profile and onboarding.
struct ThemeCards: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            ForEach(AppTheme.allCases) { theme in
                ThemeCard(theme: theme, selected: model.theme == theme) { select(theme) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    func select(_ theme: AppTheme) {
        guard theme != model.theme else { return }
        Haptics.play(.swap)
        withAnimation(Theme.Motion.spring) { model.theme = theme }
        // From the tap, while the app is foreground-active: setAlternateIconName is ignored otherwise.
        AppIconSwitcher.apply(theme.alternateIconName)
    }
}

/// A theme as a small sample of itself: its canvas, a card, its accent, its type, and its app icon.
struct ThemeCard: View {
    let theme: AppTheme
    let selected: Bool
    let action: () -> Void

    var spec: ThemeSpec { theme.spec }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack(alignment: .top, spacing: Theme.Spacing.s) {
                    swatch
                    Spacer(minLength: 0)
                    icon
                }
                // Two lines reserved whether the name needs them or not, so every card is the same height.
                Text(theme.displayName).font(spec.fonts.heading).foregroundStyle(spec.colors.textPrimary)
                    .lineLimit(2, reservesSpace: true).fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Spacing.sm)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(spec.colors.canvas, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(selected ? Theme.Colors.brass : Theme.Colors.hairline, lineWidth: selected ? 2.5 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.Colors.ink, Theme.Colors.brass)
                        .padding(6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("\(theme.displayName) theme")
        .accessibilityValue(selected ? "Selected" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Four drops: card, accent, a day wash, text.
    var swatch: some View {
        HStack(spacing: -6) {
            ForEach(Array([spec.colors.card, spec.colors.brass, spec.colors.legs, spec.colors.textPrimary].enumerated()), id: \.offset) { _, c in
                Circle().fill(c).frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(spec.colors.textPrimary.opacity(0.35), lineWidth: 1))
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder var icon: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        Group {
            #if os(iOS)
            if let ui = UIImage(named: theme.alternateIconName ?? "AppIcon") {
                Image(uiImage: ui).resizable().aspectRatio(contentMode: .fill)
            } else {
                iconFallback
            }
            #else
            iconFallback
            #endif
        }
        .frame(width: 44, height: 44)
        .clipShape(shape)
        .overlay(shape.strokeBorder(spec.colors.textPrimary.opacity(0.25), lineWidth: 1))
        .accessibilityHidden(true)
    }

    var iconFallback: some View {
        ZStack {
            spec.colors.brass
            if spec.storybook { HoneyPot(fill: 0.7, drip: true, label: nil).padding(6) }
            else { Image(systemName: "dumbbell.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(spec.colors.canvas) }
        }
    }
}
