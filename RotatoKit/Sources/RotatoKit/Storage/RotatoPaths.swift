import Foundation

/// Where Rotato keeps its files. Everything lives in the App Group container so the app, its
/// Shortcuts actions and the widget share one copy. Without the App Group entitlement (some free
/// signing setups) it falls back to the app's own Application Support folder, and the widget
/// shows a placeholder.
public enum RotatoPaths {
    public static let appGroupID = "group.com.chrisalvis.rotato"

    public static let container: URL = {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return group
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Rotato", isDirectory: true)
    }()

    public static var usesAppGroup: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    /// JSON data files.
    public static var data: URL { dir("Data") }
    /// The rotation pool: downloaded wallpapers Shortcuts can pick from (Library on Android).
    public static var pool: URL { dir("Pool") }
    /// Photos imported from the device into collections.
    public static var device: URL { dir("Device") }
    /// Rendered wallpapers handed to Shortcuts, and the widget's current image.
    public static var rendered: URL { dir("Rendered") }
    /// Cached Discover / collection images.
    public static var imageCache: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return ensure(caches.appendingPathComponent("RotatoImages", isDirectory: true))
    }

    private static func dir(_ name: String) -> URL {
        ensure(container.appendingPathComponent(name, isDirectory: true))
    }

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
