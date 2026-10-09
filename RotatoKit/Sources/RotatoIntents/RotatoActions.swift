import AppIntents
import Foundation
import RotatoKit
import UniformTypeIdentifiers
import WidgetKit

/// Which screen an action works on.
public enum RotatoScreenOption: String, AppEnum {
    case home, lock

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Screen"
    public static let caseDisplayRepresentations: [RotatoScreenOption: DisplayRepresentation] = [
        .home: "Home Screen",
        .lock: "Lock Screen",
    ]

    var screen: WallpaperScreen { self == .home ? .home : .lock }
}

/// The heart of rotation on iOS: picks the next wallpaper and returns it sized for this iPhone,
/// for the system "Set Wallpaper" action that follows it in the user's shortcut.
public struct GetRotatoWallpaperIntent: AppIntent {
    public static let title: LocalizedStringResource = "Get Rotato Wallpaper"
    public static let description = IntentDescription(
        "Picks the next wallpaper from your Rotato library, cropped and sized for this iPhone. Pass it to Set Wallpaper.",
        categoryName: "Rotation"
    )

    @Parameter(title: "Screen", default: .home)
    public var screen: RotatoScreenOption

    @Parameter(
        title: "Respect Auto-Pause",
        description: "During Rotato's night pause, return the wallpaper that's already showing.",
        default: true
    )
    public var respectAutoPause: Bool

    public static var parameterSummary: some ParameterSummary {
        Summary("Get Rotato wallpaper for \(\.$screen)") { \.$respectAutoPause }
    }

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let (url, _) = try await WallpaperService.nextWallpaper(for: screen.screen, automatic: respectAutoPause)
        let data = try Data(contentsOf: url)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(value: IntentFile(data: data, filename: "rotato-\(screen.rawValue).jpg", type: .jpeg))
    }
}

/// Queues the wallpaper shown before the current one, so the next run brings it back.
public struct PreviousRotatoWallpaperIntent: AppIntent {
    public static let title: LocalizedStringResource = "Previous Rotato Wallpaper"
    public static let description = IntentDescription(
        "Makes the next Get Rotato Wallpaper return the wallpaper shown before the current one.",
        categoryName: "Rotation"
    )

    @Parameter(title: "Screen", default: .home)
    public var screen: RotatoScreenOption

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let ok = RotationEngine().queuePrevious(for: screen.screen) != nil
        return .result(dialog: ok ? "The previous wallpaper comes back on the next run." : "There's no earlier wallpaper to go back to.")
    }
}

/// Saves what's showing to Favorites. Also the widget's Save button.
public struct SaveCurrentWallpaperIntent: AppIntent {
    public static let title: LocalizedStringResource = "Save Current Wallpaper"
    public static let description = IntentDescription("Saves the wallpaper Rotato last set to your Favorites collection.", categoryName: "Collections")

    @Parameter(title: "Screen", default: .home)
    public var screen: RotatoScreenOption

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let saved = RotationEngine().saveCurrent(screen: screen.screen)
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: saved ? "Saved to Favorites." : "It's already in Favorites.")
    }
}

/// Removes what's showing from rotation and keeps it from being added again.
public struct BlockCurrentWallpaperIntent: AppIntent {
    public static let title: LocalizedStringResource = "Block Current Wallpaper"
    public static let description = IntentDescription("Removes the current wallpaper from rotation and never adds it again.", categoryName: "Rotation")

    @Parameter(title: "Screen", default: .home)
    public var screen: RotatoScreenOption

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        RotationEngine().blockCurrent(screen: screen.screen)
        return .result(dialog: "Blocked. It won't come up again.")
    }
}
