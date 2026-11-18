import Foundation

struct MinuteBin: Codable, Equatable {
    var level: Int = 0
    var interrupted: Bool = false
    init(level: Int = 0, interrupted: Bool = false) { self.level = max(0, min(3, level)); self.interrupted = interrupted }
}

struct Clip: Codable, Equatable, Identifiable {
    var id = UUID()
    var startOffset: Double
    var duration: Double
    var peakDb: Double
    var level: Int
    var fileName: String
    var notMe = false
    init(id: UUID = UUID(), startOffset: Double, duration: Double, peakDb: Double, level: Int, fileName: String, notMe: Bool = false) {
        self.id = id; self.startOffset = startOffset; self.duration = duration; self.peakDb = peakDb
        self.level = level; self.fileName = fileName; self.notMe = notMe
    }
    enum CodingKeys: String, CodingKey { case id, startOffset, duration, peakDb, level, fileName, notMe }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startOffset = max(0, try c.decodeIfPresent(Double.self, forKey: .startOffset) ?? 0)
        duration = max(0, try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0)
        peakDb = try c.decodeIfPresent(Double.self, forKey: .peakDb) ?? -60
        level = max(0, min(3, try c.decodeIfPresent(Int.self, forKey: .level) ?? 0))
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        notMe = try c.decodeIfPresent(Bool.self, forKey: .notMe) ?? false
    }
    var minuteIndices: ClosedRange<Int> {
        let start = max(0, Int(startOffset / 60))
        return start...max(start, Int((startOffset + max(0, duration - 0.001)) / 60))
    }
}

enum EndReason: String, Codable { case normal, autoEnd, recovered }
struct AudioSegment: Codable, Equatable {
    let fileName: String
    let startOffset: Double
    let duration: Double
}

struct Night: Codable, Equatable, Identifiable {
    var id = UUID()
    var startedAt = Date()
    var endedAt: Date?
    var dayKey = ""
    var minutes: [MinuteBin] = []
    var snoreSeconds: Double = 0
    var recordedSeconds: Double = 0
    var interruptedSeconds: Double = 0
    var clips: [Clip] = []
    var talkClips: [Clip] = []
    var factors: Set<String> = []
    var endReason: EndReason = .normal
    var fullAudioFile: String?
    var audioSegments: [AudioSegment] = []
    var excludedClips: [Clip] = []
    var notMeCount = 0
    var inProgress = false
    var checkpointAt: Date?
    init(startedAt: Date = Date()) { self.startedAt = startedAt; dayKey = DayKey.make(startedAt) }
    enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, dayKey, minutes, snoreSeconds, recordedSeconds, interruptedSeconds
        case clips, talkClips, factors, endReason, fullAudioFile, audioSegments, excludedClips, notMeCount, inProgress, checkpointAt
    }
    init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        dayKey = try c.decodeIfPresent(String.self, forKey: .dayKey) ?? DayKey.make(endedAt ?? startedAt)
        minutes = try c.decodeIfPresent([MinuteBin].self, forKey: .minutes) ?? []
        snoreSeconds = try c.decodeIfPresent(Double.self, forKey: .snoreSeconds) ?? 0
        recordedSeconds = try c.decodeIfPresent(Double.self, forKey: .recordedSeconds) ?? Double(minutes.count) * 60
        interruptedSeconds = try c.decodeIfPresent(Double.self, forKey: .interruptedSeconds) ?? 0
        clips = try c.decodeIfPresent([Clip].self, forKey: .clips) ?? []
        talkClips = try c.decodeIfPresent([Clip].self, forKey: .talkClips) ?? []
        factors = try c.decodeIfPresent(Set<String>.self, forKey: .factors) ?? []
        endReason = try c.decodeIfPresent(EndReason.self, forKey: .endReason) ?? .normal
        fullAudioFile = try c.decodeIfPresent(String.self, forKey: .fullAudioFile)
        audioSegments = try c.decodeIfPresent([AudioSegment].self, forKey: .audioSegments) ?? []
        excludedClips = try c.decodeIfPresent([Clip].self, forKey: .excludedClips) ?? []
        notMeCount = exclusions.count
        inProgress = try c.decodeIfPresent(Bool.self, forKey: .inProgress) ?? false
        checkpointAt = try c.decodeIfPresent(Date.self, forKey: .checkpointAt)
    }
    var score: Int? { ScoreCalculator.score(self) }
    var sortedClips: [Clip] { clips.sorted { $0.peakDb > $1.peakDb } }
    var exclusions: [Clip] { clips.filter(\.notMe) + excludedClips }
    var adjustedSnoreSeconds: Double {
        max(0, snoreSeconds - exclusions.reduce(0) { $0 + $1.duration })
    }
    var fullSegments: [AudioSegment] {
        if let fullAudioFile, audioSegments.isEmpty {
            return [AudioSegment(fileName: fullAudioFile, startOffset: 0, duration: recordedSeconds)]
        }
        return audioSegments
    }
    var endDate: Date { endedAt ?? checkpointAt ?? startedAt.addingTimeInterval(recordedSeconds) }
    mutating func finish(at date: Date, reason: EndReason) {
        endedAt = max(startedAt, date); dayKey = DayKey.make(endDate); endReason = reason; inProgress = false
        notMeCount = exclusions.count
    }
}

enum DayKey {
    static func make(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1)
    }
}

struct Settings: Codable, Equatable {
    var fullNight = false
    var autoEndTime: Int?
    init() {}
    enum CodingKeys: String, CodingKey { case fullNight, autoEndTime }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fullNight = try c.decodeIfPresent(Bool.self, forKey: .fullNight) ?? false
        autoEndTime = try c.decodeIfPresent(Int.self, forKey: .autoEndTime).map { max(0, min(1439, $0)) }
    }
    func nextAutoEnd(after start: Date, calendar: Calendar = .current) -> Date? {
        guard let minutes = autoEndTime else { return nil }
        return calendar.nextDate(after: start, matching: DateComponents(hour: minutes / 60, minute: minutes % 60), matchingPolicy: .nextTime)
    }
}

struct AppData: Codable, Equatable {
    var version = 1
    var nights: [Night] = []
    var customFactors = FactorList.defaults
    var settings = Settings()
    var reviewAsked = false
    var milestones: Set<String> = []
    var entitlement = Entitlement()
    var expiryNoticeShown = false
    init() {}
    enum CodingKeys: String, CodingKey { case version, nights, customFactors, settings, reviewAsked, milestones, entitlement, expiryNoticeShown }
    init(from decoder: Decoder) throws {
        self.init(); let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard version == 1 else { throw StoreError.unsupportedVersion }
        nights = try c.decodeIfPresent([Night].self, forKey: .nights) ?? []
        customFactors = try c.decodeIfPresent([String].self, forKey: .customFactors) ?? FactorList.defaults
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
        reviewAsked = try c.decodeIfPresent(Bool.self, forKey: .reviewAsked) ?? false
        milestones = try c.decodeIfPresent(Set<String>.self, forKey: .milestones) ?? []
        entitlement = try c.decodeIfPresent(Entitlement.self, forKey: .entitlement) ?? Entitlement()
        expiryNoticeShown = try c.decodeIfPresent(Bool.self, forKey: .expiryNoticeShown) ?? false
    }
    mutating func upsert(_ night: Night) {
        nights.removeAll { $0.id == night.id }; nights.append(night); nights.sort { $0.startedAt > $1.startedAt }
    }
}
