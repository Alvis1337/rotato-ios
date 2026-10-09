import RotatoKit
import SwiftUI

/// The app's top level: first-run setup, then the tabs. Mirrors MainActivity's navigation
/// (Discover, Library, Collections, Settings).
public struct RotatoRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: RootTab

    public init(initialTab: RootTab = .discover) {
        _tab = State(initialValue: initialTab)
    }

    public var body: some View {
        Group {
            if model.settings.setupDone {
                TabView(selection: $tab) {
                    DiscoverScreen()
                        .tabItem { Label("Discover", systemImage: "sparkles") }
                        .tag(RootTab.discover)
                    LibraryScreen()
                        .tabItem { Label("Library", systemImage: "photo.on.rectangle") }
                        .tag(RootTab.library)
                    CollectionsScreen(onSearchDiscover: { tag in
                        DiscoverSearchRequest.shared.send(tag)
                    })
                        .tabItem { Label("Collections", systemImage: "bookmark") }
                        .tag(RootTab.collections)
                    SettingsScreen()
                        .tabItem { Label("Settings", systemImage: "gearshape") }
                        .tag(RootTab.settings)
                }
            } else {
                SetupScreen()
            }
        }
        .toastOverlay()
        .tint(.rotatoAccent)
        .preferredColorScheme(model.settings.themeMode.colorScheme)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.reload()
                Task { await model.syncPool() }
            }
        }
        .onOpenURL { model.handle($0) }
        // Any tab can hand Discover a search (a tapped tag); Discover runs it when it appears.
        .onChange(of: DiscoverSearchRequest.shared.serial) { _, _ in tab = .discover }
    }
}

public enum RootTab: String, Hashable { case discover, library, collections, settings }

extension Color {
    /// The icon's orange, so the app looks the same wherever the system accent differs.
    public static let rotatoAccent = Color(red: 0.91, green: 0.33, blue: 0.12)
}

/// Lets other tabs hand Discover a search (e.g. tapping a tag in a collection).
@MainActor
@Observable
public final class DiscoverSearchRequest {
    public static let shared = DiscoverSearchRequest()
    /// The search waiting for Discover; Discover clears it once it runs it.
    public var query: String?
    /// Bumped on every request so the tab switch can't be missed when Discover clears `query`.
    public private(set) var serial = 0

    public func send(_ q: String) {
        query = q
        serial += 1
    }
}

extension ThemeMode {
    var colorScheme: ColorScheme? {
        switch self { case .SYSTEM: nil; case .LIGHT: .light; case .DARK: .dark }
    }
}
