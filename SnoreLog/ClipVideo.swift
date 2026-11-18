import AVFoundation
import CoreGraphics
import CoreText
import CoreVideo
import Foundation

enum ClipVideo {
    private static let width = 720
    private static let height = 900
    private static let timescale: Int32 = 12

    static func make(from source: URL, brand: String) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        guard duration.seconds.isFinite, duration.seconds > 0, duration.seconds <= 25,
              let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw RecordingError.noInput
        }
        let envelope = try waveform(source)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SnoreLog-video-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let video = directory.appendingPathComponent("picture.mp4")
        let output = directory.appendingPathComponent("Snore-Log.mp4")
        do {
            try await writePicture(to: video, duration: duration, envelope: envelope, brand: brand)
            let picture = AVURLAsset(url: video)
            guard let videoTrack = try await picture.loadTracks(withMediaType: .video).first else {
                throw RecordingError.noInput
            }
            let composition = AVMutableComposition()
            let length = CMTimeMinimum(duration, try await picture.load(.duration))
            let range = CMTimeRange(start: .zero, duration: length)
            guard let sound = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
                  let canvas = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw RecordingError.noInput
            }
            try sound.insertTimeRange(range, of: audioTrack, at: .zero)
            try canvas.insertTimeRange(range, of: videoTrack, at: .zero)
            guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
                throw RecordingError.noInput
            }
            export.outputURL = output
            export.outputFileType = .mp4
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                export.exportAsynchronously { continuation.resume() }
            }
            guard export.status == .completed else { throw export.error ?? RecordingError.noInput }
            try? FileManager.default.removeItem(at: video)
            return output
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func waveform(_ source: URL) throws -> [CGFloat] {
        let file = try AVAudioFile(forReading: source, commonFormat: .pcmFormatFloat32, interleaved: false)
        let count = 72
        let step = max(1, Int(file.length) / count)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(step)) else {
            throw RecordingError.noInput
        }
        var values: [CGFloat] = []
        for _ in 0..<count {
            try file.read(into: buffer, frameCount: AVAudioFrameCount(step))
            guard buffer.frameLength > 0, let samples = buffer.floatChannelData?[0] else { break }
            let section = UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength))
            let rms = sqrt(section.reduce(0) { $0 + $1 * $1 } / Float(section.count))
            values.append(CGFloat(rms))
        }
        let peak = max(values.max() ?? 0, 0.0001)
        return values.map { min(1, $0 / peak) }
    }

    private static func writePicture(to url: URL, duration: CMTime, envelope: [CGFloat], brand: String) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ])
        guard writer.canAdd(input) else { throw RecordingError.noInput }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? RecordingError.noInput }
        writer.startSession(atSourceTime: .zero)
        do {
            guard let pool = adaptor.pixelBufferPool else { throw RecordingError.noInput }
            var pixel: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixel)
            guard status == kCVReturnSuccess, let pixel else { throw RecordingError.noInput }
            try draw(pixel, envelope: envelope, brand: brand)

            let frames = max(1, Int(ceil(duration.seconds * Double(timescale))))
            let deadline = Date().addingTimeInterval(12)
            for frame in 0..<frames {
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing, Date() < deadline else { throw writer.error ?? RecordingError.noInput }
                    try await Task.sleep(for: .milliseconds(12))
                }
                let time = CMTime(value: Int64(frame), timescale: timescale)
                guard adaptor.append(pixel, withPresentationTime: time) else { throw writer.error ?? RecordingError.noInput }
            }
            writer.endSession(atSourceTime: duration)
            input.markAsFinished()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                writer.finishWriting { continuation.resume() }
            }
            guard writer.status == .completed else { throw writer.error ?? RecordingError.noInput }
        } catch {
            if writer.status == .writing { writer.cancelWriting() }
            throw error
        }
    }

    private static func draw(_ pixel: CVPixelBuffer, envelope: [CGFloat], brand: String) throws {
        CVPixelBufferLockBaseAddress(pixel, [])
        defer { CVPixelBufferUnlockBaseAddress(pixel, []) }
        let format = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel),
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: format) else {
            throw RecordingError.noInput
        }
        context.setFillColor(CGColor(red: 13 / 255, green: 17 / 255, blue: 23 / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.setStrokeColor(CGColor(red: 227 / 255, green: 178 / 255, blue: 106 / 255, alpha: 1))
        context.setLineWidth(5)
        context.setLineCap(.round)
        for (index, level) in envelope.enumerated() {
            let x = 65 + 590 * CGFloat(index) / CGFloat(max(1, envelope.count - 1))
            let half = 3 + 128 * level
            context.move(to: CGPoint(x: x, y: 450 - half))
            context.addLine(to: CGPoint(x: x, y: 450 + half))
        }
        context.strokePath()
        let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, 27, nil)
        let string = NSAttributedString(string: brand, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.88, alpha: 1)
        ])
        let line = CTLineCreateWithAttributedString(string)
        let textWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
        context.textPosition = CGPoint(x: 664 - CGFloat(textWidth), y: 64)
        CTLineDraw(line, context)
    }
}
