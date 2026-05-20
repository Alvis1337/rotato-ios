import Foundation
import Observation

struct SourceConfig: Codable {
    var enabled: Bool = true
    var apiKey: String = ""
    var apiUser: String = ""
    var tags: String = ""
    var extraParam: String = ""  // e.g. wallhaven purity string "110", reddit subreddits JSON
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

        if let data = d.data(forKey: "source_configs"),
           let decoded = try? JSONDecoder().decode([String: SourceConfig].self, from: data) {
            sourceConfigs = decoded
        } else {
            var c: [String: SourceConfig] = [:]
            for plugin in PluginRegistry.all {
                c[plugin.id] = SourceConfig(enabled: plugin.id == "GELBOORU")
            }
            sourceConfigs = c
        }
    }
}
