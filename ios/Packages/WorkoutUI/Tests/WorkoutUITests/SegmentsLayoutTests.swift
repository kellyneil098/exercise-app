import SwiftUI
import XCTest
@testable import WorkoutUI

/// Measures the set-card progress honeycombs at the deck card's content widths (screen − 2×24 deck padding − 2×24
/// card padding: Pro Max 430, iPhone 12 390, SE/mini 375) across set counts, including over-logged sets.
@MainActor
final class SegmentsLayoutTests: XCTestCase {
    static let widths: [CGFloat] = [334, 294, 279]

    func measure(done: Int, total: Int, size: Segments.Size, theme: ThemeSpec = .hundredAcreWood, width: CGFloat = 294,
                 textSize: DynamicTypeSize = .large) -> CGSize {
        let view = Segments(done: done, total: total, size: size)
            .environment(\.theme, theme)
            .environment(\.dynamicTypeSize, textSize)
        let bounds = CGSize(width: width, height: 10_000)
        #if canImport(UIKit)
        return UIHostingController(rootView: view).sizeThatFits(in: bounds)
        #else
        return NSHostingController(rootView: view).sizeThatFits(in: bounds)
        #endif
    }

    func testProminentHoneycombsAreAboutTwiceTheListSize() {
        let compact = measure(done: 2, total: 4, size: .compact)
        let prominent = measure(done: 2, total: 4, size: .prominent)
        XCTAssertEqual(compact.height, 12, accuracy: 0.5, "list rows keep the small cells")
        XCTAssertGreaterThanOrEqual(prominent.height, compact.height * 2 - 0.5)
        XCTAssertEqual(prominent.width, 4 * 28 + 3 * Theme.Spacing.xs, accuracy: 1)
    }

    func testNeverWiderThanTheCard() {
        for width in Self.widths {
            for total in 1...16 {
                for done in Set([0, total / 2, total, total + 3]) {
                    let s = measure(done: done, total: total, size: .prominent, width: width)
                    XCTAssertLessThanOrEqual(s.width, width + 0.5, "\(done)/\(total) @ \(width)pt")
                    XCTAssertGreaterThan(s.height, 4, "\(done)/\(total) @ \(width)pt")
                }
            }
        }
    }

    /// Typical decks (up to six sets) get full-size cells even on the narrowest phone; long ones shrink to fit.
    func testFullSizeUpToSixSetsThenShrink() {
        let full = measure(done: 0, total: 3, size: .prominent).height
        XCTAssertEqual(measure(done: 0, total: 6, size: .prominent, width: 279).height, full, accuracy: 0.5)
        XCTAssertLessThan(measure(done: 0, total: 14, size: .prominent, width: 279).height, full)
    }

    func testClassicBarsAreUnchanged() {
        XCTAssertEqual(measure(done: 1, total: 4, size: .prominent, theme: .classic).height,
                       measure(done: 1, total: 4, size: .compact, theme: .classic).height, accuracy: 0.5)
    }

    #if os(iOS)
    /// Larger text sizes grow the cells, but capped so the card keeps its hierarchy.
    func testDynamicTypeGrowsCellsWithinACap() {
        let base = measure(done: 1, total: 4, size: .prominent).height
        let big = measure(done: 1, total: 4, size: .prominent, textSize: .accessibility5)
        XCTAssertGreaterThan(big.height, base)
        XCTAssertLessThanOrEqual(big.height, Segments.prominentCellMax / Segments.hexAspect + 0.5)
        XCTAssertLessThanOrEqual(measure(done: 1, total: 12, size: .prominent, width: 279, textSize: .accessibility5).width, 279.5)
    }
    #endif
}
