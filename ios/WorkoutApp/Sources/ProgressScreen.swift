import Charts
import GRDB
import SwiftUI
import WorkoutEngine
import WorkoutStore
import WorkoutUI

/// Progress (§12): per-exercise working weight over time, weekly volume, weekly mileage.
/// Partner data shows in the partner hue, side by side, never ranked.
struct ProgressScreen: View {
    @Environment(AppModel.self) private var model
    /// The user's pick; `nil` (or a pick no longer on the list) falls back to the most-performed lift (§12.1).
    @State private var exerciseKey: String?
    @State private var choosingExercise = false
    @State private var partnerId: String?
    @State private var partners: [UserDTO] = []

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Overline("Progress")
                        Text("Your numbers").font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                    }
                    .padding(.top, Theme.Spacing.s)
                    summary
                    if !partners.isEmpty {
                        HStack(spacing: Theme.Spacing.l) {
                            TextOption("Just me", icon: "person", selected: partnerId == nil) { partnerId = nil }
                            ForEach(partners, id: \.id) { p in TextOption("With \(p.displayName.isEmpty ? "partner" : p.displayName)", icon: "person.2", selected: partnerId == p.id) { partnerId = p.id } }
                        }
                    }
                    weightChart
                    volumeChart
                    mileageChart
                }
                .padding(.horizontal, Theme.Spacing.l).padding(.bottom, Theme.Spacing.xl)
            }
        }
        .presentationBackground(Theme.Colors.canvas)
        .task { partners = (try? await model.shares())?.iCanView ?? [] }
    }

    /// Four numbers that say how training is going: sessions and volume this week, plus the all-time totals.
    var summary: some View {
        let recent = model.completedSessions()
        let week = recent.filter { $0.performedAt >= Date.startOfWeek }
        let volume = volumeSeries(model.userId)
        let thisWeek = volume.last.flatMap { $0.date >= Date.startOfWeek ? $0.value : nil } ?? 0
        let miles = mileageSeries(model.userId).reduce(0) { $0 + $1.value }
        return VStack(spacing: Theme.Spacing.m) {
            HStack(alignment: .top) {
                Stat("\(week.count)", label: "this week", tint: Theme.Colors.brass)
                Spacer()
                Stat(compact(thisWeek), unit: "lb", label: "volume")
                Spacer()
                Stat("\(recent.count)", label: "sessions")
                Spacer()
                Stat(compact(miles), unit: "mi", label: "run")
            }
            Hairline()
        }
    }

    func compact(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1fk", v / 1000) : v.formatted(.number.precision(.fractionLength(0...1)))
    }

    var userIds: [(String, Color)] {
        var ids = [(model.userId, Theme.Colors.brass)]
        if let partnerId { ids.append((partnerId, Theme.Colors.partner)) }
        return ids
    }

    struct Point: Identifiable { var id: String { "\(who)-\(date.timeIntervalSince1970)" }; var who: String; var date: Date; var value: Double }

    func weightSeries(_ uid: String) -> [Point] {
        let rows = (try? model.store.db.read {
            try SetLog.filter(Column("userId") == uid && Column("exerciseKey") == selectedKey && Column("isWarmup") == false && Column("deleted") == false)
                .order(Column("completedAt")).fetchAll($0)
        }) ?? []
        var byDay: [Date: Double] = [:]
        for r in rows { let d = Calendar.current.startOfDay(for: r.completedAt); byDay[d] = max(byDay[d] ?? 0, r.weight ?? 0) }
        return byDay.sorted { $0.key < $1.key }.map { Point(who: uid, date: $0.key, value: $0.value) }
    }

    func volumeSeries(_ uid: String) -> [Point] {
        let rows = (try? model.store.db.read {
            try SetLog.filter(Column("userId") == uid && Column("isWarmup") == false && Column("deleted") == false).fetchAll($0)
        }) ?? []
        return weekly(rows.map { ($0.completedAt, Double($0.repsDone) * ($0.weight ?? 0)) }, who: uid)
    }

    func mileageSeries(_ uid: String) -> [Point] {
        let rows = (try? model.store.db.read {
            try RunRow.filter(Column("userId") == uid && Column("completedAt") != nil && Column("deleted") == false).fetchAll($0)
        }) ?? []
        return weekly(rows.map { ($0.completedAt ?? $0.weekStart, $0.distanceMi ?? 0) }, who: uid)
    }

    func weekly(_ items: [(Date, Double)], who: String) -> [Point] {
        let cal = Calendar.current
        var byWeek: [Date: Double] = [:]
        for (d, v) in items {
            let w = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)) ?? d
            byWeek[w, default: 0] += v
        }
        return byWeek.sorted { $0.key < $1.key }.map { Point(who: who, date: $0.key, value: $0.value) }
    }

    /// Exercises with at least one working set for any of `uids`, most-performed (by sessions) first.
    func performedKeys(_ uids: [String]) -> [String] {
        let marks = uids.map { _ in "?" }.joined(separator: ", ")
        let sql = """
            SELECT exerciseKey FROM set_log WHERE userId IN (\(marks)) AND isWarmup = 0 AND deleted = 0
            GROUP BY exerciseKey ORDER BY COUNT(DISTINCT sessionId) DESC, COUNT(*) DESC, exerciseKey
            """
        return (try? model.store.db.read { try String.fetchAll($0, sql: sql, arguments: StatementArguments(uids)) }) ?? []
    }

    /// Everything charted on screen (me, plus the partner when one is shown), or a starter set before any data.
    var exerciseKeys: [String] {
        let keys = performedKeys(userIds.map(\.0))
        return keys.isEmpty ? ["barbell_bench_press", "back_squat", "deadlift"] : keys
    }

    var selectedKey: String {
        let keys = exerciseKeys
        if let exerciseKey, keys.contains(exerciseKey) { return exerciseKey }
        return performedKeys([model.userId]).first ?? keys[0]
    }

    var weightChart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.sm) {
                Glyph("scalemass", tint: Theme.Colors.brass, width: 20)
                Overline("Working weight", tint: Theme.Colors.textSecondary)
            }
            Hairline()
            exerciseButton
            chart(userIds.flatMap { weightSeries($0.0) }, unit: "lb", lines: true)
        }
        .sheet(isPresented: $choosingExercise) {
            ProgressExercisePicker(keys: exerciseKeys, selected: selectedKey) { exerciseKey = $0 }
        }
    }

    /// The current exercise, with its section and pattern; tap to open the searchable picker.
    var exerciseButton: some View {
        let key = selectedKey
        let entry = model.catalog.browseEntry(forExercise: key)
        let caption = [model.catalog.title(of: model.catalog.group(ofExercise: key)), entry.detail].compactMap { $0 }.joined(separator: " · ")
        return Button { choosingExercise = true } label: {
            HStack(spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(Theme.Fonts.heading).foregroundStyle(Theme.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(caption).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.Colors.brass)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exercise")
        .accessibilityValue("\(entry.name), \(caption)")
        .accessibilityHint("Choose which exercise's working weight to chart")
        .accessibilityAddTraits(.isButton)
    }

    var volumeChart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.sm) {
                Glyph("chart.bar", tint: Theme.Colors.push, width: 20)
                Overline("Weekly volume", tint: Theme.Colors.textSecondary)
            }
            Hairline()
            chart(userIds.flatMap { volumeSeries($0.0) }, unit: "lb", lines: false)
        }
    }

    var mileageChart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.sm) {
                Glyph("figure.run", tint: Theme.Colors.pull, width: 20)
                Overline("Weekly mileage", tint: Theme.Colors.textSecondary)
            }
            Hairline()
            chart(userIds.flatMap { mileageSeries($0.0) }, unit: "mi", lines: false)
        }
    }

    @ViewBuilder func chart(_ points: [Point], unit: String, lines: Bool) -> some View {
        if points.isEmpty {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: "waveform.path.ecg").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.Colors.textTertiary)
                Text("Your first session draws the first point.").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: 56)
        } else {
            Chart(points) { p in
                if lines {
                    AreaMark(x: .value("Date", p.date), y: .value(unit, p.value)).foregroundStyle(by: .value("Who", p.who)).interpolationMethod(.monotone).opacity(0.12)
                    LineMark(x: .value("Date", p.date), y: .value(unit, p.value)).foregroundStyle(by: .value("Who", p.who)).interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    PointMark(x: .value("Date", p.date), y: .value(unit, p.value)).foregroundStyle(by: .value("Who", p.who)).symbolSize(40)
                } else {
                    BarMark(x: .value("Week", p.date, unit: .weekOfYear), y: .value(unit, p.value)).foregroundStyle(by: .value("Who", p.who)).position(by: .value("Who", p.who)).cornerRadius(4)
                }
            }
            .chartForegroundStyleScale(domain: userIds.map(\.0), range: userIds.map(\.1))
            .chartLegend(.hidden)
            .chartXAxis { AxisMarks { AxisValueLabel().foregroundStyle(Theme.Colors.textTertiary) } }
            .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(Theme.Colors.hairline); AxisValueLabel().foregroundStyle(Theme.Colors.textTertiary) } }
            .frame(height: 160)
        }
    }
}

/// Progress's exercise picker: the deck's swap picker layout (search field, overline sections, plain rows),
/// grouped by the pattern's home day from the seed (Push, Pull, Legs, then Core and Other), A–Z within each.
struct ProgressExercisePicker: View {
    let keys: [String]
    let selected: String
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        let sections = model.catalog.browseSections(keys: keys, query: query)
        Screen {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Overline("Working weight")
                ExerciseSearchField(text: $query)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if sections.isEmpty {
                                Text("No matches").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textTertiary).padding(.vertical, 12)
                            }
                            ForEach(Array(sections.enumerated()), id: \.element.id) { i, section in
                                ExercisePickerHeader(title: section.title, topPadding: i == 0 ? Theme.Spacing.s : Theme.Spacing.l)
                                ForEach(section.entries) { entry in
                                    ExercisePickerRow(name: entry.name, detail: entry.detail, selected: entry.key == selected, action: {
                                        onPick(entry.key)
                                        dismiss()
                                    })
                                    .id(entry.key)
                                }
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .onAppear { proxy.scrollTo(selected, anchor: .center) }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.Colors.canvas)
    }
}
