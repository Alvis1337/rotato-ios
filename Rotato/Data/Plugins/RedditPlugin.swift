import Foundation

struct RedditPlugin: SourcePlugin {
    let id = "REDDIT"
    let displayName = "Reddit"
    let sfSymbol = "bubble.left.and.bubble.right"
    let requiresApiKey = false
    let supportsSearch = false

    func fetch(query: String, page: Int, config: SourceConfig, nsfw: Bool) async throws -> [WallpaperItem] {
        // config.extraParam holds the current subreddit; tags holds comma-separated fallback list
        let sub = config.extraParam.isEmpty ? (config.tags.isEmpty ? "wallpapers" : config.tags) : config.extraParam
        let subreddit = sub.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "r/", with: "")

        // page > 0 not natively supported without 'after' token — return empty on deep pages
        guard page == 0 else { return [] }

        var comps = URLComponents(string: "https://www.reddit.com/r/\(subreddit)/hot.json")!
        comps.queryItems = [.init(name: "limit", value: "50")]

        let request = browserRequest(url: comps.url!)
        let decoded = try await URLSession.shared.decodedData(RedditResponse.self, from: request)
        return decoded.data.children.compactMap { mapPost($0.data, subreddit: subreddit, nsfw: nsfw) }
    }

    private func mapPost(_ p: RedditPost, subreddit: String, nsfw: Bool) -> WallpaperItem? {
        guard !p.is_video,
              let hint = p.post_hint, hint == "image",
              let urlStr = p.url, urlStr.hasSuffix(".jpg") || urlStr.hasSuffix(".jpeg") || urlStr.hasSuffix(".png"),
              let imageURL = URL(string: urlStr) else { return nil }
        if p.over_18 && !nsfw { return nil }

        let thumbURL: URL
        if let preview = p.preview?.images.first?.source.url,
           let decoded = preview.replacingOccurrences(of: "&amp;", with: "&") as String?,
           let pURL = URL(string: decoded) {
            thumbURL = pURL
        } else {
            thumbURL = imageURL
        }

        let width = p.preview?.images.first?.source.width ?? 0
        let height = p.preview?.images.first?.source.height ?? 0

        return WallpaperItem(
            id: "REDDIT_\(p.id)",
            imageURL: imageURL,
            thumbnailURL: thumbURL,
            sourceId: id,
            tags: [subreddit] + (p.title.split(separator: " ").prefix(5).map(String.init)),
            width: width,
            height: height,
            rating: p.over_18 ? "explicit" : "safe"
        )
    }
}

private struct RedditResponse: Decodable {
    let data: RedditListing
}
private struct RedditListing: Decodable {
    let children: [RedditChild]
}
private struct RedditChild: Decodable {
    let data: RedditPost
}
private struct RedditPost: Decodable {
    let id: String
    let title: String
    let url: String?
    let post_hint: String?
    let is_video: Bool
    let over_18: Bool
    let preview: RedditPreview?
}
private struct RedditPreview: Decodable {
    let images: [RedditImage]
}
private struct RedditImage: Decodable {
    let source: RedditImageSource
}
private struct RedditImageSource: Decodable {
    let url: String
    let width: Int
    let height: Int
}
