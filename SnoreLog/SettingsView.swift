import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showGuide = false

    var body: some View {
        List {
            Section {
                fullAudioSetting
                automaticEnd
                Button {
                    Task { await model.export() }
                } label: {
                    HStack {
                        Label(L.t("导出记录"), systemImage: "square.and.arrow.up")
                        Spacer()
                        if model.exportInProgress {
                            ProgressView()
                        } else {
                            Text("CSV + ZIP").font(.caption).foregroundStyle(Palette.secondary)
                        }
                    }
                }
                .disabled(model.exportInProgress || model.storageUnavailable)
                .accessibilityIdentifier("exportSetting")

                Button { showGuide = true } label: { Label(L.t("使用说明"), systemImage: "info.circle") }
                    .accessibilityIdentifier("helpSetting")

                if !Launch.isFree {
                    Button { model.paywall = true } label: {
                        HStack {
                            Label(L.t("购买与恢复"), systemImage: "bag")
                            Spacer()
                            if model.data.entitlement.purchasedPro { Text(L.t("已买断")).font(.caption) }
                        }
                    }
                    .accessibilityIdentifier("purchaseSetting")
                }
            }
            .listRowBackground(Palette.card)

            if !Launch.isFree && !model.hasPro && !model.data.expiryNoticeShown {
                Section {
                    HStack {
                        Text(L.t("体验已结束，已有记录仍可查看和导出。")).font(.footnote)
                        Spacer()
                        Button(L.t("关闭")) { model.dismissExpiryNotice() }.font(.footnote).buttonStyle(.borderless)
                    }
                    .listRowBackground(Palette.card)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(L.t("设置"))
        .accessibilityIdentifier("settingsPage")
        .sheet(isPresented: $showGuide) { GuideView() }
    }

    private var fullAudioSetting: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.hasPro {
                Toggle(isOn: Binding(get: { model.data.settings.fullNight }, set: model.setFullAudio)) {
                    Label(L.t("整晚录音"), systemImage: "waveform")
                }
                .accessibilityIdentifier("fullAudioSetting")
            } else {
                Button { model.paywall = true } label: {
                    HStack {
                        Label(L.t("整晚录音"), systemImage: "waveform")
                        Spacer()
                        Image(systemName: "lock").font(.caption)
                    }
                }
                .accessibilityIdentifier("fullAudioSetting")
            }
            Text(L.t("保留 14 天，约 115 MB/晚")).font(.caption).foregroundStyle(Palette.secondary)
            if model.fullAudioBytes > 0 {
                HStack {
                    Text(ByteCountFormatter.string(fromByteCount: model.fullAudioBytes, countStyle: .file))
                    Spacer()
                    Button(L.t("清理整晚录音"), role: .destructive) { model.cleanFullAudio() }
                        .buttonStyle(.borderless)
                        .disabled(model.exportInProgress)
                }
                .font(.caption)
            }
        }
    }

    private var automaticEnd: some View {
        VStack(spacing: 5) {
            Toggle(isOn: Binding(get: { model.data.settings.autoEndTime != nil },
                                 set: { model.setAutoEnd($0 ? 450 : nil) })) {
                Label(L.t("自动结束时间"), systemImage: "clock")
            }
            .accessibilityIdentifier("autoEndSetting")
            if let minutes = model.data.settings.autoEndTime {
                DatePicker(L.t("结束时间"), selection: Binding(get: {
                    Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
                }, set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    model.setAutoEnd((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
                }), displayedComponents: .hourAndMinute)
            }
        }
    }
}

struct GuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    item("怎么放手机", "用 iPhone 麦克风录音。把手机放在靠近你的一侧，点开始后即可锁屏。录音时请保持电量，避免从多任务界面上划关闭 App。")
                    item("分数怎么算", "分数按有效录音分钟计算。每分钟强度权重为安静 0、轻 0.4、中 0.7、响 1。把权重相加，除以有效分钟数后乘以 100 并四舍五入。中断的分钟跳过，标为「不是我」的片段所覆盖的分钟权重为 0。有效录音不足 30 分钟也会保存。")
                    item("回放和导出", "点时间轴从整晚录音的选中位置播放，只有片段时会播放最近一段。在设置导出 CSV 和 ZIP，可自己保存副本。")
                    item("录音保存在本机", "录音和因素标签保存在这台 iPhone 上，不会上传。分享时由你选择发出的内容。换机前可导出，或使用 iPhone 备份和快速开始。")
                }
                .padding(22)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle(L.t("使用说明"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L.t("完成")) { dismiss() } } }
        }
    }

    private func item(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L.t(title)).font(.headline).accessibilityAddTraits(.isHeader)
            Text(L.t(body)).foregroundStyle(Palette.secondary).lineSpacing(4)
        }
    }
}
