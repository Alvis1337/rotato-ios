import Foundation
import LocalAuthentication
import Observation
import RotatoKit
import SwiftUI

/// App-wide state shared by every screen: snapshots of the stored files plus the actions that
/// change them. Writes go through RotatoDatabase and then refresh the snapshot, so the widget
/// and Shortcuts (separate processes) always see the same data.
@MainActor
@Observable
public final class AppModel {
    public static let shared = AppModel()

    public let db: RotatoDatabase
    public let collectionsRepo: CollectionsRepository
    public let sourcesRepo: SourcesRepository
    public let catalog: PluginCatalog
    public let pool: RotationPool
    public let engine: RotationEngine

    public private(set) var settings = RotatoSettings()
    public private(set) var state = RotatoState()
    public private(set) var collections: [WallpaperCollection] = []
    public private(set) var entries: [CollectionEntry] = []
    public private(set) var sources: [SourceConfig] = []
    public private(set) var plugins: [PluginManifest] = []
    public private(set) var poolFiles: [URL] = []

    /// Locked collections unlocked with Face ID for this session.
    public var lockedUnlocked = false
    /// A short message shown at the bottom of the screen.
    public var toast: String?
    public private(set) var isSyncingPool = false

    /// Set by the app shell to run the user's Rotato shortcut (it owns `openURL`).
    public var openURL: ((URL) -> Void)?

    public init(db: RotatoDatabase = .shared) {
        self.db = db
        collectionsRepo = CollectionsRepository(db: db)
        sourcesRepo = SourcesRepository(db: db)
        catalog = PluginCatalog(db: db)
        pool = RotationPool(db: db)
        engine = RotationEngine(db: db)
        reload()
    }

    private var reloadScheduled = false

    /// Reloads when Shortcuts or the widget write (they run in other processes), coalescing bursts.
    public func observeExternalChanges() {
        RotatoDatabase.observeExternalChanges { [weak self] in
            Task { @MainActor in
                guard let self, !self.reloadScheduled else { return }
                self.reloadScheduled = true
                try? await Task.sleep(nanoseconds: 300_000_000)
                self.reloadScheduled = false
                self.reload()
            }
        }
    }

    /// Re-reads every file. Cheap enough to call after each write and on foreground.
    public func reload() {
        settings = db.read(DataFiles.settings)
        state = db.read(DataFiles.state)
        collections = db.read(DataFiles.collections)
        entries = db.read(DataFiles.entries)
        sources = db.read(DataFiles.sources)
        plugins = db.read(DataFiles.plugins)
        poolFiles = pool.files()
    }

    public func showToast(_ message: String) { toast = message }

    // MARK: Settings & state

    public func updateSettings(_ change: (inout RotatoSettings) -> Void) {
        db.update(DataFiles.settings, change)
        settings = db.read(DataFiles.settings)
    }

    public func updateState(_ change: (inout RotatoState) -> Void) {
        db.update(DataFiles.state, change)
        state = db.read(DataFiles.state)
    }

    /// Records the screen size in pixels so renders and "My Phone" filters match this device.
    public func recordScreen(width: Int, height: Int) {
        guard width > 0, height > 0,
              settings.filters.phoneScreenWidth != width || settings.filters.phoneScreenHeight != height else { return }
        updateSettings { $0.filters.phoneScreenWidth = width; $0.filters.phoneScreenHeight = height }
    }

    // MARK: Collections

    /// Collections the user can see now: locked ones need Face ID, and the content filter hides them.
    public var visibleCollections: [WallpaperCollection] {
        collections.filter { !$0.isLocked || (lockedUnlocked && !settings.nsfwHidden) }
    }

    public var lockedHiddenCount: Int {
        collections.filter(\.isLocked).count - visibleCollections.filter(\.isLocked).count
    }

    public func entries(in listId: String) -> [CollectionEntry] {
        entries.filter { $0.listId == listId }.sorted { $0.addedAt > $1.addedAt }
    }

    /// Collection ids each Discover wallpaper ("source:id") is saved in, among visible collections.
    public var savedListIds: [String: Set<String>] {
        let visible = Set(visibleCollections.map(\.id))
        var out: [String: Set<String>] = [:]
        for e in entries where visible.contains(e.listId) { out["\(e.source):\(e.sourceId)", default: []].insert(e.listId) }
        return out
    }

