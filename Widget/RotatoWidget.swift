import AppIntents
import RotatoKit
import SwiftUI
import WidgetKit

struct CurrentWallpaperEntry: TimelineEntry {
    let date: Date
    let image: CGImage?
    let isNsfw: Bool
    let blur: Bool
}

struct CurrentWallpaperProvider: TimelineProvider {
    func placeholder(in context: Context) -> CurrentWallpaperEntry {
        CurrentWallpaperEntry(date: Date(), image: nil, isNsfw: false, blur: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (CurrentWallpaperEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CurrentWallpaperEntry>) -> Void) {
        // The app and the Shortcuts action reload the widget when the wallpaper changes.
        completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(3600))))
    }

    private func load() -> CurrentWallpaperEntry {
        let db = RotatoDatabase.shared
        let state = db.read(DataFiles.state)
        let settings = db.read(DataFiles.settings)
        let current = state.current(for: .home)
        let nsfw = current.map { state.nsfwFileNames.contains($0.poolFile) } ?? false
        return CurrentWallpaperEntry(
            date: Date(),
            image: ImageLoader.thumbnail(WidgetSnapshot.url, maxPixel: 700),
            isNsfw: nsfw,
            blur: nsfw && settings.effectiveBlur
        )
    }
}

/// The current wallpaper with Previous, Save and Next, like the Android widget. Previous and
/// Next open Rotato, because only the app can run the user's shortcut.
struct CurrentWallpaperView: View {
    let entry: CurrentWallpaperEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: family == .systemSmall ? 6 : 14) {
                Link(destination: URL(string: "rotato://previous")!) { icon("backward.fill") }
                Button(intent: SaveCurrentWallpaperIntent()) { icon("star.fill") }
                    .buttonStyle(.plain)
                Link(destination: URL(string: "rotato://next")!) { icon("forward.fill") }
            }
            .padding(.bottom, 4)
        }
        .containerBackground(for: .widget) {
            if let image = entry.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: entry.blur ? 20 : 0, opaque: true)
            } else {
                ZStack {
                    LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "photo.on.rectangle").font(.largeTitle).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(.black.opacity(0.35), in: Circle())
    }
}

struct CurrentWallpaperWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CurrentWallpaper", provider: CurrentWallpaperProvider()) { entry in
            CurrentWallpaperView(entry: entry)
        }
        .configurationDisplayName("Current Wallpaper")
        .description("Your current Rotato wallpaper with Previous, Save and Next.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct RotatoWidgets: WidgetBundle {
    var body: some Widget { CurrentWallpaperWidget() }
}
