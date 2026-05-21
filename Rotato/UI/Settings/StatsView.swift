import SwiftUI
import SwiftData

private struct SourceStat: Identifiable {
    var id: String { source }
    let source: String
    let count: Int
}

private struct TagStat: Identifiable {
    var id: String { tag }
    let tag: String
    let count: Int
}

struct StatsView: View {
    @Environment(AppSettings.self) private var settings
    @Query private var collections: [SavedCollection]
    @Query private var entries: [SavedEntry]

    private var sourceBreakdown: [SourceStat] {
        let grouped = Dictionary(grouping: settings.history) { item in
            item.sourceId.isEmpty ? "unknown" : item.sourceId
        }
        return grouped
            .map { SourceStat(source: $0.key, count: $0.value.count) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.source < $1.source }
    }

    private var topTags: [TagStat] {
        var counts: [String: Int] = [:]
        for item in settings.history {
            for tag in item.tags {
                let t = tag.lowercased().trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty else { continue }
                counts[t, default: 0] += 1
            }
        }
        return counts
            .map { TagStat(tag: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag < $1.tag }
            .prefix(10)
            .map { $0 }
    }

    private var ratedCount: Int {
        settings.wallpaperRatings.values.filter { $0 > 0 }.count
    }

    var body: some View {
        List {
            Section("Wallpapers") {
                StatRow(label: "History items", value: "\(settings.history.count)")
                StatRow(label: "Rated wallpapers", value: "\(ratedCount)")
                StatRow(label: "Saved to collections", value: "\(entries.count)")
            }

            Section("Collections") {
                StatRow(label: "Collections", value: "\(collections.count)")
            }

            if !sourceBreakdown.isEmpty {
                Section("By Source") {
                    ForEach(sourceBreakdown) { stat in
                        StatRow(
                            label: "\(sourceEmoji(stat.source)) \(stat.source.capitalized)",
                            value: "\(stat.count)"
                        )
                    }
                }
            }

            if !topTags.isEmpty {
                Section("Top Tags") {
                    TagsGrid(tags: topTags)
                }
            }
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.large)
        .overlay {
            if settings.history.isEmpty && entries.isEmpty {
                ContentUnavailableView(
                    "No Data Yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Browse wallpapers in Discover to start building stats.")
                )
            }
        }
    }
}

private struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TagsGrid: View {
    let tags: [TagStat]

    var body: some View {
        FlowRow(tags: tags)
            .padding(.vertical, 4)
    }
}

// Two-column grid of tag chips for a compact, readable layout
private struct FlowRow: View {
    let tags: [TagStat]

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(tags.enumerated()), id: \.element.id) { _, tag in
                HStack(spacing: 4) {
                    Text("#\(tag.tag)")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(tag.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private func sourceEmoji(_ source: String) -> String {
    switch source.lowercased() {
    case "danbooru":        return "🐾"
    case "gelbooru":        return "💠"
    case "wallhaven":       return "🧱"
    case "rule34":          return "⚠️"
    case "reddit":          return "🤖"
    case "safebooru":       return "🛡️"
    case "konachan":        return "🎌"
    case "yandere":         return "🌸"
    case "zerochan":        return "0️⃣"
    case "animepictures", "anime-pictures": return "🎨"
    default:                return "🖼️"
    }
}
