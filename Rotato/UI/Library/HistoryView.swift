import SwiftUI

struct HistoryView: View {
    @Environment(AppSettings.self) private var settings
    @State private var selectedItem: WallpaperItem?
    @State private var showClearConfirm = false

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        Group {
            if settings.history.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Wallpapers you view in Discover will appear here.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(settings.history) { entry in
                            HistoryThumb(entry: entry, settings: settings)
                                .onTapGesture {
                                    if let item = entry.wallpaperItem {
                                        selectedItem = item
                                    }
                                }
                        }
                    }
                }
            }
        }
        .toolbar {
            if !settings.history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { showClearConfirm = true }
                        .foregroundStyle(.red)
                }
            }
        }
        .confirmationDialog("Clear all history?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { settings.history = [] }
        }
        .fullScreenCover(item: $selectedItem) { item in
            FullscreenPreviewView(items: [item], onDismiss: { selectedItem = nil })
        }
    }
}

private struct HistoryThumb: View {
    let entry: HistoryItem
    let settings: AppSettings

    var body: some View {
        let isNSFW = entry.isNSFW && !settings.nsfwEnabled
        ZStack(alignment: .bottomTrailing) {
            CachedImageView(url: URL(string: entry.thumbnailURL), contentMode: .fill)
                .aspectRatio(1, contentMode: .fill)
                .blur(radius: isNSFW ? 18 : 0)
                .clipped()

            if isNSFW {
                Image(systemName: "eye.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(4)
            }

            // Star badge if rated
            let stars = settings.rating(for: entry.id)
            if stars > 0 {
                HStack(spacing: 1) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                    Text("\(stars)")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(.yellow)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(4)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .background(Color(.systemFill))
    }
}
