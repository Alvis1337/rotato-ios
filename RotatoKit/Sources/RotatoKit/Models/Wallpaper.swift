import Foundation

/// A post fetched from a source (BrainrotWallpaper on Android).
public struct Wallpaper: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var source: String
    public var thumbUrl: String
    /// Medium quality (~850px) for grid display.
    public var sampleUrl: String
    /// Original resolution for full-screen / wallpaper.
    public var fullUrl: String
    public var resolution: String
    public var pageUrl: String
    public var tags: [String]
    public var isVideo: Bool
    public var isNsfw: Bool

    public init(
        id: String, source: String, thumbUrl: String, sampleUrl: String, fullUrl: String,
        resolution: String, pageUrl: String, tags: [String], isVideo: Bool = false, isNsfw: Bool = false
    ) {
        self.id = id; self.source = source; self.thumbUrl = thumbUrl; self.sampleUrl = sampleUrl
        self.fullUrl = fullUrl; self.resolution = resolution; self.pageUrl = pageUrl; self.tags = tags
        self.isVideo = isVideo; self.isNsfw = isNsfw
    }

    /// "source:id", the identity Discover and Collections use across sources.
    public var key: String { "\(source):\(id)" }

    /// Image the Discover grid shows. Sources without a mid-size sample (Wallhaven) report the
    /// original as sampleUrl; those use the thumbnail so tiles don't pull 4K originals.
    public var gridUrl: String {
        if sampleUrl == fullUrl, !thumbUrl.isBlank, !MediaType.isVideoURL(thumbUrl) { return thumbUrl }
        return sampleUrl.ifBlank(fullUrl)
    }

    /// Image for a Discover tile in data saver mode: the small preview when there is one.
    public var dataSaverUrl: String {
        if !thumbUrl.isBlank, !MediaType.isVideoURL(thumbUrl) { return thumbUrl }
        return gridUrl
    }

    /// Small static preview, when it differs from gridUrl, to show while that loads.
    public var lowResPreviewUrl: String? {
        guard !thumbUrl.isBlank, thumbUrl != gridUrl, !MediaType.isVideoURL(thumbUrl) else { return nil }
        return thumbUrl
    }

    /// What to copy or share: the post's page when known, else the image.
    public var shareLink: String {
        if pageUrl.hasPrefix("http") { return pageUrl }
        if fullUrl.hasPrefix("http") { return fullUrl }
        return ""
    }

    /// Width and height parsed from `resolution` ("1920x1080"), or nil when unknown.
    public var dimensions: (width: Int, height: Int)? { parseResolution(resolution) }
}

func parseResolution(_ s: String) -> (width: Int, height: Int)? {
    let parts = s.lowercased().split(whereSeparator: { $0 == "x" || $0 == "×" })
        .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
    return (parts[0], parts[1])
}

/// Detects whether a post URL points to playable video rather than a static image.
public enum MediaType {
    private static let videoExts = [".mp4", ".webm", ".mkv", ".avi", ".mov", ".gifv", ".m4v"]

    public static func isVideoURL(_ url: String) -> Bool {
        if url.isBlank { return false }
        let clean = url.split(separator: "?", maxSplits: 1).first.map(String.init) ?? url
        let noFrag = (clean.split(separator: "#", maxSplits: 1).first.map(String.init) ?? clean).lowercased()
        if videoExts.contains(where: { noFrag.hasSuffix($0) }) { return true }
        // Reddit-hosted video posts (v.redd.it) often have no file extension in the URL.
        return noFrag.contains("v.redd.it")
    }
}

/// One spelling for tag comparisons. Boorus write "hatsune_miku" while Zerochan and Wallhaven
/// write "Hatsune Miku"; without this a tag blocked from one source slipped through from another.
public func normalizeTag(_ tag: String) -> String {
    tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "_")
}

extension Wallpaper {
    public func hasAnyTag(_ normalizedTags: Set<String>) -> Bool {
        !normalizedTags.isEmpty && tags.contains { normalizedTags.contains(normalizeTag($0)) }
    }
}
