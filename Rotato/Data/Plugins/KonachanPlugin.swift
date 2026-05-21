import Foundation

struct KonachanPlugin: SourcePlugin {
    let id = "KONACHAN"
    let displayName = "Konachan"
    let description = "High-res anime wallpapers · SFW on konachan.com · NSFW on konachan.net"
    let sfSymbol = "wand.and.sparkles"
    let requiresApiKey = false
    let supportsSearch = true

    func fetch(query: String, page: Int, config: SourceConfig, nsfw: Bool) async throws -> [WallpaperItem] {
        let baseURL = nsfw ? "https://konachan.net/post.json" : "https://konachan.com/post.json"
        var comps = URLComponents(string: baseURL)!
        let tags = buildTags(query: query, configTags: config.tags)
        var items: [URLQueryItem] = [
            .init(name: "page", value: "\(page + 1)"),
            .init(name: "limit", value: "20"),
        ]
        if !tags.isEmpty { items.append(.init(name: "tags", value: tags)) }
        comps.queryItems = items

        do {
            let posts = try await URLSession.shared.decodedData([KonachanPost].self,
                                                                from: browserRequest(url: comps.url!))
            return posts.compactMap { mapPost($0) }
        } catch {
            return []
        }
    }

    private func buildTags(query: String, configTags: String) -> String {
        var parts: [String] = []
        if !query.isEmpty {
            parts += normalizeBooruQuery(query).split(separator: " ").map(String.init)
        }
        if !configTags.isEmpty {
            parts += configTags.split(separator: " ").map(String.init)
        }
        return parts.joined(separator: " ")
    }

    private func mapPost(_ p: KonachanPost) -> WallpaperItem? {
        guard let fileStr = p.file_url, let fileURL = URL(string: fileStr) else { return nil }
        let thumbStr = p.preview_url ?? p.sample_url ?? fileStr
        let thumbURL = URL(string: thumbStr) ?? fileURL
        let tags = (p.tags ?? "").split(separator: " ").prefix(40).map(String.init)
        return WallpaperItem(
            id: "KONACHAN_\(p.id)",
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

private struct KonachanPost: Decodable {
    let id: Int
    let file_url: String?
    let preview_url: String?
    let sample_url: String?
    let width: Int?
    let height: Int?
    let tags: String?
    let rating: String?
}
