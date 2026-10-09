import Foundation

/// The rotation pool: image files Shortcuts picks from (the Library tab). Files are named by
/// `poolKey(source:sourceId:)` so an entry can find its file again; photos added straight to the
/// Library get a UUID name.
public struct RotationPool: Sendable {
    public static let imageExts: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "heic"]

    public let directory: URL
    public let db: RotatoDatabase

    public init(directory: URL = RotatoPaths.pool, db: RotatoDatabase = .shared) {
        self.directory = directory
        self.db = db
    }

    /// Pool images sorted by name (stable order for sequential mode).
    public func files() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return items
            .filter { Self.imageExts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func file(named name: String) -> URL? {
        let u = directory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    /// The pool file for an entry, preferring the source-prefixed name over the older plain one.
    public func file(for source: String, sourceId: String, in files: [URL]? = nil) -> URL? {
        let all = files ?? self.files()
        let byStem = Dictionary(all.map { ($0.deletingPathExtension().lastPathComponent, $0) }, uniquingKeysWith: { a, _ in a })
        for key in [poolKey(source: source, sourceId: sourceId), sanitizeFilename(sourceId)] {
            if let f = byStem[key] { return f }
        }
        return nil
    }

    /// Writes image bytes into the pool via a temp file, so a half-written file is never picked.
    @discardableResult
    public func store(_ data: Data, key: String, ext: String) -> URL? {
        let name = "\(key).\(ext)"
        let tmp = directory.appendingPathComponent("\(name).part")
        let dest = directory.appendingPathComponent(name)
        do {
            try data.write(to: tmp, options: .atomic)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            return dest
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return nil
        }
    }

    /// Adds a photo picked from the device straight into the pool.
    @discardableResult
    public func addPhoto(_ data: Data) -> URL? {
        let ext = ImageDownloader.extFromBytes(data) ?? "jpg"
        return store(data, key: UUID().uuidString.lowercased(), ext: ext)
    }

    public func remove(_ files: [URL]) {
        let names = Set(files.map(\.lastPathComponent))
        for f in files { try? FileManager.default.removeItem(at: f) }
        db.update(DataFiles.state) { s in
            s.nsfwFileNames.subtract(names)
            for n in names { s.ratings[n] = nil }
            s.queuedNext.removeAll { names.contains($0.poolFile) }
        }
    }

    public func removeAll() { remove(files()) }

    /// Downloads one entry into the pool unless it's already there. Returns the pool file.
    @discardableResult
    public func download(_ entry: CollectionEntry, existing: [URL]? = nil) async -> URL? {
        if let f = file(for: entry.source, sourceId: entry.sourceId, in: existing), ImageDownloader.isValidImage(at: f) { return f }
        if entry.isVideo { return nil } // iOS can't use a video as a still wallpaper
        if entry.isDeviceImage {
            let src = RotatoPaths.container.appendingPathComponent(entry.fullUrl)
            guard let data = try? Data(contentsOf: src) else { return nil }
            return store(data, key: entry.poolKey, ext: src.pathExtension.ifBlank("jpg"))
        }
        let auth = danbooruAuth(for: entry.fullUrl)
        guard let r = await ImageDownloader.download(entry.fullUrl, fallback: entry.sampleUrl.ifBlank(entry.thumbUrl), authHeader: auth),
              !MediaType.isVideoURL("x.\(r.ext)") else { return nil }
        let url = store(r.data, key: entry.poolKey, ext: r.ext)
        if url != nil, entry.isNsfw {
            db.update(DataFiles.state) { $0.nsfwFileNames.insert("\(entry.poolKey).\(r.ext)") }
        }
        return url
    }

    /// Downloads every rotation-collection entry that isn't in the pool yet, a few at a time.
    /// Returns how many files were added.
    @discardableResult
    public func syncRotationCollections(limit: Int = .max) async -> Int {
        let existing = files()
        // The stealth collection is downloaded too, so stealth mode has something to show.
        let settings = db.read(DataFiles.settings)
        let repo = CollectionsRepository(db: db)
        let stealth = settings.stealthCollectionId.isEmpty ? [] : repo.entries(in: settings.stealthCollectionId)
        let missing = (repo.rotationEntries() + stealth)
            .filter { !$0.fullUrl.isBlank && !$0.isVideo && file(for: $0.source, sourceId: $0.sourceId, in: existing) == nil }
        var seen = Set<String>()
        let todo = missing.filter { seen.insert($0.poolKey).inserted }.prefix(limit)
        guard !todo.isEmpty else { return 0 }
        var added = 0
        let batches = stride(from: 0, to: todo.count, by: 4).map { Array(todo.dropFirst($0).prefix(4)) }
        for batch in batches {
            if Task.isCancelled { break }
            let results = await withTaskGroup(of: Bool.self) { group in
                for e in batch { group.addTask { await download(e, existing: existing) != nil } }
                var n = 0
                for await ok in group where ok { n += 1 }
                return n
            }
            added += results
        }
        return added
    }

    private func danbooruAuth(for url: String) -> String? {
        guard url.contains("donmai.us") else { return nil }
        let src = SourcesRepository(db: db).sources.first {
            $0.pluginId.caseInsensitiveCompare("DANBOORU") == .orderedSame && !$0.apiKey.isBlank && !$0.apiUser.isBlank
        }
        return src.flatMap(DanbooruEngine.authHeader)
    }

    /// Entry (if any) that this pool file came from.
    public func entry(for file: URL, in entries: [CollectionEntry]) -> CollectionEntry? {
        let stem = file.deletingPathExtension().lastPathComponent
        return entries.first { $0.poolKey == stem } ?? entries.first { sanitizeFilename($0.sourceId) == stem }
    }
}
