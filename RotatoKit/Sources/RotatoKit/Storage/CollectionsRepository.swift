import Foundation

/// Collections and their entries (LocalListsPreferences on Android).
public struct CollectionsRepository: Sendable {
    public let db: RotatoDatabase

    public init(db: RotatoDatabase = .shared) { self.db = db }

    public var collections: [WallpaperCollection] { db.read(DataFiles.collections) }
    public var entries: [CollectionEntry] { db.read(DataFiles.entries) }

    public func entries(in listId: String) -> [CollectionEntry] { entries.filter { $0.listId == listId } }

    /// Returns nil when the name is blank or already taken.
    @discardableResult
    public func create(name: String, useAsRotation: Bool = false, smartRule: SmartRule? = nil) -> WallpaperCollection? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let list = WallpaperCollection(name: trimmed, useAsRotation: useAsRotation, smartRule: smartRule)
        let created = db.update(DataFiles.collections) { lists -> Bool in
            if lists.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) { return false }
            lists.append(list)
            return true
        }
        return created ? list : nil
    }

    /// The collection named `name`, created if needed (e.g. "Favorites").
    public func findOrCreate(name: String) -> WallpaperCollection? {
        if let existing = collections.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { return existing }
        return create(name: name)
    }

    public func delete(_ id: String) {
        db.update(DataFiles.collections) { $0.removeAll { $0.id == id } }
        db.update(DataFiles.entries) { $0.removeAll { $0.listId == id } }
    }

    /// Moves a collection `delta` places earlier (negative) or later (positive).
    public func move(_ id: String, by delta: Int) {
        db.update(DataFiles.collections) { lists in
            guard let from = lists.firstIndex(where: { $0.id == id }) else { return }
            let to = min(max(from + delta, 0), lists.count - 1)
            guard to != from else { return }
            lists.insert(lists.remove(at: from), at: to)
        }
    }

    public func reorder(_ ids: [String]) {
        db.update(DataFiles.collections) { lists in
            let byId = Dictionary(lists.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let ordered = ids.compactMap { byId[$0] }
            let rest = lists.filter { !ids.contains($0.id) }
            lists = ordered + rest
        }
    }

    /// False when the name is blank or taken by another collection.
    @discardableResult
    public func rename(_ id: String, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return db.update(DataFiles.collections) { lists -> Bool in
            if lists.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) { return false }
            guard let i = lists.firstIndex(where: { $0.id == id }) else { return false }
            lists[i].name = trimmed
            return true
        }
    }

    /// Edits one collection in place.
    public func modify(_ id: String, _ change: (inout WallpaperCollection) -> Void) {
        db.update(DataFiles.collections) { lists in
            guard let i = lists.firstIndex(where: { $0.id == id }) else { return }
            change(&lists[i])
        }
    }

    /// False when it was already in the collection (same post or same URL).
    @discardableResult
    public func add(_ wp: Wallpaper, to listId: String) -> Bool {
        db.update(DataFiles.entries) { all -> Bool in
            if all.contains(where: { $0.listId == listId && ($0.sourceId == wp.id || (!wp.fullUrl.isBlank && $0.fullUrl == wp.fullUrl)) }) {
                return false
            }
            all.append(CollectionEntry(listId: listId, wallpaper: wp))
            return true
        }
    }

    /// Adds several entries in one write, skipping ones already in their collection. Returns how many were added.
    @discardableResult
    public func add(entries new: [CollectionEntry]) -> Int {
        guard !new.isEmpty else { return 0 }
        return db.update(DataFiles.entries) { all -> Int in
            var existing = Set(all.map { "\($0.listId)|\($0.sourceId)" })
            let fresh = new.filter { existing.insert("\($0.listId)|\($0.sourceId)").inserted }
            all += fresh
            return fresh.count
        }
    }

    public func remove(entryIds: Set<String>) {
        guard !entryIds.isEmpty else { return }
        db.update(DataFiles.entries) { $0.removeAll { entryIds.contains($0.id) } }
    }

    /// Removes a Discover wallpaper from one collection.
    public func remove(_ wp: Wallpaper, from listId: String) {
        db.update(DataFiles.entries) { all in
            all.removeAll { $0.listId == listId && $0.source == wp.source && $0.sourceId == wp.id }
        }
    }

    /// Moves entries to `targetListId` in one write, dropping ones already there. Returns how many moved.
    @discardableResult
    public func move(entryIds: Set<String>, to targetListId: String) -> Int {
        db.update(DataFiles.entries) { all -> Int in
            let inTarget = all.filter { $0.listId == targetListId }
            var ids = Set(inTarget.map(\.sourceId))
            var urls = Set(inTarget.compactMap { $0.fullUrl.nilIfBlank })
            var moved = 0
            all = all.compactMap { e in
                guard entryIds.contains(e.id), e.listId != targetListId else { return e }
                if ids.contains(e.sourceId) || (!e.fullUrl.isBlank && urls.contains(e.fullUrl)) { return nil }
                ids.insert(e.sourceId)
                if !e.fullUrl.isBlank { urls.insert(e.fullUrl) }
                moved += 1
                var copy = e
                copy.listId = targetListId
                return copy
            }
            return moved
        }
    }

    /// Copies entries into another collection, keeping the originals.
    @discardableResult
    public func copy(entryIds: Set<String>, to targetListId: String) -> Int {
        let picked = entries.filter { entryIds.contains($0.id) }
        return add(entries: picked.map { e in
            var c = e
            c.id = UUID().uuidString.lowercased()
            c.listId = targetListId
            c.addedAt = nowMillis()
            return c
        })
    }

    /// Moves everything from `fromId` into `intoId` (skipping duplicates) and deletes `fromId`.
    @discardableResult
    public func merge(_ fromId: String, into intoId: String) -> Int {
        guard fromId != intoId else { return 0 }
        let ids = Set(entries(in: fromId).map(\.id))
        let moved = move(entryIds: ids, to: intoId)
        delete(fromId)
        return moved
    }

    /// Adds a photo imported from the device. `relativePath` is under RotatoPaths.device.
    public func addDeviceImage(fileName: String, to listId: String) {
        let stem = (fileName as NSString).deletingPathExtension
        _ = add(entries: [CollectionEntry(
            listId: listId, sourceId: stem, source: "device",
            thumbUrl: "device/\(fileName)", fullUrl: "device/\(fileName)"
        )])
    }

    /// Entries that belong to rotation collections, which the pool downloads.
    public func rotationEntries() -> [CollectionEntry] {
        let ids = Set(collections.filter(\.useAsRotation).map(\.id))
        return entries.filter { ids.contains($0.listId) }
    }

    /// Smart collections: adds saved wallpapers matching each rule that aren't in it yet.
    @discardableResult
    public func refreshSmartCollections() -> Int {
        let lists = collections.filter(\.isSmartCollection)
        guard !lists.isEmpty else { return 0 }
        let all = entries
        var additions: [CollectionEntry] = []
        for list in lists {
            guard let rule = list.smartRule else { continue }
            let have = Set(all.filter { $0.listId == list.id }.map { "\($0.source)|\($0.sourceId)" })
            var seen = have
            for e in all where e.listId != list.id && rule.matches(e) {
                if seen.insert("\(e.source)|\(e.sourceId)").inserted {
                    var c = e
                    c.id = UUID().uuidString.lowercased()
                    c.listId = list.id
                    additions.append(c)
                }
            }
        }
        return add(entries: additions)
    }
}

