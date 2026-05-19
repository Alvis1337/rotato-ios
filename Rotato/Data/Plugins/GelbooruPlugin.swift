import Foundation

struct GelbooruPlugin: SourcePlugin {
    let id = "GELBOORU"
    let displayName = "Gelbooru"
    let sfSymbol = "photo.stack"
    let requiresApiKey = false
    let supportsSearch = true

    func fetch(query: String, page: Int, config: SourceConfig, nsfw: Bool) async throws -> [WallpaperItem] {
        var comps = URLComponents(string: "https://gelbooru.com/index.php")!
        let tags = buildTags(query: query, configTags: config.tags, nsfw: nsfw)
        var items: [URLQueryItem] = [
            .init(name: "page", value: "dapi"),
            .init(name: "s", value: "post"),
            .init(name: "q", value: "index"),
            .init(name: "json", value: "1"),
            .init(name: "limit", value: "30"),
            .init(name: "pid", value: "\(page)"),
            .init(name: "tags", value: tags),
        ]
        if !config.apiKey.isEmpty { items.append(.init(name: "api_key", value: config.apiKey)) }
        if !config.apiUser.isEmpty { items.append(.init(name: "user_id", value: config.apiUser)) }
        comps.queryItems = items

        let decoded = try await URLSession.shared.decodedData(GelbooruResponse.self,
                                                              from: browserRequest(url: comps.url!))
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
        if parts.isEmpty { parts = ["wallpaper", "rating:safe"] }
        return parts.joined(separator: " ")
    }

    private func mapPost(_ p: GelbooruPost) -> WallpaperItem? {
        guard let fileStr = p.file_url, let fileURL = URL(string: fileStr) else { return nil }
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
        let tags = (p.tags ?? "").split(separator: " ").prefix(40).map(String.init)
        return WallpaperItem(
            id: "GELBOORU_\(p.id)",
            imageURL: fileURL,
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
}

private struct GelbooruPost: Decodable {
    let id: Int
    let file_url: String?
    let preview_url: String?
    let hash: String?
    let width: Int?
    let height: Int?
    let tags: String?
    let rating: String?
}
