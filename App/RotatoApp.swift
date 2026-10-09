import AppIntents
import RotatoKit
import RotatoUI
import SwiftUI
import WidgetKit

@main
struct RotatoApp: App {
    @State private var model = AppModel.shared

    init() {
        AppModel.shared.observeExternalChanges()
    }

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(model)
        }
    }
}

/// Wires the things only the app knows about into the shared model: opening URLs (to run the
/// user's shortcut) and this iPhone's screen size (for renders and "My Phone" filters).
private struct AppShell: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        RotatoRootView()
            .onAppear {
                model.openURL = { openURL($0) }
                let px = UIScreen.main.nativeBounds.size
                model.recordScreen(width: Int(min(px.width, px.height)), height: Int(max(px.width, px.height)))
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { WidgetCenter.shared.reloadAllTimelines() }
            }
    }
}

/// Puts Rotato's actions in Shortcuts and Spotlight without any setup.
struct RotatoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetRotatoWallpaperIntent(),
            phrases: ["Get a wallpaper from \(.applicationName)", "Next \(.applicationName) wallpaper"],
            shortTitle: "Get Wallpaper",
            systemImageName: "photo.on.rectangle"
        )
        AppShortcut(
            intent: SaveCurrentWallpaperIntent(),
            phrases: ["Save this wallpaper in \(.applicationName)"],
            shortTitle: "Save Wallpaper",
            systemImageName: "star"
        )
        AppShortcut(
            intent: PreviousRotatoWallpaperIntent(),
            phrases: ["Previous \(.applicationName) wallpaper"],
            shortTitle: "Previous Wallpaper",
            systemImageName: "arrow.uturn.backward"
        )
    }
}
