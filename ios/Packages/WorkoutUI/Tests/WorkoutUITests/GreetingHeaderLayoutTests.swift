import SwiftUI
import WorkoutEngine
import XCTest
@testable import WorkoutUI

/// Measures `GreetingHeader` in a hosting controller at Home's content widths (iPhone 12: 390 − 2×24, iPhone SE:
/// 375 − 2×24) across name lengths and text sizes. Runs on macOS in CI (`swift test`) and on an iOS Simulator via
/// `xcodebuild test`; the vertical-budget check needs iOS fonts and Dynamic Type, so it only runs there.
@MainActor
final class GreetingHeaderLayoutTests: XCTestCase {
    static let widths: [CGFloat] = [342, 327]
    static let names = ["Neil", "Bartholomew", "Anna-Katharina von Hohenzollern", "Wolfeschlegelsteinhausenbergerdorff",
                        "José 💪🏽", "王小明", "محمد علي", "👩‍👩‍👧‍👦", ""]
    static let textSizes: [DynamicTypeSize] = [.large, .xxxLarge, .accessibility3, .accessibility5]

    func measure(_ name: String, width: CGFloat, textSize: DynamicTypeSize = .large) -> CGSize {
        let view = GreetingHeader(overline: "Wednesday, Sep 30", greeting: Greeting(dayPart: .afternoon, displayName: name)) {
            Circle().frame(width: 44, height: 44)
            Circle().frame(width: 44, height: 44)
        }
        .environment(\.dynamicTypeSize, textSize)
        let bounds = CGSize(width: width, height: 10_000)
        #if canImport(UIKit)
        return UIHostingController(rootView: view).sizeThatFits(in: bounds)
        #else
        return NSHostingController(rootView: view).sizeThatFits(in: bounds)
        #endif
    }

    func testNeverWiderThanThePhone() {
        for width in Self.widths {
            for name in Self.names {
                for size in Self.textSizes {
                    let s = measure(name, width: width, textSize: size)
                    XCTAssertLessThanOrEqual(s.width, width + 0.5, "\(name) @ \(width)pt, \(size)")
                    XCTAssertGreaterThan(s.height, 44, "\(name) @ \(width)pt, \(size)")
                }
            }
        }
    }

    func testPathologicalNameFallsBackToAStackedHeader() {
        for width in Self.widths {
            XCTAssertGreaterThan(measure("Wolfeschlegelsteinhausenbergerdorff", width: width).height,
                                 measure("Neil", width: width).height + 20, "\(width)pt")
        }
    }

    func testLargerTextNeverShrinksTheHeader() {
        for width in Self.widths {
            for name in ["Neil", "Bartholomew"] {
                let heights = Self.textSizes.map { measure(name, width: width, textSize: $0).height }
                XCTAssertEqual(heights, heights.sorted(), "\(name) @ \(width)pt")
            }
        }
    }

    #if os(iOS)
    /// The two-line fallback trades its extra line for tighter spacing below, so a long name doesn't push Home's
    /// controls down on an iPhone 12 at the default text size.
    func testTwoLineFallbackKeepsTheVerticalBudget() {
        let short = measure("Neil", width: 342).height
        for name in ["Bartholomew", "Maximiliano", "Anna-Katharina"] {
            XCTAssertEqual(measure(name, width: 342).height, short, accuracy: 4, name)
        }
    }
    #endif
}
