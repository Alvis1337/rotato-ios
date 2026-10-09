import AppKit
import RotatoKit
import RotatoUI
import SwiftUI

// The iPhone app's screens in a phone-sized Mac window, for trying Rotato without an iPhone or
// Xcode: `swift run RotatoPreview`. It shares the screens and data code with the iOS app, but
// Shortcuts, the widget and Face ID prompts are iOS-only, and controls take macOS styling.
struct RotatoPreviewApp: App {
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Rotato") {
            PreviewShell()
                .environment(model)
                .frame(minWidth: 390, idealWidth: 430, minHeight: 700, idealHeight: 900)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 430, height: 900)
    }
}

/// Launch options for scripted runs: ROTATO_AUTOSETUP=1 skips first-run setup with the default
/// sources, ROTATO_RESTORE=<backup.json> restores a backup first (Android backups work too), and
/// ROTATO_TAB=discover|library|collections|settings opens that tab.
private let env = ProcessInfo.processInfo.environment

private struct PreviewShell: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    init() {
        if let path = env["ROTATO_RESTORE"], FileManager.default.fileExists(atPath: path) {
            let summary = (try? BackupService.restore(from: URL(fileURLWithPath: path))) ?? "Restore failed"
            print(summary)
            AppModel.shared.catalog.installAllBundled()
            AppModel.shared.updateSettings { $0.setupDone = true }
            AppModel.shared.afterCollectionsChange()
        }
        if env["ROTATO_AUTOSETUP"] == "1", !AppModel.shared.settings.setupDone {
            AppModel.shared.completeSetup(enable: ["SAFEBOORU", "KONACHAN", "ZEROCHAN", "WALLHAVEN"])
        }
    }

    var body: some View {
        RotatoRootView(initialTab: env["ROTATO_TAB"].flatMap(RootTab.init) ?? .discover)
            .onAppear {
                model.openURL = { openURL($0) }
                model.observeExternalChanges()
            }
    }
}

// Run outside an .app bundle, the process needs to be told it's a regular app to get a window
// and a Dock icon.
NSApplication.shared.setActivationPolicy(.regular)
DispatchQueue.main.async { NSApplication.shared.activate(ignoringOtherApps: true) }
RotatoPreviewApp.main()
