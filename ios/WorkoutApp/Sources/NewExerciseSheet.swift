import SwiftUI
import WorkoutEngine
import WorkoutStore
import WorkoutUI

/// Create a custom exercise: name, movement pattern, equipment, how it's loaded. Saved locally, synced, and
/// from then on treated like any seed exercise (planning, swaps, progression; pictogram from its pattern).
struct NewExerciseSheet: View {
    let initialName: String
    let onCreate: (Exercise) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var pattern = "horizontal_press"
    @State private var equipment: Set<String> = []
    @State private var loadable = true
    @State private var dumbbellBased = false
    @FocusState private var nameFocused: Bool

    var patterns: [String] { model.catalog.patterns.keys.sorted() }
    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Screen {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Aside(Theme.storybook ? "A new exercise of your own" : "New exercise")
                            TextField("Name", text: $name).font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                                .textInputAutocapitalization(.words).focused($nameFocused).submitLabel(.done)
                        }
                        .padding(.top, Theme.Spacing.s)
                        Hairline()
                        SectionHeader("Movement", icon: "figure.strengthtraining.traditional", tint: Theme.Colors.brass)
                        wrap(patterns, id: \.self) { p in
                            Chip(label(p), selected: p == pattern) { pattern = p }
                        }
                        Hairline()
                        SectionHeader("Needs", icon: "dumbbell", tint: Theme.Colors.legs)
                        wrap(model.catalog.equipmentTypes.map(\.key), id: \.self) { e in
                            Chip(model.catalog.equipmentTypes.first { $0.key == e }?.label ?? e, selected: equipment.contains(e)) {
                                if equipment.contains(e) { equipment.remove(e) } else { equipment.insert(e) }
                                if e == "dumbbells" { dumbbellBased = equipment.contains(e) }
                            }
                        }
                        Hairline()
                        SectionHeader("Load", icon: "scalemass", tint: Theme.storybook ? Theme.Colors.sky : Theme.Colors.pull)
                        HStack(spacing: Theme.Spacing.s) {
                            Chip("Weighted", selected: loadable) { loadable = true }
                            Chip("Bodyweight / timed", selected: !loadable) { loadable = false }
                        }
                        if loadable {
                            HStack(spacing: Theme.Spacing.s) {
                                Chip("Plates", selected: !dumbbellBased) { dumbbellBased = false }
                                Chip("Dumbbells", selected: dumbbellBased) { dumbbellBased = true }
                            }
                        }
                    }
                    .padding(Theme.Spacing.l)
                }
                .scrollDismissesKeyboard(.interactively)
                PillButton("Create exercise", icon: "plus") {
                    guard let e = model.createExercise(name: name, pattern: pattern, equipment: equipment.sorted(), loadable: loadable, dumbbellBased: dumbbellBased)
                    else { return }
                    Haptics.play(.swap)
                    dismiss()
                    onCreate(e)
                }
                .disabled(!canSave)
                .padding(Theme.Spacing.l)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.Colors.canvas)
        .onAppear { name = initialName; nameFocused = initialName.isEmpty }
    }

    func label(_ pattern: String) -> String { pattern.replacingOccurrences(of: "_", with: " ").capitalized }

    /// Flow layout for chips.
    func wrap<T: Hashable, V: View>(_ items: [T], id: KeyPath<T, T>, @ViewBuilder content: @escaping (T) -> V) -> some View {
        FlowLayout(spacing: Theme.Spacing.s) { ForEach(items, id: id) { content($0) } }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing; rowH = max(rowH, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing; rowH = max(rowH, size.height)
        }
    }
}
