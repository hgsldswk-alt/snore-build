import Foundation

enum ScoreCalculator {
    static let weights = [0.0, 0.4, 0.7, 1.0]
    static func levels(_ night: Night) -> [MinuteBin] {
        var bins = night.minutes
        for clip in night.exclusions {
            for i in clip.minuteIndices where bins.indices.contains(i) { bins[i].level = 0 }
        }
        return bins
    }
    static func score(_ night: Night) -> Int? {
        guard night.recordedSeconds >= 1800 else { return nil }
        let bins = levels(night).filter { !$0.interrupted }
        guard !bins.isEmpty else { return nil }
        let total = bins.reduce(0.0) { $0 + weights[max(0, min(3, $1.level))] }
        return max(0, min(100, Int((100 * total / Double(bins.count)).rounded())))
    }
    static func label(_ score: Int) -> String {
        switch score { case ...10: return L.t("安静"); case ...25: return L.t("轻"); case ...50: return L.t("中"); default: return L.t("响") }
    }
    static func levelLabel(_ level: Int) -> String { L.t(["安静", "轻", "中", "响"][max(0, min(3, level))]) }
}

struct FactorComparison: Equatable {
    let withCount: Int; let withoutCount: Int
    let withAverage: Double; let withoutAverage: Double
    var difference: Double { withAverage - withoutAverage }
}
enum FactorStats {
    static func comparison(_ factor: String, nights: [Night]) -> FactorComparison? {
        let scored = nights.filter { !$0.inProgress && $0.score != nil }
        let yes = scored.filter { $0.factors.contains(factor) }.compactMap(\.score)
        let no = scored.filter { !$0.factors.contains(factor) }.compactMap(\.score)
        guard yes.count >= 3, no.count >= 3 else { return nil }
        return FactorComparison(withCount: yes.count, withoutCount: no.count,
                                withAverage: Double(yes.reduce(0, +)) / Double(yes.count),
                                withoutAverage: Double(no.reduce(0, +)) / Double(no.count))
    }
}

enum ClipSelection {
    static func insert(_ clip: Clip, into clips: inout [Clip], limit: Int) -> [Clip] {
        clips.append(clip); clips.sort { $0.peakDb > $1.peakDb }
        let removed = Array(clips.dropFirst(limit)); clips = Array(clips.prefix(limit)); return removed
    }
}

enum Recovery {
    @discardableResult static func finish(_ data: inout AppData) -> [UUID] {
        var ids: [UUID] = []
        for i in data.nights.indices where data.nights[i].inProgress {
            let night = data.nights[i]
            data.nights[i].finish(at: night.checkpointAt ?? night.startedAt.addingTimeInterval(night.recordedSeconds + night.interruptedSeconds), reason: .recovered)
            ids.append(night.id)
        }
        return ids
    }
}
