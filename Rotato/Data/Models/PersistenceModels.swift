import Foundation
import SwiftData

enum SmartRuleType: String, Codable, CaseIterable, Identifiable {
    case tag
    case source

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tag: return "Tag"
        case .source: return "Source"
        }
    }
}

struct SmartRule: Codable, Identifiable, Hashable {
    var id = UUID()
    var type: SmartRuleType
    var value: String
    var isExclude: Bool = false
}

@Model
final class SavedCollection {
    var id: UUID
    var name: String
    var createdAt: Date
    var coverImageURL: String
    var smartRulesJSON: String = ""

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.coverImageURL = ""
        self.smartRulesJSON = ""
    }
}

extension SavedCollection {
    var smartRules: [SmartRule] {
        get {
            guard !smartRulesJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let data = smartRulesJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([SmartRule].self, from: data)
            else {
                return []
            }
            return decoded.compactMap(\.sanitized)
        }
        set {
            let cleaned = newValue.compactMap(\.sanitized)
            guard !cleaned.isEmpty,
                  let data = try? JSONEncoder().encode(cleaned),
                  let encoded = String(data: data, encoding: .utf8)
            else {
                smartRulesJSON = ""
                return
            }
            smartRulesJSON = encoded
        }
    }

    var isSmartCollection: Bool {
        !smartRules.isEmpty
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
    /// The source wallpaper ID (e.g. "DANBOORU_12345"). Used as the ratings key so
    /// ratings are consistent between History (keyed on source ID) and Collections.
    var originalItemId: String = ""

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
        self.originalItemId = item.id
    }

    init(collectionId: UUID, cloning entry: SavedEntry) {
        self.id = UUID()
        self.collectionId = collectionId
        self.imageURLString = entry.imageURLString
        self.thumbnailURLString = entry.thumbnailURLString
        self.sourcePluginId = entry.sourcePluginId
        self.tags = entry.tags
        self.width = entry.width
        self.height = entry.height
        self.rating = entry.rating
        self.savedAt = Date()
        self.originalItemId = entry.originalItemId
    }

    var imageURL: URL? { URL(string: imageURLString) }
    var thumbnailURL: URL? { URL(string: thumbnailURLString) }

    var resolution: String {
        width > 0 && height > 0 ? "\(width)×\(height)" : ""
    }

    var isNSFW: Bool {
        rating == "explicit" || rating == "e" || rating == "questionable" || rating == "q"
    }

    var dedupeKey: String {
        originalItemId.isEmpty ? imageURLString : originalItemId
    }

    var wallpaperItem: WallpaperItem? {
        guard let imageURL, let thumbnailURL else { return nil }
        let itemId = originalItemId.isEmpty ? id.uuidString : originalItemId
        return WallpaperItem(
            id: itemId,
            imageURL: imageURL,
            thumbnailURL: thumbnailURL,
            sourceId: sourcePluginId,
            tags: tags,
            width: width,
            height: height,
            rating: rating
        )
    }
}

extension Array where Element == SmartRule {
    func matches(_ entry: SavedEntry) -> Bool {
        let includeRules = compactMap(\.sanitized).filter { !$0.isExclude }
        let excludeRules = compactMap(\.sanitized).filter(\.isExclude)

        if !includeRules.allSatisfy({ $0.matches(entry) }) { return false }
        if excludeRules.contains(where: { $0.matches(entry) }) { return false }
        return true
    }
}

private extension SmartRule {
    var sanitized: SmartRule? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return SmartRule(id: id, type: type, value: trimmed, isExclude: isExclude)
    }

    func matches(_ entry: SavedEntry) -> Bool {
        switch type {
        case .tag:
            return entry.tags.contains { $0.localizedCaseInsensitiveContains(value) }
        case .source:
            return entry.sourcePluginId.compare(value, options: .caseInsensitive) == .orderedSame
        }
    }
}
