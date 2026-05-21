import Foundation
import Observation

struct SourceConfig: Codable {
    var enabled: Bool = true
    var apiKey: String = ""
    var apiUser: String = ""
    var tags: String = ""
    var extraParam: String = ""  // e.g. wallhaven purity string "110", reddit subreddits JSON
    var nsfwOverride: Bool? = nil // nil = use global, true/false = override per-source
}

// MARK: - History

struct HistoryItem: Codable, Identifiable {
    var id: String
    var sourceId: String
    var thumbnailURL: String
    var imageURL: String
    var tags: [String]
    var width: Int
    var height: Int
    var rating: String
    var savedAt: Date

    var isNSFW: Bool {
        rating == "explicit" || rating == "e" || rating == "questionable" || rating == "q"
    }
}

extension HistoryItem {
    init(from item: WallpaperItem) {
        self.id = item.id
        self.sourceId = item.sourceId
        self.thumbnailURL = item.thumbnailURL.absoluteString
        self.imageURL = item.imageURL.absoluteString
        self.tags = item.tags
        self.width = item.width
        self.height = item.height
        self.rating = item.rating
        self.savedAt = Date()
    }

    var wallpaperItem: WallpaperItem? {
        guard let img = URL(string: imageURL), let thumb = URL(string: thumbnailURL) else { return nil }
        return WallpaperItem(id: id, imageURL: img, thumbnailURL: thumb,
                             sourceId: sourceId, tags: tags, width: width, height: height, rating: rating)
    }
}

// MARK: - Source Health

struct SourceHealthResult: Codable {
    var lastSuccess: Date?
    var lastError: String?
    var isTesting: Bool = false
    var successCount: Int = 0
    var totalFetches: Int = 0
}

/// All app settings backed by UserDefaults.
///
/// Uses stored properties + didSet so that @Observable correctly tracks changes
/// and SwiftUI views re-render when a value is mutated. Computed properties
/// backed by UserDefaults are NOT observed by the @Observable macro.
@Observable
final class AppSettings {
    // MARK: - NSFW

    var nsfwEnabled: Bool { didSet { UserDefaults.standard.set(nsfwEnabled, forKey: "nsfw_enabled") } }

    // MARK: - Source configs

    var sourceConfigs: [String: SourceConfig] {
        didSet {
            if let data = try? JSONEncoder().encode(sourceConfigs) {
                UserDefaults.standard.set(data, forKey: "source_configs")
            }
        }
    }

    func config(for pluginId: String) -> SourceConfig {
        sourceConfigs[pluginId] ?? SourceConfig()
    }

    func setConfig(_ config: SourceConfig, for pluginId: String) {
        var configs = sourceConfigs
        configs[pluginId] = config
        sourceConfigs = configs
    }

    // MARK: - Reddit subreddits

    var redditSubreddits: [String] { didSet { UserDefaults.standard.set(redditSubreddits, forKey: "reddit_subreddits") } }

    // MARK: - MAL

    var malAccessToken: String  { didSet { UserDefaults.standard.set(malAccessToken,  forKey: "mal_access_token")  } }
    var malRefreshToken: String { didSet { UserDefaults.standard.set(malRefreshToken, forKey: "mal_refresh_token") } }
    var malUsername: String     { didSet { UserDefaults.standard.set(malUsername,     forKey: "mal_username")      } }
    var malMinScore: Int        { didSet { UserDefaults.standard.set(malMinScore,     forKey: "mal_min_score")     } }
    var malAnimeList: [String]  { didSet { UserDefaults.standard.set(malAnimeList,    forKey: "mal_anime_list")    } }
    var malCodeVerifier: String { didSet { UserDefaults.standard.set(malCodeVerifier, forKey: "mal_code_verifier") } }

    var malFilterStatuses: Set<String> {
        didSet { UserDefaults.standard.set(Array(malFilterStatuses), forKey: "mal_filter_statuses") }
    }

    // MARK: - Discover

    var wifiOnlyDiscover: Bool { didSet { UserDefaults.standard.set(wifiOnlyDiscover, forKey: "wifi_only_discover") } }

    // MARK: - Ratings  (item ID → 1-5 stars, 0 = unrated)

