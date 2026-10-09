import PhotosUI
import RotatoKit
import SwiftUI

/// The rotation pool (HomeScreen on Android): every wallpaper Shortcuts can pick from, what's
/// showing now, and ways to steer what comes next.
public struct LibraryScreen: View {
    @Environment(AppModel.self) private var model
    @State private var sort: LibrarySort = .name
    @State private var hueFilter: Double?
    @State private var colors: [String: ImageColor] = [:]
    @State private var picks: [PhotosPickerItem] = []
    @State private var selecting = false
    @State private var selection: Set<URL> = []
    @State private var viewing: PoolItem?
    @State private var showHistory = false
    @State private var showStats = false
    @State private var confirmRemove = false
    @State private var duplicates: [DuplicateGroup]?
    @State private var findingDuplicates = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.state.totalRotations == 0 { setupBanner }
                    NowShowingCard()
                    if !model.poolFiles.isEmpty { colorChips }
                    grid
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .overlay { if model.poolFiles.isEmpty { emptyState } }
            .navigationTitle("Library")
            .toolbar { toolbar }
            .safeAreaInset(edge: .bottom) { if selecting { selectionBar } }
            .refreshable { await model.syncPool() }
            .onChange(of: picks) { _, items in importPhotos(items) }
            .task(id: model.poolFiles.count) { await loadColors() }
            .fullScreen(item: $viewing) { item in
                PoolViewer(files: shownFiles, start: item.url)
            }
            .sheet(isPresented: $showHistory) { NavigationStack { HistoryView() } }
            .sheet(isPresented: $showStats) { NavigationStack { StatsView() } }
            .confirmationDialog("Remove \(selection.count) from the Library?", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    model.removeFromPool(Array(selection))
                    selection = []
                    selecting = false
                }
            } message: {
                Text("Images from rotation collections come back unless you turn rotation off for that collection.")
            }
            .confirmationDialog(duplicateTitle, isPresented: Binding(get: { duplicates != nil }, set: { if !$0 { duplicates = nil } }), titleVisibility: .visible) {
                if let groups = duplicates, !groups.isEmpty {
                    Button("Remove \(groups.flatMap(\.duplicates).count) copies", role: .destructive) {
                        model.removeFromPool(groups.flatMap(\.duplicates))
                        duplicates = nil
                    }
                }
            } message: {
                Text("Each set keeps its highest-resolution copy.")
            }
        }
    }

    private var duplicateTitle: String {
        guard let groups = duplicates else { return "" }
        return groups.isEmpty ? "No duplicates found" : "\(groups.count) image\(groups.count == 1 ? "" : "s") saved more than once"
    }

    private func findDuplicates() {
        findingDuplicates = true
        let files = model.poolFiles
        Task {
            duplicates = await Task.detached(priority: .userInitiated) { DuplicateFinder.groups(in: files) }.value
            findingDuplicates = false
        }
    }

    // MARK: Pieces

    private var setupBanner: some View {
        NavigationLink { ShortcutsSetupView() } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill").font(.title).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Set up automatic rotation").font(.headline)
                    Text("A one-minute shortcut makes your wallpaper change on schedule.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding()
            .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var colorChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(LibraryHue.all, id: \.hue) { h in
                    Button {
                        hueFilter = hueFilter == h.hue ? nil : h.hue
                    } label: {
                        Circle()
                            .fill(h.color.gradient)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(.primary, lineWidth: hueFilter == h.hue ? 2.5 : 0).padding(-3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show \(h.name) wallpapers")
                }
                if hueFilter != nil {
                    Button("Clear") { hueFilter = nil }.font(.subheadline)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 3)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 8)], spacing: 8) {
            ForEach(shownFiles, id: \.self) { file in
                PoolTile(file: file, selected: selecting ? selection.contains(file) : nil)
                    .onTapGesture {
                        if selecting {
                            if selection.contains(file) { selection.remove(file) } else { selection.insert(file) }
                        } else {
                            viewing = PoolItem(url: file)
                        }
                    }
                    .contextMenu { PoolActions(file: file) }
            }
        }
        .overlay {
            if hueFilter != nil && shownFiles.isEmpty && !model.poolFiles.isEmpty {
                Text("No wallpapers stand out in that colour").foregroundStyle(.secondary).padding(.top, 40)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Your Library is empty", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("Turn on rotation for a collection, or add photos. These are the wallpapers your shortcut picks from.")
        } actions: {
            PhotosPicker(selection: $picks, matching: .images) {
                Text("Add photos")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .leadingBar) {
            if model.isSyncingPool { ProgressView().controlSize(.small) }
        }
        ToolbarItemGroup(placement: .trailingBar) {
            if selecting {
                Button("Done") { selecting = false; selection = [] }
            } else {
                PhotosPicker(selection: $picks, matching: .images) {
                    Image(systemName: "plus")
                }
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(LibrarySort.allCases, id: \.self) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                    Button { selecting = true } label: { Label("Select", systemImage: "checkmark.circle") }
                        .disabled(model.poolFiles.isEmpty)
                    Divider()
                    Button { showHistory = true } label: { Label("History", systemImage: "clock") }
                    Button { showStats = true } label: { Label("Stats", systemImage: "chart.bar") }
                    Button { findDuplicates() } label: { Label("Find duplicates", systemImage: "square.on.square") }
                        .disabled(model.poolFiles.count < 2 || findingDuplicates)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var selectionBar: some View {
        HStack {
            Button(selection.count == shownFiles.count ? "Deselect all" : "Select all") {
                selection = selection.count == shownFiles.count ? [] : Set(shownFiles)
            }
            Spacer()
            Text("\(selection.count) selected").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) { confirmRemove = true } label: { Image(systemName: "trash") }
                .disabled(selection.isEmpty)
        }
        .padding()
        .background(.bar)
    }

    // MARK: Data

    private var shownFiles: [URL] {
        var files = model.poolFiles
        if let hue = hueFilter {
            files = files.filter { f in
                guard let c = colors[f.lastPathComponent], !c.isNeutral else { return false }
                return ColorAnalysis.hueDistance(c.hue, hue) < 0.07
            }
        }
        switch sort {
        case .name:
            return files
        case .newest:
            return files.sorted { modified($0) > modified($1) }
        case .rating:
            return files.sorted { (model.state.ratings[$0.lastPathComponent] ?? 0) > (model.state.ratings[$1.lastPathComponent] ?? 0) }
        case .rainbow:
            return files.sorted { (colors[$0.lastPathComponent]?.rainbowKey ?? 3) < (colors[$1.lastPathComponent]?.rainbowKey ?? 3) }
        }
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func loadColors() async {
        let files = model.poolFiles, db = model.db
        colors = await Task.detached(priority: .utility) { ColorAnalysis.colors(of: files, db: db) }.value
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var datas: [Data] = []
            for item in items {
                if let d = try? await item.loadTransferable(type: Data.self) { datas.append(d) }
            }
            model.addPhotosToPool(datas)
            picks = []
        }
    }
}

struct PoolItem: Identifiable {
    let url: URL
    var id: URL { url }
}

enum LibrarySort: CaseIterable {
    case name, newest, rating, rainbow

    var label: String {
        switch self { case .name: "Name"; case .newest: "Newest"; case .rating: "Rating"; case .rainbow: "Rainbow" }
    }

    var icon: String {
        switch self { case .name: "textformat"; case .newest: "clock"; case .rating: "star"; case .rainbow: "paintpalette" }
    }
}

struct LibraryHue {
    let name: String
    let hue: Double
    var color: Color { Color(hue: hue, saturation: 0.75, brightness: 0.9) }

    static let all = [
        LibraryHue(name: "red", hue: 0.0), LibraryHue(name: "orange", hue: 0.07), LibraryHue(name: "yellow", hue: 0.15),
        LibraryHue(name: "green", hue: 0.33), LibraryHue(name: "teal", hue: 0.48), LibraryHue(name: "blue", hue: 0.6),
        LibraryHue(name: "purple", hue: 0.75), LibraryHue(name: "pink", hue: 0.9),
    ]
}

/// One pool image: rating, "up next" and NSFW blur.
struct PoolTile: View {
    @Environment(AppModel.self) private var model
    let file: URL
    /// nil when not selecting.
    let selected: Bool?

    var body: some View {
        let name = file.lastPathComponent
        let rating = model.state.ratings[name] ?? 0
        let queued = model.state.queuedNext.contains { $0.poolFile == name }
        Color.clear
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .overlay { LocalImage(file, maxPixel: 400).nsfwBlur(model.state.nsfwFileNames.contains(name)) }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottomLeading) {
                if rating > 0 {
                    HStack(spacing: 1) {
                        ForEach(0..<rating, id: \.self) { _ in Image(systemName: "star.fill") }
                    }
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
                    .padding(4)
                    .background(.black.opacity(0.4), in: Capsule())
                    .padding(5)
                }
            }
            .overlay(alignment: .topLeading) {
                if queued {
                    Label("Next", systemImage: "forward.fill")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(.tint, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let selected {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Color.accentColor : .white)
                        .shadow(radius: 2)
                        .padding(6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Menu actions for a pool image, shared by the grid's context menu and the viewer.
struct PoolActions: View {
    @Environment(AppModel.self) private var model
    let file: URL
    var onRemove: (() -> Void)?

    var body: some View {
        Menu {
            Button("Home & Lock") { model.setNow(file) }
            Button("Home Screen") { model.setNow(file, screens: [.home]) }
            Button("Lock Screen") { model.setNow(file, screens: [.lock]) }
        } label: {
            Label("Set now", systemImage: "iphone")
        }
        Button {
            model.engine.queue(file, screens: [.home, .lock])
            model.reload()
            model.showToast("Up next")
        } label: {
            Label("Use next", systemImage: "forward")
        }
        Menu {
            ForEach((0...5).reversed(), id: \.self) { n in
                Button(n == 0 ? "No rating" : String(repeating: "★", count: n)) { model.rate(file, n) }
            }
        } label: {
            Label("Rate", systemImage: "star")
        }
        Button {
            Task {
                var saved = false
                if let data = try? Data(contentsOf: file) { saved = await PhotoLibrary.save(data) }
                model.showToast(saved ? "Saved to Photos" : "Couldn't save to Photos")
            }
        } label: {
            Label("Save to Photos", systemImage: "square.and.arrow.down")
        }
        ShareLink(item: file) { Label("Share", systemImage: "square.and.arrow.up") }
        Divider()
        Button(role: .destructive) {
            model.removeFromPool([file])
            onRemove?()
        } label: {
            Label("Remove from Library", systemImage: "trash")
        }
    }
}
