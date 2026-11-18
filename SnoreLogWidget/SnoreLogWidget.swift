import ActivityKit
import SwiftUI
import WidgetKit

struct SnoreEntry: TimelineEntry {
    let date: Date
    let nights: [Night]
    let hasPro: Bool
}

struct SnoreProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnoreEntry {
        var night = Night()
        night.recordedSeconds = 27_000
        night.minutes = (0..<450).map { MinuteBin(level: $0 % 27 < 4 ? 2 : 0) }
        return SnoreEntry(date: Date(), nights: [night], hasPro: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnoreEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: Date(), data: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnoreEntry>) -> Void) {
        let now = Date()
        let data = load()
        var entries = [entry(at: now, data: data)]
        let expiry = data?.entitlement.trialEnd
        if let expiry, expiry > now, expiry <= now.addingTimeInterval(3_600) {
            entries.append(entry(at: expiry, data: data))
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3_600))))
    }

    private func load() -> AppData? { try? Store().load() }

    private func entry(at date: Date, data: AppData?) -> SnoreEntry {
        let nights = data?.nights.filter { !$0.inProgress } ?? []
        let allowed = data?.entitlement.hasPro(at: date) ?? Launch.isFree
        return SnoreEntry(date: date, nights: nights, hasPro: allowed)
    }
}

struct SnoreWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SnoreLog.LastNight", provider: SnoreProvider()) { entry in
            SnoreWidgetView(entry: entry)
        }
        .configurationDisplayName(L.t("鼾声记录"))
        .description(L.t("在主屏幕查看最近的鼾声分数"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct SnoreWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SnoreEntry
    private let ink = Color(red: 232 / 255, green: 230 / 255, blue: 225 / 255)
    private let amber = Color(red: 227 / 255, green: 178 / 255, blue: 106 / 255)
    private let dark = Color(red: 13 / 255, green: 17 / 255, blue: 23 / 255)

    var body: some View {
        content
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(dark, for: .widget)
            .widgetURL(entry.hasPro ? entry.nights.first.flatMap { nightURL($0.id.uuidString) } : nil)
    }

    @ViewBuilder private var content: some View {
        if !entry.hasPro && !entry.nights.isEmpty {
            Label(L.t("买断后可用小组件"), systemImage: "lock").font(.footnote)
        } else if let latest = entry.nights.first {
            if family == .systemMedium { trend } else { score(latest) }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "moon").foregroundStyle(amber)
                Text(L.t("暂无记录")).font(.footnote)
            }
        }
    }

    private func score(_ night: Night) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("最近一晚")).font(.caption).foregroundStyle(ink.opacity(0.68))
            Text(night.score.map(String.init) ?? "–")
                .font(.system(size: 42, weight: .bold, design: .rounded)).foregroundStyle(amber).monospacedDigit()
            Canvas { context, size in
                let bins = ScoreCalculator.levels(night)
                let count = max(1, min(28, bins.count))
                guard !bins.isEmpty else { return }
                for index in 0..<count {
                    let range = index * bins.count / count ..< (index + 1) * bins.count / count
                    let level = bins[range].map(\.level).max() ?? 0
                    let spacing = size.width / CGFloat(count)
                    let height = level == 0 ? 2 : size.height * CGFloat(level) / 3
                    let rect = CGRect(x: spacing * CGFloat(index), y: size.height - height, width: max(1, spacing - 2), height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(amber.opacity([0.2, 0.3, 0.6, 1][level])))
                }
            }
            .frame(height: 25)
            .accessibilityHidden(true)
        }
    }

    private var trend: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L.t("最近 7 晚")).font(.caption).foregroundStyle(ink.opacity(0.68))
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(entry.nights.prefix(7).reversed())) { night in
                    VStack(spacing: 4) {
                        Text(night.score.map(String.init) ?? "–").font(.caption2).monospacedDigit()
                        Capsule().fill(amber.opacity(0.65))
                            .frame(width: 9, height: 3 + CGFloat(night.score ?? 0) / 100 * 46)
                        Text(night.endDate.formatted(.dateTime.day())).font(.caption2).foregroundStyle(ink.opacity(0.68))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private func nightURL(_ id: String) -> URL? { URL(string: "snorelog://night/" + id) }

struct RecordingActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SnoreActivityAttributes.self) { context in
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Label(L.t("正在记录"), systemImage: "waveform").font(.headline)
                    Text(context.attributes.startedAt, style: .timer).font(.subheadline).monospacedDigit()
                }
                Spacer()
                stopButton(context.attributes.nightID)
            }
            .padding(17)
            .activityBackgroundTint(Color(red: 13 / 255, green: 17 / 255, blue: 23 / 255))
            .foregroundStyle(.white)
            .widgetURL(nightURL(context.attributes.nightID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(L.t("正在记录"), systemImage: "waveform")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    stopButton(context.attributes.nightID)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.startedAt, style: .timer).monospacedDigit()
                }
            } compactLeading: {
                Image(systemName: "waveform").foregroundStyle(.orange)
            } compactTrailing: {
                Text(context.attributes.startedAt, style: .timer).monospacedDigit().frame(width: 50)
            } minimal: {
                Image(systemName: "waveform").foregroundStyle(.orange)
            }
            .widgetURL(nightURL(context.attributes.nightID))
        }
    }

    private func stopButton(_ id: String) -> some View {
        Button(intent: StopRecordingIntent(nightID: id)) { Text(L.t("结束")).font(.footnote.weight(.semibold)) }
            .buttonStyle(.bordered)
            .tint(Color(red: 227 / 255, green: 178 / 255, blue: 106 / 255))
    }
}

@main
struct SnoreWidgets: WidgetBundle {
    var body: some Widget {
        SnoreWidget()
        RecordingActivityWidget()
    }
}
