import Foundation

struct WallpaperItem: Identifiable, Hashable, Sendable {
    let id: String
    let imageURL: URL
    let thumbnailURL: URL
    let sourceId: String
    let tags: [String]
    let width: Int
    let height: Int
    let rating: String

    var resolution: String {
        width > 0 && height > 0 ? "\(width)×\(height)" : ""
    }

    var aspectRatio: CGFloat {
        guard height > 0, width > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }

    var isNSFW: Bool {
        rating == "explicit" || rating == "e" || rating == "questionable" || rating == "q"
    }
}
