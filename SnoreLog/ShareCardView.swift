import CoreImage.CIFilterBuiltins
import Photos
import SwiftUI
import UIKit

struct ShareCardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var files: ShareFiles?
    @State private var status: String?
    let nightID: UUID

    var body: some View {
        NavigationStack {
            if let night = model.nights.first(where: { $0.id == nightID }) {
                ScrollView {
                    VStack(spacing: 15) {
                        GeometryReader { bounds in
                            ShareArtwork(night: night, headline: headline(night), qr: qr)
                                .frame(width: 360, height: 450)
                                .scaleEffect(bounds.size.width / 360, anchor: .topLeading)
                        }
                        .aspectRatio(0.8, contentMode: .fit)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L.t("鼾声分享卡"))
                        .accessibilityIdentifier("shareCard")

                        Button(L.t("分享图片")) { share(night) }
                            .buttonStyle(PrimaryAction())
                            .accessibilityIdentifier("shareImage")
                        HStack(spacing: 15) {
                            Button(L.t("保存图片")) { Task { await save(night) } }
                            Button(L.t("复制话题文案")) {
                                UIPasteboard.general.string = ShareText.text(night)
                                status = L.t("已复制话题文案")
                            }
                        }
                        .font(.footnote.weight(.medium))
                        if let status { Text(status).font(.footnote).foregroundStyle(Palette.secondary) }
                    }
                    .frame(maxWidth: 400)
                    .padding(19)
                    .frame(maxWidth: .infinity)
                }
                .background(Palette.background.ignoresSafeArea())
                .navigationTitle(L.t("鼾声分享卡"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L.t("关闭")) { dismiss() } } }
                .sheet(item: $files) { ActivitySheet(files: $0) }
            }
        }
    }

    private var qr: UIImage? {
        let demoURL = URL(string: "https://apps.apple.com/app-store/")
        guard let url = ShareText.storeURL ?? (Launch.isolated ? demoURL : nil) else { return nil }
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(url.absoluteString.utf8)
        generator.correctionLevel = "M"
        guard let image = generator.outputImage,
              let cg = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(image, from: image.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func headline(_ night: Night) -> String {
        model.shareTitleOverride ?? NightInsights.shareHeadline(night, nights: model.nights) ?? L.t("记下每一晚，听见自己的变化")
    }

    private func render(_ night: Night) -> Data? {
        let renderer = ImageRenderer(content: ShareArtwork(night: night, headline: headline(night), qr: qr)
            .frame(width: 360, height: 450)
            .environment(\.colorScheme, .dark)
            .environment(\.dynamicTypeSize, .large))
        renderer.scale = 3
        renderer.isOpaque = true
        return renderer.uiImage?.pngData()
    }

    private func share(_ night: Night) {
        do {
            guard let data = render(night) else { throw RecordingError.noInput }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SnoreLog-card-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("Snore-Log.png")
            try data.write(to: url, options: .atomic)
            files = ShareFiles(urls: [url])
        } catch { status = L.t("暂时无法生成图片") }
    }

    private func save(_ night: Night) async {
        guard let data = render(night) else { status = L.t("暂时无法生成图片"); return }
        let allowed = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard allowed == .authorized || allowed == .limited else {
            status = L.t("可以在系统分享菜单中保存图片")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            status = L.t("已保存到照片")
        } catch {
            status = L.t("暂时无法保存图片")
        }
    }
}

private struct ShareArtwork: View {
    let night: Night
    let headline: String
    let qr: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L.date(night.endDate))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.dim)
            HStack(alignment: .lastTextBaseline, spacing: 11) {
                Text(night.score.map(String.init) ?? "–")
                    .font(.system(size: 91, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Palette.moon)
                Text(L.t("鼾声分数"))
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.pale)
            }
            .padding(.top, 12)
            Text(headline)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Palette.pale)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .padding(.top, 8)
            Waveform(bins: ScoreCalculator.levels(night), bars: 65, accent: Palette.moon, interrupted: Palette.dim)
                .frame(height: 59)
                .padding(.top, 27)
            Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("鼾声记录")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.pale)
                    Text(L.t("录音只保存在自己的手机上")).font(.system(size: 11)).foregroundStyle(Palette.dim)
                }
                Spacer()
                if let qr {
                    Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                        .frame(width: 52, height: 52)
                        .padding(7)
                        .background(.white, in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Palette.night)
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Color.white.opacity(0.12)))
        .clipShape(RoundedRectangle(cornerRadius: 17))
    }
}
