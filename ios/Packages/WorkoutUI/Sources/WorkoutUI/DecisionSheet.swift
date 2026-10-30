import SwiftUI

/// A short decision drawn in the theme instead of a system alert. The X in the corner is the way back, so there is
/// no Cancel button; one emphasised primary action leads; an optional destructive action sits at the very bottom as
/// small plain text, set apart by a rule so a tired thumb aiming for the primary doesn't land on it.
public struct DecisionSheet: View {
    public struct Action {
        let title: String
        let icon: String?
        let hint: String?
        let perform: () -> Void
        public init(_ title: String, icon: String? = nil, hint: String? = nil, perform: @escaping () -> Void) {
            self.title = title; self.icon = icon; self.hint = hint; self.perform = perform
        }
    }

    let title: String
    let message: String
    let closeLabel: String
    let primary: Action
    let destructive: Action?
    let close: () -> Void

    public init(title: String, message: String, closeLabel: String = "Close", primary: Action, destructive: Action? = nil,
                close: @escaping () -> Void) {
        self.title = title; self.message = message; self.closeLabel = closeLabel
        self.primary = primary; self.destructive = destructive; self.close = close
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Text(title).font(Theme.Fonts.titleSmall).foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                IconButton("xmark", label: closeLabel, tint: Theme.Colors.textSecondary, action: close)
            }
            Text(message).font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Spacing.xs)
            PillButton(primary.title, icon: primary.icon, action: primary.perform)
                .accessibilityHint(primary.hint ?? "")
                .padding(.top, Theme.Spacing.l)
            if let destructive {
                Hairline().padding(.top, Theme.Spacing.xl)
                Button(action: destructive.perform) {
                    HStack(spacing: Theme.Spacing.s) {
                        if let icon = destructive.icon {
                            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.Colors.destructive)
                        }
                        Text(destructive.title).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, Theme.Spacing.m)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.s)
                .accessibilityLabel(destructive.title)
                .accessibilityHint(destructive.hint ?? "")
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.l)
        .padding(.bottom, destructive == nil ? Theme.Spacing.l : Theme.Spacing.s)
    }
}

public extension View {
    /// A bottom sheet sized to its content (it scrolls if that is taller than the screen allows), on the theme's
    /// card surface. Swiping it down dismisses it, like the close control.
    func fittedSheet<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented) { FittedSheet(content: content()) }
    }
}

struct FittedSheet<Content: View>: View {
    let content: Content
    @State private var contentHeight: CGFloat = 0
    @State private var bottomInset: CGFloat = 0
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .presentationDetents(contentHeight > 0 ? [.height(contentHeight + bottomInset)] : [.medium])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(Theme.Radius.card)
        .presentationBackground(Theme.Colors.card)
        .preferredColorScheme(theme.colorScheme)
        .tint(theme.colors.tint)
    }
}
