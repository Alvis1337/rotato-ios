import SwiftUI

struct CachedImageView: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if isLoading {
                Rectangle()
                    .fill(Color(.systemFill))
                    .overlay(ProgressView().tint(.secondary))
            } else {
                Rectangle()
                    .fill(Color(.systemFill))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .task(id: url?.absoluteString) {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        image = nil
        guard let url else { isLoading = false; return }

        if let cached = ImageMemoryCache.shared.image(for: url) {
            image = cached
            isLoading = false
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = UIImage(data: data) {
                ImageMemoryCache.shared.set(img, for: url)
                image = img
            }
        } catch {}
        isLoading = false
    }
}

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
