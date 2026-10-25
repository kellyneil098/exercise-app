import Foundation

/// Where an exercise sits when browsing the catalog. Derived from its movement pattern's `day_type` in
/// movement_patterns.json, so the seed stays the single source of the taxonomy.
public enum ExerciseGroup: Hashable, Sendable {
    /// The pattern's home day (push / pull / legs).
    case day(DayType)
    /// A pattern that belongs to no single day (e.g. core, `day_type: "any"`) is its own group.
    case pattern(String)
    /// Not in the catalog (e.g. a partner's custom exercise) or its pattern is unknown.
    case uncategorized
}

/// One titled section of the exercise browser, entries sorted by name.
public struct ExerciseBrowseSection: Identifiable, Hashable, Sendable {
    public struct Entry: Identifiable, Hashable, Sendable {
        public var id: String { key }
        public let key: String
        public let name: String
        /// Secondary line: the movement pattern (when it adds information), custom marker, or "Not in catalog".
        public let detail: String?
    }

    public var id: ExerciseGroup { group }
    public let group: ExerciseGroup
    public let title: String
    public let entries: [Entry]
}

extension Catalog {
    public func group(ofExercise key: String) -> ExerciseGroup {
        guard let e = exercises[key], let p = patterns[e.movementPattern] else { return .uncategorized }
        if let day = DayType(rawValue: p.dayType), day != .fullBody { return .day(day) }
        return .pattern(p.key)
    }

    public func title(of group: ExerciseGroup) -> String {
        switch group {
        case .day(let d): d.label
        case .pattern(let key): Catalog.patternLabel(key)
        case .uncategorized: "Other"
        }
    }

    /// Human name for a key, falling back to a tidied key for exercises the catalog doesn't know.
    public func displayName(ofExercise key: String) -> String {
        exercises[key]?.name ?? Catalog.patternLabel(key)
    }

    public static func patternLabel(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Groups `keys` into sections (Push, Pull, Legs, then cross-day patterns A–Z, then Other), names sorted
    /// A–Z within each. A non-empty `query` keeps entries whose name, pattern or section title contains it.
    public func browseSections(keys: some Sequence<String>, query: String = "") -> [ExerciseBrowseSection] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var byGroup: [ExerciseGroup: [ExerciseBrowseSection.Entry]] = [:]
        for key in Set(keys) {
            let group = group(ofExercise: key)
            let entry = browseEntry(forExercise: key)
            if !q.isEmpty {
                let haystack = [entry.name, exercises[key].map { Catalog.patternLabel($0.movementPattern) }, title(of: group)]
                guard haystack.contains(where: { $0?.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil })
                else { continue }
            }
            byGroup[group, default: []].append(entry)
        }
        return byGroup
            .map { group, entries in
                ExerciseBrowseSection(
                    group: group, title: title(of: group),
                    entries: entries.sorted {
                        let order = $0.name.localizedStandardCompare($1.name)
                        return order == .orderedSame ? $0.key < $1.key : order == .orderedAscending
                    })
            }
            .sorted { a, b in
                let (ra, rb) = (rank(a.group), rank(b.group))
                return ra == rb ? a.title.localizedStandardCompare(b.title) == .orderedAscending : ra < rb
            }
    }

    /// The row an exercise gets in the browser (name + secondary line), also used to label the current pick.
    public func browseEntry(forExercise key: String) -> ExerciseBrowseSection.Entry {
        let group = group(ofExercise: key)
        guard let e = exercises[key] else { return .init(key: key, name: displayName(ofExercise: key), detail: "Not in catalog") }
        let pattern = Catalog.patternLabel(e.movementPattern)
        let informative = pattern == title(of: group) ? nil : pattern
        let detail = e.isCustom ? ["Custom", informative].compactMap { $0 }.joined(separator: " · ") : informative
        return .init(key: key, name: e.name, detail: detail)
    }

    private func rank(_ group: ExerciseGroup) -> Int {
        switch group {
        case .day(let d): DayType.allCases.firstIndex(of: d) ?? 0
        case .pattern: DayType.allCases.count
        case .uncategorized: DayType.allCases.count + 1
        }
    }
}