    public func isSaved(_ wp: Wallpaper) -> Bool { !(savedListIds[wp.key]?.isEmpty ?? true) }

    @discardableResult
    public func createCollection(_ name: String, useAsRotation: Bool = false, smartRule: SmartRule? = nil) -> WallpaperCollection? {
        let c = collectionsRepo.create(name: name, useAsRotation: useAsRotation, smartRule: smartRule)
        if c == nil { showToast("A collection with that name already exists") }
        afterCollectionsChange()
        return c
    }

    public func save(_ wp: Wallpaper, to listId: String) {
        if collectionsRepo.add(wp, to: listId) {
            LearnedTaste.record(wp.tags, .saved, db: db)
            let name = collections.first { $0.id == listId }?.name ?? "collection"
            showToast("Saved to \(name)")
        }
        afterCollectionsChange()
    }

    public func toggle(_ wp: Wallpaper, in listId: String) {
        if savedListIds[wp.key]?.contains(listId) == true {
            collectionsRepo.remove(wp, from: listId)
            afterCollectionsChange()
        } else {
            save(wp, to: listId)
        }
    }

    /// The collection the Save button uses: the "Save to list" choice, else Favorites.
    public var saveTarget: WallpaperCollection? {
        visibleCollections.first { $0.id == settings.saveToListId } ?? visibleCollections.first { $0.name == "Favorites" }
    }

    /// Saves to the "Save to list" collection (Favorites, created on first use, when none is set).
    public func quickSave(_ wp: Wallpaper) {
        guard let target = saveTarget ?? collectionsRepo.findOrCreate(name: "Favorites") else { return }
        if savedListIds[wp.key]?.contains(target.id) == true {
            collectionsRepo.remove(wp, from: target.id)
            afterCollectionsChange()
            showToast("Removed from \(target.name)")
        } else {
            save(wp, to: target.id)
        }
    }

    // MARK: Stealth

    /// Switches stealth mode: rotation only from the stealth collection, NSFW forced off.
    public func setStealth(_ on: Bool) {
        updateSettings { $0.stealthActive = on && !$0.stealthCollectionId.isEmpty }
        if on && settings.stealthCollectionId.isEmpty { showToast("Pick a stealth collection in NSFW & Privacy first") }
    }

    /// The per-source NSFW override, cycling inherit → on → off like the Android chips.
    public func cycleSourceNsfw(_ s: SourceConfig) {
        modifySource(s) { src in
            switch src.nsfwEnabled {
            case nil: src.nsfwEnabled = true
            case true?: src.nsfwEnabled = false
            case false?: src.nsfwEnabled = nil
            }
        }
    }

    public func modifyCollection(_ id: String, _ change: (inout WallpaperCollection) -> Void) {
        collectionsRepo.modify(id, change)
        afterCollectionsChange()
    }

    public func deleteCollection(_ id: String) {
        collectionsRepo.delete(id)
        afterCollectionsChange()
    }

    /// Refreshes smart collections, the snapshot and the rotation pool after a collection change.
    public func afterCollectionsChange() {
        collectionsRepo.refreshSmartCollections()
        reload()
        Task { await syncPool() }
    }

    /// Unlocks locked collections with Face ID / Touch ID / passcode for this session.
    public func unlockLocked() async -> Bool {
        if lockedUnlocked { return true }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // No passcode set: nothing to authenticate against, so allow.
            lockedUnlocked = true
            return true
        }
        let ok = (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Show locked collections")) ?? false
        lockedUnlocked = ok
        return ok
    }

    // MARK: Sources

    public func manifest(for source: SourceConfig) -> PluginManifest? {
        plugins.first { $0.id.caseInsensitiveCompare(source.pluginId) == .orderedSame }
    }

    public var enabledSources: [SourceConfig] { sources.filter(\.enabled) }

    public func modifySource(_ s: SourceConfig, _ change: (inout SourceConfig) -> Void) {
        sourcesRepo.modify(pluginId: s.pluginId, instanceId: s.instanceId, change)
        reload()
    }

    // MARK: Pool & rotation

