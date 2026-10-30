import XCTest
@testable import WorkoutEngine

final class RecencyTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        c.locale = Locale(identifier: "en_US")
        return c
    }()

    private func date(_ day: Int, _ hour: Int, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    func testCalendarDaysNotElapsedHours() {
        let now = date(30, 1)
        XCTAssertEqual(Recency(date(30, 0), now: now, calendar: calendar), .today)
        XCTAssertEqual(Recency(date(29, 23), now: now, calendar: calendar), .yesterday)
        XCTAssertEqual(Recency(date(28, 23), now: now, calendar: calendar), .daysAgo(2))
        XCTAssertEqual(Recency(date(24, 9), now: now, calendar: calendar), .daysAgo(6))
    }

    func testAWeekOrMoreFallsBackToADate() {
        let now = date(30, 12)
        let old = date(23, 12)
        XCTAssertEqual(Recency(old, now: now, calendar: calendar), .date(old))
        XCTAssertTrue(Recency(old, now: now, calendar: calendar).text(calendar: calendar).hasPrefix("Oct"))
    }

    func testFutureReadsAsToday() {
        XCTAssertEqual(Recency(date(31, 9), now: date(30, 9), calendar: calendar), .today)
    }

    func testText() {
        XCTAssertEqual(Recency.today.text(calendar: calendar), "today")
        XCTAssertEqual(Recency.yesterday.text(calendar: calendar), "yesterday")
        XCTAssertEqual(Recency.daysAgo(2).text(calendar: calendar), "2 days ago")
    }
}
