import Foundation

/// Tags and URLs that must never be added: the global blacklist, "Never" tiers and blocked images.
public struct ContentBlocklist: Sendable {
    public let tags: Set<String>
    public let urls: Set<String>

    public init(tags: Set<String>, urls: Set<String>) {
        self.tags = tags
        self.urls = urls
    }

    public func blocks(_ wp: Wallpaper) -> Bool {
        wp.hasAnyTag(tags) || (!urls.isEmpty && (urls.contains(wp.fullUrl) || urls.contains(wp.thumbUrl)))
    }

    public static func load(db: RotatoDatabase = .shared, nsfw: Bool) -> ContentBlocklist {
        let settings = db.read(DataFiles.settings)
        let state = db.read(DataFiles.state)
        var tiers = state.sfwTagTiers
        if nsfw { tiers.merge(state.nsfwTagTiers) { _, b in b } }
        let never = tiers.filter { $0.value == .NEVER }.map(\.key)
        let tags = Set((settings.globalBlacklist + never).map(normalizeTag))
        return ContentBlocklist(tags: tags, urls: state.blockedUrls)
    }
}

/// What Discover has learned without being told: saves and sets nudge an image's tags up, skips
/// and blocks nudge them down, and older signals fade. Drives the "For you" ordering.
public enum LearnedTaste {
    public enum Signal: Double, Sendable {
        case setWallpaper = 3, saved = 2, downloaded = 1.5, skipped = -1, blocked = -3
    }

    static let decay = 0.985
    static let maxWeight = 20.0
    static let maxTags = 600

    public static func record(_ tags: [String], _ signal: Signal, db: RotatoDatabase = .shared) {
        let normalized = Array(Set(tags.map(normalizeTag).filter { !$0.isEmpty }))
        guard !normalized.isEmpty else { return }
        // Spread the signal so a 40-tag post doesn't outweigh a 5-tag one.
        let perTag = signal.rawValue / Double(normalized.count).squareRoot()
        db.update(DataFiles.state) { s in
            var w = s.learnedWeights.mapValues { $0 * decay }
            for t in normalized { w[t] = min(max((w[t] ?? 0) + perTag, -maxWeight), maxWeight) }
            let kept = w.filter { abs($0.value) >= 0.05 }.sorted { abs($0.value) > abs($1.value) }.prefix(maxTags)
            s.learnedWeights = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
    }

    /// Ranking score: learned tag affinity plus a bonus for resolutions that look good as wallpaper.
    public static func score(_ wp: Wallpaper, weights: [String: Double]) -> Double {
        let tags = wp.tags.map(normalizeTag)
        let affinity = (tags.isEmpty || weights.isEmpty) ? 0
            : tags.reduce(0) { $0 + (weights[$1] ?? 0) } / Double(tags.count).squareRoot()
        let longSide = wp.dimensions.map { max($0.width, $0.height) } ?? 0
        let resBonus: Double = switch longSide {
        case 3840...: 1.2
        case 2560...: 0.7
        case 1920...: 0.3
        case 1...999: -0.8
        default: 0
        }
        return affinity + resBonus
    }
}

/// Fills a collection from the enabled sources (FillHelper on Android).
public struct CollectionFiller: Sendable {
    public let db: RotatoDatabase

    public init(db: RotatoDatabase = .shared) { self.db = db }

    /// Adds up to `count` wallpapers matching `tags`. Returns how many were added.
    public func fill(
        listId: String, tags: String, count: Int, pluginId: String? = nil, instanceId: String? = nil,
        matchAny: Bool = false, nsfwOverride: Bool? = nil,
        minResolution: MinResolution = .ANY, aspectRatio: AspectRatio = .ANY
    ) async -> Int {
        let manifests = PluginCatalog(db: db).installed
        let settings = db.read(DataFiles.settings)
        let globalNsfw = settings.effectiveNsfw
        func manifest(_ s: SourceConfig) -> PluginManifest? {
            manifests.first { $0.id.caseInsensitiveCompare(s.pluginId) == .orderedSame }
        }
        // Global NSFW is a ceiling: overrides can force SFW but never re-enable NSFW.
        func nsfw(_ s: SourceConfig) -> Bool { globalNsfw && s.nsfwEnabled != false && nsfwOverride != false }
        let candidates = SourcesRepository(db: db).sources.filter { s in
            guard s.enabled else { return false }
            if let pluginId, s.pluginId != pluginId { return false }
            if let instanceId, s.instanceId != instanceId { return false }
            guard let m = manifest(s) else { return false }
            return PluginExecutor.canServe(m, nsfw: nsfw(s), source: s)
        }.shuffled()
        guard !candidates.isEmpty else { return 0 }

        var filters = settings.filters
        filters.minResolution = minResolution
        filters.aspectRatio = aspectRatio
        filters.matchAny = matchAny
        let blocklist = ContentBlocklist.load(db: db, nsfw: globalNsfw)
        let repo = CollectionsRepository(db: db)
        var added = 0
        for _ in 0..<15 where added < count {
            var addedThisRound = 0
            for s in candidates where added < count {
                guard let m = manifest(s) else { continue }
                let page = await PluginExecutor.fetchPage(FetchRequest(
                    manifest: m, source: s, query: tags.trimmingCharacters(in: .whitespaces),
                    nsfw: nsfw(s), filters: filters, limit: count - added + 5
                ))
                for wp in page where added < count && !blocklist.blocks(wp) {
                    if repo.add(wp, to: listId) { added += 1; addedThisRound += 1 }
                }
            }
            if addedThisRound == 0 { break }
        }
        return added
    }
}
