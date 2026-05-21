import Foundation

struct WallhavenPlugin: SourcePlugin {
    let id = "WALLHAVEN"
    let displayName = "Wallhaven"
    let sfSymbol = "mountain.2"
    let requiresApiKey = true
    let supportsSearch = true

    func fetch(query: String, page: Int, config: SourceConfig, nsfw: Bool) async throws -> [WallpaperItem] {
        var comps = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        // purity: extraParam holds purity string like "110" (sfw+sketchy); default "100" (sfw only)
        let purity = config.extraParam.isEmpty ? (nsfw ? "111" : "100") : config.extraParam
        var qi: [URLQueryItem] = [
            .init(name: "categories", value: "111"),
            .init(name: "purity", value: purity),
            .init(name: "sorting", value: "hot"),
            .init(name: "page", value: "\(page + 1)"),
            .init(name: "atleast", value: "1920x1080"),
        ]
        if !query.isEmpty { qi.append(.init(name: "q", value: query)) }
        else if !config.tags.isEmpty { qi.append(.init(name: "q", value: config.tags)) }
        if !config.apiKey.isEmpty { qi.append(.init(name: "apikey", value: config.apiKey)) }
        comps.queryItems = qi

        var request = browserRequest(url: comps.url!)
        let decoded = try await URLSession.shared.decodedData(WallhavenResponse.self, from: request)
        return decoded.data.map { mapWallpaper($0) }
    }

    private func mapWallpaper(_ w: WallhavenWallpaper) -> WallpaperItem {
        let tags = w.tags?.map { $0.name } ?? []
        return WallpaperItem(
            id: "WALLHAVEN_\(w.id)",
            imageURL: URL(string: w.path)!,
            thumbnailURL: URL(string: w.thumbs.large)!,
            sourceId: id,
            tags: Array(tags.prefix(40)),
            width: w.dimension_x,
            height: w.dimension_y,
            rating: w.purity == "sfw" ? "safe" : w.purity
        )
    }
}

private struct WallhavenResponse: Decodable {
    let data: [WallhavenWallpaper]
}

private struct WallhavenWallpaper: Decodable {
    let id: String
    let path: String
    let purity: String
    let dimension_x: Int
    let dimension_y: Int
    let thumbs: Thumbs
    let tags: [WallhavenTag]?

    struct Thumbs: Decodable {
        let large: String
        let original: String
    }
}

private struct WallhavenTag: Decodable {
    let name: String
}
