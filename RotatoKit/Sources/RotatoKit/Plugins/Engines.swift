import Foundation

public struct FetchRequest: Sendable {
    public var manifest: PluginManifest
    public var source: SourceConfig
    public var query: String
    /// Post ids to leave out (already shown).
    public var exclude: Set<String>
    public var nsfw: Bool
    public var filters: DiscoverFilters
    public var limit: Int

    public init(
        manifest: PluginManifest, source: SourceConfig, query: String, exclude: Set<String> = [],
        nsfw: Bool, filters: DiscoverFilters = DiscoverFilters(), limit: Int = 100
    ) {
        self.manifest = manifest; self.source = source; self.query = query; self.exclude = exclude
        self.nsfw = nsfw; self.filters = filters; self.limit = limit
    }

    /// User override wins over manifest default.
    var baseUrl: String {
        var b = source.baseUrl.ifBlank(manifest.defaultBaseUrl)
        while b.hasSuffix("/") { b.removeLast() }
        return b
    }
}

/// Fetches from one API family. Engines are stateless; everything comes from the request.
public protocol PluginEngine: Sendable {
    func fetchPage(_ r: FetchRequest) async -> [Wallpaper]
    func canServe(_ manifest: PluginManifest, nsfw: Bool, source: SourceConfig) -> Bool
}

extension PluginEngine {
    public func canServe(_ manifest: PluginManifest, nsfw: Bool, source: SourceConfig) -> Bool {
        defaultCanServe(manifest, nsfw: nsfw, source: source)
    }

    func defaultCanServe(_ manifest: PluginManifest, nsfw: Bool, source: SourceConfig) -> Bool {
        if manifest.requiresCredentials {
            if manifest.needsApiKey && source.apiKey.isBlank { return false }
            if manifest.needsApiUser && source.apiUser.isBlank { return false }
        }
        if !nsfw && manifest.adultOnly { return false }
        // NSFW mode asks sources for explicit posts only; safe-only sites have none.
        return !(nsfw && manifest.safeContent)
    }
}

/// Routes fetches to the engine for a manifest's protocol.
public enum PluginExecutor {
    static let engines: [PluginProtocol: any PluginEngine] = [
        .GELBOORU: GelbooruEngine(),
        .DANBOORU: DanbooruEngine(),
        .MOEBOORU: MoebooruEngine(),
        .WALLHAVEN: WallhavenEngine(),
        .REDDIT: RedditEngine(),
        .ZEROCHAN: ZerochanEngine(),
    ]

    public static func fetchPage(_ r: FetchRequest) async -> [Wallpaper] {
        guard let engine = engines[r.manifest.protocol], engine.canServe(r.manifest, nsfw: r.nsfw, source: r.source) else { return [] }
        return await engine.fetchPage(r)
    }

    public static func fetchOne(_ r: FetchRequest) async -> Wallpaper? {
        var req = r
        req.limit = 20
        return await fetchPage(req).randomElement()
    }

    public static func canServe(_ manifest: PluginManifest, nsfw: Bool, source: SourceConfig) -> Bool {
        engines[manifest.protocol]?.canServe(manifest, nsfw: nsfw, source: source) ?? false
    }
}

// MARK: - Gelbooru family (Gelbooru, Rule34, Safebooru)

