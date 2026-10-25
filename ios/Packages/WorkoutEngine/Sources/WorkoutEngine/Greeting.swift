import Foundation

/// Home's time-of-day greeting, split into its phrase and the name it addresses so the header can lay it out
/// inline ("Good morning, Neil") or as two lines when the name is long. The stored display name is never altered:
/// the greeting addresses its first word, as onboarding asks for a first name.
public struct Greeting: Equatable, Sendable {
    public enum DayPart: String, CaseIterable, Sendable {
        case morning, afternoon, evening

        /// Before noon is morning, noon to 6 pm afternoon, 6 pm onwards evening.
        public init(hour: Int) {
            self = hour < 12 ? .morning : hour < 18 ? .afternoon : .evening
        }

        public var phrase: String {
            switch self {
            case .morning: "Good morning"
            case .afternoon: "Good afternoon"
            case .evening: "Good evening"
            }
        }
    }

    public let dayPart: DayPart
    /// `nil` when the display name is empty or only whitespace.
    public let name: String?

    public init(dayPart: DayPart, displayName: String) {
        self.dayPart = dayPart
        name = Self.firstName(of: displayName)
    }

    public init(date: Date = .now, calendar: Calendar = .current, displayName: String) {
        self.init(dayPart: DayPart(hour: calendar.component(.hour, from: date)), displayName: displayName)
    }

    public var phrase: String { dayPart.phrase }

    /// The single-line form, also what VoiceOver reads whichever layout is on screen.
    public var inline: String { name.map { "\(phrase), \($0)" } ?? phrase }

    /// First whitespace-separated word (any Unicode whitespace, e.g. the ideographic space), untouched otherwise
    /// so punctuation, emoji and non-Latin scripts survive.
    public static func firstName(of displayName: String) -> String? {
        displayName.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }
}
