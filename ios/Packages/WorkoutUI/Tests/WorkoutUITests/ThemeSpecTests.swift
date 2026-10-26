import SwiftUI
import XCTest
@testable import WorkoutUI

/// Every theme must populate every token, and the chosen theme must survive a relaunch.
final class ThemeSpecTests: XCTestCase {
    func testEveryThemeHasEveryToken() {
        let tokenCount = ThemeSpec.classic.colors.all.count
        let fontCount = ThemeSpec.classic.fonts.all.count
        XCTAssertGreaterThan(tokenCount, 30)
        for theme in AppTheme.allCases {
            let spec = theme.spec
            XCTAssertEqual(spec.id, theme)
            XCTAssertEqual(spec.colors.all.count, tokenCount, "\(theme) colour tokens")
            XCTAssertEqual(spec.fonts.all.count, fontCount, "\(theme) font tokens")
            for (i, c) in spec.colors.all.enumerated() { XCTAssertNotNil(c.cgColor ?? resolved(c), "\(theme) colour #\(i) resolves") }
            XCTAssertGreaterThan(spec.radius.card, 0); XCTAssertGreaterThan(spec.radius.control, 0); XCTAssertGreaterThan(spec.radius.chip, 0)
            XCTAssertFalse(theme.displayName.isEmpty)
        }
        // The two looks are genuinely different systems, not a tint.
        XCTAssertNotEqual(ThemeSpec.classic.colorScheme, ThemeSpec.hundredAcreWood.colorScheme)
        XCTAssertFalse(ThemeSpec.classic.storybook); XCTAssertTrue(ThemeSpec.hundredAcreWood.storybook)
        XCTAssertNil(AppTheme.classic.alternateIconName); XCTAssertEqual(AppTheme.hundredAcreWood.alternateIconName, "AppIcon-Hunny")
    }

    func testStaticTokensFollowTheCurrentTheme() {
        let before = Theme.current
        defer { Theme.current = before }
        Theme.current = .classic
        XCTAssertEqual(Theme.Colors.canvas, ThemeSpec.classic.colors.canvas)
        XCTAssertFalse(Theme.storybook)
        Theme.current = .hundredAcreWood
        XCTAssertEqual(Theme.Colors.canvas, ThemeSpec.hundredAcreWood.colors.canvas)
        XCTAssertEqual(Theme.Colors.honey, ThemeSpec.hundredAcreWood.colors.brass)
        XCTAssertTrue(Theme.storybook)
    }

    func testFreshInstallsStartInTheStorybook() throws {
        let (defaults, suite) = try fresh(); defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AppTheme.load(from: defaults, onboarded: false), .hundredAcreWood, "Natalie's first open is Pooh")
        XCTAssertEqual(defaults.string(forKey: AppTheme.defaultsKey), "hundredAcreWood", "the answer is written back")
        XCTAssertEqual(AppTheme.load(from: defaults, onboarded: true), .hundredAcreWood, "and stays once onboarded")
    }

    func testOnboardedInstallsWithoutAChoiceKeepClassic() throws {
        let (defaults, suite) = try fresh(); defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AppTheme.load(from: defaults, onboarded: true), .classic, "existing users keep the default look")
        XCTAssertEqual(defaults.string(forKey: AppTheme.defaultsKey), "classic", "pinned so a later fresh-install rule can't flip them")
        XCTAssertEqual(AppTheme.load(from: defaults, onboarded: false), .classic)
    }

    func testSelectionPersists() throws {
        let (defaults, suite) = try fresh(); defer { defaults.removePersistentDomain(forName: suite) }
        AppTheme.hundredAcreWood.save(to: defaults)
        XCTAssertEqual(AppTheme.load(from: defaults, onboarded: true), .hundredAcreWood)
        AppTheme.classic.save(to: defaults)
        XCTAssertEqual(AppTheme.load(from: defaults, onboarded: false), .classic, "a choice beats the fresh-install default")
        defaults.set("not-a-theme", forKey: AppTheme.defaultsKey)
        XCTAssertEqual(AppTheme.load(from: defaults, onboarded: false), .classic, "an unknown value falls back")
    }

    private func fresh() throws -> (UserDefaults, String) {
        let suite = "ThemeSpecTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suite)), suite)
    }

    /// Opaque dynamic colours have no `cgColor`; resolving them through a resolved-colour view is enough to prove they exist.
    private func resolved(_ c: Color) -> Any? { c.description.isEmpty ? nil : c.description }
}
