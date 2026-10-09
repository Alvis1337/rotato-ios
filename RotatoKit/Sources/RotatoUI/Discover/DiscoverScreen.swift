import RotatoKit
import SwiftUI

/// Discover (BrainrotScreen on Android): a masonry grid (or compact square grid) of posts from
/// the enabled sources, with source chips to switch sources on and off. Tapping a post opens
/// the full-screen viewer; search and Discover settings float at the bottom.
public struct DiscoverScreen: View {
    @Environment(AppModel.self) private var model
    @State private var feed = DiscoverModel()
    @AppStorage("discoverCompactGrid") private var compact = false
    @State private var searching = false
    @State private var showSettings = false
    @State private var viewerStart: ViewerStart?
    @State private var showHealth = false
    @State private var showSources = false
    private let searchRequest = DiscoverSearchRequest.shared

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        header.id("top")
                        sourceChips
                        if compact { squareGrid } else { masonry }
                        if feed.loadingMore { ProgressView().frame(maxWidth: .infinity).padding() }
                    }
                    .padding(.bottom, 90)
                }
                .refreshable { feed.reset() }
                .overlay { stateOverlay }
                .overlay(alignment: .bottomTrailing) { floatingButtons(proxy) }
            }
            .navigationDestination(for: String.self) { _ in SourcesScreen().toolbar(.visible, for: .automatic) }
            .navigationDestination(isPresented: $showSources) { SourcesScreen().toolbar(.visible, for: .automatic) }
            .sheet(isPresented: $searching) {
                DiscoverSearchSheet(current: feed.query, suggestions: suggestions) { q in feed.reset(query: q) }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    DiscoverSettingsView()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } } }
                }
            }
            .sheet(isPresented: $showHealth) { NavigationStack { SourceHealthView(health: feed.health) } }
            .fullScreen(item: $viewerStart) { start in
                WallpaperViewer(items: feed.items, startIndex: start.index)
            }
            .toolbar(.hidden, for: .automatic)
        }
        .onAppear {
            feed.startIfNeeded()
            consumeSearchRequest()
        }
        .onChange(of: searchRequest.query) { _, _ in consumeSearchRequest() }
        .onChange(of: feedSignature) { _, _ in feed.reset() }
        #if DEBUG
        // Scripted screenshots: ROTATO_OPEN_VIEWER=1 opens the first post (2 expands its card).
        .onChange(of: feed.items.count) { old, new in
            if old == 0, new > 0, ProcessInfo.processInfo.environment["ROTATO_OPEN_VIEWER"] != nil {
                viewerStart = ViewerStart(index: 0)
            }
        }
        #endif
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Discover").font(.title.bold())
            Spacer()
            Button { feed.reset() } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.rotatoAccent.opacity(0.2), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.rotatoAccent)
            Button { withAnimation { compact.toggle() } } label: {
                Image(systemName: compact ? "rectangle.split.3x1" : "square.grid.2x2")
                    .font(.title3)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            Menu {
                Button { showHealth = true } label: { Label("Source health", systemImage: "stethoscope") }
                // A button, not a NavigationLink: links inside menus don't navigate on every platform.
                Button { showSources = true } label: { Label("Manage sources", systemImage: "server.rack") }
            } label: {
                Image(systemName: "ellipsis").font(.title3).frame(width: 32, height: 40)
            }
            .dockMenuStyle()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// Every configured source as a chip; tap to switch it on or off for Discover.
    private var sourceChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Sources", systemImage: "line.3.horizontal.decrease")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chipSources) { s in
                        let m = model.manifest(for: s)
                        let missingKey = (m?.requiresCredentials ?? false) && s.apiKey.isBlank
                        Button {
                            model.modifySource(s) { $0.enabled.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                if s.enabled { Image(systemName: "checkmark").font(.caption2.bold()) }
                                Text(s.instanceId.isEmpty ? (m?.name ?? s.pluginId.capitalized) : "r/\(s.instanceId)")
                                if missingKey { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                                else if (m?.needsApiKey ?? false) && !s.apiKey.isBlank { Image(systemName: "key.fill").opacity(0.5) }
                            }
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(s.enabled ? Color.rotatoAccent.opacity(0.22) : .clear, in: Capsule())
                            .overlay(Capsule().stroke(s.enabled ? Color.rotatoAccent.opacity(0.6) : .secondary.opacity(0.4)))
                        }
                        .buttonStyle(.plain)
                    }
                    NavigationLink(value: "sources") {
                        Image(systemName: "plus").font(.caption.bold())
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(.secondary.opacity(0.4)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
            }
        }
    }

    /// Sources with a row, hiding adult-only ones under the content filter.
    private var chipSources: [SourceConfig] {
        model.sources.filter { s in
            guard let m = model.manifest(for: s) else { return false }
            if m.isMultiInstance && s.instanceId.isEmpty { return false }
            return !(model.settings.nsfwHidden && m.adultOnly)
        }
    }

    // MARK: Grids

    private var masonry: some View {
        let columns = 3
        var heights = Array(repeating: 0.0, count: columns)
        var buckets = Array(repeating: [(Int, Wallpaper)](), count: columns)
        for (i, wp) in feed.items.enumerated() {
            let c = heights.firstIndex(of: heights.min()!)!
            buckets[c].append((i, wp))
            heights[c] += 1 / tileRatio(wp)
        }
        return HStack(alignment: .top, spacing: 6) {
            ForEach(0..<columns, id: \.self) { c in
                LazyVStack(spacing: 6) {
                    ForEach(buckets[c], id: \.1.key) { i, wp in tile(wp, index: i, ratio: tileRatio(wp)) }
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private var squareGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(Array(feed.items.enumerated()), id: \.element.key) { i, wp in tile(wp, index: i, ratio: 1) }
        }
        .padding(.horizontal, 8)
    }

    private func tileRatio(_ wp: Wallpaper) -> Double {
        let r = wp.dimensions.map { Double($0.width) / Double($0.height) } ?? (2.0 / 3.0)
        return min(max(r, 0.5), 1.4)
    }

    private func tile(_ wp: Wallpaper, index i: Int, ratio: Double) -> some View {
        GridTile(wallpaper: wp, ratio: ratio, dataSaver: model.settings.discoverDataSaver, saved: model.isSaved(wp))
            .onTapGesture { viewerStart = ViewerStart(index: i) }
            .onAppear { feed.onAppear(index: i) }
            .contextMenu { gridMenu(wp) }
    }

    @ViewBuilder
    private func gridMenu(_ wp: Wallpaper) -> some View {
        Button { model.quickSave(wp) } label: { Label("Save to Favorites", systemImage: "bookmark") }
        Button { Task { await model.setNow(wp) } } label: { Label("Set now", systemImage: "photo.on.rectangle") }
            .disabled(wp.isVideo)
        Button {
            Task { if await model.addToPool(wp) != nil { model.showToast("Added to Library") } }
        } label: {
            Label("Add to Library", systemImage: "arrow.down.to.line")
        }
        .disabled(wp.isVideo)
        Divider()
        Button { feed.skip(wp); feed.remove(wp) } label: { Label("Not for me", systemImage: "hand.thumbsdown") }
        Button(role: .destructive) {
            model.block(wp)
            feed.remove(wp)
            model.showToast("Blocked")
        } label: {
            Label("Block", systemImage: "hand.raised")
        }
    }

    // MARK: Overlays

    private func floatingButtons(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            if !feed.query.isEmpty {
                Button { searching = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        Text(feed.query.replacingOccurrences(of: "_", with: " ")).lineLimit(1)
                        Button { feed.reset(query: "") } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Button { searching = true } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Color.rotatoAccent, in: RoundedRectangle(cornerRadius: 18))
                    .shadow(radius: 6, y: 2)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if feed.items.isEmpty {
            if feed.loading || (feed.noResults == nil && !feed.endReached) {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("Finding wallpapers…").foregroundStyle(.secondary)
                }
            } else if model.enabledSources.isEmpty || feed.noResults == .noSources {
                ContentUnavailableView {
                    Label("No sources on", systemImage: "server.rack")
                } description: {
                    Text("Tap a source above to turn it on. Safebooru, Konachan and Wallhaven work without a key.")
                } actions: {
                    NavigationLink("Manage sources", value: "sources").buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView {
                    Label(feed.noResults == .searchEmpty ? "Nothing for \"\(feed.query)\"" : "You've seen everything",
                          systemImage: "sparkle.magnifyingglass")
                } description: {
                    Text(feed.noResults == .searchEmpty
                         ? "Check the spelling as the sites write it (like hatsune_miku), or loosen the filters."
                         : "Your sources ran out of new posts for these filters.")
                } actions: {
                    Button(feed.query.isEmpty ? "Start over" : "Clear search") { feed.reset(query: "") }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: Helpers

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
        feed.reset(query: q)
    }
}

/// A grid tile with the source badge (bottom left) and saved/video marks.
struct GridTile: View {
    let wallpaper: Wallpaper
    var ratio: Double
    let dataSaver: Bool
    let saved: Bool

    var body: some View {
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay {
                RemoteImage(dataSaver ? wallpaper.dataSaverUrl : wallpaper.gridUrl, preview: wallpaper.lowResPreviewUrl, maxPixel: 600)
                    .nsfwBlur(wallpaper.isNsfw)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomLeading) {
                InfoPill(text: SourceStyle.name(wallpaper.source), color: SourceStyle.color(wallpaper.source).opacity(0.92), bold: true)
                    .scaleEffect(0.85, anchor: .bottomLeading)
                    .padding(5)
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    if wallpaper.isVideo { Image(systemName: "play.fill") }
                    if saved { Image(systemName: "bookmark.fill").foregroundStyle(Color.rotatoAccent) }
                }
                .font(.caption)
                .foregroundStyle(.white)
                .shadow(radius: 2)
                .padding(6)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
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
