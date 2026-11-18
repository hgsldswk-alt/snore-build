import Foundation
import XCTest

final class DetectionTests: XCTestCase {
    func testConstantNoiseAndAnIsolatedBurstStayUnscored() {
        var detector = SnoreDetector()
        for step in 0..<2_400 {
            let volume = step == 700 ? -25.0 : -47.0
            _ = detector.consume(Observation(time: Double(step) * 0.75, rmsDb: volume, snoring: 0.8))
        }
        XCTAssertTrue(detector.confirmed.isEmpty)
        XCTAssertEqual(detector.noiseFloor, -47)
    }

    func testRhythmicBurstsRespectIntensityAndIncludeFirstTwoOnsets() {
        var detector = SnoreDetector()
        let levels = [12: -53.0, 17: -45.0, 22: -32.0, 27: -42.0]
        for step in 0...33 {
            let aboveNoise = levels[step]
            _ = detector.consume(Observation(time: Double(step) * 0.75, rmsDb: aboveNoise ?? -60,
                snoring: aboveNoise == nil ? 0 : 0.8))
        }
        XCTAssertEqual(detector.confirmed.map(\.level), [1, 2, 3, 2])
        XCTAssertEqual(detector.snoreSeconds, 6, accuracy: 0.01)
        XCTAssertEqual(detector.minutes(duration: 25), [MinuteBin(level: 3)])
    }

    func testOngoingSpeechRevokesEventsButShortSpeechProducesClip() {
        var detector = SnoreDetector()
        for step in 0...12 {
            _ = detector.consume(Observation(time: Double(step) * 0.75, rmsDb: -61))
        }
        for step in 13..<23 {
            _ = detector.consume(Observation(time: Double(step) * 0.75, rmsDb: -32, speech: 0.8))
        }
        _ = detector.consume(Observation(time: 17.25, rmsDb: -61))
        XCTAssertEqual(detector.talks.count, 1)
        for step in 24..<424 {
            let burst = step % 5 == 0
            _ = detector.consume(Observation(time: Double(step) * 0.75, rmsDb: -30,
                snoring: burst ? 0.8 : 0, speech: 0.8))
        }
        _ = detector.flush(at: 320)
        XCTAssertTrue(detector.confirmed.isEmpty)
        XCTAssertEqual(detector.talks.count, 1)
    }

    func testWeakBreathingAndNoiseDrift() {
        var detector = SnoreDetector()
        for step in 0...800 {
            let noise = min(-45, -65 + Double(step) / 30)
            let burst = step % 5 == 0
            _ = detector.consume(Observation(time: Double(step) * 0.75, rmsDb: noise + (burst ? 8 : 0),
                breathing: burst ? 0.7 : 0))
        }
        XCTAssertTrue(detector.confirmed.isEmpty)
        XCTAssertEqual(detector.noiseFloor, -45, accuracy: 0.1)
    }

    func testRulesRecognizeLowFrequencyBurstsInPCM() {
        var detector = SnoreDetector()
        let count = Int(SpectralFeatures.sampleRate * 1.5)
        let quiet = Array(repeating: Float(0.0003), count: count)
        let burst: [Float] = (0..<count).map { index in
            let seconds = Double(index) / SpectralFeatures.sampleRate
            return Float(0.12 * sin(2 * .pi * 110 * seconds) * pow(sin(.pi * seconds / 1.5), 2))
        }
        XCTAssertGreaterThan(SpectralFeatures.observation(burst[...], at: 0).snoring, 0.5)
        for index in 0...24 {
            let pcm = [8, 13, 18].contains(index) ? burst : quiet
            _ = detector.consume(SpectralFeatures.observation(pcm[...], at: Double(index) * 0.75))
        }
        XCTAssertEqual(detector.confirmed.count, 3)
        detector.breakRhythm()
        _ = detector.consume(SpectralFeatures.observation(burst[...], at: 21))
        XCTAssertEqual(detector.confirmed.count, 3)
    }
}

final class NightLogicTests: XCTestCase {
    func testShortNightAndScoringWithGapsAndExclusions() {
        var night = Night()
        night.minutes = Array(repeating: MinuteBin(level: 3), count: 30)
        night.recordedSeconds = 60
        XCTAssertNil(night.score)
        night.recordedSeconds = 1_800
        XCTAssertEqual(night.score, 100)
        night.minutes[0] = MinuteBin(interrupted: true)
        XCTAssertEqual(night.score, 100)
        night.clips = [Clip(startOffset: 60, duration: 20, peakDb: -15, level: 3, fileName: "short.m4a", notMe: true)]
        night.snoreSeconds = 20
        XCTAssertEqual(night.adjustedSnoreSeconds, 0)
        XCTAssertEqual(night.score, 97)
        night.clips[0].notMe = false
        XCTAssertEqual(night.score, 100)
        night.minutes = Array(repeating: MinuteBin(), count: 30)
        XCTAssertEqual(night.score, 0)
    }

    func testClipSelectionKeepsTheLoudest() {
        var clips: [Clip] = []
        for index in 0..<40 {
            let clip = Clip(startOffset: Double(index), duration: 1, peakDb: Double(index) - 60, level: 1, fileName: "\(index).m4a")
            _ = ClipSelection.insert(clip, into: &clips, limit: 30)
        }
        XCTAssertEqual(clips.count, 30)
        XCTAssertEqual(clips.first?.peakDb, -21)
        XCTAssertEqual(clips.last?.peakDb, -50)
    }