/// Gelbooru-compatible APIs. Variants come from manifest extras:
/// - `response`: "object" (`{"@attributes":{count},"post":[...]}`) or "array" (bare array)
/// - `count`: "json" (read count from page 0), "xml" (separate XML count call) or "random"
/// - `imageUrl`: "file_url" or "safebooru" (`{base}/images/{directory}/{image}`)
/// - `ratingTag`: "general" or "safe"
/// - `pageUrlTemplate`: post page URL with `{base}` and `{id}`
struct GelbooruEngine: PluginEngine {
    func fetchPage(_ r: FetchRequest) async -> [Wallpaper] {
        let base = r.baseUrl
        let extras = r.manifest.extras
        let tagQuery = buildTagQuery(r.query, nsfw: r.nsfw, extras: extras, filters: r.filters)
        let auth = (!r.source.apiKey.isBlank && !r.source.apiUser.isBlank)
            ? "&api_key=\(r.source.apiKey.urlEncoded)&user_id=\(r.source.apiUser.urlEncoded)" : ""
        let url = "\(base)/index.php?page=dapi&s=post&q=index&json=1&limit=\(r.limit)&tags=\(tagQuery.urlEncoded)\(auth)"
        guard let posts = await loadPage(url: url, base: base, tagQuery: tagQuery, auth: auth, limit: r.limit, extras: extras) else { return [] }
        return posts.compactMap { post in
            let id = post.str("id")
            if r.exclude.contains(id) { return nil }
            guard r.filters.matches(width: post.int("width"), height: post.int("height")) else { return nil }
            return build(post, base: base, manifest: r.manifest, extras: extras, nsfw: r.nsfw)
        }
    }

    func buildTagQuery(_ query: String, nsfw: Bool, extras: [String: String], filters: DiscoverFilters) -> String {
        let tokens = queryTokens(query)
        let rating = extras["ratingTag"] ?? "general"
        var parts: [String] = []
        if !tokens.isEmpty {
            parts.append(filters.matchAny && tokens.count > 1 ? "( \(tokens.joined(separator: " ~ ")) )" : tokens.joined(separator: " "))
        }
        parts.append(nsfw ? "-rating:\(rating)" : "rating:\(rating)")
        return parts.joined(separator: " ")
    }

    /// Loads a random page. Sites without a usable count guess a page and fall back to page 0
    /// when the guess is past the end, so small tag searches still return something.
    private func loadPage(url: String, base: String, tagQuery: String, auth: String, limit: Int, extras: [String: String]) async -> [[String: Any]]? {
        let format = extras["response"] ?? "object"
        var page0: [String: Any]?
        let pid: Int
        switch extras["count"] ?? "json" {
        case "xml":
            let countUrl = "\(base)/index.php?page=dapi&s=post&q=index&limit=1&tags=\(tagQuery.urlEncoded)\(auth)"
            var count = 0
            if let (data, _) = await HTTP.data(countUrl), let body = String(data: data, encoding: .utf8),
               let m = body.range(of: #"count="(\d+)""#, options: .regularExpression) {
                count = Int(body[m].filter(\.isNumber)) ?? 0
            }
            pid = count > 0 ? Int.random(in: 0...min(max((count - 1) / limit, 0), 100)) : 0
        case "random":
            pid = Int.random(in: 0...(Int(extras["countMax"] ?? "") ?? 200))
        default:
            page0 = await HTTP.jsonObject("\(url)&pid=0")
            let count = page0?.obj("@attributes")?.int("count") ?? 0
            pid = count > 0 ? Int.random(in: 0...min(max((count - 1) / limit, 0), 100)) : 0
        }
        var posts: [[String: Any]]?
        if pid == 0, let p0 = page0, format == "object" {
            posts = p0.objs("post")
        } else {
            posts = await loadArray(url: url, pid: pid, format: format)
        }
        if (posts?.isEmpty ?? true), pid > 0 { posts = await loadArray(url: url, pid: 0, format: format) }
        return posts
    }

    private func loadArray(url: String, pid: Int, format: String) async -> [[String: Any]]? {
        if format == "object" { return await HTTP.jsonObject("\(url)&pid=\(pid)")?.objs("post") }
        return await HTTP.jsonArray("\(url)&pid=\(pid)")
    }

