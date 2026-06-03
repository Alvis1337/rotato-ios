import Foundation
import Network
import Observation

@Observable
@MainActor
final class DiscoverViewModel {
    var items: [WallpaperItem] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var searchQuery = ""
    var matchAny = false
    var currentPage = 0
    var hasMore = true
    var noResults = false

    /// Source IDs the user has toggled ON in the chip row.
    /// Empty = all enabled sources are active.
    var activeSourceIds: Set<String> = []

    private let settings: AppSettings
    /// MAL title injected for the current load session (when searchQuery is empty).
    private(set) var currentMalTag: String = ""

    init(settings: AppSettings) {
        self.settings = settings
    }

    func load() async {
        guard !isLoading, !isLoadingMore else { return }
        isLoading = true
        errorMessage = nil
        noResults = false
        currentPage = 0
        hasMore = true

        // Inject a random MAL anime title when the user hasn't typed a query
        if searchQuery.isEmpty && !settings.malAnimeList.isEmpty {
            currentMalTag = settings.malAnimeList.randomElement() ?? ""
        } else {
            currentMalTag = ""
        }

        do {
            let results = try await fetchFromEnabledSources(page: 0)
            items = results.shuffled()
            noResults = items.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadMore() async {
        guard !isLoadingMore, !isLoading, hasMore, !items.isEmpty else { return }
        // Respect wifi-only setting for auto-triggered loads
        if settings.wifiOnlyDiscover, !(await isOnWiFi()) { return }
        isLoadingMore = true
        currentPage += 1

        do {
            let more = try await fetchFromEnabledSources(page: currentPage)
            if more.isEmpty {
                hasMore = false
            } else {
                let existingIds = Set(items.map { $0.id })
                let deduped = more.filter { !existingIds.contains($0.id) }
                if deduped.isEmpty {
                    // All new results were duplicates — stop to prevent infinite loop
                    hasMore = false
                } else {
                    items.append(contentsOf: deduped.shuffled())
                }
            }
        } catch {
            if !isLoading { currentPage -= 1 }
        }
        isLoadingMore = false
    }

    func search() async {
        await load()
    }

    func clearSearch() {
        searchQuery = ""
        matchAny = false
        Task { await load() }
    }

    func queryForPlugin(_ pluginId: String) -> String {
        guard matchAny else { return searchQuery }

        let tokens = searchQuery
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        guard tokens.count > 1 else { return searchQuery }

        switch pluginId.uppercased() {
        case "DANBOORU", "SAFEBOORU":
            return tokens.map { "~\($0)" }.joined(separator: " ")
        case "GELBOORU", "RULE34", "YANDERE", "KONACHAN":
            return "( " + tokens.joined(separator: " ~ ") + " )"
        default:
            return tokens.first ?? searchQuery
        }
    }

    /// Toggle a source chip. If we go from N active → 0 active, treat as "all active" again.
    func toggleSource(_ id: String) {
        let wasEmpty = activeSourceIds.isEmpty
        let enabledIds = Set(PluginRegistry.all.filter { settings.config(for: $0.id).enabled }.map { $0.id })

        if wasEmpty {
            // All were active — show only the tapped one
            activeSourceIds = [id]
        } else {
            if activeSourceIds.contains(id) {
                activeSourceIds.remove(id)
                if activeSourceIds.isEmpty { activeSourceIds = [] }  // back to "all"
            } else {
                activeSourceIds.insert(id)
                // If all enabled sources are now active, collapse back to empty (= all)
                if activeSourceIds == enabledIds { activeSourceIds = [] }
            }
        }
        Task { await load() }
    }

    // MARK: - Private

    private func isOnWiFi() async -> Bool {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
            let queue = DispatchQueue(label: "com.rotato.wifi-check")
            monitor.pathUpdateHandler = { path in
                continuation.resume(returning: path.status == .satisfied)
                monitor.cancel()
            }
            monitor.start(queue: queue)
        }
    }

    private func fetchFromEnabledSources(page: Int) async throws -> [WallpaperItem] {
        let configs = settings.sourceConfigs
        let nsfw = settings.nsfwEnabled
        let userQuery = searchQuery
        let malTag = currentMalTag

        let enabledPlugins = PluginRegistry.all.filter { plugin in
            configs[plugin.id]?.enabled == true &&
            (activeSourceIds.isEmpty || activeSourceIds.contains(plugin.id))
        }

        guard !enabledPlugins.isEmpty else { return [] }

        return try await withThrowingTaskGroup(of: [WallpaperItem].self) { group in
            for plugin in enabledPlugins {
                var config = configs[plugin.id] ?? SourceConfig()
                // Inject a random configured subreddit for the Reddit plugin
                if plugin.id == "REDDIT", !settings.redditSubreddits.isEmpty {
                    config.extraParam = settings.redditSubreddits.randomElement() ?? "wallpapers"
                }
                let pluginQuery = userQuery.isEmpty ? malTag : queryForPlugin(plugin.id)
                let q = plugin.supportsSearch ? pluginQuery : ""
                // Per-source NSFW override; falls back to global setting
                let effectiveNsfw = config.nsfwOverride ?? nsfw
                group.addTask {
                    (try? await plugin.fetch(
                        query: q,
                        page: page,
                        config: config,
                        nsfw: effectiveNsfw
                    )) ?? []
                }
            }
            var all: [WallpaperItem] = []
            for try await result in group { all += result }
            return all
        }
    }
}
