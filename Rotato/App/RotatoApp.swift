import SwiftUI
import SwiftData

@main
struct RotatoApp: App {
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: [SavedCollection.self, SavedEntry.self])
                .environment(settings)
        }
    }
}
