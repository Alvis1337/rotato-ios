import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var showClearHistoryConfirm = false

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

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
                    NavigationLink("Source Health") { SourceHealthView() }
                }

                Section("Auto-Rotation") {
                    NavigationLink("Setup Wallpaper Rotation") { AutoRotationView() }
                }

                Section("MyAnimeList") {
                    NavigationLink("MAL Integration") { MalSettingsView() }
                }

                Section("Diagnostics") {
                    NavigationLink("Stats") { StatsView() }
                }

                Section {
                    Button("Clear History & Ratings", role: .destructive) {
                        showClearHistoryConfirm = true
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("Clears all viewed wallpaper history and star ratings. This cannot be undone.")
                }

                Section("About") {
                    NavigationLink("What's New") { WhatIsNewView() }
                    NavigationLink("Open Source Licenses") { LicensesView() }
                    Link("Privacy Policy", destination: URL(string: "https://alvis1337.github.io/rotato/privacy/")!)
                    Link("Terms of Service", destination: URL(string: "https://alvis1337.github.io/rotato/terms/")!)
                    Link("Website", destination: URL(string: "https://alvis1337.github.io/rotato/")!)
                    Link("GitHub – Rotato iOS", destination: URL(string: "https://github.com/Alvis1337/rotato-ios")!)
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: buildNumber)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Clear History & Ratings?",
                isPresented: $showClearHistoryConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear \(settings.history.count) items", role: .destructive) {
                    settings.history = []
                    settings.wallpaperRatings = [:]
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all viewed wallpapers from your history and clear all star ratings.")
            }
        }
    }
}
