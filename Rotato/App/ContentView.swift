import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "sparkles") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "photo.stack") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
