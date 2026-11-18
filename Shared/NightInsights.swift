import Foundation

struct Milestone: Equatable {
    let id: String
    let title: String
}

enum NightInsights {
    static func previousWeekDifference(_ night: Night, nights: [Night]) -> Int? {
        guard let score = night.score,
              let first = Calendar.current.date(byAdding: .day, value: -7,
                  to: Calendar.current.startOfDay(for: night.endDate)) else { return nil }
        let values = nights.filter { $0.endDate >= first && $0.endDate < night.endDate && $0.dayKey != night.dayKey }
            .compactMap(\.score)
        guard !values.isEmpty else { return nil }
        let mean = Double(values.reduce(0, +)) / Double(values.count)
        return Int((Double(score) - mean).rounded())
    }

    static func shareHeadline(_ night: Night, nights: [Night]) -> String? {
        guard let score = night.score else { return nil }
        let previous = nights.filter { $0.endDate < night.endDate }.compactMap(\.score)
        if score == 0 && !previous.contains(0) { return L.t("第一次记下 0 分") }
        if let best = previous.min(), score < best { return L.t("最安静的一晚") }
        if let difference = previousWeekDifference(night, nights: nights), difference < 0 {
            return L.f("比前 7 晚平均低 %@ 分", String(-difference))
        }
        for factor in night.factors.sorted() {
            if let result = FactorStats.comparison(factor, nights: nights) {
                return L.f("%@ · %@", L.t(factor), comparisonLabel(result.difference))
            }
        }
        return nil
    }

    static func comparisonLabel(_ difference: Double) -> String {
        let points = Int(difference.rounded())
        if points == 0 { return L.t("平均分相同") }
        return L.f(points < 0 ? "平均低 %@ 分" : "平均高 %@ 分", String(abs(points)))
    }

    static func streak(on night: Night, nights: [Night], calendar: Calendar = .current) -> Int {
        let days = Set(nights.filter { $0.recordedSeconds > 0 && !$0.inProgress }.map {
            calendar.startOfDay(for: $0.endDate)
        })
        var day = calendar.startOfDay(for: night.endDate)
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }

    static func milestone(for night: Night, data: AppData) -> Milestone? {
        let nights = data.nights.filter { !$0.inProgress && $0.endDate <= night.endDate }
        let streak = streak(on: night, nights: nights)
        for days in [30, 7] {
            let id = "streak-\(days)"
            if streak >= days, !data.milestones.contains(id) {
                return Milestone(id: id, title: L.f("连续记录 %@ 晚", String(days)))
            }
        }
        guard night.score != nil else { return nil }
        for factor in data.customFactors {
            let id = "factor-" + factor
            guard !data.milestones.contains(id), let result = FactorStats.comparison(factor, nights: nights),
                  FactorStats.comparison(factor, nights: nights.filter { $0.id != night.id }) == nil else { continue }
            return Milestone(id: id, title: L.f("%@ · %@", L.t(factor), comparisonLabel(result.difference)))
        }
        return nil
    }
}
