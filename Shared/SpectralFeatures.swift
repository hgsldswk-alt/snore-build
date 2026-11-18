import Foundation

enum SpectralFeatures {
    static let sampleRate = 4_000.0
    private static let bands: [[Double]] = [
        [75, 110, 155, 210], [280, 380, 510, 680], [850, 1_080, 1_360, 1_700]
    ]
    private static let coefficients = bands.map { band in
        band.map { 2 * cos(2 * Double.pi * $0 / sampleRate) }
    }

    static func observation(_ samples: ArraySlice<Float>, at time: Double) -> Observation {
        guard !samples.isEmpty else { return Observation(time: time, rmsDb: -120) }
        let energy = samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count)
        let db = 10 * log10(max(1e-12, energy))
        var totals = [0.0, 0.0, 0.0]
        var frameEnergy: [Double] = []
        let frameSize = 256
        for start in stride(from: samples.startIndex, through: samples.endIndex - frameSize, by: frameSize) {
            let frame = samples[start..<(start + frameSize)]
            frameEnergy.append(frame.reduce(0.0) { $0 + Double($1 * $1) })
            for (index, band) in coefficients.enumerated() {
                for coefficient in band {
                    var previous = 0.0
                    var older = 0.0
                    for sample in frame {
                        let state = Double(sample) + coefficient * previous - older
                        older = previous
                        previous = state
                    }
                    totals[index] += max(0, previous * previous + older * older - coefficient * previous * older)
                }
            }
        }
        let sum = max(1e-12, totals.reduce(0, +))
        let low = totals[0] / sum
        let mid = totals[1] / sum
        let high = totals[2] / sum
        let activeFrames = frameEnergy.filter { $0 >= energy * Double(frameSize) * 0.16 }.count
        let activeRatio = Double(activeFrames) / Double(max(1, frameEnergy.count))
        let audible = db > -64
        let voicelike = audible && mid + high > 0.47 && mid > 0.15 && activeRatio > 0.30
        let lowBurst = audible && low > 0.60 && high < 0.19 && activeRatio > 0.19
        let breathlike = audible && low > 0.37 && high > 0.20 && mid < 0.32 && activeRatio > 0.22
        return Observation(time: time, rmsDb: db, snoring: lowBurst ? 0.8 : 0,
            breathing: breathlike ? 0.7 : 0, speech: voicelike ? 0.7 : 0)
    }
}
