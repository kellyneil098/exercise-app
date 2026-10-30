import SwiftUI
import XCTest
@testable import WorkoutUI

/// Measures `DecisionSheet` (the end-workout sheet) at full phone widths — iPhone SE 375, iPhone 12–16 390/393 — in
/// both themes, so the primary action, the copy and the discard link fit a small phone without scrolling.
@MainActor
final class DecisionSheetLayoutTests: XCTestCase {
    static let widths: [CGFloat] = [375, 390]
    static let message = "Saving keeps the 18 sets you logged and updates your next targets. Discarding deletes them."

    func sheet(destructive: Bool = true, message: String = message) -> DecisionSheet {
        DecisionSheet(title: "End this workout?", message: message, closeLabel: "Keep going",
                      primary: .init("Finish and save progress", icon: "checkmark") {},
                      destructive: destructive ? .init("Discard this workout", icon: "trash") {} : nil) {}
    }

    func measure(_ view: some View, width: CGFloat, theme: ThemeSpec, textSize: DynamicTypeSize = .large) -> CGSize {
        let before = Theme.current
        defer { Theme.current = before }
        Theme.current = theme
        let root = view.environment(\.theme, theme).environment(\.dynamicTypeSize, textSize)
        let bounds = CGSize(width: width, height: 10_000)
        #if canImport(UIKit)
        return UIHostingController(rootView: root).sizeThatFits(in: bounds)
        #else
        return NSHostingController(rootView: root).sizeThatFits(in: bounds)
        #endif
    }

    func testFitsSmallPhonesInBothThemes() {
        for theme in [ThemeSpec.classic, .hundredAcreWood] {
            for width in Self.widths {
                let s = measure(sheet(), width: width, theme: theme)
                XCTAssertLessThanOrEqual(s.width, width + 0.5, "\(theme.id) @ \(width)pt")
                // Well under half an iPhone SE (667 pt): a compact sheet, not a full-screen takeover.
                XCTAssertLessThan(s.height, 400, "\(theme.id) @ \(width)pt")
                XCTAssertGreaterThan(s.height, 44 + 56, "\(theme.id) @ \(width)pt")
            }
        }
    }

    /// The discard link is set well below the primary action: its rule and gap plus a full 44-pt target.
    func testDiscardIsSeparatedFromThePrimaryAction() {
        for theme in [ThemeSpec.classic, .hundredAcreWood] {
            let with = measure(sheet(), width: 375, theme: theme).height
            let without = measure(sheet(destructive: false), width: 375, theme: theme).height
            XCTAssertGreaterThanOrEqual(with - without, Theme.Spacing.xl + 44 - Theme.Spacing.l, "\(theme.id)")
        }
    }

    func testLongCopyWrapsInsteadOfWidening() {
        let long = String(repeating: Self.message + " ", count: 3)
        for theme in [ThemeSpec.classic, .hundredAcreWood] {
            for size in [DynamicTypeSize.large, .accessibility5] {
                let short = measure(sheet(), width: 375, theme: theme, textSize: size)
                let tall = measure(sheet(message: long), width: 375, theme: theme, textSize: size)
                XCTAssertLessThanOrEqual(tall.width, 375.5, "\(theme.id) \(size)")
                XCTAssertGreaterThan(tall.height, short.height, "\(theme.id) \(size)")
            }
        }
    }
}
