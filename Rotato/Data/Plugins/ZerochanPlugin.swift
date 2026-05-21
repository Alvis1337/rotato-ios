import Foundation

struct ZerochanPlugin: SourcePlugin {
    let id = "ZEROCHAN"
    let displayName = "Zerochan"
    let description = "zerochan.net · Anime art aggregator · Clean, curated images"
    let sfSymbol = "star.circle"
    let requiresApiKey = false
    let supportsSearch = true

    func fetch(query: String, page: Int, config: SourceConfig, nsfw: Bool) async throws -> [WallpaperItem] {
        var comps = URLComponents(string: "https://www.zerochan.net/")!
        let search = buildQuery(query: query, configTags: config.tags, nsfw: nsfw)
        comps.queryItems = [
            .init(name: "json", value: nil),
            .init(name: "l", value: "20"),
            .init(name: "p", value: "\(page + 1)"),
            .init(name: "t", value: "0"),
            .init(name: "strict", value: "0"),
            .init(name: "q", value: search),
        ]

        var request = browserRequest(url: comps.url!)
        request.setValue("https://www.zerochan.net/", forHTTPHeaderField: "Referer")

        do {
            let decoded = try await URLSession.shared.decodedData(ZerochanResponse.self, from: request)
            return await fetchDetails(for: decoded.items)
        } catch {
            return []
        }
    }

    private func buildQuery(query: String, configTags: String, nsfw: Bool) -> String {
        var parts: [String] = []
        if !query.isEmpty { parts.append(query.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if !configTags.isEmpty { parts.append(configTags.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if !nsfw {
            // Zerochan is overwhelmingly SFW; avoid adding an unsupported rating filter.
        }
        let search = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty ? "wallpaper" : search
    }

    private func fetchDetails(for items: [ZerochanItem]) async -> [WallpaperItem] {
        await withTaskGroup(of: WallpaperItem?.self, returning: [WallpaperItem].self) { group in
            for item in items {
                group.addTask { await mapItem(item) }
            }

            var wallpapers: [WallpaperItem] = []
            for await wallpaper in group {
                if let wallpaper { wallpapers.append(wallpaper) }
            }
            return wallpapers
        }
    }

    private func mapItem(_ item: ZerochanItem) async -> WallpaperItem? {
        if let imageURL = item.imageURL {
            let thumbURL = item.thumbnailURL ?? imageURL
            return buildWallpaper(item, imageURL: imageURL, thumbnailURL: thumbURL, tags: item.allTags)
        }

        let detail = await fetchDetail(id: item.id)
        let imageURL = detail?.imageURL ?? item.thumbnailURL
        let thumbURL = item.thumbnailURL ?? detail?.thumbnailURL ?? imageURL
        guard let imageURL, let thumbURL else { return nil }

        let tags = detail?.allTags.isEmpty == false ? detail?.allTags ?? [] : item.allTags
        if let detail {
            return buildWallpaper(detail, imageURL: imageURL, thumbnailURL: thumbURL, tags: tags)
        }
        return buildWallpaper(item, imageURL: imageURL, thumbnailURL: thumbURL, tags: tags)
    }

    private func buildWallpaper(_ item: any ZerochanImage, imageURL: URL, thumbnailURL: URL, tags: [String]) -> WallpaperItem {
        WallpaperItem(
            id: "ZEROCHAN_\(item.id)",
            imageURL: imageURL,
            thumbnailURL: thumbnailURL,
            sourceId: id,
            tags: Array(tags.prefix(40)),
            width: item.width ?? 0,
            height: item.height ?? 0,
            rating: "safe"
        )
    }

    private func fetchDetail(id: Int) async -> ZerochanDetail? {
        var comps = URLComponents(string: "https://www.zerochan.net/\(id)")!
        comps.queryItems = [.init(name: "json", value: nil)]

        var request = browserRequest(url: comps.url!)
        request.setValue("https://www.zerochan.net/", forHTTPHeaderField: "Referer")

        do {
            return try await URLSession.shared.decodedData(ZerochanDetail.self, from: request)
        } catch {
            return nil
        }
    }
}

private protocol ZerochanImage {
    var id: Int { get }
    var width: Int? { get }
    var height: Int? { get }
    var thumbnail: String? { get }
    var large: String? { get }
    var full: String? { get }
    var tag: String? { get }
    var tags: [String]? { get }
}

private extension ZerochanImage {
    var imageURL: URL? {
        if let full, let url = URL(string: full) { return url }
        if let large, let url = URL(string: large) { return url }
        return nil
    }

    var thumbnailURL: URL? {
        if let thumbnail, let url = URL(string: thumbnail) { return url }
        if let large, let url = URL(string: large) { return url }
        if let full, let url = URL(string: full) { return url }
        return nil
    }

    var allTags: [String] {
        if let tags, !tags.isEmpty { return tags }
        if let tag, !tag.isEmpty { return [tag] }
        return []
    }
}

private struct ZerochanResponse: Decodable {
    let items: [ZerochanItem]
}

private struct ZerochanItem: Decodable, ZerochanImage {
    let id: Int
    let thumbnail: String?
    let large: String?
    let full: String?
    let width: Int?
    let height: Int?
    let tag: String?
    let tags: [String]?
}

private struct ZerochanDetail: Decodable, ZerochanImage {
    let id: Int
    let thumbnail: String?
    let large: String?
    let full: String?
    let width: Int?
    let height: Int?
    let tag: String?
    let tags: [String]?

    private enum CodingKeys: String, CodingKey {
        case id, small, medium, large, full, width, height, primary, tags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        thumbnail = try container.decodeIfPresent(String.self, forKey: .medium)
            ?? container.decodeIfPresent(String.self, forKey: .small)
        large = try container.decodeIfPresent(String.self, forKey: .large)
        full = try container.decodeIfPresent(String.self, forKey: .full)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        tag = try container.decodeIfPresent(String.self, forKey: .primary)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
    }
}