    private func build(_ post: [String: Any], base: String, manifest: PluginManifest, extras: [String: String], nsfw: Bool) -> Wallpaper? {
        let id = post.str("id")
        guard !id.isBlank else { return nil }
        let fullUrl: String
        if extras["imageUrl"] == "safebooru" {
            let dir = post.str("directory"), img = post.str("image")
            guard !dir.isBlank, !img.isBlank else { return nil }
            fullUrl = "\(base)/images/\(dir)/\(img)"
        } else {
            fullUrl = post.str("file_url")
        }
        guard !fullUrl.isBlank else { return nil }
        let isVideo = MediaType.isVideoURL(fullUrl)
        // preview_url is always a static frame, even for video posts.
        let thumb = post.str("preview_url").ifBlank(fullUrl)
        let sample = isVideo ? fullUrl : post.str("sample_url").ifBlank(fullUrl)
        let template = extras["pageUrlTemplate"] ?? "{base}/index.php?page=post&s=view&id={id}"
        return Wallpaper(
            id: id, source: manifest.id.lowercased(), thumbUrl: thumb, sampleUrl: sample, fullUrl: fullUrl,
            resolution: "\(post.int("width"))x\(post.int("height"))",
            pageUrl: template.replacingOccurrences(of: "{base}", with: base).replacingOccurrences(of: "{id}", with: id),
            tags: post.str("tags").split(separator: " ").map(String.init),
            isVideo: isVideo, isNsfw: nsfw
        )
    }
}

// MARK: - Danbooru

/// Danbooru-compatible APIs (Basic auth, `/posts.json?random=true`). Free accounts get one tag;
/// Gold accounts (level 30+) get the full query and id excludes.
struct DanbooruEngine: PluginEngine {
    private static let levelCache = LevelCache()
    private static let goldLevel = 30

    func fetchPage(_ r: FetchRequest) async -> [Wallpaper] {
        let base = r.baseUrl
        let auth = Self.authHeader(r.source)
        var isPremium = false
        if let auth { isPremium = await accountLevel(r.source, auth: auth, base: base) >= Self.goldLevel }
        let tagQuery = buildTagQuery(r.query, nsfw: r.nsfw, isPremium: isPremium, exclude: Array(r.exclude), filters: r.filters)
        let url = "\(base)/posts.json?tags=\(tagQuery.urlEncoded)&limit=\(r.limit)&random=true"
        guard let arr = await HTTP.jsonArray(url, headers: auth.map { ["Authorization": $0] } ?? [:]) else { return [] }
        return arr.compactMap { post in
            let id = String(post.int("id"))
            if r.exclude.contains(id) { return nil }
            guard r.filters.matches(width: post.int("image_width"), height: post.int("image_height")) else { return nil }
            if post.str("file_url").isBlank && post.str("large_file_url").isBlank { return nil }
            return build(post, base: base, manifest: r.manifest, nsfw: r.nsfw)
        }
    }

    static func authHeader(_ source: SourceConfig) -> String? {
        guard !source.apiKey.isBlank, !source.apiUser.isBlank else { return nil }
        return "Basic " + Data("\(source.apiUser):\(source.apiKey)".utf8).base64EncodedString()
    }

    /// Only a successful answer is cached, so a timeout doesn't pin a Gold account to level 0.
    private func accountLevel(_ source: SourceConfig, auth: String, base: String) async -> Int {
        let key = "\(source.apiUser):\(source.apiKey)@\(base)"
        if let cached = await Self.levelCache.get(key) { return cached }
        guard let profile = await HTTP.jsonObject("\(base)/profile.json", headers: ["Authorization": auth]) else { return 0 }
        let level = profile.int("level")
        await Self.levelCache.set(key, level)
        return level
    }

    func buildTagQuery(_ query: String, nsfw: Bool, isPremium: Bool, exclude: [String], filters: DiscoverFilters) -> String {
        let tokens = queryTokens(query)
        let effective = Array(tokens.prefix(isPremium ? tokens.count : 1))
        var parts: [String] = []
        if !effective.isEmpty {
            parts.append(filters.matchAny && effective.count > 1 ? effective.map { "~\($0)" }.joined(separator: " ") : effective.joined(separator: " "))
        }
        parts.append(nsfw ? "-rating:g" : "rating:g")
        if isPremium { parts += exclude.prefix(3).map { "-id:\($0)" } }
        return parts.joined(separator: " ")
    }

