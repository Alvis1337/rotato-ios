import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Content") {
                    Toggle("NSFW Content", isOn: $settings.nsfwEnabled)
                }

                Section("Discover") {
                    Toggle("Wi-Fi Only", isOn: $settings.wifiOnlyDiscover)
                    Text("When enabled, auto-loading more results is paused on mobile data. You can still pull to refresh manually.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
