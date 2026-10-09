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

private struct PreviewShell: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        RotatoRootView()
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
