import Foundation
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

    private let settings: AppSettings

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

    // MARK: - Private

    private func fetchFromEnabledSources(page: Int) async throws -> [WallpaperItem] {
        let configs = settings.sourceConfigs
        let nsfw = settings.nsfwEnabled
        let query = searchQuery  // capture off actor before spawning tasks

        let enabledPlugins = PluginRegistry.all.filter { plugin in
            configs[plugin.id]?.enabled == true
        }

        guard !enabledPlugins.isEmpty else { return [] }

        return try await withThrowingTaskGroup(of: [WallpaperItem].self) { group in
            for plugin in enabledPlugins {
                let config = configs[plugin.id] ?? SourceConfig()
                group.addTask {
                    (try? await plugin.fetch(
                        query: query,
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
