import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Turns a pool image into a screen-sized wallpaper: smart crop around the subject, gentle
/// enlarging of small images, and the home screen blur/dim effects. The result is what the
/// Shortcuts action returns for "Set Wallpaper".
public enum WallpaperRenderer {
    /// Fallback when the app hasn't recorded the screen yet (iPhone 15/16 size).
    public static let defaultScreen = CGSize(width: 1179, height: 2556)

    public static func screenSize(_ settings: RotatoSettings) -> CGSize {
        let f = settings.filters
        guard f.phoneScreenWidth > 0, f.phoneScreenHeight > 0 else { return defaultScreen }
        return CGSize(width: f.phoneScreenWidth, height: f.phoneScreenHeight)
    }

    /// Renders `file` for `screen` and writes a JPEG into the Rendered folder. Returns its URL.
    public static func render(_ file: URL, for screen: WallpaperScreen, settings: RotatoSettings) throws -> URL {
        let target = screenSize(settings)
        guard let image = ImageLoader.thumbnail(file, maxPixel: Int(max(target.width, target.height) * 1.5)) else {
            throw RotationFailure.unreadable(file.lastPathComponent)
        }
        let framed = frame(image, to: target, fit: settings.wallpaperFit, screen: screen)
        let effects = settings.wallpaperEffects
        let applyEffects = !effects.isNone && (screen == .home || effects.onLockScreen)
        let final = applyEffects ? (applyingEffects(framed, effects) ?? framed) : framed
        let out = RotatoPaths.rendered.appendingPathComponent("\(screen.rawValue).jpg")
        try writeJPEG(final, to: out)
        return out
    }

    /// Crops or letterboxes `image` to exactly `size` pixels.
    public static func frame(_ image: CGImage, to size: CGSize, fit: WallpaperFit, screen: WallpaperScreen) -> CGImage {
        let w = Int(size.width), h = Int(size.height)
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }
        ctx.interpolationQuality = .high
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        switch fit {
        case .FIT:
            // Letterbox on a blurred, darkened fill of the same image.
            let fillScale = max(size.width / iw, size.height / ih)
            let fillRect = CGRect(x: (size.width - iw * fillScale) / 2, y: (size.height - ih * fillScale) / 2, width: iw * fillScale, height: ih * fillScale)
            if let blurred = applyingEffects(image, WallpaperEffects(blur: 2, dimPercent: 40)) { ctx.draw(blurred, in: fillRect) }
            let s = min(size.width / iw, size.height / ih)
            ctx.draw(image, in: CGRect(x: (size.width - iw * s) / 2, y: (size.height - ih * s) / 2, width: iw * s, height: ih * s))
        case .FILL, .SMART:
            let s = max(size.width / iw, size.height / ih)
            let dw = iw * s, dh = ih * s
            var cx = 0.5, cy = 0.5
            if fit == .SMART, let focus = subjectCenter(image) {
                cx = focus.x
                // Keep the subject clear of the lock screen clock: aim it a little lower.
                cy = screen == .lock ? min(focus.y + 0.08, 1) : focus.y
            }
            // cx/cy are in top-left-origin unit coordinates of the image.
            let ox = clamp(size.width / 2 - cx * dw, min: size.width - dw, max: 0)
            let oyTop = clamp(size.height / 2 - cy * dh, min: size.height - dh, max: 0)
            // CGContext's origin is bottom-left.
            let oy = size.height - dh - oyTop
            ctx.draw(image, in: CGRect(x: ox, y: oy, width: dw, height: dh))
        }
        return ctx.makeImage() ?? image
    }

    /// Centre of the most eye-catching region, in top-left-origin unit coordinates.
    public static func subjectCenter(_ image: CGImage) -> CGPoint? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let obs = request.results?.first,
              let objects = obs.salientObjects, !objects.isEmpty else { return nil }
        // Union of the salient boxes, weighted toward the most confident.
        let best = objects.max { $0.confidence < $1.confidence } ?? objects[0]
        let box = best.boundingBox // normalized, bottom-left origin
        return CGPoint(x: box.midX, y: 1 - box.midY)
    }

    static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Blur (0/1/2) and dim baked into the image.
    public static func applyingEffects(_ image: CGImage, _ effects: WallpaperEffects) -> CGImage? {
        var ci = CIImage(cgImage: image)
        let extent = ci.extent
        if effects.blur > 0 {
            let radius = Double(max(image.width, image.height)) * (effects.blur == 1 ? 0.006 : 0.016)
            ci = ci.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: extent)
        }
        if effects.dimPercent > 0 {
            let k = 1 - Double(effects.dimPercent) / 100
            ci = ci.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0),
            ])
        }
        return ciContext.createCGImage(ci, from: extent)
    }

    public static func writeJPEG(_ image: CGImage, to url: URL, quality: Double = 0.92) throws {
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).part")
        guard let dest = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw RotationFailure.unreadable(url.lastPathComponent)
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw RotationFailure.unreadable(url.lastPathComponent) }
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: tmp, to: url)
    }

    private static func clamp(_ v: CGFloat, min lo: CGFloat, max hi: CGFloat) -> CGFloat { Swift.min(Swift.max(v, lo), hi) }
}

/// The whole "next wallpaper" step, for Shortcuts and the in-app "Set now".
public enum WallpaperService {
    /// Syncs a few missing rotation images (bounded so Shortcuts doesn't time out), picks the
    /// next wallpaper for `screen` and renders it.
    public static func nextWallpaper(for screen: WallpaperScreen, automatic: Bool, db: RotatoDatabase = .shared) async throws -> (rendered: URL, pick: RotationPick) {
        let pool = RotationPool(db: db)
        if pool.files().isEmpty {
            await pool.syncRotationCollections(limit: 3)
        } else {
            // Keep the pool topping up in the background of each run, without delaying it much.
            _ = await withTaskGroup(of: Void.self) { g in
                g.addTask { await pool.syncRotationCollections(limit: 2) }
                g.addTask { try? await Task.sleep(nanoseconds: 4_000_000_000) }
                await g.next()
                g.cancelAll()
            }
        }
        let engine = RotationEngine(db: db)
        let pick = try engine.next(for: screen, automatic: automatic)
        let settings = db.read(DataFiles.settings)
        do {
            let url = try WallpaperRenderer.render(pick.file, for: screen, settings: settings)
            // The widget shows the home screen wallpaper.
            if screen == .home { try? WidgetSnapshot.write(from: pick.file) }
            return (url, pick)
        } catch {
            db.update(DataFiles.state) { $0.addError(RotationError(.RENDER_FAILED, "Couldn't prepare \(pick.file.lastPathComponent)")) }
            throw error
        }
    }
}

/// A small copy of the current wallpaper for the widget to show.
public enum WidgetSnapshot {
    public static var url: URL { RotatoPaths.rendered.appendingPathComponent("widget.jpg") }

    public static func write(from file: URL) throws {
        guard let img = ImageLoader.thumbnail(file, maxPixel: 800) else { return }
        try WallpaperRenderer.writeJPEG(img, to: url, quality: 0.8)
    }
}
