import AVFoundation
import Foundation

final class RecordingAudio {
    private struct Block {
        let start: Double
        let samples: [Float]
    }

    private let store: Store
    private let keepsFullAudio: Bool
    private let keepsTalk: Bool
    private var night: Night
    private var detector = SnoreDetector()
    private var format: AVAudioFormat?
    private var streamID: UUID?
    private var offset = 0.0
    private var pcm: [Block] = []
    private var segment: AVAudioFile?
    private var segmentName = ""
    private var segmentStart = 0.0
    private var segmentLength = 0.0
    private var gapStart: Double?
    private var gaps: [Range<Double>] = []
    private var analyticSamples: [Float] = []
    private var analyticStart = 0.0
    private var filtered: Float = 0
    private var phase = 0.0
    private var unsavedClipFiles: Set<String> = []
    private(set) var didFailToWriteAudio = false

    init(night: Night, store: Store, keepsFullAudio: Bool, keepsTalk: Bool) {
        self.night = night
        self.store = store
        self.keepsFullAudio = keepsFullAudio
        self.keepsTalk = keepsTalk
    }

    var snoreCount: Int { detector.confirmed.count }

    func begin(id: UUID, sampleRate: Double, at date: Date) throws {
        guard let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw RecordingError.noInput
        }
        format = mono
        let start = max(offset, date.timeIntervalSince(night.startedAt))
        if let gapStart, start > gapStart { gaps.append(gapStart..<start) }
        gapStart = nil
        offset = max(0, start)
        analyticStart = offset
        analyticSamples.removeAll(keepingCapacity: true)
        pcm.removeAll(keepingCapacity: true)
        filtered = 0
        phase = 0
        streamID = id
    }

    func append(_ samples: [Float], stream id: UUID) {
        guard streamID == id, let format, !samples.isEmpty else { return }
        let length = Double(samples.count) / format.sampleRate
        pcm.append(Block(start: offset, samples: samples))
        pcm.removeAll { $0.start < offset - 48 }

        if keepsFullAudio {
            do {
                if segment == nil {
                    segmentName = night.id.uuidString + "-" + UUID().uuidString + ".m4a"
                    segmentStart = offset
                    segment = try audioFile(store.fullURL(segmentName), format: format)
                }
                if let segment {
                    try write(samples[...], to: segment, format: format)
                    segmentLength += length
                }
            } catch {
                didFailToWriteAudio = true
                closeSegment()
            }
        }

        let filterWeight = Float(1 - exp(-2 * Double.pi * 1_700 / format.sampleRate))
        for sample in samples {
            filtered += filterWeight * (sample - filtered)
            phase += SpectralFeatures.sampleRate
            if phase >= format.sampleRate {
                analyticSamples.append(filtered)
                phase -= format.sampleRate
            }
        }

        offset += length
        night.recordedSeconds += length
        let window = Int(detector.config.windowDuration * SpectralFeatures.sampleRate)
        let hop = window / 2
        while analyticSamples.count >= window {
            let observation = SpectralFeatures.observation(analyticSamples.prefix(window), at: analyticStart)
            apply(detector.consume(observation))
            analyticSamples.removeFirst(hop)
            analyticStart += Double(hop) / SpectralFeatures.sampleRate
        }
    }

    func pause(at date: Date, ending: Bool = false) {
        guard streamID != nil else { return }
        streamID = nil
        apply(detector.flush(at: offset))
        detector.breakRhythm()
        closeSegment()
        if !ending { gapStart = min(offset, max(0, date.timeIntervalSince(night.startedAt))) }
    }

    func snapshot(at date: Date, end: EndReason? = nil) -> Night {
        closeSegment()
        let elapsed = max(offset, date.timeIntervalSince(night.startedAt))
        let allGaps = gaps + (gapStart.map { $0 < elapsed ? [$0..<elapsed] : [] } ?? [])
        night.minutes = detector.minutes(duration: elapsed)
        for gap in allGaps {
            let first = max(0, Int(gap.lowerBound / 60))
            let last = max(first, Int(max(0, gap.upperBound - 0.001) / 60))
            for index in first...last where night.minutes.indices.contains(index) {
                night.minutes[index].interrupted = true
            }
        }
        night.snoreSeconds = min(night.recordedSeconds, detector.snoreSeconds)
        night.interruptedSeconds = allGaps.reduce(0) { $0 + $1.upperBound - $1.lowerBound }
        night.checkpointAt = night.startedAt.addingTimeInterval(elapsed)
        if let end { night.finish(at: night.checkpointAt ?? date, reason: end) }
        return night
    }

    func discardSupersededClips(committed: Night) {
        let referenced = Set((night.clips + night.talkClips + committed.clips + committed.talkClips).map(\.fileName))
        for file in unsavedClipFiles.subtracting(referenced) {
            try? FileManager.default.removeItem(at: store.clipURL(nightID: night.id, fileName: file))
        }
        unsavedClipFiles = referenced
    }

    private func closeSegment() {
        segment = nil
        if segmentLength > 0 {
            night.audioSegments.append(AudioSegment(fileName: segmentName, startOffset: segmentStart, duration: segmentLength))
        }
        segmentLength = 0
    }

    private func apply(_ events: [DetectionEvent]) {
        for event in events {
            if event.kind == .talk && !keepsTalk { continue }
            if event.kind == .external {
                night.clips.removeAll { $0.startOffset < event.end && $0.startOffset + $0.duration > event.start }
                night.talkClips.removeAll { $0.startOffset < event.end && $0.startOffset + $0.duration > event.start }
                continue
            }
            let clips = event.kind == .snore ? night.clips : night.talkClips
            let limit = event.kind == .snore ? detector.config.snoreClipLimit : detector.config.talkClipLimit
            if clips.count >= limit && event.peakDb <= (clips.last?.peakDb ?? -160) { continue }
            do {
                guard let clip = try makeClip(event) else { continue }
                let removed: [Clip]
                if event.kind == .snore {
                    removed = ClipSelection.insert(clip, into: &night.clips, limit: limit)
                } else {
                    removed = ClipSelection.insert(clip, into: &night.talkClips, limit: limit)
                }
                unsavedClipFiles.insert(clip.fileName)
                unsavedClipFiles.formUnion(removed.map(\.fileName))
            } catch {
                didFailToWriteAudio = true
            }
        }
    }

    private func makeClip(_ event: DetectionEvent) throws -> Clip? {
        guard let format else { return nil }
        let start = max(event.start, pcm.first?.start ?? event.start)
        let end = min(offset, event.end)
        let loudest = pcm.filter { $0.start >= start && $0.start < end }
            .max { energy($0.samples) < energy($1.samples) }
        let clipStart = end - start > detector.config.clipDuration
            ? max(start, min(end - detector.config.clipDuration, (loudest?.start ?? start) - 10))
            : start
        let clipEnd = min(end, clipStart + detector.config.clipDuration)
        guard clipEnd > clipStart else { return nil }

        let name = UUID().uuidString + ".m4a"
        let url = store.clipURL(nightID: night.id, fileName: name)
        let file = try audioFile(url, format: format)
        do {
            for block in pcm {
                let first = max(0, Int((clipStart - block.start) * format.sampleRate))
                let last = min(block.samples.count, Int((clipEnd - block.start) * format.sampleRate))
                if first < last { try write(block.samples[first..<last], to: file, format: format) }
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return Clip(startOffset: clipStart, duration: clipEnd - clipStart,
                    peakDb: event.peakDb, level: event.level, fileName: name)
    }

    private func energy(_ samples: [Float]) -> Float {
        samples.reduce(0) { $0 + $1 * $1 } / Float(max(1, samples.count))
    }

    private func audioFile(_ url: URL, format: AVAudioFormat) throws -> AVAudioFile {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32_000
        ]
        return try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    private func write(_ samples: ArraySlice<Float>, to file: AVAudioFile, format: AVAudioFormat) throws {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData else { throw RecordingError.noInput }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        _ = samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel[0].update(from: base, count: samples.count) }
        }
        try file.write(from: buffer)
    }
}
