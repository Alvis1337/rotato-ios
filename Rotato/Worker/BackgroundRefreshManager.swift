import BackgroundTasks
import Foundation

/// Registers and handles BGAppRefreshTask so iOS keeps the app alive enough
/// for the FetchNextWallpaperIntent to run quickly from Shortcuts automations.
///
/// Also pre-warms the wallpaper cache so the Shortcut intent returns faster.
enum BackgroundRefreshManager {
    static let taskIdentifier = "com.chrisalvis.rotato.refresh"

    // MARK: - Registration (call at app startup)

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            handleRefresh(task: task as! BGAppRefreshTask)
        }
    }

    static func scheduleIfNeeded() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min minimum
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: - Handler

    private static func handleRefresh(task: BGAppRefreshTask) {
        scheduleIfNeeded() // re-schedule for next cycle

        let taskWork = Task {
            defer { task.setTaskCompleted(success: !Task.isCancelled) }

            // Pre-warm: fetch a random item URL and store it in UserDefaults
            // so the next Shortcut intent run can return faster.
            let settings = AppSettings()
            let configs = settings.sourceConfigs
            let enabled = PluginRegistry.all.filter { configs[$0.id]?.enabled == true }

            for plugin in enabled.shuffled().prefix(1) {
                var config = configs[plugin.id] ?? SourceConfig()
                if plugin.id == "REDDIT", !settings.redditSubreddits.isEmpty {
                    config.extraParam = settings.redditSubreddits.randomElement() ?? "wallpapers"
                }
                if let items = try? await plugin.fetch(query: "", page: 0, config: config, nsfw: settings.nsfwEnabled),
                   let item = items.randomElement() {
                    UserDefaults.standard.set(item.imageURL.absoluteString, forKey: "prefetched_wallpaper_url")
                }
                break
            }
        }

        task.expirationHandler = {
            taskWork.cancel()
        }
    }
}
