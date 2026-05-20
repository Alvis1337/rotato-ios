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
        guard !isLoading else { return }
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
        guard !isLoadingMore, hasMore, !items.isEmpty else { return }
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
                items.append(contentsOf: deduped.shuffled())
            }
        } catch {
            currentPage -= 1
        }
        isLoadingMore = false
    }

    func search() async {
        await load()
    }

    func clearSearch() {
        searchQuery = ""
        Task { await load() }
    }

    /// Toggle a source chip. If we go from N active → 0 active, treat as "all active" again.
    func toggleSource(_ id: String) {
        let wasEmpty = activeSourceIds.isEmpty
        let enabledIds = Set(PluginRegistry.all.filter { settings.config(for: $0.id).enabled }.map { $0.id })

        if wasEmpty {
            // All were active — deactivate all except the tapped one
            activeSourceIds = enabledIds.subtracting([id])
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
            var resumed = false
            monitor.pathUpdateHandler = { path in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: path.status == .satisfied)
                monitor.cancel()
            }
            monitor.start(queue: DispatchQueue.global(qos: .utility))
        }
    }

    private func fetchFromEnabledSources(page: Int) async throws -> [WallpaperItem] {
        let configs = settings.sourceConfigs
        let nsfw = settings.nsfwEnabled
        let userQuery = searchQuery
        let malTag = currentMalTag
        // Use MAL-injected tag when no user query, for plugins that support search
        let effectiveQuery = userQuery.isEmpty ? malTag : userQuery

        let enabledPlugins = PluginRegistry.all.filter { plugin in
            configs[plugin.id]?.enabled == true &&
            (activeSourceIds.isEmpty || activeSourceIds.contains(plugin.id))
        }

        guard !enabledPlugins.isEmpty else { return [] }

        return try await withThrowingTaskGroup(of: [WallpaperItem].self) { group in
            for plugin in enabledPlugins {
                let config = configs[plugin.id] ?? SourceConfig()
                let q = plugin.supportsSearch ? effectiveQuery : ""
                group.addTask {
                    (try? await plugin.fetch(
                        query: q,
                        page: page,
                        config: config,
                        nsfw: nsfw
                    )) ?? []
                }
            }
            var all: [WallpaperItem] = []
            for try await result in group { all += result }
            return all
        }
    }
}
