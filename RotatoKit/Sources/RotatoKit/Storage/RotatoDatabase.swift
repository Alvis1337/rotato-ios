import Foundation

/// A typed JSON file in the data directory.
public struct DataFile<Value: Codable & Sendable>: Sendable {
    public let name: String
    public let empty: @Sendable () -> Value

    public init(_ name: String, empty: @escaping @Sendable () -> Value) {
        self.name = name
        self.empty = empty
    }
}

public enum DataFiles {
    public static let collections = DataFile<[WallpaperCollection]>("collections.json") { [] }
    public static let entries = DataFile<[CollectionEntry]>("entries.json") { [] }
    public static let sources = DataFile<[SourceConfig]>("sources.json") { [] }
    public static let plugins = DataFile<[PluginManifest]>("plugins.json") { [] }
    public static let customStores = DataFile<[String]>("custom_stores.json") { [] }
    public static let settings = DataFile<RotatoSettings>("settings.json") { RotatoSettings() }
    public static let state = DataFile<RotatoState>("state.json") { RotatoState() }
}

/// File-backed storage shared by the app, its intents and the widget. Every write re-reads the
/// file under a coordinated write and replaces it atomically, so processes never lose each
/// other's changes (the role DataStore plays on Android). Writers post a Darwin notification so
/// other processes can refresh.
public final class RotatoDatabase: @unchecked Sendable {
    public static let shared = RotatoDatabase(directory: RotatoPaths.data)

    public static let changedNotification = Notification.Name("RotatoDatabaseChanged")
    static let darwinName = "com.chrisalvis.rotato.changed" as CFString

    let directory: URL
    private let lock = NSRecursiveLock()

    public init(directory: URL) {
        self.directory = directory
        RotatoPaths.ensure(directory)
    }

    private func url<V>(_ file: DataFile<V>) -> URL { directory.appendingPathComponent(file.name) }

    public func read<V>(_ file: DataFile<V>) -> V {
        lock.lock(); defer { lock.unlock() }
        var result: V?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url(file), options: [], error: &err) { u in
            result = Self.decode(file, at: u)
        }
        return result ?? file.empty()
    }

    /// Applies `mutate` to the current contents and writes the result. Returns what `mutate` returns.
    @discardableResult
    public func update<V, R>(_ file: DataFile<V>, _ mutate: (inout V) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        var err: NSError?
        let target = url(file)
        var outcome: R?
        NSFileCoordinator().coordinate(writingItemAt: target, options: [], error: &err) { u in
            var value = Self.decode(file, at: u) ?? file.empty()
            outcome = mutate(&value)
            Self.encode(value, to: u)
        }
        let result: R
        if let outcome {
            result = outcome
        } else {
            // Coordination failed (should not happen for local files): write without it.
            var value = Self.decode(file, at: target) ?? file.empty()
            result = mutate(&value)
            Self.encode(value, to: target)
        }
        Self.notifyChanged()
        return result
    }

    public func write<V>(_ file: DataFile<V>, _ value: V) {
        update(file) { $0 = value }
    }

    private static func decode<V>(_ file: DataFile<V>, at url: URL) -> V? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        if let v = try? JSONDecoder().decode(V.self, from: data) { return v }
        // Arrays decode element by element so one bad row doesn't drop the whole file.
        if let lossy = LossyDecoding.decodeArray(V.self, from: data) { return lossy }
        return nil
    }

    private static func encode<V: Encodable>(_ value: V, to url: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func notifyChanged() {
        NotificationCenter.default.post(name: changedNotification, object: nil)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(darwinName), nil, nil, true)
    }

    /// Calls `handler` on the main queue whenever another process writes.
    public static func observeExternalChanges(_ handler: @escaping @Sendable () -> Void) {
        ExternalChangeObserver.shared.handler = handler
        ExternalChangeObserver.shared.start()
    }
}

final class ExternalChangeObserver: @unchecked Sendable {
    static let shared = ExternalChangeObserver()
    var handler: (@Sendable () -> Void)?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let me = Unmanaged<ExternalChangeObserver>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { me.handler?() }
            },
            RotatoDatabase.darwinName, nil, .deliverImmediately
        )
    }
}

enum LossyDecoding {
    static func decodeArray<V>(_ type: V.Type, from data: Data) -> V? {
        if V.self == [WallpaperCollection].self { return try? JSONDecoder().decode(LossyArray<WallpaperCollection>.self, from: data).elements as? V }
        if V.self == [CollectionEntry].self { return try? JSONDecoder().decode(LossyArray<CollectionEntry>.self, from: data).elements as? V }
        if V.self == [SourceConfig].self { return try? JSONDecoder().decode(LossyArray<SourceConfig>.self, from: data).elements as? V }
        if V.self == [PluginManifest].self { return try? JSONDecoder().decode(LossyArray<PluginManifest>.self, from: data).elements as? V }
        return nil
    }
}
