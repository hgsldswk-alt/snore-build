import Foundation

struct DetectionConfig {
    var noiseWindow: Double = 120
    var noisePercentile: Double = 0.2
    var minimumAboveNoise: Double = 6
    var snoringConfidence: Double = 0.5
    var breathingConfidence: Double = 0.6
    var breathingAboveNoise: Double = 12
    var speechConfidence: Double = 0.6
    var externalConfidence: Double = 0.5
    var externalDuration: Double = 30
    var rhythmWindow: Double = 60
    var minimumCandidates = 3
    var minimumInterval: Double = 2.5
    var maximumInterval: Double = 8
    var mediumAboveNoise: Double = 12
    var loudAboveNoise: Double = 20
    var windowDuration: Double = 1.5
    var clipDuration: Double = 20
    var snoreClipLimit = 30
    var talkClipLimit = 10
}
struct Observation {
    var time: Double
    var rmsDb: Double
    var snoring: Double = 0
    var breathing: Double = 0
    var speech: Double = 0
    var music: Double = 0
    var tv: Double = 0
}
struct DetectionEvent: Equatable {
    enum Kind { case snore, talk, external }
    var kind: Kind
    var start: Double
    var end: Double
    var peakDb: Double
    var level: Int
}

struct SnoreDetector {
    var config = DetectionConfig()
    private(set) var noiseFloor: Double = -60
    private var noise: [(Double, Double)] = []
    private var candidates: [DetectionEvent] = []
    private(set) var confirmed: [DetectionEvent] = []
    private(set) var talks: [DetectionEvent] = []
    private var externalStart: Double?
    private var externalLast: Double = 0
    private var externalPeak: Double = -160
    private var speechStart: Double?
    private var speechPeak: Double = -160
    private var externalActive = false
    private var wasCandidate = false
    private var lastTime: Double = -1

    mutating func consume(_ o: Observation) -> [DetectionEvent] {
        guard o.time.isFinite, o.rmsDb.isFinite, o.time > lastTime else { return [] }
        lastTime = o.time
        noise.append((o.time, o.rmsDb)); noise.removeAll { o.time - $0.0 > config.noiseWindow }
        let sorted = noise.map { $0.1 }.sorted()
        noiseFloor = sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * config.noisePercentile))]
        var output: [DetectionEvent] = []
        let above = o.rmsDb - noiseFloor
        let external = max(o.music, max(o.tv, o.speech)) >= config.externalConfidence
        if external {
            if externalStart == nil { externalStart = o.time; externalPeak = o.rmsDb }
            externalLast = o.time + config.windowDuration; externalPeak = max(externalPeak, o.rmsDb)
            if o.speech >= config.speechConfidence && above >= config.minimumAboveNoise {
                if speechStart == nil { speechStart = o.time }; speechPeak = max(speechPeak, o.rmsDb)
            }
            if let start = externalStart, o.time - start > config.externalDuration {
                externalActive = true
                confirmed.removeAll { $0.end > start }; candidates.removeAll { $0.end > start }
                talks.removeAll { $0.end > start }
                output.append(DetectionEvent(kind: .external, start: start, end: externalLast, peakDb: externalPeak, level: 0))
            }
        } else if let start = externalStart {
            if !externalActive, let talkStart = speechStart, externalLast - start <= config.externalDuration + config.windowDuration {
                let talk = DetectionEvent(kind: .talk, start: talkStart, end: externalLast, peakDb: speechPeak, level: 1)
                talks.append(talk); output.append(talk)
            }
            externalStart = nil; speechStart = nil; speechPeak = -160; externalActive = false
        }
        let candidate = above >= config.minimumAboveNoise && !externalActive &&
            (o.snoring >= config.snoringConfidence || (o.breathing >= config.breathingConfidence && above >= config.breathingAboveNoise))
        defer { wasCandidate = candidate }
        guard candidate else { return output }
        guard !wasCandidate else { return output }
        let level = above < config.mediumAboveNoise ? 1 : (above <= config.loudAboveNoise ? 2 : 3)
        let event = DetectionEvent(kind: .snore, start: o.time, end: o.time + config.windowDuration, peakDb: o.rmsDb, level: level)
        candidates.removeAll { o.time - $0.start > config.rhythmWindow }
        if let last = candidates.last {
            let gap = o.time - last.start
            if gap < config.minimumInterval { return output }
            if gap > config.maximumInterval { candidates.removeAll() }
        }
        candidates.append(event)
        if candidates.count >= config.minimumCandidates {
            for item in candidates where !confirmed.contains(where: { $0.start == item.start }) {
                confirmed.append(item); output.append(item)
            }
        }
        return output
    }
    mutating func flush(at time: Double) -> [DetectionEvent] {
        consume(Observation(time: max(lastTime + 0.001, time), rmsDb: noiseFloor))
    }
    mutating func breakRhythm() {
        candidates.removeAll()
        wasCandidate = false
    }
    func minutes(duration: Double) -> [MinuteBin] {
        var bins = Array(repeating: MinuteBin(), count: max(0, Int(ceil(duration / 60))))
        for event in confirmed {
            let first = max(0, Int(event.start / 60)); let last = max(first, Int((event.end - 0.001) / 60))
            for i in first...last where bins.indices.contains(i) { bins[i].level = max(bins[i].level, event.level) }
        }
        return bins
    }
    var snoreSeconds: Double {
        var end: Double = 0; var sum: Double = 0
        for event in confirmed.sorted(by: { $0.start < $1.start }) {
            sum += max(0, event.end - max(end, event.start)); end = max(end, event.end)
        }
        return sum
    }
}