    func testRecoverCheckpointAcrossMidnightAndDecodeOldRecords() throws {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        var night = Night(startedAt: startOfDay.addingTimeInterval(-3_600))
        night.inProgress = true
        let checkpoint = startOfDay.addingTimeInterval(300)
        night.checkpointAt = checkpoint
        var data = AppData()
        data.upsert(night)
        XCTAssertEqual(Recovery.finish(&data), [night.id])
        XCTAssertEqual(data.nights[0].endedAt, checkpoint)
        XCTAssertEqual(data.nights[0].dayKey, DayKey.make(checkpoint))
        XCTAssertEqual(data.nights[0].endReason, .recovered)
        XCTAssertTrue(Recovery.finish(&data).isEmpty)
        let legacy = try JSONDecoder().decode(Night.self, from: Data(#"{"recordedSeconds":1200,"fullAudioFile":"night.m4a"}"#.utf8))
        XCTAssertEqual(legacy.fullSegments.first?.fileName, "night.m4a")
        XCTAssertEqual(legacy.fullSegments.first?.duration, 1200)
        XCTAssertTrue(legacy.excludedClips.isEmpty)
    }

    func testComparisonRequiresThreeScoredNightsPerGroup() throws {
        let nights = (0..<6).map { index -> Night in
            var night = Night(startedAt: Date().addingTimeInterval(Double(-index) * 86_400))
            night.recordedSeconds = 1_800
            night.minutes = Array(repeating: MinuteBin(level: index < 3 ? 1 : 2), count: 30)
            if index < 3 { night.factors = ["side"] }
            return night
        }
        XCTAssertNil(FactorStats.comparison("side", nights: Array(nights.prefix(5))))
        let result = try XCTUnwrap(FactorStats.comparison("side", nights: nights))
        XCTAssertEqual(result.withCount, 3)
        XCTAssertEqual(result.withoutCount, 3)
        XCTAssertEqual(result.difference, -30)
    }

    func testTrialUsesPaidStartAndRestorationCannotExtendIt() {
        let firstOpen = Date(timeIntervalSince1970: 1_800_000_000)
        let paid = firstOpen.addingTimeInterval(100 * 86_400)
        var entitlement = Entitlement(firstOpen: firstOpen, proStartedAt: paid)
        XCTAssertFalse(Launch.freePeriod)
        XCTAssertTrue(entitlement.hasPro(at: paid))
        XCTAssertTrue(entitlement.hasPro(at: paid.addingTimeInterval(-30)))
        XCTAssertFalse(entitlement.hasPro(at: paid.addingTimeInterval(-601)))
        let trialEnd = paid.addingTimeInterval(30 * 86_400)
        XCTAssertFalse(entitlement.hasPro(at: trialEnd))
        entitlement.trialClaimedAt = paid.addingTimeInterval(3_600)
        XCTAssertEqual(entitlement.trialEnd, trialEnd)
        entitlement.trialClaimedAt = paid.addingTimeInterval(-86_400)
        XCTAssertEqual(entitlement.trialEnd, trialEnd.addingTimeInterval(-86_400))
        entitlement.purchasedPro = true
        XCTAssertTrue(entitlement.hasPro(at: trialEnd.addingTimeInterval(1)))
    }

    func testCleanFullAudioPreservesClipsAndExportWorks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Store(root: root)
        let now = Date()
        var night = Night(startedAt: now.addingTimeInterval(-16 * 86_400))
        night.finish(at: night.startedAt.addingTimeInterval(1_800), reason: .normal)
        night.audioSegments = [.init(fileName: "segment.m4a", startOffset: 60, duration: 200)]
        let clip = Clip(startOffset: 12, duration: 2, peakDb: -30, level: 1, fileName: "clip.m4a")
        night.clips = [clip]
        let files = [store.fullURL("segment.m4a"), store.clipURL(nightID: night.id, fileName: clip.fileName)]
        for file in files {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0x12, 0x34]).write(to: file)
        }
        var data = AppData()
        data.upsert(night)
        try store.save(data)
        data = try store.load()
        try store.cleanFull(&data, now: now)
        XCTAssertTrue(data.nights[0].fullSegments.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: files[0].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: files[1].path))
        let output = try Export.make(data, store: store)
        defer { try? FileManager.default.removeItem(at: output[0].deletingLastPathComponent()) }
        XCTAssertTrue(try String(contentsOf: output[0], encoding: .utf8).contains(night.dayKey))
        let zip = try Data(contentsOf: output[1])
        XCTAssertEqual(Array(zip.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
        XCTAssertTrue(zip.range(of: Data("clip.m4a".utf8)) != nil)
    }

    func testFactorListRoundTrip() throws {
        let text = try FactorList.encode(["Side", " Side ", "", "Hard workout"])
        XCTAssertEqual(try FactorList.decode(text), ["Side", "Hard workout"])
        XCTAssertThrowsError(try FactorList.decode("Invalid copy"))
    }

    func testStreakCountsUniqueDaysNotSessions() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.startOfDay(for: Date())
        var nights: [Night] = []
        for offset in [0, 0, -1, -2, -4] {
            let start = try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: day))
            var night = Night(startedAt: start)
            night.recordedSeconds = 1_800
            night.finish(at: start.addingTimeInterval(1_800), reason: .normal)
            nights.append(night)
        }
        XCTAssertEqual(NightInsights.streak(on: nights[0], nights: nights, calendar: calendar), 3)
    }
}
