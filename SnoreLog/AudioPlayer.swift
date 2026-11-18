import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var clipID: UUID?
    @Published private(set) var isPlaying = false
    private var player: AVAudioPlayer?
    private var remaining: [AudioSegment] = []
    private var store: Store?

    func play(_ clip: Clip, night: Night, store: Store, toggle: Bool = true) throws {
        if toggle, clipID == clip.id, isPlaying { stop(); return }
        stop()
        try load(store.clipURL(nightID: night.id, fileName: clip.fileName))
        clipID = clip.id
    }

    func play(from offset: Double, segments: [AudioSegment], store: Store) throws {
        stop()
        let sorted = segments.sorted { $0.startOffset < $1.startOffset }
        guard let index = sorted.firstIndex(where: { $0.startOffset + $0.duration > offset }) else {
            throw RecordingError.noInput
        }
        let segment = sorted[index]
        try load(store.fullURL(segment.fileName), offset: max(0, offset - segment.startOffset))
        self.store = store
        remaining = Array(sorted.dropFirst(index + 1))
    }

    private func load(_ url: URL, offset: Double = 0) throws {
        let audio = try AVAudioPlayer(contentsOf: url)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        audio.delegate = self
        audio.currentTime = min(offset, max(0, audio.duration - 0.01))
        guard audio.play() else {
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            throw RecordingError.noInput
        }
        player = audio
        isPlaying = true
    }

    func stop() {
        let wasPlaying = player != nil
        player?.stop()
        player = nil
        store = nil
        remaining.removeAll()
        clipID = nil
        isPlaying = false
        if wasPlaying { try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation]) }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard player === self.player else { return }
            if flag, let store = self.store, let next = self.remaining.first {
                self.remaining.removeFirst()
                do { try self.load(store.fullURL(next.fileName)); return } catch {}
            }
            self.stop()
        }
    }
}
