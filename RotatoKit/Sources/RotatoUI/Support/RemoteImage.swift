import CryptoKit
import Foundation
import RotatoKit
import SwiftUI

/// Loads and caches images for grids and the viewer: memory cache, then disk cache, then the
/// network with the Referer headers some booru CDNs need. Throttled hosts (429/5xx) are retried
/// once after a short pause.
public actor ImagePipeline {
    public static let shared = ImagePipeline()

    private let memory = NSCache<NSString, CGImageBox>()
    private var inFlight: [String: Task<CGImage?, Never>] = [:]

    init() { memory.countLimit = 300 }

    public func image(_ url: String, maxPixel: Int) async -> CGImage? {
        let key = "\(maxPixel)|\(url)" as NSString
        if let hit = memory.object(forKey: key) { return hit.image }
        if let running = inFlight[key as String] { return await running.value }
        let task = Task<CGImage?, Never> { await Self.load(url, maxPixel: maxPixel) }
        inFlight[key as String] = task
        let img = await task.value
        inFlight[key as String] = nil
        if let img { memory.setObject(CGImageBox(img), forKey: key) }
        return img
    }

    /// Original bytes for saving or sharing: container files directly, URLs via the disk cache.
    public func cachedData(_ url: String) async -> Data? {
        if !url.hasPrefix("http") {
            let file = url.hasPrefix("/") ? URL(fileURLWithPath: url) : RotatoPaths.container.appendingPathComponent(url)
            return try? Data(contentsOf: file)
        }
        if let d = try? Data(contentsOf: Self.diskURL(url)) { return d }
        return await Self.fetch(url)
    }

    private static func load(_ url: String, maxPixel: Int) async -> CGImage? {
        // Device photos and pool files are paths inside the container.
        if !url.hasPrefix("http") {
            let file = url.hasPrefix("/") ? URL(fileURLWithPath: url) : RotatoPaths.container.appendingPathComponent(url)
            return ImageLoader.thumbnail(file, maxPixel: maxPixel)
        }
        let disk = diskURL(url)
        if let data = try? Data(contentsOf: disk), let img = ImageLoader.thumbnail(data, maxPixel: maxPixel) { return img }
        guard let data = await fetch(url) else { return nil }
        try? data.write(to: disk, options: .atomic)
        return ImageLoader.thumbnail(data, maxPixel: maxPixel)
    }

    private static func fetch(_ url: String) async -> Data? {
        guard let req = HTTP.request(url, headers: HTTP.imageHeaders(for: url)) else { return nil }
        for attempt in 0..<2 {
            if let (data, resp) = try? await HTTP.session.data(for: req), let http = resp as? HTTPURLResponse {
                if (200..<300).contains(http.statusCode) { return data }
                guard http.statusCode == 429 || http.statusCode >= 500, attempt == 0 else { return nil }
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        return nil
    }

    static func diskURL(_ url: String) -> URL {
        let hash = SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
        return RotatoPaths.imageCache.appendingPathComponent(String(hash.prefix(32)))
    }

    /// Empties the disk cache.
    public static func clearDiskCache() {
        let dir = RotatoPaths.imageCache
        for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: f)
        }
    }
}

final class CGImageBox {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

/// An image from a URL (or container path) through ImagePipeline. Shows `placeholder`
/// (or a low-res preview) while loading.
public struct RemoteImage: View {
    let url: String
    var previewUrl: String?
    var maxPixel: Int
    var contentMode: ContentMode

    @State private var image: CGImage?
    @State private var preview: CGImage?
    @State private var failed = false

    public init(_ url: String, preview: String? = nil, maxPixel: Int = 800, contentMode: ContentMode = .fill) {
        self.url = url
        self.previewUrl = preview
        self.maxPixel = maxPixel
        self.contentMode = contentMode
    }

    public var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: contentMode)
            } else if let preview {
                Image(decorative: preview, scale: 1).resizable().aspectRatio(contentMode: contentMode).blur(radius: 6)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay {
                        if failed { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
                        else { ProgressView().controlSize(.small) }
                    }
            }
        }
        .task(id: url) {
            failed = false
            image = nil
            if let previewUrl, preview == nil {
                preview = await ImagePipeline.shared.image(previewUrl, maxPixel: 200)
            }
            image = await ImagePipeline.shared.image(url, maxPixel: maxPixel)
            failed = image == nil
        }
    }
}

/// A pool or device file shown directly.
public struct LocalImage: View {
    let file: URL
    var maxPixel: Int
    var contentMode: ContentMode

    public init(_ file: URL, maxPixel: Int = 600, contentMode: ContentMode = .fill) {
        self.file = file
        self.maxPixel = maxPixel
        self.contentMode = contentMode
    }

    public var body: some View {
        RemoteImage(file.path, maxPixel: maxPixel, contentMode: contentMode)
    }
}
