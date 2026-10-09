import Foundation

/// Backups in the Android app's format (version 4): sources with keys, a few preferences,
/// collections, their wallpapers and installed plugins. Backups move between the two apps;
/// iOS-only settings ride along under "iosSettings", which Android ignores.
public enum BackupService {
    struct Backup: Codable {
        var version: Int = 4
        var sources: [SourceConfig]
        var preferences: Preferences
        var collections: [WallpaperCollection]
        var collectionWallpapers: [CollectionEntry]
        var installedPlugins: [PluginManifest]
        var iosSettings: RotatoSettings?

        enum CodingKeys: String, CodingKey {
            case version, sources, preferences, collections, collectionWallpapers, installedPlugins, iosSettings
        }

        init(sources: [SourceConfig], preferences: Preferences, collections: [WallpaperCollection],
             collectionWallpapers: [CollectionEntry], installedPlugins: [PluginManifest], iosSettings: RotatoSettings?) {
            self.sources = sources; self.preferences = preferences; self.collections = collections
            self.collectionWallpapers = collectionWallpapers; self.installedPlugins = installedPlugins; self.iosSettings = iosSettings
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = c.value(.version, 0)
            guard version > 0 else {
                throw DecodingError.dataCorruptedError(forKey: .version, in: c, debugDescription: "Not a Rotato backup")
            }
            sources = (c.optionalValue(.sources) as LossyArray<SourceConfig>?)?.elements ?? []
            preferences = c.value(.preferences, Preferences())
            collections = (c.optionalValue(.collections) as LossyArray<WallpaperCollection>?)?.elements ?? []
            collectionWallpapers = (c.optionalValue(.collectionWallpapers) as LossyArray<CollectionEntry>?)?.elements ?? []
            installedPlugins = (c.optionalValue(.installedPlugins) as LossyArray<PluginManifest>?)?.elements ?? []
            iosSettings = c.optionalValue(.iosSettings)
        }
    }

    /// The preferences both apps share.
    struct Preferences: Codable {
        var shuffleMode: Bool?
        var nsfwMode: Bool?
        var nsfwHidden: Bool?
        var minResolution: String?
        var aspectRatio: String?
    }

    /// Writes a backup file to the temporary folder and returns it (for ShareLink).
    public static func export(db: RotatoDatabase = .shared) throws -> URL {
        let s = db.read(DataFiles.settings)
        let backup = Backup(
            sources: db.read(DataFiles.sources),
            preferences: Preferences(
                shuffleMode: s.shuffleMode, nsfwMode: s.nsfwMode, nsfwHidden: s.nsfwHidden,
                minResolution: s.filters.minResolution.rawValue, aspectRatio: s.filters.aspectRatio.rawValue
            ),
            collections: db.read(DataFiles.collections),
            // Device photos live only on this phone.
            collectionWallpapers: db.read(DataFiles.entries).filter { !$0.isDeviceImage },
            installedPlugins: db.read(DataFiles.plugins),
            iosSettings: s
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let day = Date().formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rotato-backup-\(day).json")
        try enc.encode(backup).write(to: url, options: .atomic)
        return url
    }

    /// Restores a backup: sources and plugins are replaced, collections and wallpapers merged in.
    /// Returns a one-line summary.
    @discardableResult
    public static func restore(from url: URL, db: RotatoDatabase = .shared) throws -> String {
        let backup = try JSONDecoder().decode(Backup.self, from: Data(contentsOf: url))
        if !backup.installedPlugins.isEmpty { db.write(DataFiles.plugins, backup.installedPlugins) }
        db.write(DataFiles.sources, backup.sources)
        db.update(DataFiles.collections) { lists in
            let have = Set(lists.map(\.id))
            lists += backup.collections.filter { !have.contains($0.id) }
        }
        let added = CollectionsRepository(db: db).add(entries: backup.collectionWallpapers)
        db.update(DataFiles.settings) { s in
            if let ios = backup.iosSettings {
                let done = s.setupDone, screenW = s.filters.phoneScreenWidth, screenH = s.filters.phoneScreenHeight
                s = ios
                s.setupDone = done
                s.filters.phoneScreenWidth = screenW
                s.filters.phoneScreenHeight = screenH
            } else {
                let p = backup.preferences
                if let v = p.shuffleMode { s.shuffleMode = v }
                if let v = p.nsfwMode { s.nsfwMode = v }
                if let v = p.nsfwHidden { s.nsfwHidden = v }
                if let v = p.minResolution.flatMap(MinResolution.init) { s.filters.minResolution = v }
                if let v = p.aspectRatio.flatMap(AspectRatio.init) { s.filters.aspectRatio = v }
            }
        }
        return "Restored \(backup.collections.count) collections, \(added) wallpapers, \(backup.sources.count) sources"
    }
}
