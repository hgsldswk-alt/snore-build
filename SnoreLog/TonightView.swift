import SwiftUI
import UIKit

struct TonightView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @State private var batteryLow = false
    @State private var tapCount = 0

    var body: some View {
        GeometryReader { bounds in
            let compact = bounds.size.height < 650
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    PageHeader(title: L.t("今晚"), subtitle: L.date(model.now, weekday: true))
                    controls(compact: compact)
                        .padding(.top, compact ? 40 : 66)
                        .padding(.bottom, compact ? 28 : 44)
                    if let latest = model.nights.first {
                        NavigationLink(value: latest.id) { recentCard(latest) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("lastNight")
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
                .frame(minHeight: bounds.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Palette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(Palette.background, for: .tabBar)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: tapCount)
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = !Launch.isolated
            updateBattery()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in updateBattery() }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in updateBattery() }
    }

    private func controls(compact: Bool) -> some View {
        VStack(spacing: 14) {
            Button {
                tapCount += 1
                Task { await model.startRecording() }
            } label: {
                VStack(spacing: 11) {
                    if model.starting {
                        ProgressView().tint(Palette.accent)
                    } else {
                        Circle().fill(Palette.accent).frame(width: 19, height: 19).accessibilityHidden(true)
                    }
                    Text(L.t("开始记录"))
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                }
                .padding(28)
                .frame(width: compact ? 172 : 198, height: compact ? 172 : 198)
                .foregroundStyle(Palette.accent)
                .background(Palette.accent.opacity(0.10), in: Circle())
                .overlay(Circle().strokeBorder(Palette.accent, lineWidth: 2))
                .padding(17)
                .overlay(Circle().strokeBorder(Palette.accent.opacity(0.28), lineWidth: 1.5))
                .contentShape(Circle())
            }
            .buttonStyle(CirclePressStyle())
            .disabled(model.starting)
            .accessibilityIdentifier("startButton")

            if model.permissionDenied {
                Text(L.t("需要麦克风才能录鼾声")).font(.footnote).foregroundStyle(Palette.secondary)
                Button(L.t("去设置")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .accessibilityIdentifier("microphoneSettings")
            } else {
                Text(L.t(batteryLow ? "电量低，建议插上充电" : "放床头，锁屏即可"))
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func recentCard(_ night: Night) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Calendar.current.isDateInToday(night.endDate) ? L.t("昨晚") : L.date(night.endDate))
                Spacer()
                Image(systemName: "chevron.right").font(.caption2)
            }
            .font(.footnote)
            .foregroundStyle(Palette.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(night.score.map(String.init) ?? "–")
                    .font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Palette.accent)
                Text(L.f("打鼾 %@ 分钟", String(Int(night.adjustedSnoreSeconds / 60))))
                    .font(.footnote)
                    .foregroundStyle(Palette.secondary)
            }
            Waveform(bins: ScoreCalculator.levels(night), bars: 64).frame(height: 42)
        }
        .nightCard(18)
        .contentShape(Rectangle())
    }

    private func updateBattery() {
        let device = UIDevice.current
        batteryLow = device.batteryLevel >= 0 && device.batteryLevel < 0.30 && device.batteryState == .unplugged
    }
}

struct CirclePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.18), value: configuration.isPressed)
    }
}

struct RecordingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var dimmed = false
    @State private var pulsing = false
    @State private var reset = 0
    let startedAt: Date

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if dimmed {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(L.clock(context.date))
                        .font(.system(size: 40, weight: .light, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Palette.dim.opacity(0.72))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .contentShape(Rectangle())
                .onTapGesture { dimmed = false; reset += 1 }
                .accessibilityAction { dimmed = false; reset += 1 }
                .accessibilityLabel(L.t("点一下恢复显示"))
            } else {
                recordingControls
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled()
        .task(id: reset) {
            guard !Launch.isolated, !voiceOver else { return }
            do { try await Task.sleep(for: .seconds(10)); dimmed = true } catch {}
        }
    }

    private var recordingControls: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Palette.moon).frame(width: 6, height: 6)
                Text(L.t("正在记录")).font(.footnote)
            }
            .foregroundStyle(Palette.moon)
            .padding(.top, 18)
            Spacer()
            Circle()
                .fill(Palette.moon.opacity(0.085))
                .overlay(Circle().strokeBorder(Palette.moon.opacity(0.55), lineWidth: 1.2))
                .frame(width: 108, height: 108)
                .scaleEffect(pulsing && !reduceMotion ? 1.12 : 1)
                .onAppear {
                    if !Launch.isolated && !reduceMotion {
                        withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { pulsing = true }
                    }
                }
                .accessibilityHidden(true)
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = Launch.isolated ? 11_560 : context.date.timeIntervalSince(startedAt)
                Text(L.duration(elapsed))
                    .font(.system(size: 51, weight: .light, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Palette.pale)
            }
            Text(L.f("检测到鼾声 %@ 段", String(model.snoreCount)))
                .font(.subheadline)
                .foregroundStyle(Palette.dim)
                .padding(.top, 12)
            Text(L.t("锁屏即可，避免上划关闭 App"))
                .font(.footnote)
                .foregroundStyle(Palette.dim)
                .padding(.top, 6)
            Spacer()
            Text(L.t("长按结束"))
                .font(.headline)
                .foregroundStyle(Palette.moon)
                .frame(width: 216, height: 53)
                .background(Palette.moon.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.moon.opacity(0.55)))
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.6) { model.stopRecording() }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.stopRecording() }
                .accessibilityIdentifier("stopButton")
            Text(L.t("10 秒后屏幕变暗，点一下恢复"))
                .font(.caption)
                .foregroundStyle(Palette.dim)
                .padding(.top, 16)
                .padding(.bottom, 20)
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
