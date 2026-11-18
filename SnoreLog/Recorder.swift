import ActivityKit
import AVFoundation
import Foundation

enum RecordingError: Error { case noInput }
enum StartResult { case started, denied }

@MainActor
final class Recorder {
    var onCheckpoint: ((Night) -> Bool)?
    var onFinish: ((Night, Bool) -> Bool)?
    var onCount: ((Int) -> Void)?
    var startedAt: Date?
    private var processor: RecordingAudio?
    private var fakeNight: Night?
    var demoNight: Night? { fakeNight }
    private let queue = DispatchQueue(label: "com.hgsldswk.snore.recording", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var heartbeat: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var checkpointAt: Date?
    private var autoEndAt: Date?
    private var systemInterrupted = false
    private var lastResumeAttempt = Date.distantPast
    private var activity: Activity<SnoreActivityAttributes>?

    func start(store: Store, keepsFullAudio: Bool, keepsTalk: Bool, settings: Settings) async throws -> StartResult {
        if Launch.has("-mic-denied") { return .denied }
        if Launch.fakeAudio {
            startDemo()
            return .started
        }
        guard await AVAudioApplication.requestRecordPermission() else { return .denied }
        try store.prepare()
        var night = Night()
        night.inProgress = true
        night.checkpointAt = night.startedAt
        processor = RecordingAudio(night: night, store: store, keepsFullAudio: keepsFullAudio, keepsTalk: keepsTalk)
        do {
            try connect()
            guard onCheckpoint?(night) == true else { throw RecordingError.noInput }
        } catch {
            disconnect()
            deactivateSession()
            processor = nil
            throw error
        }
        startedAt = night.startedAt
        autoEndAt = settings.nextAutoEnd(after: night.startedAt)
        checkpointAt = night.startedAt
        observeSession()
        startActivity(night)
        startHeartbeat()
        return .started
    }

    func startDemo(night: Night = DemoData.lastNight()) {
        fakeNight = night
        startedAt = Date().addingTimeInterval(-11_560)
        onCount?(12)
    }

    func checkpoint() {
        guard let processor, startedAt != nil else { return }
        let night = queue.sync { processor.snapshot(at: Date()) }
        if onCheckpoint?(night) == true {
            checkpointAt = Date()
            queue.async { processor.discardSupersededClips(committed: night) }
        } else {
            checkpointAt = Date().addingTimeInterval(-270)
        }
    }

    func stop(reason: EndReason = .normal) {
        guard startedAt != nil else { return }
        let now = Date()
        startedAt = nil
        heartbeat?.cancel()
        heartbeat = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        autoEndAt = nil
        systemInterrupted = false
        if let fakeNight {
            self.fakeNight = nil
            _ = onFinish?(fakeNight, false)
            return
        }
        disconnect()
        if let processor {
            let (night, writeFailed) = queue.sync {
                processor.pause(at: now, ending: true)
                return (processor.snapshot(at: now, end: reason), processor.didFailToWriteAudio)
            }
            if onFinish?(night, writeFailed) == true {
                queue.async { processor.discardSupersededClips(committed: night) }
            }
        }
        processor = nil
        deactivateSession()
        endActivity()
    }

    func stopNight(_ id: String) {
        guard activity?.attributes.nightID == id else { return }
        stop()
    }

    func clearAbandonedActivities() {
        let stale = Activity<SnoreActivityAttributes>.activities
        Task {
            for item in stale { await item.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func connect() throws {
        guard let processor else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
        try session.setActive(true)
        if let mic = session.availableInputs?.first(where: { $0.portType == .builtInMic }),
           session.preferredInput?.uid != mic.uid {
            try session.setPreferredInput(mic)
        }
        let inputEngine = AVAudioEngine()
        let input = inputEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate >= SpectralFeatures.sampleRate, format.channelCount > 0,
              format.commonFormat == .pcmFormatFloat32, !format.isInterleaved else {
            throw RecordingError.noInput
        }
        let id = UUID()
        try queue.sync { try processor.begin(id: id, sampleRate: format.sampleRate, at: Date()) }
        input.installTap(onBus: 0, bufferSize: 4_096, format: nil) { [queue] buffer, _ in
            guard let channel = buffer.floatChannelData else { return }
            let samples = Array(UnsafeBufferPointer(start: channel[0], count: Int(buffer.frameLength)))
            queue.async { processor.append(samples, stream: id) }
        }
        do {
            inputEngine.prepare()
            try inputEngine.start()
            engine = inputEngine
        } catch {
            input.removeTap(onBus: 0)
            queue.sync { processor.pause(at: Date()) }
            throw error
        }
    }

    private func disconnect() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.engine = nil
        }
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, let processor = self.processor else { return }
                let now = Date()
                if let due = self.autoEndAt, now >= due {
                    self.stop(reason: .autoEnd)
                    return
                }
                if self.engine?.isRunning != true && !self.systemInterrupted {
                    self.resume(at: now)
                }
                let count = self.queue.sync { processor.snoreCount }
                self.onCount?(count)
                if now.timeIntervalSince(self.checkpointAt ?? now) >= 300 {
                    self.checkpoint()
                }
            }
        }
    }

    private func pause() {
        disconnect()
        if let processor { queue.sync { processor.pause(at: Date()) } }
        checkpoint()
    }

    private func resume(at date: Date = Date(), immediately: Bool = false) {
        guard startedAt != nil, !systemInterrupted,
              immediately || date.timeIntervalSince(lastResumeAttempt) >= 5 else { return }
        lastResumeAttempt = date
        if engine != nil { pause() }
        do { try connect() } catch { deactivateSession() }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
                Task { @MainActor in
                    guard let self, self.startedAt != nil else { return }
                    self.systemInterrupted = type == .began
                    if type == .began { self.pause() } else { self.resume(immediately: true) }
                }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.systemInterrupted = false
                    self?.resume(immediately: true)
                }
            },
            center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] note in
                let changedEngine = note.object as? AVAudioEngine
                Task { @MainActor in
                    guard let self, let changedEngine, changedEngine === self.engine else { return }
                    self.resume(immediately: true)
                }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.startedAt != nil, !self.systemInterrupted else { return }
                    let session = AVAudioSession.sharedInstance()
                    let input = session.currentRoute.inputs.first
                    if self.engine?.isRunning != true || input?.portType != .builtInMic {
                        self.resume()
                    }
                }
            }
        ]
    }

    private func startActivity(_ night: Night) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = SnoreActivityAttributes(startedAt: night.startedAt, nightID: night.id.uuidString)
        activity = try? Activity.request(attributes: attributes,
            content: ActivityContent(state: .init(snoreCount: 0), staleDate: nil), pushType: nil)
    }

    private func endActivity() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
