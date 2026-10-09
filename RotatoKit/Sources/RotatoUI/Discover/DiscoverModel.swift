import Foundation
import Observation
import RotatoKit

/// Discover's screen state over DiscoverFeed (the UI half of BrainrotViewModel).
@MainActor
@Observable
final class DiscoverModel {
    private(set) var items: [Wallpaper] = []
    private(set) var loading = false
    private(set) var loadingMore = false
    private(set) var endReached = false
    private(set) var noResults: NoResultsReason?
    private(set) var query = ""
    private(set) var health: [SourceHealth] = []
    /// The last few skipped or blocked posts, for Undo.
    private(set) var undoStack: [(Wallpaper, Int)] = []

    private let feed: DiscoverFeed
    private let db: RotatoDatabase
    private var loadTask: Task<Void, Never>?
    private var started = false

    init(db: RotatoDatabase = .shared) {
        self.db = db
        feed = DiscoverFeed(db: db)
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        loadMore()
    }

    /// Starts the feed over, optionally with a new search.
    func reset(query newQuery: String? = nil) {
        loadTask?.cancel()
        loadTask = nil
        if let newQuery { query = newQuery.trimmingCharacters(in: .whitespacesAndNewlines) }
        items = []
        endReached = false
        noResults = nil
        undoStack = []
        let q = query
        let feed = self.feed
        loadTask = Task {
            await feed.reset(query: q)
            loadTask = nil
            loadMore()
        }
    }

    /// Loads the next batch unless one is already loading or the feed ran out.
    func loadMore() {
        guard loadTask == nil, !endReached else { return }
        let initial = items.isEmpty
        if initial { loading = true } else { loadingMore = true }
        let feed = self.feed
        loadTask = Task {
            let batch = await feed.next(initial: initial)
            if Task.isCancelled { return }
            let have = Set(items.map(\.key))
            items += batch.items.filter { !have.contains($0.key) }
            endReached = batch.endReached
            noResults = batch.noResults
            health = await feed.health.values.sorted { $0.name < $1.name }
            loading = false
            loadingMore = false
            loadTask = nil
        }
    }

    /// Prefetches when the viewer gets near the end.
    func onAppear(index: Int) {
        if index >= items.count - 6 { loadMore() }
    }

    /// Removes a post from the feed (skip in grid mode, block), remembering it for Undo.
    func remove(_ wp: Wallpaper) {
        guard let i = items.firstIndex(where: { $0.key == wp.key }) else { return }
        items.remove(at: i)
        undoStack.append((wp, i))
        if undoStack.count > 3 { undoStack.removeFirst() }
        if items.count < 6 { loadMore() }
    }

    func undo() -> Int? {
        guard let (wp, i) = undoStack.popLast() else { return nil }
        let at = min(i, items.count)
        items.insert(wp, at: at)
        return at
    }

    func skip(_ wp: Wallpaper) {
        LearnedTaste.record(wp.tags, .skipped, db: db)
    }
}
