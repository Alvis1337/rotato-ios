import Foundation

/// A wallpaper the user asked to show next ("Set now" / "Use next"), consumed per screen.
public struct QueuedWallpaper: Codable, Hashable, Sendable {
    public var poolFile: String
    public var screens: Set<WallpaperScreen>
    public var queuedAt: Int64

    public init(poolFile: String, screens: Set<WallpaperScreen>, queuedAt: Int64 = nowMillis()) {
        self.poolFile = poolFile; self.screens = screens; self.queuedAt = queuedAt
    }
}

public enum RotationFailure: LocalizedError, Sendable {
    case poolEmpty
    case unreadable(String)

    public var errorDescription: String? {
        switch self {
        case .poolEmpty: "Your Rotato library is empty. Add photos or turn on rotation for a collection."
        case .unreadable(let name): "Couldn't read \(name)."
        }
    }
}

public struct RotationPick: Sendable {
    public let file: URL
    public let entry: CollectionEntry?
    public let isNsfw: Bool
    /// True when auto-pause kept the current wallpaper instead of picking a new one.
    public let paused: Bool
}

/// Picks the next wallpaper for a screen, the job WallpaperWorker does on Android. Shortcuts
/// calls this through the "Get Rotato Wallpaper" action; the result is then rendered and handed
/// to the system "Set Wallpaper" action.
public struct RotationEngine: Sendable {
    public let db: RotatoDatabase
    public let pool: RotationPool

    public init(db: RotatoDatabase = .shared, pool: RotationPool? = nil) {
        self.db = db
        self.pool = pool ?? RotationPool(db: db)
    }

    /// Picks (and records) the next wallpaper for `screen`. `automatic` runs respect auto-pause.
    public func next(for screen: WallpaperScreen, automatic: Bool = true, now: Date = Date()) throws -> RotationPick {
        let settings = db.read(DataFiles.settings)
        var state = db.read(DataFiles.state)
        let lists = db.read(DataFiles.collections)
        let entries = db.read(DataFiles.entries)
        let files = pool.files()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)

        // Auto-pause keeps what's showing; returning it makes the Set Wallpaper step a no-op.
        let hour = Calendar.current.component(.hour, from: now)
        if automatic, settings.autoPause.isInNightWindow(hour: hour),
           let current = state.current(for: screen), let f = pool.file(named: current.poolFile) {
            db.update(DataFiles.state) { $0.lastSkipReason = "Paused: night schedule is active" }
            return RotationPick(file: f, entry: pool.entry(for: f, in: entries), isNsfw: state.nsfwFileNames.contains(f.lastPathComponent), paused: true)
        }

        let candidates = candidatePool(for: screen, settings: settings, state: state, lists: lists, entries: entries, files: files, nowMs: nowMs)
        guard !candidates.isEmpty else {
            db.update(DataFiles.state) { $0.addError(RotationError(.POOL_EMPTY, "Rotation ran but the library pool is empty — add photos or link a collection")) }
            throw RotationFailure.poolEmpty
        }

        // A wallpaper the user queued wins, if it's still there and allowed here.
        var picked: URL?
        state.queuedNext.removeAll { nowMs - $0.queuedAt > 30 * 60_000 }
        if let i = state.queuedNext.firstIndex(where: { $0.screens.contains(screen) }),
           let f = pool.file(named: state.queuedNext[i].poolFile) {
            picked = f
            state.queuedNext[i].screens.remove(screen)
            if state.queuedNext[i].screens.isEmpty { state.queuedNext.remove(at: i) }
        }

        let file = picked ?? select(from: candidates, screen: screen, settings: settings, state: &state, now: now)
        let entry = pool.entry(for: file, in: entries)
        let isNsfw = state.nsfwFileNames.contains(file.lastPathComponent) || (entry?.isNsfw ?? false)

