import Foundation

public enum ScreenRotationTarget: String, Codable, CaseIterable, Sendable {
    case BOTH, HOME_ONLY, LOCK_ONLY

    public var label: String {
        switch self {
        case .BOTH: "Home & Lock"
        case .HOME_ONLY: "Home only"
        case .LOCK_ONLY: "Lock only"
        }
    }
}

/// Tag rules for smart collections. A wallpaper matches when it has every `requireAll` tag, at
/// least one `requireAny` tag (if any are given) and none of the `excludeAny` tags. The source
/// name counts as a tag so rules can match by source.
public struct SmartRule: Codable, Hashable, Sendable {
    public var requireAll: [String] = []
    public var requireAny: [String] = []
    public var excludeAny: [String] = []

    public init(requireAll: [String] = [], requireAny: [String] = [], excludeAny: [String] = []) {
        self.requireAll = requireAll; self.requireAny = requireAny; self.excludeAny = excludeAny
    }

    public var isEmpty: Bool { requireAll.isEmpty && requireAny.isEmpty && excludeAny.isEmpty }

    public func matches(tags: [String], source: String) -> Bool {
        // Tags are compared in one spelling so "Cat Ears" (Zerochan) matches a "cat_ears" rule.
        let entryTags = (tags + [source]).map(normalizeTag).filter { !$0.isEmpty }
        func has(_ needle: String) -> Bool { entryTags.contains { $0.contains(normalizeTag(needle)) } }
        if !requireAll.isEmpty, !requireAll.allSatisfy(has) { return false }
        if !requireAny.isEmpty, !requireAny.contains(where: has) { return false }
        if excludeAny.contains(where: has) { return false }
        return true
    }

    public func matches(_ entry: CollectionEntry) -> Bool { matches(tags: entry.tags, source: entry.source) }

    enum CodingKeys: String, CodingKey { case requireAll, requireAny, excludeAny }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requireAll = c.value(.requireAll, [])
        requireAny = c.value(.requireAny, [])
        excludeAny = c.value(.excludeAny, [])
    }
}

/// A collection of saved wallpapers (LocalList on Android).
public struct WallpaperCollection: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var createdAt: Int64
    /// When true, everything in this collection is downloaded into the rotation pool.
    public var useAsRotation: Bool
    public var rotationTarget: ScreenRotationTarget
    /// Hidden behind Face ID / passcode until unlocked this session.
    public var isLocked: Bool
    public var coverUrl: String
    /// Non-nil for smart collections, which auto-populate from saved wallpapers that match.
    public var smartRule: SmartRule?
    /// If set, this collection only rotates every N minutes regardless of the global interval.
    public var rotationIntervalMinutes: Int?
    public var lastRotationMs: Int64
    /// NSFW blur is skipped for everything in this collection.
    public var blurExempt: Bool

    public init(
        id: String = UUID().uuidString.lowercased(), name: String, createdAt: Int64 = nowMillis(),
        useAsRotation: Bool = false, rotationTarget: ScreenRotationTarget = .BOTH, isLocked: Bool = false,
        coverUrl: String = "", smartRule: SmartRule? = nil, rotationIntervalMinutes: Int? = nil,
        lastRotationMs: Int64 = 0, blurExempt: Bool = false
    ) {
        self.id = id; self.name = name; self.createdAt = createdAt; self.useAsRotation = useAsRotation
        self.rotationTarget = rotationTarget; self.isLocked = isLocked; self.coverUrl = coverUrl
        self.smartRule = smartRule; self.rotationIntervalMinutes = rotationIntervalMinutes
        self.lastRotationMs = lastRotationMs; self.blurExempt = blurExempt
    }

    public var isSmartCollection: Bool { smartRule.map { !$0.isEmpty } ?? false }

    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, useAsRotation, rotationTarget, isLocked, coverUrl, smartRule
        case rotationIntervalMinutes, lastRotationMs, blurExempt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = c.value(.createdAt, nowMillis())
        useAsRotation = c.value(.useAsRotation, false)
        rotationTarget = c.value(.rotationTarget, .BOTH)
        isLocked = c.value(.isLocked, false)
        coverUrl = c.value(.coverUrl, "")
        smartRule = c.optionalValue(.smartRule)
        rotationIntervalMinutes = c.optionalValue(.rotationIntervalMinutes)
        lastRotationMs = c.value(.lastRotationMs, 0)
        blurExempt = c.value(.blurExempt, false)
    }
}

