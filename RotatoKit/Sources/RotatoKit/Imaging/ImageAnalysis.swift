import CoreGraphics
import Foundation
import ImageIO

extension DataFiles {
    /// Cached average brightness (0–1) by pool file name.
    public static let looks = DataFile<[String: Double]>("looks.json") { [:] }
}

public enum ImageAnalysis {
    public static let darkThreshold = 0.35

    /// Brightness for each file, computing and caching the ones not seen before.
    public static func brightness(of files: [URL], db: RotatoDatabase = .shared) -> [String: Double] {
        var cache = db.read(DataFiles.looks)
        let missing = files.filter { cache[$0.lastPathComponent] == nil }
        if !missing.isEmpty {
            var fresh: [String: Double] = [:]
            for f in missing { if let b = averageBrightness(f) { fresh[f.lastPathComponent] = b } }
            let names = Set(files.map(\.lastPathComponent))
            db.update(DataFiles.looks) { c in
                c.merge(fresh) { _, n in n }
                // Forget files that left the pool.
                if c.count > names.count * 2 { c = c.filter { names.contains($0.key) } }
            }
            cache.merge(fresh) { _, n in n }
        }
        return cache
    }

    /// Mean luminance from a tiny downsample.
    public static func averageBrightness(_ url: URL) -> Double? {
        guard let img = ImageLoader.thumbnail(url, maxPixel: 64) else { return nil }
        let w = 16, h = 16
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var total = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            total += 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])
        }
        return total / Double(w * h) / 255
    }
}

public enum ImageLoader {
    /// Decodes a downsampled image without loading the full bitmap.
    public static func thumbnail(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return thumbnail(src, maxPixel: maxPixel)
    }

    public static func thumbnail(_ data: Data, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return thumbnail(src, maxPixel: maxPixel)
    }

    static func thumbnail(_ src: CGImageSource, maxPixel: Int) -> CGImage? {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// Pixel size without decoding.
    public static func pixelSize(_ url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
    }
}
