import Foundation
import SwiftData

@Model
final class SavedCollection {
    var id: UUID
    var name: String
    var createdAt: Date
    var coverImageURL: String

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.coverImageURL = ""
    }
}

@Model
final class SavedEntry {
    var id: UUID
    var collectionId: UUID
    var imageURLString: String
    var thumbnailURLString: String
    var sourcePluginId: String
    var tags: [String]
    var width: Int
    var height: Int
    var rating: String
    var savedAt: Date

    init(collectionId: UUID, from item: WallpaperItem) {
        self.id = UUID()
        self.collectionId = collectionId
        self.imageURLString = item.imageURL.absoluteString
        self.thumbnailURLString = item.thumbnailURL.absoluteString
        self.sourcePluginId = item.sourceId
        self.tags = item.tags
        self.width = item.width
        self.height = item.height
        self.rating = item.rating
        self.savedAt = Date()
    }

    var imageURL: URL? { URL(string: imageURLString) }
    var thumbnailURL: URL? { URL(string: thumbnailURLString) }

    var resolution: String {
        width > 0 && height > 0 ? "\(width)×\(height)" : ""
    }

    var isNSFW: Bool {
        rating == "explicit" || rating == "e" || rating == "questionable" || rating == "q"
    }
}
