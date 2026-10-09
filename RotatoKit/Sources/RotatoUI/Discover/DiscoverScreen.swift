import RotatoKit
import SwiftUI

/// Discover (BrainrotScreen on Android): a full-screen swipe feed from the enabled sources, or a
/// grid. The dock holds Save, Set, Skip, Details and More.
public struct DiscoverScreen: View {
    @Environment(AppModel.self) private var model
    @State private var feed = DiscoverModel()
    @AppStorage("discoverGrid") private var gridMode = false
    @State private var position: Int? = 0
    @State private var searching = false
    @State private var details: Wallpaper?
    @State private var saving: Wallpaper?
    @State private var viewerStart: ViewerStart?
    @State private var handsFree = false
    @State private var showHealth = false
    private let searchRequest = DiscoverSearchRequest.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                if gridMode {
                    grid
                } else {
                    Color.black.ignoresSafeArea()
                    pager
                }
                stateOverlay
            }
            .navigationTitle(feed.query.isEmpty ? "Discover" : feed.query.replacingOccurrences(of: "_", with: " "))
            .inlineTitle()
            .toolbar { toolbar }
            .navigationBarBackgroundHidden(!gridMode)
            .sheet(isPresented: $searching) {
                DiscoverSearchSheet(current: feed.query, suggestions: suggestions) { q in
                    position = 0
                    feed.reset(query: q)
                }
            }
            .sheet(item: $details) { wp in
                WallpaperDetailsSheet(wallpaper: wp) { tag in search(tag) }
            }
            .sheet(item: $saving) { wp in SaveToCollectionsSheet(wallpaper: wp) }
            .sheet(isPresented: $showHealth) { NavigationStack { SourceHealthView(health: feed.health) } }
            .fullScreen(item: $viewerStart) { start in
                WallpaperViewer(items: feed.items, startIndex: start.index)
            }
            .navigationDestination(for: String.self) { _ in SourcesScreen() }
        }
        .onAppear {
            feed.startIfNeeded()
            consumeSearchRequest()
        }
        .onChange(of: searchRequest.query) { _, _ in consumeSearchRequest() }
        .onChange(of: feedSignature) { _, _ in
            position = 0
            feed.reset()
        }
        .task(id: handsFree) {
            // Hands-free: move on every few seconds, like a slideshow.
            while handsFree && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                guard handsFree, !gridMode else { continue }
                withAnimation { position = min((position ?? 0) + 1, max(feed.items.count - 1, 0)) }
            }
        }
    }

    // MARK: Feed

    private var pager: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(Array(feed.items.enumerated()), id: \.element.key) { i, wp in
                    FeedPage(wallpaper: wp, isCurrent: position == i)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(i)
                        .onAppear { feed.onAppear(index: i) }
                        .onTapGesture(count: 2) { save(wp) }
                }
                if feed.loadingMore {
                    ProgressView().tint(.white).containerRelativeFrame([.horizontal, .vertical])
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $position)
        .scrollIndicators(.hidden)
        .ignoresSafeArea()
        .refreshable { feed.reset() }
        .overlay(alignment: .bottom) {
            if let i = position, feed.items.indices.contains(i) {
                let wp = feed.items[i]
                VStack(spacing: 10) {
                    FeedCaption(wallpaper: wp)
                    WallpaperActionsDock(
                        wallpaper: wp,
                        onDetails: { details = wp },
                        onPickCollections: { saving = wp },
                        onSkip: { skip(wp, at: i) },
                        onBlock: { block(wp) }
                    )
                }
                .padding(.bottom, 12)
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], spacing: 6) {
                ForEach(Array(feed.items.enumerated()), id: \.element.key) { i, wp in
                    GridTile(wallpaper: wp, dataSaver: model.settings.discoverDataSaver, saved: model.isSaved(wp))
                        .onTapGesture { viewerStart = ViewerStart(index: i) }
                        .onAppear { feed.onAppear(index: i) }
                        .contextMenu { gridMenu(wp) }
                }
            }
            .padding(6)
            if feed.loadingMore { ProgressView().padding() }
        }
        .refreshable { feed.reset() }
    }

    @ViewBuilder
    private func gridMenu(_ wp: Wallpaper) -> some View {
        Button { model.quickSave(wp) } label: { Label("Save to Favorites", systemImage: "star") }
        Button { saving = wp } label: { Label("Save to collections…", systemImage: "bookmark") }
        Button { Task { await model.setNow(wp) } } label: { Label("Set now", systemImage: "iphone") }
            .disabled(wp.isVideo)
        Button { details = wp } label: { Label("Details", systemImage: "info.circle") }
        Divider()
        Button { feed.skip(wp); feed.remove(wp) } label: { Label("Not for me", systemImage: "hand.thumbsdown") }
        Button(role: .destructive) { block(wp) } label: { Label("Block", systemImage: "hand.raised") }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if feed.items.isEmpty {
            if feed.loading || (feed.noResults == nil && !feed.endReached) {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("Finding wallpapers…").foregroundStyle(.secondary)
                }
                .tint(gridMode ? nil : .white)
                .foregroundStyle(gridMode ? Color.primary : .white)
            } else if model.enabledSources.isEmpty || feed.noResults == .noSources {
                ContentUnavailableView {
                    Label("No sources on", systemImage: "server.rack")
                } description: {
                    Text("Turn on a source to fill Discover. Sources without a key, like Safebooru or Wallhaven, work straight away.")
                } actions: {
                    NavigationLink("Choose sources", value: "sources").buttonStyle(.borderedProminent)
                }
                .environment(\.colorScheme, gridMode ? .light : .dark)
            } else {
                ContentUnavailableView {
                    Label(feed.noResults == .searchEmpty ? "Nothing for \"\(feed.query)\"" : "You've seen everything",
                          systemImage: "sparkle.magnifyingglass")
                } description: {
                    Text(feed.noResults == .searchEmpty
                         ? "Check the spelling as the sites write it (like hatsune_miku), or loosen the filters in Settings → Discover."
                         : "Your sources ran out of new posts for these filters.")
                } actions: {
                    Button(feed.query.isEmpty ? "Start over" : "Clear search") { feed.reset(query: "") }
                        .buttonStyle(.borderedProminent)
                }
                .environment(\.colorScheme, gridMode ? .light : .dark)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .leadingBar) {
            Button { gridMode.toggle() } label: {
                Image(systemName: gridMode ? "rectangle.portrait" : "square.grid.2x2")
            }
            if !feed.undoStack.isEmpty {
                Button {
                    if let at = feed.undo() { withAnimation { position = at } }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
            }
        }
        ToolbarItemGroup(placement: .trailingBar) {
            Button { searching = true } label: { Image(systemName: "magnifyingglass") }
            Menu {
                if !feed.query.isEmpty {
                    Button { feed.reset(query: "") } label: { Label("Clear search", systemImage: "xmark.circle") }
                }
                Button { feed.reset() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                Toggle(isOn: $handsFree) { Label("Hands-free", systemImage: "play.circle") }
                    .disabled(gridMode)
                Toggle(isOn: settingBinding(model, \.forYouEnabled)) { Label("For you", systemImage: "heart.text.square") }
                Divider()
                Button { showHealth = true } label: { Label("Source health", systemImage: "stethoscope") }
                NavigationLink(value: "sources") { Label("Sources", systemImage: "server.rack") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: Actions

    /// Changes that make the current feed wrong: NSFW, filters, the set of enabled sources.
    private var feedSignature: String {
        let s = model.settings
        let sources = model.enabledSources.map { "\($0.id)|\($0.apiKey.isEmpty)|\($0.nsfwEnabled.map(String.init) ?? "-")|\($0.tags)" }
        return "\(s.effectiveNsfw)|\(s.filters.minResolution)|\(s.filters.aspectRatio)|\(sources.sorted())"
    }

    private var suggestions: [String] {
        var counts: [String: Int] = [:]
        for wp in feed.items.prefix(80) { for t in wp.tags { counts[normalizeTag(t), default: 0] += 1 } }
        return counts.filter { $0.value >= 2 && $0.key.count > 2 }.sorted { $0.value > $1.value }.prefix(24).map(\.key)
    }

    private func consumeSearchRequest() {
        guard let q = searchRequest.query else { return }
        searchRequest.query = nil
        search(q)
    }

    private func search(_ q: String) {
        position = 0
        feed.reset(query: q)
    }

    private func save(_ wp: Wallpaper) {
        Haptics.success()
        model.quickSave(wp)
    }

    private func skip(_ wp: Wallpaper, at i: Int) {
        feed.skip(wp)
        withAnimation { position = min(i + 1, max(feed.items.count - 1, 0)) }
    }

    private func block(_ wp: Wallpaper) {
        model.block(wp)
        feed.remove(wp)
        model.showToast("Blocked. Undo brings it back to the feed.")
    }
}

/// One full-screen post: the image fitted over a blurred fill of itself.
struct FeedPage: View {
    @Environment(AppModel.self) private var model
    let wallpaper: Wallpaper
    let isCurrent: Bool

    var body: some View {
        let url = model.settings.discoverDataSaver ? wallpaper.gridUrl : wallpaper.sampleUrl.ifBlank(wallpaper.fullUrl)
        ZStack {
            RemoteImage(wallpaper.dataSaverUrl, maxPixel: 200)
                .blur(radius: 40, opaque: true)
                .overlay(Color.black.opacity(0.35))
            Group {
                if wallpaper.isVideo, model.settings.videoPreviewMode == .AUTOPLAY, let u = URL(string: wallpaper.fullUrl) {
                    LoopingVideo(url: u, playing: isCurrent, muted: true)
                } else {
                    RemoteImage(MediaType.isVideoURL(url) ? wallpaper.thumbUrl : url, preview: wallpaper.lowResPreviewUrl, maxPixel: 1800, contentMode: .fit)
                        .overlay {
                            if wallpaper.isVideo {
                                Image(systemName: "play.circle.fill").font(.system(size: 54)).foregroundStyle(.white.opacity(0.85))
                            }
                        }
                }
            }
            .padding(.vertical, 60)
        }
        .clipped()
        .nsfwBlur(wallpaper.isNsfw)
        .contentShape(Rectangle())
    }
}

/// Source and top tags above the dock.
struct FeedCaption: View {
    let wallpaper: Wallpaper

    var body: some View {
        HStack(spacing: 6) {
            Text(wallpaper.source.capitalized).fontWeight(.semibold)
            if let d = wallpaper.dimensions { Text("· \(d.width)×\(d.height)") }
            if wallpaper.isNsfw { Text("· NSFW").foregroundStyle(.red) }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(0.9))
        .shadow(radius: 3)
    }
}

/// A grid tile sized to the post's aspect ratio (within limits).
struct GridTile: View {
    let wallpaper: Wallpaper
    let dataSaver: Bool
    let saved: Bool

    var body: some View {
        let ratio = wallpaper.dimensions.map { Double($0.width) / Double($0.height) } ?? (2.0 / 3.0)
        Color.clear
            .aspectRatio(min(max(ratio, 0.5), 1.4), contentMode: .fit)
            .overlay {
                RemoteImage(dataSaver ? wallpaper.dataSaverUrl : wallpaper.gridUrl, preview: wallpaper.lowResPreviewUrl, maxPixel: 600)
                    .nsfwBlur(wallpaper.isNsfw)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                if saved {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow).padding(6).shadow(radius: 2)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if wallpaper.isVideo {
                    Image(systemName: "play.fill").font(.caption).foregroundStyle(.white).padding(6).shadow(radius: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Tag search with pinned searches and suggestions from the current feed.
struct DiscoverSearchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let current: String
    let suggestions: [String]
    let run: (String) -> Void
    @State private var text = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Tags, like blue_sky scenery", text: $text)
                            .plainTextEntry()
                            .submitLabel(.search)
                            .onSubmit { go(text) }
                        if !text.isBlank {
                            Button {
                                let q = normalizeUserQuery(text)
                                model.updateSettings { s in
                                    if s.pinnedSearches.contains(q) { s.pinnedSearches.removeAll { $0 == q } } else { s.pinnedSearches.insert(q, at: 0) }
                                }
                            } label: {
                                Image(systemName: model.settings.pinnedSearches.contains(normalizeUserQuery(text)) ? "pin.fill" : "pin")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                } footer: {
                    Text("Use the sites' tag spelling. Separate tags with spaces; -tag excludes.")
                }
                if !model.settings.pinnedSearches.isEmpty {
                    Section("Pinned") {
                        ForEach(model.settings.pinnedSearches, id: \.self) { q in
                            Button(q) { go(q) }.foregroundStyle(.primary)
                        }
                        .onDelete { idx in model.updateSettings { $0.pinnedSearches.remove(atOffsets: idx) } }
                    }
                }
                if !suggestions.isEmpty {
                    Section("In your feed") {
                        FlowLayout(spacing: 6) {
                            ForEach(suggestions, id: \.self) { tag in
                                Button(tag.replacingOccurrences(of: "_", with: " ")) { go(tag) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Search")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !current.isEmpty {
                    ToolbarItem(placement: .confirmationAction) { Button("Clear") { go("") } }
                }
            }
            .onAppear { text = current }
        }
        .presentationDetents([.medium, .large])
    }

    private func go(_ q: String) {
        run(normalizeUserQuery(q))
        dismiss()
    }
}

/// How each source did this session.
struct SourceHealthView: View {
    @Environment(\.dismiss) private var dismiss
    let health: [SourceHealth]

    var body: some View {
        List {
            if health.isEmpty { Text("No fetches yet").foregroundStyle(.secondary) }
            ForEach(health) { h in
                HStack {
                    Circle().fill(h.successes > 0 ? .green : .red).frame(width: 10, height: 10)
                    VStack(alignment: .leading) {
                        Text(h.name)
                        Text("\(h.successes) of \(h.fetches) fetches returned posts").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let t = h.lastSuccess {
                        Text(t, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Source Health")
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
