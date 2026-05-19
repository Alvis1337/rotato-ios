import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    Toggle("NSFW Content", isOn: Binding(
                        get: { settings.nsfwEnabled },
                        set: { settings.nsfwEnabled = $0 }
                    ))
                }

                Section("Sources") {
                    NavigationLink("Configure Sources") { SourceSettingsView() }
                }

                Section("MyAnimeList") {
                    NavigationLink("MAL Integration") { MalSettingsView() }
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    LabeledContent("Build", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
                    Link("GitHub – Rotato iOS", destination: URL(string: "https://github.com/Alvis1337/rotato-ios")!)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
