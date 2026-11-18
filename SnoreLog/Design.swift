import SwiftUI
import UIKit

enum Palette {
    static let night = color(0x0D1117)
    static let nightCard = color(0x161B24)
    static let moon = color(0xE3B26A)
    static let pale = color(0xE8E6E1)
    static let dim = color(0x8B93A1)

    static let background = adaptive(light: 0xF6F4EF, dark: 0x0D1117)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x161B24)
    static let ink = adaptive(light: 0x24201D, dark: 0xE8E6E1)
    static let secondary = adaptive(light: 0x686158, dark: 0x8B93A1)
    static let line = adaptive(light: 0xDED8CE, dark: 0x262D39)
    static let accent = adaptive(light: 0x97601B, dark: 0xE3B26A)
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x20190F)

    static func color(_ hex: Int) -> Color { Color(uiColor: uiColor(hex)) }
    private static func adaptive(light: Int, dark: Int) -> Color {
        Color(uiColor: UIColor { uiColor($0.userInterfaceStyle == .dark ? dark : light) })
    }
    private static func uiColor(_ hex: Int) -> UIColor {
        UIColor(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
                blue: Double(hex & 255) / 255, alpha: 1)
    }
}

extension View {
    func nightCard(_ inset: CGFloat = 16) -> some View {
        padding(inset).background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
    }
}

struct PageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.largeTitle.bold()).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Palette.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Waveform: View {
    let bins: [MinuteBin]
    var bars: Int?
    var accent = Palette.accent
    var interrupted = Palette.secondary
    var selection: Double?

    var body: some View {
        Canvas { context, size in
            guard !bins.isEmpty else { return }
            let count = min(bins.count, bars ?? bins.count)
            let spacing = size.width / CGFloat(count)
            let width = max(0.45, min(4, spacing * 0.64))
            for index in 0..<count {
                let start = index * bins.count / count
                let end = (index + 1) * bins.count / count
                let group = bins[start..<end]
                let level = min(3, max(0, group.map(\.level).max() ?? 0))
                let hasGap = group.contains(where: \.interrupted)
                let barHeight = hasGap ? size.height * 0.3 : [min(3, size.height), size.height * 0.43,
                    size.height * 0.71, size.height][level]
                let rect = CGRect(x: spacing * CGFloat(index) + (spacing - width) / 2,
                                  y: size.height - barHeight, width: width, height: barHeight)
                let color = hasGap ? interrupted.opacity(0.68) : accent.opacity([0.19, 0.30, 0.60, 1][level])
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(color))
            }
            if let selection {
                let x = min(size.width - 1, max(1, size.width * selection))
                let rect = CGRect(x: x - 1, y: 0, width: 2, height: size.height)
                context.fill(Path(rect), with: .color(accent))
            }
        }
        .accessibilityHidden(true)
    }
}

struct PrimaryAction: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(Palette.onAccent)
            .background(Palette.accent.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct ActivitySheet: UIViewControllerRepresentable {
    let files: ShareFiles
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: files.urls, applicationActivities: nil)
        if files.removeParentWhenFinished, let folder = files.urls.first?.deletingLastPathComponent() {
            controller.completionWithItemsHandler = { _, _, _, _ in
                try? FileManager.default.removeItem(at: folder)
            }
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
