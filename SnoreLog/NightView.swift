import StoreKit
import SwiftUI

struct NightView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.requestReview) private var requestReview
    @State private var showAllClips = false
    @State private var showTalkClips = false
    @State private var selection: Double?
    @State private var pendingShare: ShareFiles?
    @State private var makingVideo = false
    let nightID: UUID

    var body: some View {
        Group {
            if let night = model.nights.first(where: { $0.id == nightID }) {
                result(night)
                    .navigationTitle(L.f("%@早上", L.date(night.endDate)))
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L.t("分享")) { model.showShare(for: night.id) }.accessibilityIdentifier("shareNight")
                        }
                    }
                    .task(id: model.recentResultID) {
                        guard model.recentResultID == night.id, !Launch.isolated else { return }
                        do { try await Task.sleep(for: .seconds(2)) } catch { return }
                        if model.shouldRequestReview(for: night) { requestReview() }
                    }
            } else {
                ContentUnavailableView(L.t("暂无记录"), systemImage: "moon")
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onDisappear { model.player.stop() }
        .sheet(item: $pendingShare) { ActivitySheet(files: $0) }
    }

    private func result(_ night: Night) -> some View {
        List {
            row(summary(night))
            row(timeline(night))
            if night.endReason == .recovered {
                row(note(L.f("记录在 %@ 中断，已保存之前的数据", L.clock(night.endDate)), icon: "clock.arrow.circlepath"))
            }
            if night.notMeCount >= 3 {
                row(note(L.t("可能录到了别人，手机可以再靠近你一些"), icon: "iphone"))
            }
            if !night.sortedClips.isEmpty {
                row(sectionLabel(L.t("最响的片段")))
                let clips = showAllClips ? night.sortedClips : Array(night.sortedClips.prefix(3))
                ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                    clipRow(clip, index: index, night: night, talk: false)
                }
                if night.clips.count > 3 {
                    row(Button(L.t(showAllClips ? "收起片段" : "更多片段")) { showAllClips.toggle() }
                        .font(.footnote).buttonStyle(.plain).foregroundStyle(Palette.accent))
                }
            }
            row(factors(night))
            if !night.talkClips.isEmpty {
                row(talkHeader(night))
                if showTalkClips {
                    ForEach(Array(night.talkClips.enumerated()), id: \.element.id) { index, clip in
                        clipRow(clip, index: index, night: night, talk: true)
                    }
                }
            }
            if let milestone = NightInsights.milestone(for: night, data: model.data), model.hasPro || milestone.id.hasPrefix("streak-") {
                row(milestoneRow(milestone, night: night))
            } else if let headline = NightInsights.shareHeadline(night, nights: model.nights) {
                row(Button { model.showShare(for: night.id) } label: {
                    note(headline, icon: "square.and.arrow.up")
                }.buttonStyle(.plain))
            }
            if let difference = NightInsights.previousWeekDifference(night, nights: model.nights), difference > 0 {
                row(Button(L.t("去看看各因素下的分数")) { model.tab = .factors }
                    .buttonStyle(.plain).foregroundStyle(Palette.accent).font(.footnote))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func row<Content: View>(_ content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 4, leading: 22, bottom: 4, trailing: 22))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    private func summary(_ night: Night) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 15) {
                Text(night.score.map(String.init) ?? "–")
                    .font(.system(size: 72, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Palette.accent)
                    .accessibilityIdentifier("nightScore")
                VStack(alignment: .leading, spacing: 5) {
                    Text(L.t("鼾声分数") + (night.score.map { " · " + ScoreCalculator.label($0) } ?? ""))
                        .font(.headline)
                    if let difference = NightInsights.previousWeekDifference(night, nights: model.nights), difference < 0 {
                        Text(L.f("比前 7 晚平均低 %@ 分", String(-difference))).font(.footnote).foregroundStyle(Palette.secondary)
                    } else if night.score == nil {
                        Text(L.t("记录较短，未出分数")).font(.footnote).foregroundStyle(Palette.secondary)
                    }
                }
            }
            HStack(spacing: 10) {
                let percentage = 100 * night.adjustedSnoreSeconds / max(1, night.recordedSeconds)
                metric(L.t("打鼾"), L.f("%@ 分钟", String(Int(night.adjustedSnoreSeconds / 60))),
                       sub: "\(Int(percentage.rounded()))%")
                metric(L.t("记录"), L.duration(night.recordedSeconds),
                       sub: L.clock(night.startedAt) + "–" + L.clock(night.endDate))
            }
        }
    }

    private func metric(_ label: String, _ value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.footnote).foregroundStyle(Palette.secondary)
            Text(value).font(.system(.title3, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.68)
            Text(sub).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nightCard(14)
    }

    private func timeline(_ night: Night) -> some View {
        let duration = max(1, night.endDate.timeIntervalSince(night.startedAt))
        let fraction = selection ?? 0
        let playable = !night.fullSegments.isEmpty || !night.clips.isEmpty
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.t(playable ? "时间轴 · 点按回放" : "时间轴")).font(.footnote).foregroundStyle(Palette.secondary)
                Spacer()
                if selection != nil { Text(L.clock(night.startedAt.addingTimeInterval(fraction * duration))).font(.caption).foregroundStyle(Palette.accent) }
            }
            GeometryReader { bounds in
                Waveform(bins: ScoreCalculator.levels(night), bars: 144, selection: selection)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in selection = position(value.location.x, width: bounds.size.width) }
                        .onEnded { value in
                            let fraction = position(value.location.x, width: bounds.size.width)
                            selection = fraction
                            model.play(at: fraction * duration, night: night)
                        })
            }
            .frame(height: 46)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L.t("时间轴"))
            .accessibilityValue(L.clock(night.startedAt.addingTimeInterval(fraction * duration)))
            .accessibilityAdjustableAction { direction in
                let step = 60 / duration
                switch direction {
                case .increment: selection = min(0.999, fraction + step)
                case .decrement: selection = max(0, fraction - step)
                @unknown default: break
                }
            }
            .accessibilityAction { model.play(at: fraction * duration, night: night) }
            .accessibilityIdentifier("nightTimeline")
            HStack {
                Text(L.clock(night.startedAt))
                Spacer()
                if let loudest = night.sortedClips.first(where: { !$0.notMe }) {
                    Text(L.f("最响 %@", L.clock(night.startedAt.addingTimeInterval(loudest.startOffset))))
                }
                Spacer()
                Text(L.clock(night.endDate))
            }
            .font(.caption2)
            .foregroundStyle(Palette.secondary)
            if night.interruptedSeconds > 0 {
                Text(L.f("中断 %@", L.duration(night.interruptedSeconds))).font(.caption).foregroundStyle(Palette.secondary)
            }
        }
        .nightCard(15)
    }

    private func position(_ x: CGFloat, width: CGFloat) -> Double {
        min(0.9999, max(0, Double(x / max(1, width))))
    }

    private func clipRow(_ clip: Clip, index: Int, night: Night, talk: Bool) -> some View {
        row(ClipRow(player: model.player, clip: clip, night: night, index: index, talk: talk))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { model.removeClip(clip, nightID: night.id) } label: {
                    Label(L.t("删除"), systemImage: "trash")
                }
                .disabled(model.exportInProgress)
                Button {
                    share(clip, nightID: night.id)
                } label: { Label(L.t("分享"), systemImage: "square.and.arrow.up") }
                .tint(Palette.accent)
                .disabled(makingVideo)
            }
    }

    private func share(_ clip: Clip, nightID: UUID) {
        let source = model.store.clipURL(nightID: nightID, fileName: clip.fileName)
        guard FileManager.default.fileExists(atPath: source.path) else { model.error = L.t("这段音频已不可用"); return }
        let brand = L.t("鼾声记录")
        makingVideo = true
        Task {
            defer { makingVideo = false }
            if let video = try? await Task.detached(priority: .userInitiated, operation: {
                try await ClipVideo.make(from: source, brand: brand)
            }).value {
                pendingShare = ShareFiles(urls: [video])
            } else if FileManager.default.fileExists(atPath: source.path) {
                pendingShare = ShareFiles(urls: [source], removeParentWhenFinished: false)
            }
        }
    }

    private func factors(_ night: Night) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel(L.t("昨晚的情况 · 点一下即记"))
                Spacer()
                NavigationLink(L.t("编辑")) { FactorEditor() }
                    .font(.footnote)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    let options = FactorList.clean(model.data.customFactors + night.factors.sorted())
                    ForEach(Array(options.enumerated()), id: \.element) { index, factor in
                        let picked = night.factors.contains(factor)
                        Button {
                            model.toggleFactor(factor, nightID: night.id)
                        } label: {
                            Text(L.t(factor))
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 13)
                                .frame(minHeight: 37)
                                .foregroundStyle(picked ? Palette.onAccent : Palette.accent)
                                .background(Palette.accent.opacity(picked ? 1 : 0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(picked ? .isSelected : [])
                        .accessibilityIdentifier("factor_\(index)")
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func talkHeader(_ night: Night) -> some View {
        Button {
            showTalkClips.toggle()
        } label: {
            HStack {
                Label(L.t("梦话片段"), systemImage: "waveform")
                Spacer()
                Text(String(night.talkClips.count))
                Image(systemName: showTalkClips ? "chevron.up" : "chevron.down")
                    .font(.caption)
            }
            .foregroundStyle(Palette.secondary)
            .nightCard()
        }
        .buttonStyle(.plain)
    }

    private func milestoneRow(_ milestone: Milestone, night: Night) -> some View {
        HStack(spacing: 12) {
            Button { model.showShare(for: night.id, title: milestone.title) } label: {
                Label(milestone.title, systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.accent)
            Button { model.dismissMilestone(milestone.id) } label: {
                Image(systemName: "xmark").frame(width: 36, height: 38)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.secondary)
            .accessibilityLabel(L.t("关闭"))
        }
        .nightCard(12)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.footnote).foregroundStyle(Palette.secondary).accessibilityAddTraits(.isHeader)
    }

    private func note(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.footnote).foregroundStyle(Palette.secondary).nightCard(12)
    }
}

struct ClipRow: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var player: AudioPlayer
    let clip: Clip
    let night: Night
    let index: Int
    let talk: Bool

    var body: some View {
        HStack(spacing: 10) {
            let playing = player.clipID == clip.id && player.isPlaying
            Button { model.play(clip, night: night) } label: {
                Image(systemName: playing ? "stop.fill" : "play.fill")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .foregroundStyle(index == 0 && !clip.notMe ? Palette.onAccent : Palette.accent)
                    .background(index == 0 && !clip.notMe ? Palette.accent : Palette.accent.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t(playing ? "停止回放" : "播放片段"))
            .accessibilityIdentifier(talk ? "playTalk_\(index)" : "playClip_\(index)")
            VStack(alignment: .leading, spacing: 4) {
                Text(L.clock(night.startedAt.addingTimeInterval(clip.startOffset))).monospacedDigit()
                Text(talk ? L.f("%@ 秒", String(Int(ceil(clip.duration)))) :
                    ScoreCalculator.levelLabel(clip.level) + " · " + L.f("%@ 秒", String(Int(ceil(clip.duration)))))
                    .font(.caption)
                    .foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 3)
            if !talk {
                Button { model.toggleNotMe(clip.id, nightID: night.id) } label: {
                    HStack(spacing: 4) {
                        if clip.notMe { Image(systemName: "checkmark") }
                        Text(L.t("不是我"))
                    }
                    .font(.caption)
                    .foregroundStyle(clip.notMe ? Palette.accent : Palette.secondary)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 38)
                    .overlay(Capsule().strokeBorder(clip.notMe ? Palette.accent : Palette.line))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(clip.notMe ? .isSelected : [])
                .accessibilityIdentifier("notMe_\(index)")
            }
        }
        .nightCard(10)
    }
}
