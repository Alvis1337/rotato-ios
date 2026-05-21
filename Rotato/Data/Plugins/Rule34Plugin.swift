import Foundation

struct Rule34Plugin: SourcePlugin {
    let id = "RULE34"
    let displayName = "Rule34"
    let description = "Everything has rule 34 · No account needed · NSFW-only content"
    let sfSymbol = "exclamationmark.triangle"
    let requiresApiKey = false
    let supportsSearch = true

    private static let videoExts = [".mp4", ".webm", ".mkv", ".avi", ".mov"]

    func fetch(query: String, page: Int, config: SourceConfig, nsfw: Bool) async throws -> [WallpaperItem] {
        let tags = buildTags(query: query, configTags: config.tags)
        let limit = 30

        func makeURL(pid: Int) -> URL {
            var comps = URLComponents(string: "https://api.rule34.xxx/index.php")!
            comps.queryItems = [
                .init(name: "page", value: "dapi"),
                .init(name: "s", value: "post"),
                .init(name: "q", value: "index"),
                .init(name: "json", value: "1"),
                .init(name: "limit", value: "\(limit)"),
                .init(name: "pid", value: "\(pid)"),
                .init(name: "tags", value: tags),
            ]
            return comps.url!
        }

        // Fetch XML count endpoint to find valid pid range, then pick a random page.
        // Without this, paging into an empty range silently returns nothing.
        let safePid: Int
        if page == 0, let countURL = makeCountURL(tags: tags) {
            let countReq = browserRequest(url: countURL)
            if let (data, _) = try? await URLSession.shared.data(for: countReq),
               let xml = String(data: data, encoding: .utf8),
               let countStr = xml.firstMatch(of: /count="(\d+)"/)?.1,
               let count = Int(countStr), count > limit {
                let maxPid = min((count - 1) / limit, 200)
                safePid = Int.random(in: 0...maxPid)
            } else {
                safePid = 0
            }
        } else {
            safePid = page
        }

        let posts = try await URLSession.shared.decodedData([Rule34Post].self,
                                                            from: browserRequest(url: makeURL(pid: safePid)))
        return posts.compactMap { mapPost($0) }
    }

    private func makeCountURL(tags: String) -> URL? {
        var comps = URLComponents(string: "https://api.rule34.xxx/index.php")
        comps?.queryItems = [
            .init(name: "page", value: "dapi"),
            .init(name: "s", value: "post"),
            .init(name: "q", value: "index"),
            .init(name: "limit", value: "1"),
            .init(name: "tags", value: tags),
        ]
        return comps?.url
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
        guard !Self.videoExts.contains(where: { fileStr.lowercased().hasSuffix($0) }) else { return nil }
        let sampleStr = p.sample_url ?? p.file_url ?? fileStr
        let imageURL = URL(string: sampleStr) ?? fileURL
        let thumbStr = p.preview_url ?? sampleStr
        let thumbURL = URL(string: thumbStr) ?? fileURL
        let tags = (p.tags ?? "").split(separator: " ").prefix(40).map(String.init)
        return WallpaperItem(
            id: "RULE34_\(p.id)",
            imageURL: imageURL,
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
    let sample_url: String?
    let preview_url: String?
    let width: Int?
    let height: Int?
    let tags: String?
}
