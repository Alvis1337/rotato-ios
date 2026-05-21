import Foundation

struct DanbooruPlugin: SourcePlugin {
    let id = "DANBOORU"
    let displayName = "Danbooru"
    let sfSymbol = "camera.aperture"
    let requiresApiKey = true
    let supportsSearch = true

    func fetch(query: String, page: Int, config: SourceConfig, nsfw: Bool) async throws -> [WallpaperItem] {
        var comps = URLComponents(string: "https://danbooru.donmai.us/posts.json")!
        let tags = buildTags(query: query, configTags: config.tags, nsfw: nsfw)
        comps.queryItems = [
            .init(name: "tags", value: tags),
            .init(name: "limit", value: "30"),
            .init(name: "page", value: "\(page + 1)"),
        ]
        var request = browserRequest(url: comps.url!)
        if !config.apiKey.isEmpty && !config.apiUser.isEmpty {
            let creds = "\(config.apiUser):\(config.apiKey)".data(using: .utf8)!.base64EncodedString()
            request.setValue("Basic \(creds)", forHTTPHeaderField: "Authorization")
        }
        let posts = try await URLSession.shared.decodedData([DanbooruPost].self, from: request)
        return posts.compactMap { mapPost($0) }
    }

    private func buildTags(query: String, configTags: String, nsfw: Bool) -> String {
        var parts: [String] = []
        if !query.isEmpty { parts += normalizeBooruQuery(query).split(separator: " ").map(String.init) }
        if !configTags.isEmpty { parts += configTags.split(separator: " ").map(String.init) }
        if !nsfw { parts.append("rating:general") }
        if parts.isEmpty { parts = ["rating:general"] }
        return parts.prefix(2).joined(separator: " ")  // Danbooru free tier: max 2 tags
    }

    private func mapPost(_ p: DanbooruPost) -> WallpaperItem? {
        guard let fileURL = p.fileURL else { return nil }
        let thumbURL = p.previewFileURL ?? fileURL
        let tags = (p.tag_string ?? "").split(separator: " ").prefix(40).map(String.init)
        return WallpaperItem(
            id: "DANBOORU_\(p.id)",
            imageURL: fileURL,
            thumbnailURL: thumbURL,
            sourceId: id,
            tags: Array(tags),
            width: p.image_width ?? 0,
            height: p.image_height ?? 0,
            rating: p.rating ?? "g"
        )
    }
}

private struct DanbooruPost: Decodable {
    let id: Int
    let file_url: String?
    let large_file_url: String?
    let preview_file_url: String?
    let image_width: Int?
    let image_height: Int?
    let tag_string: String?
    let rating: String?

    var fileURL: URL? {
        if let s = large_file_url ?? file_url { return URL(string: s) }
        return nil
    }
    var previewFileURL: URL? {
        if let s = preview_file_url { return URL(string: s) }
        return nil
    }
}
