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
    @State private var exerciseKey: String = "bench_press"
    @State private var partnerId: String?
    @State private var partners: [UserDTO] = []

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Overline("Progress")
                    if !partners.isEmpty {
                        HStack(spacing: Theme.Spacing.s) {
                            Chip("Just me", selected: partnerId == nil) { partnerId = nil }
                            ForEach(partners, id: \.id) { p in Chip("With \(p.displayName.isEmpty ? "partner" : p.displayName)", selected: partnerId == p.id) { partnerId = p.id } }
                        }
                    }
                    Card { weightChart }
                    Card { volumeChart }
                    Card { mileageChart }
                }
                .padding(Theme.Spacing.l)
            }
        }
        .presentationBackground(Theme.Colors.canvas)
        .task { partners = (try? await model.shares())?.iCanView ?? [] }
    }

    var userIds: [(String, Color)] {
        var ids = [(model.userId, Theme.Colors.brass)]
        if let partnerId { ids.append((partnerId, Theme.Colors.partner)) }
        return ids
    }

    struct Point: Identifiable { var id: String { "\(who)-\(date.timeIntervalSince1970)" }; var who: String; var date: Date; var value: Double }

    func weightSeries(_ uid: String) -> [Point] {
        let rows = (try? model.store.db.read {
            try SetLog.filter(Column("userId") == uid && Column("exerciseKey") == exerciseKey && Column("isWarmup") == false && Column("deleted") == false)
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

    var exerciseKeys: [String] {
        let mine = (try? model.store.db.read { try String.fetchAll($0, sql: "SELECT DISTINCT exerciseKey FROM set_log WHERE userId = ? ORDER BY exerciseKey", arguments: [model.userId]) }) ?? []
        return mine.isEmpty ? ["bench_press", "back_squat", "deadlift"] : mine
    }

    var weightChart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Overline("Working weight")
                Spacer()
                Picker("", selection: $exerciseKey) { ForEach(exerciseKeys, id: \.self) { Text(model.catalog.exercises[$0]?.name ?? $0).tag($0) } }
                    .labelsHidden().tint(Theme.Colors.textSecondary)
            }
            chart(userIds.flatMap { weightSeries($0.0) }, unit: "lb", lines: true)
        }
    }

    var volumeChart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Overline("Weekly volume")
            chart(userIds.flatMap { volumeSeries($0.0) }, unit: "lb", lines: false)
        }
    }

    var mileageChart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Overline("Weekly mileage")
            chart(userIds.flatMap { mileageSeries($0.0) }, unit: "mi", lines: false)
        }
    }

    @ViewBuilder func chart(_ points: [Point], unit: String, lines: Bool) -> some View {
        if points.isEmpty {
            Text("Nothing yet.").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textTertiary).frame(height: 120)
        } else {
            Chart(points) { p in
                if lines {
                    LineMark(x: .value("Date", p.date), y: .value(unit, p.value)).foregroundStyle(by: .value("Who", p.who)).interpolationMethod(.monotone)
                    PointMark(x: .value("Date", p.date), y: .value(unit, p.value)).foregroundStyle(by: .value("Who", p.who))
                } else {
                    BarMark(x: .value("Week", p.date, unit: .weekOfYear), y: .value(unit, p.value)).foregroundStyle(by: .value("Who", p.who)).position(by: .value("Who", p.who))
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
