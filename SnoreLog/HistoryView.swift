import Charts
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var month = Calendar.current.startOfDay(for: Date())
    @State private var days = 7
    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: L.t("历史"))
                calendarCard
                if model.nights.isEmpty {
                    ContentUnavailableView(L.t("暂无记录"), systemImage: "moon",
                        description: Text(L.t("今晚记一次，早上就能在这里看到。")))
                } else {
                    if let best = model.nights.filter({ $0.score != nil }).min(by: { ($0.score ?? 101) < ($1.score ?? 101) }) {
                        NavigationLink(value: best.id) {
                            HStack {
                                Label(L.t("最安静的一晚"), systemImage: "moon.stars")
                                Spacer()
                                Text(L.date(best.endDate)).foregroundStyle(Palette.secondary)
                                Text(best.score.map(String.init) ?? "–").monospacedDigit()
                            }
                            .font(.subheadline)
                            .nightCard()
                        }
                        .buttonStyle(.plain)
                    }
                    trends
                    recentList
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .background(Palette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("historyPage")
    }

    private var calendarCard: some View {
        VStack(spacing: 11) {
            HStack {
                monthButton(-1, icon: "chevron.left", label: L.t("上个月"))
                Spacer()
                Text(month.formatted(.dateTime.year().month(.wide))).font(.headline)
                Spacer()
                monthButton(1, icon: "chevron.right", label: L.t("下个月"))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(0..<7) { offset in
                    let index = (calendar.firstWeekday - 1 + offset) % 7
                    Text(calendar.veryShortStandaloneWeekdaySymbols[index]).font(.caption2).foregroundStyle(Palette.secondary)
                }
                ForEach(Array(monthDates.enumerated()), id: \.offset) { _, date in
                    if let date { dayCell(date) } else { Color.clear.frame(height: 39) }
                }
            }
        }
        .nightCard(12)
    }

    private func monthButton(_ amount: Int, icon: String, label: String) -> some View {
        Button {
            if let start = calendar.dateInterval(of: .month, for: month)?.start,
               let shifted = calendar.date(byAdding: .month, value: amount, to: start) { month = shifted }
        } label: {
            Image(systemName: icon).frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.accent)
        .accessibilityLabel(label)
    }

    private var monthDates: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let first = calendar.component(.weekday, from: interval.start)
        let blanks = (7 + first - calendar.firstWeekday) % 7
        return Array(repeating: nil, count: blanks) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    @ViewBuilder private func dayCell(_ date: Date) -> some View {
        let records = model.nights.filter { $0.dayKey == DayKey.make(date) }
        if let first = records.first {
            if records.count == 1 {
                NavigationLink(value: first.id) { dayLabel(date, records: records) }
                    .buttonStyle(.plain)
            } else {
                NavigationLink {
                    dayList(date, records: records)
                } label: { dayLabel(date, records: records) }
                .buttonStyle(.plain)
            }
        } else {
            dayLabel(date, records: records)
        }
    }

    private func dayLabel(_ date: Date, records: [Night]) -> some View {
        let score = records.compactMap(\.score).max() ?? 0
        return VStack(spacing: 3) {
            Text(String(calendar.component(.day, from: date))).font(.subheadline).foregroundStyle(Palette.ink)
            Circle().fill(records.isEmpty ? Color.clear : Palette.accent.opacity(0.35 + 0.65 * Double(score) / 100))
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(calendar.isDateInToday(date) ? Palette.accent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L.date(date))
        .accessibilityValue(records.isEmpty ? "" : L.f("%@ 次记录", String(records.count)))
    }

    private func dayList(_ date: Date, records: [Night]) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(records) { record in recordLink(record) }
            }
            .padding(22)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(L.date(date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("最近记录")).font(.headline)
            ForEach(model.nights.prefix(7)) { record in recordLink(record) }
        }
    }

    private func recordLink(_ record: Night) -> some View {
        NavigationLink(value: record.id) {
            HStack {
                Text(L.date(record.endDate))
                Text(L.clock(record.startedAt) + "–" + L.clock(record.endDate)).foregroundStyle(Palette.secondary)
                Spacer()
                Text(record.score.map(String.init) ?? "–").monospacedDigit().foregroundStyle(Palette.accent)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Palette.secondary)
            }
            .font(.subheadline)
            .nightCard(12)
        }
        .buttonStyle(.plain)
    }

    private var trends: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L.t("鼾声趋势")).font(.headline)
                Spacer()
                if !model.hasPro { Image(systemName: "lock").foregroundStyle(Palette.secondary) }
            }
            if model.hasPro {
                Picker(L.t("时间范围"), selection: $days) {
                    ForEach([7, 30, 90], id: \.self) { count in
                        Text(L.f("%@ 天", String(count))).tag(count)
                    }
                }
                .pickerStyle(.segmented)
                let points = trendPoints
                if points.isEmpty {
                    Text(L.t("暂无分数")).foregroundStyle(Palette.secondary).font(.footnote)
                } else {
                    Chart(points) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Score", point.average))
                        PointMark(x: .value("Date", point.date), y: .value("Score", point.average))
                    }
                    .foregroundStyle(Palette.accent)
                    .chartYScale(domain: 0.0...100.0)
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .frame(height: 132)
                    .accessibilityLabel(L.t("鼾声趋势"))
                }
            } else {
                Button(L.t("解锁趋势")) { model.paywall = true }
            }
        }
        .nightCard()
    }

    private struct TrendPoint: Identifiable {
        let date: Date
        let average: Double
        var id: Date { date }
    }

    private var trendPoints: [TrendPoint] {
        let end = calendar.startOfDay(for: model.now)
        let start = calendar.date(byAdding: .day, value: 1 - days, to: end) ?? end
        let nights = model.nights.filter { $0.endDate >= start }
        let groups = Dictionary(grouping: nights) { calendar.startOfDay(for: $0.endDate) }
        return groups.compactMap { date, records in
            let scores = records.compactMap(\.score)
            guard !scores.isEmpty else { return nil }
            return TrendPoint(date: date, average: Double(scores.reduce(0, +)) / Double(scores.count))
        }.sorted { $0.date < $1.date }
    }
}
