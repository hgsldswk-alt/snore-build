import Foundation
import AVFoundation
import SwiftUI
import UIKit
import WidgetKit

enum AppTab: String, CaseIterable {
    case tonight, history, factors, settings

    var title: String {
        switch self {
        case .tonight: return L.t("今晚")
        case .history: return L.t("历史")
        case .factors: return L.t("因素")
        case .settings: return L.t("设置")
        }
    }

    var icon: String {
        switch self {
        case .tonight: return "moon"
        case .history: return "calendar"
        case .factors: return "slider.horizontal.3"
        case .settings: return "gearshape"
        }
    }
}

struct ShareFiles: Identifiable {
    let id = UUID()
    let urls: [URL]
    var removeParentWhenFinished = true
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var data = AppData()
    @Published private(set) var recordingStart: Date?
    @Published private(set) var starting = false
    @Published private(set) var snoreCount = 0
    @Published private(set) var permissionDenied = false
    @Published private(set) var now = Date()
    @Published private(set) var exportInProgress = false
    @Published private(set) var storageUnavailable = false
    @Published private(set) var fullAudioBytes: Int64 = 0
    @Published var tab = AppTab.tonight
    @Published var path: [UUID] = []
    @Published var paywall = false
    @Published var shareNightID: UUID?
    var shareTitleOverride: String?
    @Published var shareFiles: ShareFiles?
    @Published var error: String?
    @Published var recentResultID: UUID?

    let store: Store
    let player = AudioPlayer()
    let purchases = Purchases()
    private let recorder = Recorder()
    private var hasUncommittedChanges = false
    private var lastAudioCleanup = Date.distantPast

    var nights: [Night] { data.nights.filter { !$0.inProgress } }
    var hasPro: Bool { data.entitlement.hasPro(at: now) }
    var remainingDays: Int { data.entitlement.remainingDays(at: now) }

    init() {
        store = Launch.isolated
            ? Store(root: FileManager.default.temporaryDirectory.appendingPathComponent("SnoreLog-demo-" + UUID().uuidString))
            : Store()
        do {
            data = try store.load()
            if Launch.has("-demo-night") || Launch.has("-recovered") {
                DemoData.seed(&data, store: store)
            }
            now = Date()
            if !Launch.isFree {
                let start = data.entitlement.proStartedAt ?? now
                data.entitlement.proStartedAt = Launch.isolated ? start : TrialAnchor.earliest(start)
            }
            if Launch.has("-expired") {
                data.entitlement.proStartedAt = now.addingTimeInterval(-31 * 86_400)
            }
            let recovered = Recovery.finish(&data)
            if let id = recovered.first {
                path = [id]
                recentResultID = id
            }
            if !Launch.isolated { pruneExpiredAudio() }
            if persist() && !Launch.isolated { store.discardUnreferencedAudio(in: data) }
        } catch {
            storageUnavailable = true
            self.error = L.t("暂时无法读取本机记录")
        }
        fullAudioBytes = store.fullBytes()

        recorder.onCheckpoint = { [weak self] night in
            guard let self else { return false }
            self.data.upsert(night)
            return self.persist()
        }
        recorder.onFinish = { [weak self] night, audioError in
            guard let self else { return false }
            self.recordingStart = nil
            self.data.upsert(night)
            self.fullAudioBytes = self.store.fullBytes()
            let saved = self.persist(reloadWidget: true)
            if audioError && saved { self.error = L.t("部分音频未能保存，已保留可用记录") }
            self.recentResultID = night.id
            self.open(night.id)
            return saved
        }
        recorder.onCount = { [weak self] count in
            if self?.snoreCount != count { self?.snoreCount = count }
        }
        RecordingActions.stop = { [weak self] id in self?.recorder.stopNight(id) }
        if !Launch.isolated { recorder.clearAbandonedActivities() }
        configureDemo()
    }

