import RotatoKit
import SwiftUI

/// Each source's badge colour, as on Android.
enum SourceStyle {
    static func color(_ source: String) -> Color {
        switch source.lowercased() {
        case "wallhaven": Color(hex: 0x1565C0)
        case "konachan": Color(hex: 0x6A1B9A)
        case "danbooru": Color(hex: 0x2E7D32)
        case "rule34": Color(hex: 0xAD1457)
        case "zerochan": Color(hex: 0x00838F)
        case "gelbooru": Color(hex: 0x880E4F)
        case "safebooru": Color(hex: 0x1B5E20)
        case "reddit": Color(hex: 0xBF360C)
        case "yandere": Color(hex: 0x311B92)
        default: Color(hex: 0x37474F)
        }
    }

    static func name(_ source: String) -> String {
        source == "device" ? "Your photo" : source.prefix(1).uppercased() + source.dropFirst()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// A small rounded label.
struct InfoPill: View {
    let text: String
    var icon: String?
    var color: Color = .black.opacity(0.55)
    var bold = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .semibold)) }
            Text(text).font(.system(size: 11, weight: bold ? .bold : .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .background(color, in: Capsule())
    }
}

/// The facts about a post: source, size class, resolution, shape, video/NSFW and position.
struct ImageInfoPills: View {
    let wallpaper: Wallpaper
    var position: String?

    var body: some View {
        FlowLayout(spacing: 6) {
            InfoPill(text: SourceStyle.name(wallpaper.source), color: SourceStyle.color(wallpaper.source).opacity(0.9), bold: true)
            if let d = wallpaper.dimensions {
                InfoPill(text: sizeClass(max(d.width, d.height)), bold: true)
                InfoPill(text: "\(d.width) × \(d.height)")
                InfoPill(text: shape(Double(d.width) / Double(d.height)))
            }
            if wallpaper.isVideo { InfoPill(text: "Video", icon: "play.fill") }
            if wallpaper.isNsfw { InfoPill(text: "NSFW", color: .red.opacity(0.85)) }
            if let position { InfoPill(text: position) }
        }
    }

    private func sizeClass(_ longSide: Int) -> String {
        switch longSide {
        case 7680...: "8K"
        case 3840...: "4K"
        case 2560...: "QHD"
        case 1920...: "FHD"
        case 1280...: "HD"
        default: "Low res"
        }
    }

    private func shape(_ r: Double) -> String { r > 1.15 ? "Landscape" : r < 0.87 ? "Portrait" : "Square" }
}

/// A post's tags as one line: "absurdres · blonde hair · +24".
func tagSummary(_ tags: [String], shown: Int = 3) -> String {
    let pretty = tags.map { $0.replacingOccurrences(of: "_", with: " ") }
    let head = pretty.prefix(shown).joined(separator: " · ")
    return pretty.count > shown ? "\(head) · +\(pretty.count - shown)" : head
}
