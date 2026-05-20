import Foundation
import Observation

struct SourceConfig: Codable {
    var enabled: Bool = true
    var apiKey: String = ""
    var apiUser: String = ""
    var tags: String = ""
    var extraParam: String = ""  // e.g. wallhaven purity string "110", reddit subreddits JSON
}

@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    // MARK: - NSFW

    var nsfwEnabled: Bool {
        get { defaults.bool(forKey: "nsfw_enabled") }
        set { defaults.set(newValue, forKey: "nsfw_enabled") }
    }

    // MARK: - Source configs

    var sourceConfigs: [String: SourceConfig] {
        get {
            guard let data = defaults.data(forKey: "source_configs"),
                  let decoded = try? JSONDecoder().decode([String: SourceConfig].self, from: data)
            else { return defaultConfigs() }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: "source_configs")
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

    private func defaultConfigs() -> [String: SourceConfig] {
        var c: [String: SourceConfig] = [:]
        for plugin in PluginRegistry.all {
            c[plugin.id] = SourceConfig(enabled: plugin.id == "GELBOORU")
        }
        return c
    }

    // MARK: - Reddit subreddits

    var redditSubreddits: [String] {
        get { defaults.stringArray(forKey: "reddit_subreddits") ?? ["wallpapers", "EarthPorn"] }
        set { defaults.set(newValue, forKey: "reddit_subreddits") }
    }

    // MARK: - MAL

    var malAccessToken: String {
        get { defaults.string(forKey: "mal_access_token") ?? "" }
        set { defaults.set(newValue, forKey: "mal_access_token") }
    }

    var malRefreshToken: String {
        get { defaults.string(forKey: "mal_refresh_token") ?? "" }
        set { defaults.set(newValue, forKey: "mal_refresh_token") }
    }

    var malUsername: String {
        get { defaults.string(forKey: "mal_username") ?? "" }
        set { defaults.set(newValue, forKey: "mal_username") }
    }

    var malFilterStatuses: Set<String> {
        get { Set(defaults.stringArray(forKey: "mal_filter_statuses") ?? ["watching", "completed"]) }
        set { defaults.set(Array(newValue), forKey: "mal_filter_statuses") }
    }

    var malMinScore: Int {
        get { defaults.integer(forKey: "mal_min_score") }
        set { defaults.set(newValue, forKey: "mal_min_score") }
    }

    var malAnimeList: [String] {
        get { defaults.stringArray(forKey: "mal_anime_list") ?? [] }
        set { defaults.set(newValue, forKey: "mal_anime_list") }
    }

    var malCodeVerifier: String {
        get { defaults.string(forKey: "mal_code_verifier") ?? "" }
        set { defaults.set(newValue, forKey: "mal_code_verifier") }
    }

    // MARK: - Discover

    var wifiOnlyDiscover: Bool {
        get { defaults.bool(forKey: "wifi_only_discover") }
        set { defaults.set(newValue, forKey: "wifi_only_discover") }
    }
}
