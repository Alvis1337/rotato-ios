import Foundation

struct AnimePicturesPlugin: SourcePlugin {
    let id = "ANIMEPICTURES"
    let displayName = "Anime Pictures"
    let sfSymbol = "paintpalette"
    let requiresApiKey = false
    let supportsSearch = true

    func fetch(query: String, page: Int, config: SourceConfig, nsfw: Bool) async throws -> [WallpaperItem] {
        var comps = URLComponents(string: "https://anime-pictures.net/api/v3/posts")!
        let search = buildTags(query: query, configTags: config.tags)
        var items: [URLQueryItem] = [
            .init(name: "page", value: "\(page)"),
            .init(name: "posts_per_page", value: "20"),
            .init(name: "lang", value: "en"),
            .init(name: "erotics", value: nsfw ? "2" : "0"),
        ]
        if !search.isEmpty { items.append(.init(name: "search_tag", value: search)) }
        comps.queryItems = items

        do {
            let decoded = try await URLSession.shared.decodedData(AnimePicturesResponse.self,
                                                                  from: browserRequest(url: comps.url!))
            return decoded.posts.compactMap { mapPost($0) }
        } catch {
            return []
        }
    }

    private func buildTags(query: String, configTags: String) -> String {
        var parts: [String] = []
        if !query.isEmpty { parts.append(query.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if !configTags.isEmpty { parts.append(configTags.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mapPost(_ p: AnimePicturesPost) -> WallpaperItem? {
        guard let imageURL = resolveImageURL(p), let thumbURL = resolvePreviewURL(p.small_preview)
            ?? resolvePreviewURL(p.big_preview) ?? resolvePreviewURL(p.large_preview) ?? imageURL
        else { return nil }

        return WallpaperItem(
            id: "ANIMEPICTURES_\(p.id)",
            imageURL: imageURL,
            thumbnailURL: thumbURL,
            sourceId: id,
            tags: Array((p.tags ?? []).prefix(40)),
            width: p.width ?? 0,
            height: p.height ?? 0,
            rating: rating(for: p.erotics)
        )
    }

    private func resolveImageURL(_ post: AnimePicturesPost) -> URL? {
        resolvePreviewURL(post.download_url)
            ?? resolveDetailFileURL(post.file_url)
            ?? resolvePreviewURL(post.file_url)
            ?? resolvePreviewURL(post.large_preview)
            ?? resolvePreviewURL(post.big_preview)
            ?? resolvePreviewURL(post.small_preview)
    }

    private func resolvePreviewURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if let url = URL(string: value), url.scheme != nil { return url }
        return URL(string: value, relativeTo: URL(string: "https://anime-pictures.net"))?.absoluteURL
    }

    private func resolveDetailFileURL(_ value: String?) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        if value.contains("://") { return URL(string: value) }
        let path = value.hasPrefix("/") ? String(value.dropFirst()) : value
        return URL(string: "https://api.anime-pictures.net/pictures/get_image/\(path)")
    }

    private func rating(for erotics: Int?) -> String {
        switch erotics ?? 0 {
        case 0: return "safe"
        case 1: return "questionable"
        default: return "explicit"
        }
    }
}

private struct AnimePicturesResponse: Decodable {
    let posts: [AnimePicturesPost]
}

private struct AnimePicturesPost: Decodable {
    let id: Int
    let md5: String?
    let ext: String?
    let width: Int?
    let height: Int?
    let tags: [String]?
    let erotics: Int?
    let small_preview: String?
    let big_preview: String?
    let large_preview: String?
    let download_url: String?
    let file_url: String?
}