    var wallpaperRatings: [String: Int] {
        didSet {
            if let data = try? JSONEncoder().encode(wallpaperRatings) {
                UserDefaults.standard.set(data, forKey: "wallpaper_ratings")
            }
        }
    }

    func rating(for itemId: String) -> Int { wallpaperRatings[itemId] ?? 0 }

    func setRating(_ stars: Int, for itemId: String) {
        var r = wallpaperRatings
        if stars == 0 { r.removeValue(forKey: itemId) } else { r[itemId] = max(1, min(5, stars)) }
        wallpaperRatings = r
    }

    // MARK: - History  (most recent first, capped at 200)

    var history: [HistoryItem] {
        didSet {
            if let data = try? JSONEncoder().encode(history) {
                UserDefaults.standard.set(data, forKey: "history")
            }
        }
    }

    func addToHistory(_ item: WallpaperItem) {
        var h = history
        h.removeAll { $0.id == item.id }         // deduplicate
        h.insert(HistoryItem(from: item), at: 0) // newest first
        if h.count > 200 {
            let removed = h.dropFirst(200).map { $0.id }
            h = Array(h.prefix(200))
            // Prune ratings for IDs no longer in history
            if !removed.isEmpty {
                let removedSet = Set(removed)
                var r = wallpaperRatings
                removedSet.forEach { r.removeValue(forKey: $0) }
                wallpaperRatings = r
            }
        }
        history = h
    }

    // MARK: - Source health

    var sourceHealth: [String: SourceHealthResult] {
        didSet {
            if let data = try? JSONEncoder().encode(sourceHealth) {
                UserDefaults.standard.set(data, forKey: "source_health")
            }
        }
    }

    func updateHealth(_ result: SourceHealthResult, for pluginId: String) {
        var h = sourceHealth
        h[pluginId] = result
        sourceHealth = h
    }

    // MARK: - Init

    init() {
        let d = UserDefaults.standard

        nsfwEnabled      = d.bool(forKey: "nsfw_enabled")
        wifiOnlyDiscover = d.bool(forKey: "wifi_only_discover")

        redditSubreddits  = d.stringArray(forKey: "reddit_subreddits") ?? ["wallpapers", "EarthPorn"]
        malAccessToken    = d.string(forKey: "mal_access_token")  ?? ""
        malRefreshToken   = d.string(forKey: "mal_refresh_token") ?? ""
        malUsername       = d.string(forKey: "mal_username")      ?? ""
        malAnimeList      = d.stringArray(forKey: "mal_anime_list") ?? []
        malCodeVerifier   = d.string(forKey: "mal_code_verifier") ?? ""
        malMinScore       = d.integer(forKey: "mal_min_score")
        malFilterStatuses = Set(d.stringArray(forKey: "mal_filter_statuses") ?? ["watching", "completed"])

        if let data = d.data(forKey: "wallpaper_ratings"),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            wallpaperRatings = decoded
        } else {
            wallpaperRatings = [:]
        }

        if let data = d.data(forKey: "history"),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            history = decoded
        } else {
            history = []
        }

        if let data = d.data(forKey: "source_health"),
           let decoded = try? JSONDecoder().decode([String: SourceHealthResult].self, from: data) {
            sourceHealth = decoded
        } else {
            sourceHealth = [:]
        }

        if let data = d.data(forKey: "source_configs"),
           let decoded = try? JSONDecoder().decode([String: SourceConfig].self, from: data) {
            // Merge saved configs with any new plugins that weren't previously registered
            var merged = decoded
            for plugin in PluginRegistry.all where merged[plugin.id] == nil {
                merged[plugin.id] = SourceConfig(enabled: plugin.id == "GELBOORU" || plugin.id == "SAFEBOORU")
            }
            sourceConfigs = merged
        } else {
            var c: [String: SourceConfig] = [:]
            for plugin in PluginRegistry.all {
                let enabledByDefault = plugin.id == "GELBOORU" || plugin.id == "SAFEBOORU"
                c[plugin.id] = SourceConfig(enabled: enabledByDefault)
            }
            sourceConfigs = c
        }
    }
}
