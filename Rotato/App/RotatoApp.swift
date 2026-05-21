import SwiftUI
import SwiftData
import UIKit

@main
struct RotatoApp: App {
    @State private var settings = AppSettings()

    init() {
        BackgroundRefreshManager.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: [SavedCollection.self, SavedEntry.self])
                .environment(settings)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    BackgroundRefreshManager.scheduleIfNeeded()
                }
        }
    }
}
