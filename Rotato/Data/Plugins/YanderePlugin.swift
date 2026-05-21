import Foundation

struct YanderePlugin: SourcePlugin {
    let id = "YANDERE"
    let displayName = "Yande.re"
    let description = "yande.re · High-quality anime wallpapers · Moebooru-based board"
    let sfSymbol = "sparkles"
    let requiresApiKey = false
    let supportsSearch = true

    private static let videoExts = [".mp4", ".webm", ".mkv", ".avi", ".mov"]

    func fetch(query: String, page: Int, config: SourceConfig, nsfw: Bool) async throws -> [WallpaperItem] {
        var comps = URLComponents(string: "https://yande.re/post.json")!
        let tags = buildTags(query: query, configTags: config.tags, nsfw: nsfw)
        var items: [URLQueryItem] = [
            .init(name: "page", value: "\(page + 1)"),
            .init(name: "limit", value: "20"),
        ]
        if !tags.isEmpty { items.append(.init(name: "tags", value: tags)) }
        comps.queryItems = items

        do {
            let posts = try await URLSession.shared.decodedData([YanderePost].self,
                                                                from: browserRequest(url: comps.url!))
            return posts.compactMap { mapPost($0) }
        } catch {
            return []
        }
    }

    private func buildTags(query: String, configTags: String, nsfw: Bool) -> String {
        var parts: [String] = ["order:random"]
        if !query.isEmpty {
            parts += normalizeBooruQuery(query).split(separator: " ").map(String.init)
        }
        if !configTags.isEmpty {
            parts += configTags.split(separator: " ").map(String.init)
        }
        if !nsfw { parts.append("rating:safe") }
        return parts.joined(separator: " ")
    }

    private func mapPost(_ p: YanderePost) -> WallpaperItem? {
        guard let fileStr = p.file_url, let fileURL = URL(string: fileStr) else { return nil }
        guard !Self.videoExts.contains(where: { fileStr.lowercased().hasSuffix($0) }) else { return nil }
        let thumbStr = p.preview_url ?? p.sample_url ?? fileStr
        let thumbURL = URL(string: thumbStr) ?? fileURL
        let tags = (p.tags ?? "").split(separator: " ").prefix(40).map(String.init)
        return WallpaperItem(
            id: "YANDERE_\(p.id)",
            imageURL: fileURL,
            thumbnailURL: thumbURL,
            sourceId: id,
            tags: Array(tags),
            width: p.width ?? 0,
            height: p.height ?? 0,
            rating: mapRating(p.rating)
        )
    }

    private func mapRating(_ rating: String?) -> String {
        switch rating {
        case "s": return "safe"
        case "q": return "questionable"
        case "e": return "explicit"
        default: return rating ?? "safe"
        }
    }
}

private struct YanderePost: Decodable {
    let id: Int
    let file_url: String?
    let preview_url: String?
    let sample_url: String?
    let width: Int?
    let height: Int?
    let tags: String?
    let rating: String?
}
