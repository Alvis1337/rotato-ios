import AppIntents
import Foundation
import UniformTypeIdentifiers

// MARK: - App Intent

/// Fetches a random wallpaper from your enabled Rotato sources and returns the image.
///
/// Loophole: iOS 16+ Shortcuts Automation lets you chain this with the built-in
/// "Set Wallpaper" action on a time-based trigger with "Don't Ask Before Running"
/// disabled — giving you fully automatic background rotation without any private APIs.
struct FetchNextWallpaperIntent: AppIntent {
    static var title: LocalizedStringResource = "Fetch Next Wallpaper"
    static var description = IntentDescription(
        "Downloads a random wallpaper from your enabled Rotato sources. " +
        "Chain with 'Set Wallpaper' in a Shortcuts automation to auto-rotate your wallpaper.",
        categoryName: "Wallpaper"
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some ReturnsValue<IntentFile> {
        // Read settings (UserDefaults.standard is accessible even when app is not foregrounded)
        let settings = AppSettings()
        let configs = settings.sourceConfigs
        let nsfw = settings.nsfwEnabled

        // Pick from enabled plugins
        let enabled = PluginRegistry.all.filter { configs[$0.id]?.enabled == true }
        guard !enabled.isEmpty else {
            throw RotatoIntentError.noSourcesEnabled
        }

        // Try each shuffled plugin until we get a result
        for plugin in enabled.shuffled() {
            var config = configs[plugin.id] ?? SourceConfig()
            if plugin.id == "REDDIT", !settings.redditSubreddits.isEmpty {
                config.extraParam = settings.redditSubreddits.randomElement() ?? "wallpapers"
            }

            let page = Int.random(in: 0..<3)
            guard let items = try? await plugin.fetch(query: "", page: page, config: config, nsfw: nsfw),
                  let item = items.randomElement() else { continue }

            let (data, response) = try await URLSession.shared.data(from: item.imageURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            guard !data.isEmpty else { continue }

            // Detect MIME type from data magic bytes for a clean filename
            let ext = imageExtension(for: data)
            let file = IntentFile(data: data, filename: "rotato-wallpaper.\(ext)",
                                  type: ext == "png" ? .png : .jpeg)
            return .result(value: file)
        }

        throw RotatoIntentError.noResults
    }

    private func imageExtension(for data: Data) -> String {
        guard data.count >= 4 else { return "jpg" }
        let bytes = [UInt8](data.prefix(4))
        if bytes[0] == 0x89 && bytes[1] == 0x50 { return "png" }
        if bytes[0] == 0x47 && bytes[1] == 0x49 { return "gif" }
        if bytes[0] == 0xFF && bytes[1] == 0xD8 { return "jpg" }
        return "jpg"
    }
}

// MARK: - Errors

enum RotatoIntentError: LocalizedError {
    case noSourcesEnabled
    case noResults

    var errorDescription: String? {
        switch self {
        case .noSourcesEnabled: return "No sources are enabled in Rotato. Open the app and enable at least one source."
        case .noResults:        return "Could not fetch wallpapers from enabled sources. Check your internet connection."
        }
    }
}