    private func build(_ post: [String: Any], base: String, manifest: PluginManifest, nsfw: Bool) -> Wallpaper? {
        let large = post.str("large_file_url")
        let full = post.str("file_url").ifBlank(large)
        // Ugoira (zip of frames) can't be shown.
        if full.lowercased().hasSuffix(".zip") { return nil }
        let isVideo = MediaType.isVideoURL(full)
        let sample = isVideo ? full : large.ifBlank(post.str("file_url"))
        let id = String(post.int("id"))
        let tags = [post.str("tag_string_general"), post.str("tag_string_character"), post.str("tag_string_copyright")]
            .joined(separator: " ").split(separator: " ").map { unescapeHTML(String($0)) }
        return Wallpaper(
            id: id, source: manifest.id.lowercased(), thumbUrl: post.str("preview_file_url").ifBlank(sample),
            sampleUrl: sample, fullUrl: full, resolution: "\(post.int("image_width"))x\(post.int("image_height"))",
            pageUrl: "\(base)/posts/\(id)", tags: tags, isVideo: isVideo, isNsfw: nsfw
        )
    }
}

actor LevelCache {
    private var values: [String: Int] = [:]
    func get(_ k: String) -> Int? { values[k] }
    func set(_ k: String, _ v: Int) { values[k] = v }
}

// MARK: - Moebooru (Konachan, Yande.re)

struct MoebooruEngine: PluginEngine {
    func fetchPage(_ r: FetchRequest) async -> [Wallpaper] {
        let base = r.baseUrl
        let tagQuery = buildTagQuery(r.query, nsfw: r.nsfw, filters: r.filters)
        guard let arr = await HTTP.jsonArray("\(base)/post.json?tags=\(tagQuery.urlEncoded)&limit=\(r.limit)") else { return [] }
        return arr.compactMap { post in
            let id = String(post.int("id"))
            if r.exclude.contains(id) { return nil }
            guard r.filters.matches(width: post.int("width"), height: post.int("height")) else { return nil }
            let full = post.str("file_url")
            guard !full.isBlank else { return nil }
            let isVideo = MediaType.isVideoURL(full)
            let sample = isVideo ? full : post.str("sample_url").ifBlank(full)
            return Wallpaper(
                id: id, source: r.manifest.id.lowercased(), thumbUrl: post.str("preview_url").ifBlank(sample),
                sampleUrl: sample, fullUrl: full, resolution: "\(post.int("width"))x\(post.int("height"))",
                pageUrl: "\(base)/post/show/\(id)", tags: post.str("tags").split(separator: " ").map(String.init),
                isVideo: isVideo, isNsfw: r.nsfw
            )
        }
    }

    func buildTagQuery(_ query: String, nsfw: Bool, filters: DiscoverFilters) -> String {
        let tokens = queryTokens(query)
        var parts: [String] = []
        if !tokens.isEmpty {
            parts.append(filters.matchAny && tokens.count > 1 ? tokens.map { "~\($0)" }.joined(separator: " ") : tokens.joined(separator: " "))
        }
        parts.append(nsfw ? "-rating:s" : "rating:s")
        parts.append("order:random")
        return parts.joined(separator: " ")
    }
}

// MARK: - Wallhaven

struct WallhavenEngine: PluginEngine {
    func canServe(_ manifest: PluginManifest, nsfw: Bool, source: SourceConfig) -> Bool {
        // Wallhaven only serves NSFW to logged-in API keys.
        if nsfw && source.apiKey.isBlank { return false }
        return defaultCanServe(manifest, nsfw: nsfw, source: source)
    }

    func fetchPage(_ r: FetchRequest) async -> [Wallpaper] {
        let base = r.baseUrl
        guard let json = await HTTP.jsonObject(buildUrl(r)), let data = json.objs("data") else { return [] }
        return data.compactMap { post in
            let id = post.str("id")
            guard !id.isBlank, !r.exclude.contains(id) else { return nil }
            let full = post.str("path")
            guard !full.isBlank else { return nil }
            let thumbs = post.obj("thumbs")
            // "original" keeps the aspect ratio (small/large are 3:2 crops).
            let thumb = [thumbs?.str("original"), thumbs?.str("large"), thumbs?.str("small")]
                .compactMap { $0 }.first { !$0.isBlank } ?? full
            let tags = post.objs("tags")?.map { $0.str("name") }.filter { !$0.isBlank } ?? []
            return Wallpaper(
                id: id, source: r.manifest.id.lowercased(), thumbUrl: thumb, sampleUrl: full, fullUrl: full,
                resolution: post.str("resolution"), pageUrl: "\(base)/w/\(id)",
                tags: tags.isEmpty ? r.query.split(whereSeparator: \.isWhitespace).map(String.init) : tags,
                isVideo: MediaType.isVideoURL(full), isNsfw: post.str("purity") != "sfw"
            )
        }
    }

