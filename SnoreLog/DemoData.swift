import AVFoundation
import Foundation

enum DemoData {
    static func lastNight(daysAgo: Int = 0) -> Night {
        let end = Calendar.current.date(byAdding: .day, value: -daysAgo,
            to: Calendar.current.startOfDay(for: Date())) ?? Date()
        var night = Night(startedAt: end.addingTimeInterval(-12 * 60))
        night.finish(at: end.addingTimeInterval(7.5 * 3_600), reason: .normal)
        night.recordedSeconds = 27_720
        night.snoreSeconds = 2_763
        night.minutes = (0..<462).map { minute in
            let bands = [95..<111, 129..<145, 199..<219, 266..<283, 314..<327, 381..<389]
            return MinuteBin(level: bands.contains { $0.contains(minute) } ? (minute % 4 == 0 ? 2 : 3) : 0)
        }
        let offsets = [204, 128, 315, 106, 138, 211, 218, 271, 278, 325, 382, 390]
        night.clips = offsets.enumerated().map { index, minute in
            Clip(startOffset: Double(minute * 60 + (index == 0 ? 50 : 10)), duration: 20 - Double(index % 4) * 3,
                 peakDb: -17 - Double(index), level: index == 0 ? 3 : 2, fileName: "snore-\(index).m4a", notMe: index == 2)
        }
        night.talkClips = [155, 349].enumerated().map { index, minute in
            Clip(startOffset: Double(minute * 60), duration: 4, peakDb: -24, level: 1, fileName: "talk-\(index).m4a")
        }
        night.factors = ["侧睡", "止鼾贴/鼻贴"]
        night.notMeCount = night.exclusions.count
        if daysAgo > 0 {
            let isQuiet = daysAgo % 3 == 0
            let length = (isQuiet ? 22 : 33) + (daysAgo * 7 % 16)
            night.minutes = (0..<462).map { MinuteBin(level: $0 % 100 < length ? 2 : 0) }
            night.snoreSeconds = Double(length * 85)
            night.factors = []
            if isQuiet { night.factors.insert("侧睡") }
            if daysAgo % 4 == 0 { night.factors.insert("止鼾贴/鼻贴") }
            if daysAgo % 4 == 1 { night.factors.insert("喝酒") }
            night.clips = []
            night.talkClips = []
            night.notMeCount = 0
        }
        return night
    }

    static func seed(_ data: inout AppData, store: Store) {
        var night = lastNight()
        if Launch.has("-recovered") {
            night.endReason = .recovered
            night.interruptedSeconds = 540
            for index in 299..<308 { night.minutes[index].interrupted = true }
        }
        data.nights = [night] + (1...18).map { lastNight(daysAgo: $0) }
        writeClips(night, to: store)
    }

    static func writeClips(_ night: Night, to store: Store) {
        let rate = 16_000.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
        for clip in night.clips + night.talkClips {
            let url = store.clipURL(nightID: night.id, fileName: clip.fileName)
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            let frames = AVAudioFrameCount(clip.duration * rate)
            guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                  let samples = pcm.floatChannelData?[0] else { continue }
            pcm.frameLength = frames
            for index in 0..<Int(frames) {
                let time = Double(index) / rate
                let wave = sin(time * 2 * .pi * 112) + 0.34 * sin(time * 2 * .pi * 224)
                let envelope = pow(max(0, sin(time / 4 * 2 * .pi)), 3)
                samples[index] = Float(0.18 * wave * envelope)
            }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32_000]
            if let file = try? AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false) {
                try? file.write(from: pcm)
            }
        }
    }
}