    private func configureDemo() {
        if Launch.has("-history") { tab = .history }
        if Launch.has("-factors") { tab = .factors }
        if Launch.has("-settings") { tab = .settings }
        if Launch.has("-paywall") { tab = .settings; paywall = true }
        if Launch.has("-mic-denied") { permissionDenied = true }
        if let id = nights.first?.id, Launch.has("-night") || Launch.has("-share") || Launch.has("-recovered") {
            path = [id]
            if Launch.has("-share") { shareNightID = id }
        }
        if Launch.has("-recording") {
            let demoNight = nights.first ?? DemoData.lastNight()
            DemoData.writeClips(demoNight, to: store)
            recorder.startDemo(night: demoNight)
            recordingStart = recorder.startedAt
        }
    }

    func open(_ id: UUID) {
        tab = .tonight
        path = [id]
    }

    func showShare(for id: UUID, title: String? = nil) {
        shareTitleOverride = title
        shareNightID = id
    }

    func openURL(_ url: URL) {
        guard url.scheme == "snorelog", url.host == "night", let id = UUID(uuidString: url.lastPathComponent),
              nights.contains(where: { $0.id == id }) else { return }
        open(id)
    }

    func startRecording() async {
        guard !starting, recordingStart == nil else { return }
        guard !storageUnavailable else { self.error = L.t("暂时无法读取本机记录"); return }
        starting = true
        defer { starting = false }
        player.stop()
        now = Date()
        do {
            let result = try await recorder.start(store: store, keepsFullAudio: hasPro && data.settings.fullNight, keepsTalk: hasPro,
                settings: data.settings)
            switch result {
            case .denied:
                permissionDenied = true
            case .started:
                if Launch.fakeAudio, let night = recorder.demoNight { DemoData.writeClips(night, to: store) }
                permissionDenied = false
                snoreCount = Launch.fakeAudio ? 12 : 0
                recordingStart = recorder.startedAt
            }
        } catch {
            data.nights.removeAll(where: \.inProgress)
            self.error = L.t("暂时无法开始记录")
        }
    }

    func stopRecording() {
        recorder.stop()
    }

    func becameActive() async {
        now = Date()
        if !Launch.isolated { permissionDenied = AVAudioApplication.shared.recordPermission == .denied }
        if !Launch.isolated && recordingStart == nil && now.timeIntervalSince(lastAudioCleanup) >= 3_600 {
            pruneExpiredAudio()
        }
        purchases.start { [weak self] trial, purchased in
            guard let self, !self.storageUnavailable else { return }
            let original = self.data.entitlement
            self.now = Date()
            self.data.entitlement.purchasedPro = purchased
            if let trial {
                self.data.entitlement.trialClaimedAt = min(self.data.entitlement.trialClaimedAt ?? trial, trial)
                let start = self.data.entitlement.proStartedAt ?? self.now
                self.data.entitlement.proStartedAt = TrialAnchor.earliest(min(start, trial))
            }
            if original != self.data.entitlement { self.persist(reloadWidget: true) }
        }
        await purchases.refresh()
    }

    private func pruneExpiredAudio() {
        guard !storageUnavailable, !exportInProgress else { return }
        lastAudioCleanup = now
        let before = data.nights
        do { try store.cleanFull(&data, now: now) }
        catch { self.error = L.t("暂时无法删除音频") }
        if before != data.nights { persist() }
        fullAudioBytes = store.fullBytes()
    }

    func wentIntoBackground() {
        recorder.checkpoint()
        if hasUncommittedChanges { persist(reloadWidget: recordingStart == nil) }
    }

    @discardableResult
    private func persist(reloadWidget: Bool = false) -> Bool {
        guard !storageUnavailable else { return false }
        do {
            try store.save(data)
            hasUncommittedChanges = false
            if reloadWidget && !Launch.isolated { WidgetCenter.shared.reloadAllTimelines() }
            return true
        } catch {
            hasUncommittedChanges = true
            if recordingStart == nil { self.error = L.t("暂时无法保存，请检查本机空间后再试") }
            return false
        }
    }

