import Foundation

struct GelbooruPlugin: SourcePlugin {
    let id = "GELBOORU"
    let displayName = "Gelbooru"
    let description = "General-purpose imageboard · API key unlocks higher rate limits & NSFW"
    let sfSymbol = "photo.stack"
    let requiresApiKey = true
    let requiresApiUser = true
    let supportsSearch = true

    private static let videoExts = [".mp4", ".webm", ".mkv", ".avi", ".mov"]

    func fetch(query: String, page: Int, config: SourceConfig, nsfw: Bool) async throws -> [WallpaperItem] {
        let tags = buildTags(query: query, configTags: config.tags, nsfw: nsfw)
        let authItems: [URLQueryItem] = [
            config.apiKey.isEmpty ? nil : URLQueryItem(name: "api_key", value: config.apiKey),
            config.apiUser.isEmpty ? nil : URLQueryItem(name: "user_id", value: config.apiUser),
        ].compactMap { $0 }

        func makeRequest(pid: Int) -> URLRequest {
            var comps = URLComponents(string: "https://gelbooru.com/index.php")!
            comps.queryItems = [
                .init(name: "page", value: "dapi"),
                .init(name: "s", value: "post"),
                .init(name: "q", value: "index"),
                .init(name: "json", value: "1"),
                .init(name: "limit", value: "30"),
                .init(name: "pid", value: "\(pid)"),
                .init(name: "tags", value: tags),
            ] + authItems
            return browserRequest(url: comps.url!)
        }

        // For page == 0, fetch page 0 to discover total count then pick a safe random pid.
        // For page > 0, skip the count-discovery request and use the page directly.
        let decoded: GelbooruResponse
        if page == 0 {
            let page0 = try await URLSession.shared.decodedData(GelbooruResponse.self, from: makeRequest(pid: 0))
            let count = page0.attributes?.count ?? 0
            let limit = 30
            let maxPid = max(0, min((count - 1) / limit, 100))
            let safePid = Int.random(in: 0...maxPid)
            if safePid == 0 {
                decoded = page0
            } else {
                decoded = try await URLSession.shared.decodedData(GelbooruResponse.self, from: makeRequest(pid: safePid))
            }
        } else {
            decoded = try await URLSession.shared.decodedData(GelbooruResponse.self, from: makeRequest(pid: min(page, 100)))
        }
        return (decoded.post ?? []).compactMap { mapPost($0) }
    }

    private func buildTags(query: String, configTags: String, nsfw: Bool) -> String {
        var parts: [String] = []
        if !query.isEmpty {
            parts += normalizeBooruQuery(query).split(separator: " ").map(String.init)
        }
        if !configTags.isEmpty {
            parts += configTags.split(separator: " ").map(String.init)
        }
        if !nsfw { parts.append("rating:safe") }
        if parts.isEmpty { parts = nsfw ? ["wallpaper"] : ["wallpaper", "rating:safe"] }
        return parts.joined(separator: " ")
    }

    private func mapPost(_ p: GelbooruPost) -> WallpaperItem? {
        guard let fileStr = p.file_url, let fileURL = URL(string: fileStr) else { return nil }
        // Skip video posts — can't display mp4/webm in a wallpaper grid
        guard !Self.videoExts.contains(where: { fileStr.lowercased().hasSuffix($0) }) else { return nil }
        // Use preview_url when available; reconstruct from hash/directory otherwise
        let thumbURL: URL
        if let preview = p.preview_url, let pURL = URL(string: preview) {
            thumbURL = pURL
        } else if let hash = p.hash, hash.count >= 4 {
            let d1 = String(hash.prefix(2))
            let d2 = String(hash.dropFirst(2).prefix(2))
            thumbURL = URL(string: "https://gelbooru.com/thumbnails/\(d1)/\(d2)/thumbnail_\(hash).jpg") ?? fileURL
        } else {
            thumbURL = fileURL
        }
        let sampleURL = p.sample_url.flatMap { URL(string: $0) } ?? fileURL
        let tags = (p.tags ?? "").split(separator: " ").prefix(40).map(String.init)
        return WallpaperItem(
            id: "GELBOORU_\(p.id)",
            imageURL: sampleURL,
            thumbnailURL: thumbURL,
            sourceId: id,
            tags: Array(tags),
            width: p.width ?? 0,
            height: p.height ?? 0,
            rating: p.rating ?? "safe"
        )
    }
}

private struct GelbooruResponse: Decodable {
    let post: [GelbooruPost]?
    let attributes: GelbooruAttributes?

    private enum CodingKeys: String, CodingKey {
        case post
        case attributes = "@attributes"
    }
}

private struct GelbooruAttributes: Decodable {
    let count: Int?
}

private struct GelbooruPost: Decodable {
    let id: Int
    let file_url: String?
    let sample_url: String?
    let preview_url: String?
    let hash: String?
    let width: Int?
    let height: Int?
    let tags: String?
    let rating: String?
}