        state.totalRotations += 1
        state.lastSkipReason = nil
        state.recordShown(HistoryItem(
            thumbUrl: entry?.thumbUrl ?? "", sampleUrl: entry?.sampleUrl ?? "", fullUrl: entry?.fullUrl ?? "",
            source: entry?.source ?? "local", timestamp: nowMs, tags: entry?.tags ?? [], pageUrl: entry?.pageUrl ?? "",
            poolFile: file.lastPathComponent, screen: screen
        ))
        let finalState = state
        db.update(DataFiles.state) { s in
            s.currentIndex = finalState.currentIndex
            s.lockIndex = finalState.lockIndex
            s.queuedNext = finalState.queuedNext
            s.totalRotations = finalState.totalRotations
            s.lastSkipReason = nil
            s.history = finalState.history
        }
        if let listId = entry?.listId, lists.first(where: { $0.id == listId })?.rotationIntervalMinutes != nil {
            CollectionsRepository(db: db).modify(listId) { $0.lastRotationMs = nowMs }
        }
        return RotationPick(file: file, entry: entry, isNsfw: isNsfw, paused: false)
    }

    /// Pool files allowed on `screen` right now.
    func candidatePool(
        for screen: WallpaperScreen, settings: RotatoSettings, state: RotatoState,
        lists: [WallpaperCollection], entries: [CollectionEntry], files: [URL], nowMs: Int64
    ) -> [URL] {
        // Stealth mode: only the stealth collection, and never anything NSFW.
        if settings.stealthActive, !settings.stealthCollectionId.isEmpty {
            let stealth = entries.filter { $0.listId == settings.stealthCollectionId && !$0.isNsfw }
                .compactMap { pool.file(for: $0.source, sourceId: $0.sourceId, in: files) }
                .filter { !state.nsfwFileNames.contains($0.lastPathComponent) }
            if !stealth.isEmpty { return stealth }
        }
        let rotationLists = lists.filter(\.useAsRotation)
        // Per-collection intervals: lists on cooldown sit out, unless every list is on cooldown.
        let ready = rotationLists.filter { l in
            guard let mins = l.rotationIntervalMinutes else { return true }
            return nowMs - l.lastRotationMs >= Int64(mins) * 60_000
        }
        let active = ready.isEmpty ? rotationLists : ready
        let hasPerScreen = active.contains { $0.rotationTarget != .BOTH }

        var base = files
        if hasPerScreen {
            let ids = Set(active.filter { $0.rotationTarget == .BOTH || $0.rotationTarget == (screen == .home ? .HOME_ONLY : .LOCK_ONLY) }.map(\.id))
            let forScreen = entries.filter { ids.contains($0.listId) }.compactMap { pool.file(for: $0.source, sourceId: $0.sourceId, in: files) }
            if !forScreen.isEmpty { base = forScreen }
        } else if active.count < rotationLists.count {
            // Some lists are on cooldown: leave their images out of this turn.
            let cooling = Set(rotationLists.filter { l in !active.contains { $0.id == l.id } }.map(\.id))
            let coolingFiles = Set(entries.filter { cooling.contains($0.listId) }.compactMap { pool.file(for: $0.source, sourceId: $0.sourceId, in: files)?.lastPathComponent })
            let rest = files.filter { !coolingFiles.contains($0.lastPathComponent) }
            if !rest.isEmpty { base = rest }
        }

        var excluded = Set<String>()
        // Content filter: NSFW images and anything only in a locked collection sit out.
        if settings.nsfwHidden {
            excluded.formUnion(state.nsfwFileNames)
            let locked = Set(lists.filter(\.isLocked).map(\.id))
            let openKeys = Set(entries.filter { !locked.contains($0.listId) }.map { "\($0.source)|\($0.sourceId)" })
            for e in entries where locked.contains(e.listId) && !openKeys.contains("\(e.source)|\(e.sourceId)") {
                if let f = pool.file(for: e.source, sourceId: e.sourceId, in: files) { excluded.insert(f.lastPathComponent) }
            }
        }
        // Opt-in: NSFW wallpapers stay off the lock screen.
        if screen == .lock && settings.nsfwHomeOnly { excluded.formUnion(state.nsfwFileNames) }
        return excluded.isEmpty ? base : base.filter { !excluded.contains($0.lastPathComponent) }
    }

    func select(from images: [URL], screen: WallpaperScreen, settings: RotatoSettings, state: inout RotatoState, now: Date) -> URL {
        let currentName = state.current(for: screen)?.poolFile
        if !settings.shuffleMode {
            if screen == .home {
                let i = state.currentIndex % images.count
                state.currentIndex = (i + 1) % images.count
                return images[i]
            }
            let i = state.lockIndex % images.count
            state.lockIndex = (i + 1) % images.count
            return images[i]
        }
        var pool = settings.matchTimeOfDay ? timeOfDayPool(images, now: now) : images
        // Don't show the same wallpaper twice in a row.
        if pool.count > 1, let currentName { pool.removeAll { $0.lastPathComponent == currentName } }
        // Ratings weight shuffle: 5 stars comes up five times as often as 1 star; unrated counts as 2.
        var weighted: [URL] = []
        for f in pool {
            let rating = min(max(state.ratings[f.lastPathComponent] ?? 0, 0), 5)
            weighted += Array(repeating: f, count: rating == 0 ? 2 : rating)
        }
        return weighted.randomElement() ?? images[0]
    }

    /// Night (8pm–7am): the darker images; daytime: the brighter ones. Falls back to everything
    /// when fewer than two fit, so rotation never stalls.
    func timeOfDayPool(_ images: [URL], now: Date) -> [URL] {
        let hour = Calendar.current.component(.hour, from: now)
        let wantDark = hour >= 20 || hour < 7
        let looks = ImageAnalysis.brightness(of: images, db: db)
        let matching = images.filter { f in
            guard let b = looks[f.lastPathComponent] else { return false }
            return wantDark ? b <= ImageAnalysis.darkThreshold : b > ImageAnalysis.darkThreshold
        }
        return matching.count >= 2 ? matching : images
    }

    // MARK: Actions from the widget, Shortcuts and the app

    /// Queues pool files to be shown next on the given screens.
    public func queue(_ file: URL, screens: Set<WallpaperScreen>) {
        db.update(DataFiles.state) { s in
            s.queuedNext.removeAll { $0.poolFile == file.lastPathComponent }
            s.queuedNext.insert(QueuedWallpaper(poolFile: file.lastPathComponent, screens: screens), at: 0)
        }
    }

    /// The wallpaper shown before the current one on `screen`, queued so the next run shows it again.
    @discardableResult
    public func queuePrevious(for screen: WallpaperScreen) -> URL? {
        let history = db.read(DataFiles.state).history.filter { $0.screen == screen }
        guard history.count >= 2 else { return nil }
        for item in history.dropFirst() {
            if let f = pool.file(named: item.poolFile) {
                queue(f, screens: [screen])
                return f
            }
        }
        return nil
    }

    /// Saves what's showing on `screen` to a collection (Favorites by default).
    @discardableResult
    public func saveCurrent(screen: WallpaperScreen = .home, toCollectionNamed name: String = "Favorites") -> Bool {
        guard let current = db.read(DataFiles.state).current(for: screen) else { return false }
        let repo = CollectionsRepository(db: db)
        guard let list = repo.findOrCreate(name: name) else { return false }
        let entries = repo.entries
        if let f = pool.file(named: current.poolFile), let e = pool.entry(for: f, in: entries) {
            return repo.add(e.wallpaper, to: list.id)
        }
        // A photo added straight to the Library: save the pool file itself.
        let stem = (current.poolFile as NSString).deletingPathExtension
        let copy = RotatoPaths.device.appendingPathComponent(current.poolFile)
        if let f = pool.file(named: current.poolFile), !FileManager.default.fileExists(atPath: copy.path) {
            try? FileManager.default.copyItem(at: f, to: copy)
        }
        return repo.add(entries: [CollectionEntry(
            listId: list.id, sourceId: stem, source: "device",
            thumbUrl: "device/\(current.poolFile)", fullUrl: "device/\(current.poolFile)"
        )]) > 0
    }

    /// Blocks what's showing on `screen`: removed from the pool and never added again.
    public func blockCurrent(screen: WallpaperScreen = .home) {
        guard let current = db.read(DataFiles.state).current(for: screen) else { return }
        db.update(DataFiles.state) { s in
            if !current.fullUrl.isBlank { s.blockedUrls.insert(current.fullUrl) }
            if !current.thumbUrl.isBlank { s.blockedUrls.insert(current.thumbUrl) }
        }
        LearnedTaste.record(current.tags, .blocked, db: db)
        if let f = pool.file(named: current.poolFile) { pool.remove([f]) }
    }
}