    func toggleFactor(_ factor: String, nightID: UUID) {
        guard let index = data.nights.firstIndex(where: { $0.id == nightID }) else { return }
        if data.nights[index].factors.remove(factor) == nil { data.nights[index].factors.insert(factor) }
        persist(reloadWidget: true)
    }

    func toggleNotMe(_ id: UUID, nightID: UUID) {
        guard let index = data.nights.firstIndex(where: { $0.id == nightID }),
              let clipIndex = data.nights[index].clips.firstIndex(where: { $0.id == id }) else { return }
        data.nights[index].clips[clipIndex].notMe.toggle()
        data.nights[index].notMeCount = data.nights[index].exclusions.count
        persist(reloadWidget: true)
    }

    func removeClip(_ clip: Clip, nightID: UUID) {
        guard !exportInProgress, let index = data.nights.firstIndex(where: { $0.id == nightID }) else { return }
        if player.clipID == clip.id { player.stop() }
        if clip.notMe {
            var exclusion = clip
            exclusion.fileName = ""
            data.nights[index].excludedClips.append(exclusion)
        }
        data.nights[index].clips.removeAll { $0.id == clip.id }
        data.nights[index].talkClips.removeAll { $0.id == clip.id }
        if persist(reloadWidget: true) {
            do { try store.removeClip(clip, nightID: nightID) }
            catch { self.error = L.t("暂时无法删除音频") }
        }
    }

    func play(_ clip: Clip, night: Night) {
        do { try player.play(clip, night: night, store: store) }
        catch { self.error = L.t("这段音频已不可用") }
    }

    func play(at offset: Double, night: Night) {
        let nearest = night.clips.min { abs($0.startOffset - offset) < abs($1.startOffset - offset) }
        do {
            if !night.fullSegments.isEmpty {
                try player.play(from: offset, segments: night.fullSegments, store: store)
            } else if let nearest {
                try player.play(nearest, night: night, store: store, toggle: false)
            }
        } catch {
            if !night.fullSegments.isEmpty, let nearest {
                do { try player.play(nearest, night: night, store: store, toggle: false); return } catch {}
            }
            self.error = L.t("这段音频已不可用")
        }
    }

    func setFactors(_ terms: [String]) {
        data.customFactors = FactorList.clean(terms)
        persist()
    }

    func setFullAudio(_ enabled: Bool) {
        guard hasPro || !enabled else { paywall = true; return }
        data.settings.fullNight = enabled
        persist()
    }

    func setAutoEnd(_ minutes: Int?) {
        data.settings.autoEndTime = minutes
        persist()
    }

    func cleanFullAudio() {
        guard !exportInProgress, !storageUnavailable else { return }
        player.stop()
        do {
            try store.cleanFull(&data, all: true)
            persist()
            fullAudioBytes = store.fullBytes()
        } catch {
            self.error = L.t("暂时无法删除音频")
        }
    }

    func export() async {
        guard !exportInProgress, !storageUnavailable else { return }
        exportInProgress = true
        defer { exportInProgress = false }
        var snapshot = data
        snapshot.nights = nights
        let store = store
        do {
            let urls = try await Task.detached(priority: .userInitiated) { [snapshot, store] in
                try Export.make(snapshot, store: store)
            }.value
            shareFiles = ShareFiles(urls: urls)
        } catch {
            self.error = L.t("暂时无法导出记录")
        }
    }

    func dismissMilestone(_ id: String) {
        data.milestones.insert(id)
        persist()
    }

    func shouldRequestReview(for night: Night) -> Bool {
        guard !Launch.isolated, !data.reviewAsked, recentResultID == night.id,
              night.endReason != .recovered, night.score != nil,
              nights.filter({ $0.score != nil && $0.endReason != .recovered }).count >= 3 else { return false }
        data.reviewAsked = true
        return persist()
    }

    func dismissExpiryNotice() {
        data.expiryNoticeShown = true
        persist()
    }
}
