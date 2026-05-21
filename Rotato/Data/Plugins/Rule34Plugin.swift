import Foundation

struct Rule34Plugin: SourcePlugin {
    let id = "RULE34"
    let displayName = "Rule34"
    let description = "Everything has rule 34 · No account needed · NSFW-only content"
    let sfSymbol = "exclamationmark.triangle"
    let requiresApiKey = false
    let supportsSearch = true

    func fetch(query: String, page: Int, config: SourceConfig, nsfw: Bool) async throws -> [WallpaperItem] {
        var comps = URLComponents(string: "https://api.rule34.xxx/index.php")!
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
        let posts = try await URLSession.shared.decodedData([Rule34Post].self,
                                                            from: browserRequest(url: comps.url!))
        return posts.compactMap { mapPost($0) }
    }

    private func buildTags(query: String, configTags: String) -> String {
        var parts: [String] = []
        if !query.isEmpty { parts += normalizeBooruQuery(query).split(separator: " ").map(String.init) }
        if !configTags.isEmpty { parts += configTags.split(separator: " ").map(String.init) }
        if parts.isEmpty { parts = ["wallpaper"] }
        return parts.joined(separator: " ")
    }

    private func mapPost(_ p: Rule34Post) -> WallpaperItem? {
        guard let fileStr = p.file_url, let fileURL = URL(string: fileStr) else { return nil }
        let thumbStr = p.preview_url ?? fileStr
        let thumbURL = URL(string: thumbStr) ?? fileURL
        let tags = (p.tags ?? "").split(separator: " ").prefix(40).map(String.init)
        return WallpaperItem(
            id: "RULE34_\(p.id)",
            imageURL: fileURL,
            thumbnailURL: thumbURL,
            sourceId: id,
            tags: Array(tags),
            width: p.width ?? 0,
            height: p.height ?? 0,
            rating: "explicit"
        )
    }
}

private struct Rule34Post: Decodable {
    let id: Int
    let file_url: String?
    let preview_url: String?
    let width: Int?
    let height: Int?
    let tags: String?
}