    func buildUrl(_ r: FetchRequest) -> String {
        let purity = effectivePurity(r.source.wallhavenPurity, nsfw: r.nsfw)
        let categories = r.filters.animeOnly ? "010" : "111"
        // Wallhaven tags use spaces; booru-style queries arrive with underscores.
        let q = r.query.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "_", with: " ")
        var url = "\(r.baseUrl)/api/v1/search?q=\(q.urlEncoded)&categories=\(categories)&purity=\(purity)&sorting=random"
        let f = r.filters
        switch f.minResolution {
        case .ANY: break
        case .MY_PHONE:
            if f.phoneScreenWidth > 0 && f.phoneScreenHeight > 0 { url += "&atleast=\(f.phoneMinWidth)x\(f.phoneMinHeight)" }
        default:
            url += "&atleast=\(f.minResolution.width)x\(f.minResolution.height)"
        }
        switch f.aspectRatio {
        case .ANY: break
        case .MY_PHONE: url += "&ratios=9x16,9x18,9x19.5,9x20"
        default: url += "&ratios=\(f.aspectRatio.wallhavenKey)"
        }
        if !r.source.apiKey.isBlank { url += "&apikey=\(r.source.apiKey.urlEncoded)" }
        return url
    }

    private func effectivePurity(_ stored: String, nsfw: Bool) -> String {
        let s = Array(stored.count == 3 ? stored : "110")
        if nsfw { return "\(s[0])\(s[1])1" }
        let effective = "\(s[0])\(s[1])0"
        return effective == "000" ? "100" : effective
    }
}

// MARK: - Reddit

/// Public subreddits (`/r/{sub}/top.json`). The subreddit is the source's instanceId.
struct RedditEngine: PluginEngine {
    func fetchPage(_ r: FetchRequest) async -> [Wallpaper] {
        let sub = r.source.instanceId.trimmingCharacters(in: .whitespaces)
        guard !sub.isBlank,
              let json = await HTTP.jsonObject("https://www.reddit.com/r/\(sub.urlEncoded)/top.json?limit=100&raw_json=1&t=month"),
              let children = json.obj("data")?.objs("children") else { return [] }
        var out: [Wallpaper] = []
        for child in children {
            guard let post = child.obj("data") else { continue }
            if !r.nsfw && post.bool("over_18") { continue }
            guard isSupported(post) else { continue }
            let id = post.str("id")
            guard !id.isBlank, !r.exclude.contains(id) else { continue }
            let preview = post.obj("preview")?.objs("images")?.first
            let src = preview?.obj("source")
            guard r.filters.matches(width: src?.int("width") ?? 0, height: src?.int("height") ?? 0) else { continue }
            guard let full = mediaUrl(post) else { continue }
            let isVideo = MediaType.isVideoURL(full)
            let thumb = (preview?.objs("resolutions")?.last?.str("url")).map(unescapeHTML)?.nilIfBlank
                ?? (src?.str("url")).map(unescapeHTML)?.nilIfBlank ?? full
            let w = src?.int("width") ?? 0, h = src?.int("height") ?? 0
            let permalink = post.str("permalink")
            out.append(Wallpaper(
                id: id, source: "reddit", thumbUrl: thumb, sampleUrl: isVideo ? full : thumb, fullUrl: full,
                resolution: w > 0 && h > 0 ? "\(w)x\(h)" : "",
                pageUrl: permalink.isBlank ? "https://reddit.com/r/\(sub)" : "https://reddit.com\(permalink)",
                tags: [sub], isVideo: isVideo, isNsfw: post.bool("over_18")
            ))
            if out.count >= r.limit { break }
        }
        return out
    }

