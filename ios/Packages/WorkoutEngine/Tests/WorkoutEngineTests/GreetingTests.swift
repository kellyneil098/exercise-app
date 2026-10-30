import XCTest
@testable import WorkoutEngine

final class GreetingTests: XCTestCase {
    func testDayPartBoundaries() {
        let expected: [(Int, Greeting.DayPart)] = [
            (0, .morning), (5, .morning), (11, .morning),
            (12, .afternoon), (17, .afternoon),
            (18, .evening), (23, .evening),
        ]
        for (hour, part) in expected { XCTAssertEqual(Greeting.DayPart(hour: hour), part, "hour \(hour)") }
    }

    func testPhrasesPerDayPart() {
        XCTAssertEqual(Greeting.DayPart.allCases.map(\.phrase), ["Good morning", "Good afternoon", "Good evening"])
    }

    func testInlineAndSplitForms() {
        for part in Greeting.DayPart.allCases {
            let g = Greeting(dayPart: part, displayName: "Neil")
            XCTAssertEqual(g.phrase, part.phrase)
            XCTAssertEqual(g.name, "Neil")
            XCTAssertEqual(g.inline, "\(part.phrase), Neil")
        }
    }

    func testEmptyOrBlankNameDropsTheComma() {
        for blank in ["", "   ", "\t\n"] {
            let g = Greeting(dayPart: .evening, displayName: blank)
            XCTAssertNil(g.name)
            XCTAssertEqual(g.inline, "Good evening")
        }
    }

    func testFirstNameKeepsPunctuationEmojiAndScripts() {
        let cases: [(String, String)] = [
            ("Neil Kelly", "Neil"),
            ("  Neil   Kelly ", "Neil"),
            ("Anna-Katharina von Hohenzollern", "Anna-Katharina"),
            ("O'Brien", "O'Brien"),
            ("J.R.R. Tolkien", "J.R.R."),
            ("💪 Neil", "💪"),
            ("Neil💪🏽", "Neil💪🏽"),
            ("👩‍👩‍👧‍👦", "👩‍👩‍👧‍👦"),
            ("José", "José"),
            ("Ζωή Παπαδοπούλου", "Ζωή"),
            ("Дмитрий Иванов", "Дмитрий"),
            ("محمد علي", "محمد"),
            ("王小明", "王小明"),
            ("山田\u{3000}太郎", "山田"),
            ("Wolfeschlegelsteinhausenbergerdorff", "Wolfeschlegelsteinhausenbergerdorff"),
        ]
        for (display, first) in cases { XCTAssertEqual(Greeting.firstName(of: display), first, display) }
    }

    func testDateInitialiserUsesTheCalendarsHour() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        func at(_ hour: Int) throws -> Date { try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: hour, minute: 30))) }
        XCTAssertEqual(Greeting(date: try at(8), calendar: cal, displayName: "Neil").inline, "Good morning, Neil")
        XCTAssertEqual(Greeting(date: try at(13), calendar: cal, displayName: "Neil").inline, "Good afternoon, Neil")
        XCTAssertEqual(Greeting(date: try at(21), calendar: cal, displayName: "Neil").inline, "Good evening, Neil")
    }
}
