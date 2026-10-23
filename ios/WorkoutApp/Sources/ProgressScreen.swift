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
    @State private var exerciseKey: String = "barbell_bench_press"
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
        return mine.isEmpty ? ["barbell_bench_press", "back_squat", "deadlift"] : mine
    }

    var weightChart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.sm) {
                Glyph("scalemass", tint: Theme.Colors.brass, width: 20)
                Overline("Working weight", tint: Theme.Colors.textSecondary)
                Spacer()
                Picker("", selection: $exerciseKey) { ForEach(exerciseKeys, id: \.self) { Text(model.catalog.exercises[$0]?.name ?? $0).tag($0) } }
                    .labelsHidden().tint(Theme.Colors.textSecondary)
            }
            Hairline()
            chart(userIds.flatMap { weightSeries($0.0) }, unit: "lb", lines: true)
        }
        .onAppear { if !exerciseKeys.contains(exerciseKey), let first = exerciseKeys.first { exerciseKey = first } }
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
