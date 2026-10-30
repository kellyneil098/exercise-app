import Foundation

/// How long ago a session happened, in calendar days, for Home's secondary "last" text: "today", "yesterday",
/// "3 days ago" within the week, then a short date.
public enum Recency: Equatable, Sendable {
    case today, yesterday
    case daysAgo(Int)
    case date(Date)

    /// Counts calendar-day boundaries, so 11 pm yesterday is "yesterday" at 1 am. A date in the future (clock skew)
    /// reads as today.
    public init(_ date: Date, now: Date = .now, calendar: Calendar = .current) {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: self = .today
        case 1: self = .yesterday
        case 2..<7: self = .daysAgo(days)
        default: self = .date(date)
        }
    }

    /// Lower-case so it can follow other words ("last · 2 days ago", "done yesterday").
    public func text(calendar: Calendar = .current) -> String {
        switch self {
        case .today: "today"
        case .yesterday: "yesterday"
        case .daysAgo(let n): "\(n) days ago"
        case .date(let d):
            d.formatted(Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
                .day().month(.abbreviated))
        }
    }
}
