import Foundation

public enum NoResultsReason: Sendable {
    case noSources
    case searchEmpty
    case exhausted
}

/// How a source fared in this session (SourceHealth on Android).
public struct SourceHealth: Sendable, Hashable, Identifiable {
    public let id: String
    public var name: String
    public var fetches = 0
    public var successes = 0
    public var lastError: String?
    public var lastSuccess: Date?
}

/// Builds the Discover feed (BrainrotViewModel.loadMore on Android):
///  1. Queries are computed once per session per source, so pages stay cached between loads.
///  2. Every (source, query) page is fetched in parallel into a shuffled cache.
///  3. Batches drain round-robin from the caches, skipping seen, blocked and blacklisted posts.
///  4. Each batch is ordered by tag tiers and, for "For you", by learned taste.
public actor DiscoverFeed {
    public struct Batch: Sendable {
        public let items: [Wallpaper]
        public let endReached: Bool
        public let noResults: NoResultsReason?
    }

    struct Request {
        let source: SourceConfig
        let manifest: PluginManifest
        let queries: [String]
        let nsfw: Bool
    }

    private let db: RotatoDatabase
    private var requests: [Request]?
    private var caches: [String: [Wallpaper]] = [:]
    private var drainOrder: [String] = []
    private var drainCursor = 0
    private var displayed: Set<String> = []
    private var consecutiveEmpty = 0
    private var generation = 0
    public private(set) var query = ""
    public private(set) var health: [String: SourceHealth] = [:]
    public private(set) var hasItems = false

    public init(db: RotatoDatabase = .shared) {
        self.db = db
        displayed = Set(db.read(DataFiles.state).seenKeys)
    }

    /// Starts over with `query` ("" for the general feed). Seen history is cleared, as on Android.
    public func reset(query: String) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        generation += 1
        requests = nil
        caches = [:]
        drainOrder = []
        drainCursor = 0
        displayed = []
        consecutiveEmpty = 0
        hasItems = false
        db.update(DataFiles.state) { $0.seenKeys = [] }
    }

    /// Marks a post as shown elsewhere (undo, restored items) so it isn't served again.
    public func markDisplayed(_ keys: [String]) { displayed.formUnion(keys) }

    /// Loads the next batch. `initial` asks for a double batch to fill the first screen.
    public func next(initial: Bool) async -> Batch {
        let settings = db.read(DataFiles.settings)
        let state = db.read(DataFiles.state)
        let nsfw = settings.effectiveNsfw
        let target = settings.discoverBatchSize * (initial ? 2 : 1)
        let gen = generation

        if requests == nil { requests = buildRequests(settings: settings) }
        guard let requests, !requests.isEmpty else {
            return Batch(items: [], endReached: true, noResults: .noSources)
        }

        var tiers = state.sfwTagTiers
        if nsfw { tiers.merge(state.nsfwTagTiers) { _, b in b } }
        let blacklist = Set(settings.globalBlacklist.map(normalizeTag)).union(tiers.filter { $0.value == .NEVER }.map(\.key))
        let boost = Set(tiers.filter { $0.value == .LOVE || $0.value == .LIKE }.map(\.key))
        let demote = Set(tiers.filter { $0.value == .DISLIKE }.map(\.key))
        let blockedUrls = state.blockedUrls
        // Strict filters discard most of a page, so fetch more candidates per call.
        let f = settings.filters
        let fetchLimit = (f.aspectRatio != .ANY || f.minResolution != .ANY) ? 200 : 100

        var items: [Wallpaper] = []
        var skipped = 0
        for round in 0..<3 where items.count < target {
            await fillCaches(requests, filters: f, limit: fetchLimit, generation: gen)
            guard gen == generation else { return Batch(items: [], endReached: false, noResults: nil) }
            while items.count < target, let wp = drainOne() {
                if displayed.contains(wp.key) { skipped += 1; if skipped >= 200 { break }; continue }
                if wp.hasAnyTag(blacklist) || blockedUrls.contains(wp.fullUrl) || blockedUrls.contains(wp.thumbUrl) { skipped += 1; continue }
                // With NSFW off nothing fetched as NSFW is ever shown, whatever cache it came from.
                if !nsfw && wp.isNsfw { skipped += 1; continue }
                skipped = 0
                displayed.insert(wp.key)
                items.append(wp)
            }
            // Still short: clear the caches so the next round fetches fresh random pages.
            if round < 2 && items.count < target { caches = [:] }
        }

        if items.isEmpty {
            if !hasItems {
                return Batch(items: [], endReached: true, noResults: query.isEmpty ? .exhausted : .searchEmpty)
            }
            // Two empty pages in a row with content showing: the filters are too tight to find more.
            consecutiveEmpty += 1
            if consecutiveEmpty >= 2 { consecutiveEmpty = 0; return Batch(items: [], endReached: true, noResults: nil) }
            caches = [:]
            return Batch(items: [], endReached: false, noResults: nil)
        }

        consecutiveEmpty = 0
        hasItems = true
        let ordered = order(items, boost: boost, demote: demote, forYou: settings.forYouEnabled && query.isEmpty, weights: state.learnedWeights)
        let keys = items.map(\.key)
        db.update(DataFiles.state) { s in
            s.seenKeys += keys
            if s.seenKeys.count > RotatoState.seenCap { s.seenKeys.removeFirst(s.seenKeys.count - RotatoState.seenCap) }
        }
        return Batch(items: ordered, endReached: false, noResults: nil)
    }

    // MARK: Steps

    func buildRequests(settings: RotatoSettings) -> [Request] {
        let manifests = PluginCatalog(db: db).installed
        let nsfw = settings.effectiveNsfw
        return SourcesRepository(db: db).sources.filter(\.enabled).compactMap { s in
            guard let m = manifests.first(where: { $0.id.caseInsensitiveCompare(s.pluginId) == .orderedSame }) else { return nil }
            if m.requiresCredentials && (s.apiKey.isBlank || (m.needsApiUser && s.apiUser.isBlank)) { return nil }
            // Global NSFW is a ceiling: a source can opt out, never back in.
            let effective = nsfw && s.nsfwEnabled != false
            guard PluginExecutor.canServe(m, nsfw: effective, source: s) else { return nil }
            var queries = [query.isEmpty ? s.tags.trimmingCharacters(in: .whitespaces) : query]
            // Searches with more tags than a source allows would fail there, so skip it.
            if m.maxTagCount != Int.max {
                queries = queries.filter { $0.split(whereSeparator: \.isWhitespace).count <= m.maxTagCount }
            }
            guard !queries.isEmpty else { return nil }
            return Request(source: s, manifest: m, queries: queries, nsfw: effective)
        }
    }

    private func cacheKey(_ s: SourceConfig, _ q: String) -> String { "\(s.pluginId):\(s.instanceId):\(q)" }

    /// Fetches every empty (source, query) cache in parallel.
    private func fillCaches(_ requests: [Request], filters: DiscoverFilters, limit: Int, generation gen: Int) async {
        var jobs: [(String, FetchRequest, SourceConfig, String)] = []
        for r in requests {
            let prefix = "\(r.manifest.id.lowercased()):"
            let excludes = Set(displayed.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) })
            for q in r.queries {
                let key = cacheKey(r.source, q)
                if !(caches[key]?.isEmpty ?? true) { continue }
                let fr = FetchRequest(manifest: r.manifest, source: r.source, query: q, exclude: excludes, nsfw: r.nsfw, filters: filters, limit: limit)
                jobs.append((key, fr, r.source, r.manifest.name))
            }
        }
        guard !jobs.isEmpty else { return }
        let results = await withTaskGroup(of: (String, [Wallpaper]).self) { group in
            for (key, fr, _, _) in jobs { group.addTask { (key, await PluginExecutor.fetchPage(fr)) } }
            var out: [String: [Wallpaper]] = [:]
            for await (k, page) in group { out[k] = page }
            return out
        }
        guard gen == generation else { return }
        for (key, _, source, name) in jobs {
            let page = results[key] ?? []
            recordHealth(source, name: name, ok: !page.isEmpty)
            if !page.isEmpty { caches[key] = page.shuffled() }
        }
        drainOrder = caches.keys.sorted().shuffled()
        drainCursor = 0
    }

    /// One post from the next non-empty cache, round-robin, so sources interleave.
    private func drainOne() -> Wallpaper? {
        let order = drainOrder.filter { !(caches[$0]?.isEmpty ?? true) }
        guard !order.isEmpty else { return nil }
        let key = order[drainCursor % order.count]
        drainCursor += 1
        return caches[key]?.popLast()
    }

    func order(_ items: [Wallpaper], boost: Set<String>, demote: Set<String>, forYou: Bool, weights: [String: Double]) -> [Wallpaper] {
        var ordered = items
        if !boost.isEmpty || !demote.isEmpty {
            let boosted = items.filter { $0.hasAnyTag(boost) }
            let demoted = items.filter { !$0.hasAnyTag(boost) && $0.hasAnyTag(demote) }
            let rest = items.filter { !$0.hasAnyTag(boost) && !$0.hasAnyTag(demote) }
            ordered = boosted + rest + demoted
        }
        guard forYou else { return ordered }
        // Rank by learned taste and wallpaper suitability, keeping a little of the tier order
        // and some jitter so the feed doesn't feel sorted.
        let scored = ordered.enumerated().map { i, wp in
            (wp, LearnedTaste.score(wp, weights: weights) - Double(i) * 0.02 + Double.random(in: 0..<0.8))
        }
        return scored.sorted { $0.1 > $1.1 }.map(\.0)
    }

    private func recordHealth(_ s: SourceConfig, name: String, ok: Bool) {
        let id = s.instanceId.isEmpty ? s.pluginId : "\(s.pluginId):\(s.instanceId)"
        var h = health[id] ?? SourceHealth(id: id, name: s.instanceId.isEmpty ? name : "r/\(s.instanceId)")
        h.fetches += 1
        if ok { h.successes += 1; h.lastSuccess = Date(); h.lastError = nil } else { h.lastError = "No results" }
        health[id] = h
    }
}