    /// Downloads rotation-collection images that aren't in the pool yet.
    public func syncPool() async {
        guard !isSyncingPool else { return }
        isSyncingPool = true
        defer { isSyncingPool = false }
        let pool = self.pool
        let added = await Task.detached { await pool.syncRotationCollections() }.value
        if added > 0 { poolFiles = pool.files(); state = db.read(DataFiles.state) }
    }

    public func addPhotosToPool(_ datas: [Data]) {
        var n = 0
        for d in datas where pool.addPhoto(d) != nil { n += 1 }
        poolFiles = pool.files()
        showToast(n == 1 ? "Added 1 photo" : "Added \(n) photos")
    }

    public func removeFromPool(_ files: [URL]) {
        pool.remove(files)
        reload()
    }

    public func rate(_ file: URL, _ stars: Int) {
        updateState { $0.ratings[file.lastPathComponent] = stars == 0 ? nil : min(max(stars, 1), 5) }
    }

    /// Downloads a Discover wallpaper into the pool (for "Set now"). Returns its pool file.
    public func addToPool(_ wp: Wallpaper) async -> URL? {
        let entry = CollectionEntry(listId: "", wallpaper: wp)
        let pool = self.pool
        let file = await Task.detached { await pool.download(entry) }.value
        poolFiles = pool.files()
        state = db.read(DataFiles.state)
        return file
    }

    /// Shows `file` next on `screens` and runs the user's Rotato shortcut so it applies now.
    public func setNow(_ file: URL, screens: Set<WallpaperScreen> = [.home, .lock]) {
        engine.queue(file, screens: screens)
        state = db.read(DataFiles.state)
        runShortcut()
    }

    public func setNow(_ wp: Wallpaper, screens: Set<WallpaperScreen> = [.home, .lock]) async {
        guard !wp.isVideo else { showToast("Videos can't be wallpapers on iPhone"); return }
        guard let file = await addToPool(wp) else { showToast("Couldn't download that image"); return }
        LearnedTaste.record(wp.tags, .setWallpaper, db: db)
        setNow(file, screens: screens)
    }

    /// Opens Shortcuts to run the user's shortcut, coming back to Rotato afterwards.
    public func runShortcut() {
        var c = URLComponents(string: "shortcuts://x-callback-url/run-shortcut")!
        c.queryItems = [
            URLQueryItem(name: "name", value: settings.shortcutName),
            URLQueryItem(name: "x-success", value: "rotato://shortcut-done"),
            URLQueryItem(name: "x-error", value: "rotato://shortcut-error"),
        ]
        if let url = c.url { openURL?(url) }
    }

    /// Handles rotato:// links (Shortcuts callbacks).
    public func handle(_ url: URL) {
        guard url.scheme == "rotato" else { return }
        reload()
        switch url.host {
        // From the widget: widgets can't run shortcuts, so they open Rotato to do it.
        case "next": runShortcut()
        case "previous":
            if engine.queuePrevious(for: .home) != nil { runShortcut() } else { showToast("No earlier wallpaper yet") }
        case "shortcut-done": showToast("Wallpaper set")
        case "shortcut-error": showToast("Shortcut \"\(settings.shortcutName)\" didn't run. Check Settings → Shortcuts setup.")
        default: break
        }
    }

    // MARK: Blocking

    public func block(_ wp: Wallpaper) {
        updateState { s in
            if !wp.fullUrl.isBlank { s.blockedUrls.insert(wp.fullUrl) }
            if !wp.thumbUrl.isBlank { s.blockedUrls.insert(wp.thumbUrl) }
        }
        LearnedTaste.record(wp.tags, .blocked, db: db)
    }

    // MARK: First run

    /// Installs the bundled plugins and turns on the safe, keyless ones.
    public func completeSetup(enable pluginIds: Set<String>) {
        catalog.installAllBundled()
        for id in pluginIds { sourcesRepo.setPluginEnabled(id, true) }
        _ = collectionsRepo.findOrCreate(name: "Favorites")
        updateSettings { $0.setupDone = true }
        reload()
    }
}

extension AppModel {
    /// The engine-ready filters for Discover and fills.
    public var discoverFilters: DiscoverFilters { settings.filters }
}
