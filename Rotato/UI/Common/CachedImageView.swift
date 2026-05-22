import SwiftUI

struct CachedImageView: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var shimmerPhase: CGFloat = -1.0

    var body: some View {
        ZStack {
            contentMode == .fill ? Color(.systemFill) : Color.clear
            if let image {
                if contentMode == .fill {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            } else if isLoading {
                if contentMode == .fill { shimmerView }
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .clipped()
        .task(id: url?.absoluteString) {
            await load()
        }
    }

    private var shimmerView: some View {
        Rectangle()
            .fill(Color(.systemFill))
            .overlay(
                LinearGradient(
                    colors: [
                        Color(.systemFill),
                        Color(.systemBackground).opacity(0.55),
                        Color(.systemFill)
                    ],
                    startPoint: UnitPoint(x: shimmerPhase, y: 0.5),
                    endPoint: UnitPoint(x: shimmerPhase + 0.6, y: 0.5)
                )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    shimmerPhase = 1.6
                }
            }
    }

    private func load() async {
        isLoading = true
        image = nil
        guard let url else { isLoading = false; return }
        let loadingURL = url

        // 1. Memory cache
        if let cached = ImageMemoryCache.shared.image(for: url) {
            image = cached
            isLoading = false
            return
        }

        // 2. Disk cache
        if let diskImg = DiskImageCache.shared.image(for: url) {
            ImageMemoryCache.shared.set(diskImg, for: url)
            image = diskImg
            isLoading = false
            return
        }

        // 3. Network
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Guard: task cancelled or the view has already moved to a different URL
            guard !Task.isCancelled, self.url == loadingURL else {
                isLoading = false
                return
            }
            if let img = UIImage(data: data) {
                ImageMemoryCache.shared.set(img, for: url)
                DiskImageCache.shared.set(data, for: url)
                image = img
            }
        } catch {}
        isLoading = false
    }
}

// MARK: - Memory cache

final class ImageMemoryCache: @unchecked Sendable {
    static let shared = ImageMemoryCache()
    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 100 * 1024 * 1024  // 100 MB
    }

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func set(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

// MARK: - Disk cache

final class DiskImageCache: @unchecked Sendable {
    static let shared = DiskImageCache()
    private let cacheDir: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = caches.appendingPathComponent("RotatoImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    private func key(for url: URL) -> String {
        // Simple hex hash of the URL string to avoid filesystem unsafe chars
        let str = url.absoluteString
        var hash: UInt64 = 14695981039346656037
        for byte in str.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }

    func image(for url: URL) -> UIImage? {
        let file = cacheDir.appendingPathComponent(key(for: url))
        guard let data = try? Data(contentsOf: file) else { return nil }
        return UIImage(data: data)
    }

    func set(_ data: Data, for url: URL) {
        let file = cacheDir.appendingPathComponent(key(for: url))
        try? data.write(to: file, options: .atomic)
    }
}