/// Configured sources (LocalSourcesPreferences on Android).
public struct SourcesRepository: Sendable {
    public let db: RotatoDatabase

    public init(db: RotatoDatabase = .shared) { self.db = db }

    public var sources: [SourceConfig] { db.read(DataFiles.sources) }

    public func modify(pluginId: String, instanceId: String = "", _ change: (inout SourceConfig) -> Void) {
        db.update(DataFiles.sources) { all in
            guard let i = all.firstIndex(where: { $0.pluginId == pluginId && $0.instanceId == instanceId }) else { return }
            change(&all[i])
        }
    }

    public func upsert(_ source: SourceConfig) {
        db.update(DataFiles.sources) { all in
            if let i = all.firstIndex(where: { $0.pluginId == source.pluginId && $0.instanceId == source.instanceId }) {
                all[i] = source
            } else {
                all.append(source)
            }
        }
    }

    public func addInstance(pluginId: String, instanceId: String) {
        let trimmed = instanceId.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        db.update(DataFiles.sources) { all in
            if all.contains(where: { $0.pluginId == pluginId && $0.instanceId == trimmed }) { return }
            all.append(SourceConfig(pluginId: pluginId, instanceId: trimmed, enabled: true))
        }
    }

    public func removeInstance(pluginId: String, instanceId: String) {
        db.update(DataFiles.sources) { $0.removeAll { $0.pluginId == pluginId && $0.instanceId == instanceId } }
    }

    public func remove(pluginId: String) {
        db.update(DataFiles.sources) { $0.removeAll { $0.pluginId == pluginId } }
    }

    /// Switches every row of a plugin on or off, creating its default row if it has none.
    public func setPluginEnabled(_ pluginId: String, _ enabled: Bool) {
        db.update(DataFiles.sources) { all in
            if !all.contains(where: { $0.pluginId == pluginId }) {
                if pluginId != PluginCatalog.redditId { all.append(SourceConfig(pluginId: pluginId, enabled: enabled)) }
            } else {
                for i in all.indices where all[i].pluginId == pluginId { all[i].enabled = enabled }
            }
        }
    }

    /// Adds a disabled default row for each installed plugin that has none.
    public func ensureRows(for pluginIds: [String]) {
        db.update(DataFiles.sources) { all in
            let have = Set(all.map(\.pluginId))
            var seen = Set<String>()
            for id in pluginIds where !have.contains(id) && id != PluginCatalog.redditId && seen.insert(id).inserted {
                all.append(SourceConfig(pluginId: id, enabled: false))
            }
        }
    }
}
