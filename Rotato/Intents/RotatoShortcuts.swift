import AppIntents

/// Registers Rotato's actions in the Shortcuts catalog so they appear
/// automatically when users search for "Rotato" in Shortcuts or Automation.
struct RotatoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FetchNextWallpaperIntent(),
            phrases: [
                "Rotate wallpaper with \(.applicationName)",
                "Change wallpaper with \(.applicationName)",
                "Fetch wallpaper with \(.applicationName)"
            ],
            shortTitle: "Rotate Wallpaper",
            systemImageName: "photo.on.rectangle.angled"
        )
    }

    static var shortcutTileColor: ShortcutTileColor = .purple
}
