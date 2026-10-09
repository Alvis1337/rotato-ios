import CoreGraphics
import Foundation

/// The colour that stands out in an image: hue (0–1), how vivid it is, and overall brightness.
public struct ImageColor: Codable, Hashable, Sendable {
    public var hue: Double
    public var saturation: Double
    public var brightness: Double

    /// Near-grey images sort after the colourful ones in rainbow order.
    public var isNeutral: Bool { saturation < 0.15 }

    /// Rainbow position: hue for colourful images, then greys from light to dark.
    public var rainbowKey: Double { isNeutral ? 2 - brightness : hue }
}

extension DataFiles {
    public static let colors = DataFile<[String: ImageColor]>("colors.json") { [:] }
}

public enum ColorAnalysis {
    /// Colours for each file, computing and caching new ones.
    public static func colors(of files: [URL], db: RotatoDatabase = .shared) -> [String: ImageColor] {
        var cache = db.read(DataFiles.colors)
        let missing = files.filter { cache[$0.lastPathComponent] == nil }
        if !missing.isEmpty {
            var fresh: [String: ImageColor] = [:]
            for f in missing { if let c = dominantColor(f) { fresh[f.lastPathComponent] = c } }
            db.update(DataFiles.colors) { $0.merge(fresh) { _, n in n } }
            cache.merge(fresh) { _, n in n }
        }
        return cache
    }

    /// Saturation-weighted average hue over a small downsample, so a red subject on a grey
    /// background reads as red rather than muddy pink.
    public static func dominantColor(_ url: URL) -> ImageColor? {
        guard let img = ImageLoader.thumbnail(url, maxPixel: 96) else { return nil }
        return dominantColor(img)
    }

    public static func dominantColor(_ img: CGImage) -> ImageColor? {
        let w = 24, h = 24
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sx = 0.0, sy = 0.0, wsum = 0.0, satSum = 0.0, briSum = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            let (hh, s, v) = hsv(Double(px[i]) / 255, Double(px[i + 1]) / 255, Double(px[i + 2]) / 255)
            let weight = s * s * v
            sx += cos(hh * 2 * .pi) * weight
            sy += sin(hh * 2 * .pi) * weight
            wsum += weight
            satSum += s
            briSum += v
        }
        let n = Double(w * h)
        var hue = wsum > 0 ? atan2(sy, sx) / (2 * .pi) : 0
        if hue < 0 { hue += 1 }
        return ImageColor(hue: hue, saturation: satSum / n, brightness: briSum / n)
    }

    /// Hue distance on the colour wheel, 0–0.5.
    public static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 1)
        return min(d, 1 - d)
    }

    static func hsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }
}
