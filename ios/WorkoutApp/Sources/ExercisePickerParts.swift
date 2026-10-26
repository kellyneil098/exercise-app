import SwiftUI
import WorkoutUI

/// Building blocks shared by the exercise pickers (deck swap/add and Progress), so both look and behave the same.

/// Rounded search field with a clear button.
struct ExerciseSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.Colors.textTertiary).accessibilityHidden(true)
            TextField("Search exercises", text: $text)
                .font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textPrimary)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(Theme.Colors.textTertiary).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.storybook ? Theme.Colors.paper : Theme.Colors.cardRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
            .strokeBorder(Theme.storybook ? Theme.Colors.ink.opacity(0.4) : Theme.Colors.hairline, lineWidth: Theme.storybook ? Theme.Stroke.outline : 1))
    }
}

/// Overline that heads a group of picker rows.
struct ExercisePickerHeader: View {
    let title: String
    var topPadding: CGFloat = Theme.Spacing.l

    var body: some View {
        Group { if Theme.storybook { SectionTitle(title) } else { Overline(title) } }.padding(.top, topPadding).padding(.bottom, Theme.Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One tappable exercise: name over a caption, optional trailing content, hairline beneath.
/// `selected` marks the current pick in brass with a check.
struct ExercisePickerRow<Trailing: View>: View {
    let name: String
    let detail: String?
    var dimmed = false
    var selected = false
    /// Exercise key + movement pattern; the storybook theme leads the row with the bear doing the movement.
    var art: (key: String, pattern: String)? = nil
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack(spacing: Theme.Spacing.sm) {
                    if Theme.storybook, let art {
                        ExerciseArt(exerciseKey: art.key, pattern: art.pattern, animated: false)
                            .frame(width: 60, height: 36)
                            .background(WashBlob(color: Theme.Colors.honey, opacity: dimmed ? 0.1 : 0.22))
                            .saturation(dimmed ? 0.3 : 1)
                            .opacity(dimmed ? 0.6 : 1)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(selected ? Theme.Fonts.bodyMedium : Theme.Fonts.body)
                            .foregroundStyle(selected && !Theme.storybook ? Theme.Colors.brass : dimmed ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                        if let detail { Text(detail).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary) }
                    }
                    Spacer()
                    trailing()
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.Colors.honeyInk)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                Hairline()
            }
        }
        .buttonStyle(PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension ExercisePickerRow where Trailing == EmptyView {
    init(name: String, detail: String?, dimmed: Bool = false, selected: Bool = false, art: (key: String, pattern: String)? = nil, action: @escaping () -> Void) {
        self.init(name: name, detail: detail, dimmed: dimmed, selected: selected, art: art, action: action) { EmptyView() }
    }
}
