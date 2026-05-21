import SwiftUI

struct ChangelogEntry: Identifiable {
    let id: String
    let version: String
    let date: String
    let changes: [ChangeItem]
}

struct ChangeItem: Identifiable {
    let id = UUID()
    let emoji: String
    let text: String
}

struct WhatIsNewView: View {
    private let entries: [ChangelogEntry] = [
        ChangelogEntry(
            id: "1.1",
            version: "1.1",
            date: "May 2025",
            changes: [
                ChangeItem(emoji: "⭐️", text: "Star ratings (1–5) on any wallpaper — tap again to clear"),
                ChangeItem(emoji: "📜", text: "Wallpaper history screen with NSFW blur and star badges"),
                ChangeItem(emoji: "📊", text: "Stats screen — history count, collections, source breakdown, top tags"),
                ChangeItem(emoji: "🔍", text: "Sort and search inside collections (by date, rating, or source)"),
                ChangeItem(emoji: "🛡️", text: "Safebooru plugin — safe-for-work booru source"),
                ChangeItem(emoji: "🌸", text: "Yande.re plugin — high-quality anime wallpaper board"),
                ChangeItem(emoji: "🩺", text: "Source Health — test any source and view per-source stats"),
                ChangeItem(emoji: "🔀", text: "Per-source NSFW override — override the global setting per source"),
                ChangeItem(emoji: "🔑", text: "API key fields now visible for Danbooru and Wallhaven"),
                ChangeItem(emoji: "🐛", text: "Fixed MAL connect crash on first launch"),
                ChangeItem(emoji: "🐛", text: "Fixed Save to Collection silently doing nothing"),
                ChangeItem(emoji: "🐛", text: "Fixed Share sheet not appearing from fullscreen viewer"),
                ChangeItem(emoji: "🐛", text: "Fixed Discover screen shaking when scrolling to top"),
                ChangeItem(emoji: "🐛", text: "Fixed blank screen after dismissing fullscreen viewer"),
            ]
        ),
        ChangelogEntry(
            id: "1.0",
            version: "1.0",
            date: "April 2025",
            changes: [
                ChangeItem(emoji: "🚀", text: "Initial release of Rotato for iOS"),
                ChangeItem(emoji: "🖼️", text: "Discover wallpapers from 8 sources: Gelbooru, Danbooru, Rule34, Wallhaven, Konachan, Zerochan, Anime Pictures, Reddit"),
                ChangeItem(emoji: "💾", text: "Save wallpapers to collections or your Photos library"),
                ChangeItem(emoji: "📁", text: "Create and manage multiple collections"),
                ChangeItem(emoji: "🔞", text: "NSFW toggle with per-image blur masking"),
                ChangeItem(emoji: "🎌", text: "MyAnimeList integration — filter wallpapers by your anime list"),
                ChangeItem(emoji: "📡", text: "Wi-Fi only mode for metered connections"),
                ChangeItem(emoji: "🔗", text: "Share wallpapers directly from the fullscreen viewer"),
            ]
        ),
    ]

    var body: some View {
        List {
            ForEach(entries) { entry in
                Section {
                    ForEach(entry.changes) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Text(item.emoji)
                                .font(.title3)
                                .frame(width: 28)
                            Text(item.text)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Version \(entry.version)")
                            .font(.headline)
                            .textCase(nil)
                        Spacer()
                        Text(entry.date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                    }
                }
            }
        }
        .navigationTitle("What's New")
        .navigationBarTitleDisplayMode(.large)
    }
}