    private func isSupported(_ post: [String: Any]) -> Bool {
        if post.bool("is_video") {
            return !(post.obj("media")?.obj("reddit_video")?.str("fallback_url").isBlank ?? true)
        }
        if post.str("post_hint") == "image" { return true }
        let url = post.str("url_overridden_by_dest").ifBlank(post.str("url"))
        if url.contains("i.redd.it") { return true }
        if url.contains("i.imgur.com") { return [".jpg", ".jpeg", ".png", ".webp"].contains { url.hasSuffix($0) } }
        if url.lowercased().hasSuffix(".gifv") { return true }
        return MediaType.isVideoURL(url)
    }

    private func mediaUrl(_ post: [String: Any]) -> String? {
        if post.bool("is_video"), let f = post.obj("media")?.obj("reddit_video")?.str("fallback_url"), !f.isBlank {
            return unescapeHTML(f)
        }
        let url = post.str("url_overridden_by_dest").ifBlank(post.str("url"))
        if url.isBlank { return nil }
        if url.lowercased().hasSuffix(".gifv") { return String(url.dropLast(5)) + ".mp4" }
        return url
    }
}

// MARK: - Zerochan

/// Zerochan's JSON API. It wants an identifying User-Agent, and the list endpoint has no full
/// image URL, so each item is looked up individually.
struct ZerochanEngine: PluginEngine {
    private let pageSize = 20
    private let maxPage = 50
    private let ua = ["User-Agent": "Rotato wallpaper app - alvis"]

    func fetchPage(_ r: FetchRequest) async -> [Wallpaper] {
        let base = r.baseUrl
        var items = await search(base, r.query, page: Int.random(in: 1...maxPage)) ?? []
        if items.isEmpty { items = await search(base, r.query, page: 1) ?? [] }
        let candidates = items.filter { item in
            let id = item.str("id")
            return !id.isBlank && !r.exclude.contains(id) && r.filters.matches(width: item.int("width"), height: item.int("height"))
        }.prefix(min(r.limit, pageSize))
        return await withTaskGroup(of: (Int, Wallpaper?).self) { group in
            for (i, item) in candidates.enumerated() {
                group.addTask { (i, await build(base, item, manifest: r.manifest)) }
            }
            var results: [(Int, Wallpaper)] = []
            for await (i, wp) in group { if let wp { results.append((i, wp)) } }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func search(_ base: String, _ query: String, page: Int) async -> [[String: Any]]? {
        let q = query.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "+", with: " ")
        let url = q.isBlank ? "\(base)/?json&l=\(pageSize)&p=\(page)" : "\(base)/?q=\(q.urlEncoded)&json&l=\(pageSize)&p=\(page)"
        return await HTTP.jsonObject(url, headers: ua)?.objs("items")
    }

    private func build(_ base: String, _ item: [String: Any], manifest: PluginManifest) async -> Wallpaper? {
        let id = item.str("id")
        guard !id.isBlank, let detail = await HTTP.jsonObject("\(base)/\(id)?json", headers: ua) else { return nil }
        let full = detail.str("full").ifBlank(detail.str("large"))
        guard !full.isBlank else { return nil }
        let sample = detail.str("large").ifBlank(detail.str("medium")).ifBlank(item.str("thumbnail")).ifBlank(full)
        let thumb = item.str("thumbnail").ifBlank(detail.str("medium")).ifBlank(sample)
        let tags = (detail.arr("tags") as? [String]).flatMap { $0.isEmpty ? nil : $0 } ?? (item.arr("tags") as? [String]) ?? []
        let w = detail.int("width") > 0 ? detail.int("width") : item.int("width")
        let h = detail.int("height") > 0 ? detail.int("height") : item.int("height")
        return Wallpaper(
            id: id, source: manifest.id.lowercased(), thumbUrl: thumb, sampleUrl: sample, fullUrl: full,
            resolution: "\(w)x\(h)", pageUrl: "\(base)/\(id)", tags: tags, isVideo: MediaType.isVideoURL(full)
        )
    }
}