/// A wallpaper saved to a collection (LocalWallpaperEntry on Android).
public struct CollectionEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var listId: String
    public var sourceId: String
    public var source: String
    public var thumbUrl: String
    public var sampleUrl: String
    public var fullUrl: String
    public var resolution: String
    public var pageUrl: String
    public var tags: [String]
    public var addedAt: Int64
    public var isVideo: Bool
    public var isNsfw: Bool

    public init(
        id: String = UUID().uuidString.lowercased(), listId: String, sourceId: String, source: String,
        thumbUrl: String, sampleUrl: String = "", fullUrl: String, resolution: String = "", pageUrl: String = "",
        tags: [String] = [], addedAt: Int64 = nowMillis(), isVideo: Bool = false, isNsfw: Bool = false
    ) {
        self.id = id; self.listId = listId; self.sourceId = sourceId; self.source = source
        self.thumbUrl = thumbUrl; self.sampleUrl = sampleUrl; self.fullUrl = fullUrl
        self.resolution = resolution; self.pageUrl = pageUrl; self.tags = tags; self.addedAt = addedAt
        self.isVideo = isVideo; self.isNsfw = isNsfw
    }

    public init(listId: String, wallpaper wp: Wallpaper) {
        self.init(
            listId: listId, sourceId: wp.id, source: wp.source, thumbUrl: wp.thumbUrl, sampleUrl: wp.sampleUrl,
            fullUrl: wp.fullUrl, resolution: wp.resolution, pageUrl: wp.pageUrl, tags: wp.tags,
            isVideo: wp.isVideo, isNsfw: wp.isNsfw
        )
    }

    /// Back to the Discover model, for the shared viewer.
    public var wallpaper: Wallpaper {
        Wallpaper(
            id: sourceId, source: source, thumbUrl: thumbUrl, sampleUrl: sampleUrl, fullUrl: fullUrl,
            resolution: resolution, pageUrl: pageUrl, tags: tags, isVideo: isVideo, isNsfw: isNsfw
        )
    }

    /// Device photos live in the app container ("device/<uuid>.jpg"); everything else is a URL.
    public var isDeviceImage: Bool { source == "device" }

    public var poolKey: String { RotatoKit.poolKey(source: source, sourceId: sourceId) }

    enum CodingKeys: String, CodingKey {
        case id, listId, sourceId, source, thumbUrl, sampleUrl, fullUrl, resolution, pageUrl, tags, addedAt, isVideo, isNsfw
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        listId = try c.decode(String.self, forKey: .listId)
        sourceId = try c.decode(String.self, forKey: .sourceId)
        // Deterministic fallback so an entry without an id always gets the same one.
        id = c.value(.id, "\(listId):\(sourceId)")
        source = c.value(.source, "")
        thumbUrl = c.value(.thumbUrl, "")
        sampleUrl = c.value(.sampleUrl, "")
        fullUrl = c.value(.fullUrl, "")
        resolution = c.value(.resolution, "")
        pageUrl = c.value(.pageUrl, "")
        tags = c.value(.tags, [])
        addedAt = c.value(.addedAt, nowMillis())
        isVideo = c.value(.isVideo, false)
        isNsfw = c.value(.isNsfw, false)
    }
}

private let unsafeFilenameChars = try! NSRegularExpression(pattern: "[^A-Za-z0-9._-]")

public func sanitizeFilename(_ s: String) -> String {
    let range = NSRange(s.startIndex..., in: s)
    let cleaned = unsafeFilenameChars.stringByReplacingMatches(in: s, range: range, withTemplate: "_")
    return String(cleaned.prefix(80))
}

/// File name (without extension) for an image in the rotation pool. Ids are prefixed with their
/// source so Gelbooru #12345 and Danbooru #12345 don't collide. Device images keep their plain id.
public func poolKey(source: String, sourceId: String) -> String {
    if source.isBlank || source == "device" { return sanitizeFilename(sourceId) }
    return sanitizeFilename("\(source.lowercased())_\(sourceId)")
}
