import Foundation

struct SafebooruPlugin: SourcePlugin {
    let id = "SAFEBOORU"
    let displayName = "Safebooru"
    let description = "safebooru.org · Safe-for-work imageboard · All content is SFW"
    let sfSymbol = "shield.lefthalf.filled"
    let requiresApiKey = false
    let supportsSearch = true

    func fetch(query: String, page: Int, config: SourceConfig, nsfw: Bool) async throws -> [WallpaperItem] {
        var comps = URLComponents(string: "https://safebooru.org/index.php")!
        let tags = buildTags(query: query, configTags: config.tags)
        comps.queryItems = [
            .init(name: "page", value: "dapi"),
            .init(name: "s", value: "post"),
            .init(name: "q", value: "index"),
            .init(name: "json", value: "1"),
            .init(name: "limit", value: "30"),
            .init(name: "pid", value: "\(page)"),
            .init(name: "tags", value: tags),
        ]
        let posts = try await URLSession.shared.decodedData([SafebooruPost].self,
                                                            from: browserRequest(url: comps.url!))
        return posts.compactMap { mapPost($0) }
    }

    private func buildTags(query: String, configTags: String) -> String {
        var parts: [String] = []
        if !query.isEmpty { parts += normalizeBooruQuery(query).split(separator: " ").map(String.init) }
        if !configTags.isEmpty { parts += configTags.split(separator: " ").map(String.init) }
        return parts.joined(separator: " ")
    }

    private func mapPost(_ p: SafebooruPost) -> WallpaperItem? {
        // Skip video posts
        let videoExts = [".mp4", ".webm", ".mkv", ".gif"]
        guard !videoExts.contains(where: { p.image.lowercased().hasSuffix($0) }) else { return nil }
        let fullURLStr = "https://safebooru.org/images/\(p.directory)/\(p.image)"
        guard let fullURL = URL(string: fullURLStr) else { return nil }
        let thumbURL = p.preview_url.flatMap { URL(string: $0) }
            ?? p.sample_url.flatMap { URL(string: $0) }
            ?? fullURL
        let tags = p.tags.split(separator: " ").prefix(40).map(String.init)
        return WallpaperItem(
            id: "SAFEBOORU_\(p.id)",
            imageURL: fullURL,
            thumbnailURL: thumbURL,
            sourceId: id,
            tags: Array(tags),
            width: p.width ?? 0,
            height: p.height ?? 0,
            rating: "safe"
        )
    }
}

private struct SafebooruPost: Decodable {
    let id: Int
    let directory: String
    let image: String
    let preview_url: String?
    let sample_url: String?
    let width: Int?
    let height: Int?
    let tags: String
}
