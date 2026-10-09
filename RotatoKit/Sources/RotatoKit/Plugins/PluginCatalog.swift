import Foundation

public enum StoreResult: Sendable {
    case success(name: String, entries: [PluginStoreEntry])
    case failure(name: String, error: String)
}

public enum PluginCatalogError: LocalizedError {
    case fetchFailed(String)
    case invalidManifest(String)
    case emptyStore

    public var errorDescription: String? {
        switch self {
        case .fetchFailed(let url): "Couldn't download \(url)"
        case .invalidManifest(let url): "Not a valid Rotato plugin: \(url)"
        case .emptyStore: "No plugins found at this URL."
        }
    }
}

/// Installed plugins (bundled and from remote URLs) and plugin stores (PluginRepository on Android).
public struct PluginCatalog: Sendable {
    public static let storeIndexURL = "https://raw.githubusercontent.com/Alvis1337/rotato/main/plugin-store/index.json"
    public static let defaultStoreName = "Rotato Official"
    public static let redditId = "REDDIT"
    static let bundledIds: Set<String> = ["GELBOORU", "DANBOORU", "RULE34", "SAFEBOORU", "WALLHAVEN", "KONACHAN", "YANDERE", "ZEROCHAN", "REDDIT"]

    public let db: RotatoDatabase

    public init(db: RotatoDatabase = .shared) { self.db = db }

    public var installed: [PluginManifest] { db.read(DataFiles.plugins) }

    public func manifest(_ id: String) -> PluginManifest? {
        installed.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
    }

    /// Every manifest shipped with the app, installed or not.
    public static let bundled: [PluginManifest] = {
        guard let dir = Bundle.module.url(forResource: "plugins", withExtension: nil),
              let indexData = try? Data(contentsOf: dir.appendingPathComponent("index.json")),
              let names = try? JSONDecoder().decode([String].self, from: indexData) else { return [] }
        return names.compactMap { name in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
            return try? JSONDecoder().decode(PluginManifest.self, from: data)
        }
    }()

    /// Built-in plugins that aren't installed (e.g. removed by the user).
    public var missingBundled: [PluginManifest] {
        let have = Set(installed.map(\.id))
        return Self.bundled.filter { !have.contains($0.id) }
    }

    public func save(_ manifest: PluginManifest) {
        db.update(DataFiles.plugins) { all in
            all.removeAll { $0.id == manifest.id }
            all.append(manifest)
        }
        SourcesRepository(db: db).ensureRows(for: [manifest.id])
    }

    public func installBundled(_ id: String) {
        guard let m = Self.bundled.first(where: { $0.id == id }) else { return }
        save(m)
    }

    public func installAllBundled() {
        let have = Set(installed.map(\.id))
        let missing = Self.bundled.filter { !have.contains($0.id) }
        guard !missing.isEmpty else { return }
        db.update(DataFiles.plugins) { $0 += missing }
        SourcesRepository(db: db).ensureRows(for: missing.map(\.id))
    }

    public func uninstall(_ id: String) {
        db.update(DataFiles.plugins) { $0.removeAll { $0.id == id } }
        SourcesRepository(db: db).remove(pluginId: id)
    }

    /// Fetches a manifest JSON from `url`, validates it and installs it.
    @discardableResult
    public func install(fromURL url: String) async throws -> PluginManifest {
        guard let (data, _) = await HTTP.data(url, headers: ["User-Agent": "Rotato/1.0 plugin-installer"]) else {
            throw PluginCatalogError.fetchFailed(url)
        }
        guard var manifest = try? JSONDecoder().decode(PluginManifest.self, from: data) else {
            throw PluginCatalogError.invalidManifest(url)
        }
        manifest.sourceUrl = url
        save(manifest)
        return manifest
    }

    // MARK: Stores

    public var customStoreURLs: [String] { db.read(DataFiles.customStores) }

    /// Entries from the default store and every custom one, keyed by index URL, in order.
    public func fetchAllStores() async -> [(url: String, result: StoreResult)] {
        let urls = [Self.storeIndexURL] + customStoreURLs
        return await withTaskGroup(of: (Int, String, StoreResult).self) { group in
            for (i, url) in urls.enumerated() {
                group.addTask {
                    do {
                        let (name, entries) = try await fetchStore(url)
                        return (i, url, .success(name: name, entries: entries))
                    } catch {
                        let name = url == Self.storeIndexURL ? Self.defaultStoreName : (URL(string: url)?.host ?? url)
                        return (i, url, .failure(name: name, error: error.localizedDescription))
                    }
                }
            }
            var out: [(Int, String, StoreResult)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
        }
    }

    public func fetchStore(_ url: String) async throws -> (name: String, entries: [PluginStoreEntry]) {
        guard let (data, _) = await HTTP.data(url, headers: ["User-Agent": "Rotato/1.0 plugin-store"]),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PluginCatalogError.fetchFailed(url)
        }
        let name = obj.str("name").ifBlank(URL(string: url)?.host ?? url)
        let raw = (obj["plugins"] as? [Any]) ?? []
        let rawData = (try? JSONSerialization.data(withJSONObject: raw)) ?? Data("[]".utf8)
        var entries = (try? JSONDecoder().decode(LossyArray<PluginStoreEntry>.self, from: rawData))?.elements ?? []
        for i in entries.indices {
            entries[i].storeSource = url
            entries[i].storeName = name
        }
        return (name, entries)
    }

    /// Plugin ids where the store has a newer versionCode than the installed one.
    public func updatesAvailable(in entries: [PluginStoreEntry]) -> Set<String> {
        let have = Dictionary(installed.map { ($0.id, $0.versionCode) }, uniquingKeysWith: { a, _ in a })
        return Set(entries.filter { e in have[e.id].map { e.versionCode > $0 } ?? false }.map(\.id))
    }

    /// Validates `url` as a plugin index and adds it. Returns the store's name.
    @discardableResult
    public func addCustomStore(_ url: String) async throws -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let (name, entries) = try await fetchStore(trimmed)
        if entries.isEmpty { throw PluginCatalogError.emptyStore }
        db.update(DataFiles.customStores) { if !$0.contains(trimmed) { $0.append(trimmed) } }
        return name
    }

    public func removeCustomStore(_ url: String) {
        db.update(DataFiles.customStores) { $0.removeAll { $0 == url } }
    }
}
