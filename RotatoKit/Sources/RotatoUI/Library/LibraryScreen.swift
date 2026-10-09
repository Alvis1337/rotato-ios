import PhotosUI
import RotatoKit
import SwiftUI

/// The rotation pool (HomeScreen on Android): Library, History and Stats tabs. The Library shows
/// the rotation status, a colour filter, every wallpaper your shortcut picks from, and Back /
/// Set Now / Add Photos / Save to collection.
public struct LibraryScreen: View {
    @Environment(AppModel.self) private var model
    @State private var section: LibrarySection = .library
    @State private var sort: LibrarySort = .name
    @State private var colorFilter: LibraryColorFilter?
    @State private var colors: [String: ImageColor] = [:]
    @State private var picks: [PhotosPickerItem] = []
    @State private var selecting = false
    @State private var selection: Set<URL> = []
    @State private var viewing: PoolItem?
    @State private var confirmRemove = false
    @State private var duplicates: [DuplicateGroup]?
    @State private var findingDuplicates = false
    @State private var savingToCollection = false

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sectionTabs
                switch section {
                case .library: library
                case .history: HistoryView()
                case .stats: StatsView()
                }
            }
            .toolbar(.hidden, for: .automatic)
            .onChange(of: picks) { _, items in importPhotos(items) }
            .task(id: model.poolFiles.count) { await loadColors() }
            .fullScreen(item: $viewing) { item in PoolViewer(files: shownFiles, start: item.url) }
            .sheet(isPresented: $savingToCollection) {
                CollectionPicker(title: "Save \(saveTargets.count) to…") { c in
                    let n = savePoolFiles(saveTargets, to: c.id)
                    model.showToast("Saved \(n) to \(c.name)")
                    selection = []
                    selecting = false
                }
            }
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

    // MARK: Sections

    private var sectionTabs: some View {
        HStack(spacing: 0) {
            ForEach(LibrarySection.allCases, id: \.self) { s in
                Button { withAnimation(.easeInOut(duration: 0.2)) { section = s } } label: {
                    VStack(spacing: 6) {
                        Image(systemName: s.icon).font(.title3)
                        Text(s.label).font(.subheadline)
                        Rectangle().fill(section == s ? Color.rotatoAccent : .clear).frame(height: 3).clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(section == s ? Color.primary : .secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var library: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                RotationStatusCard()
                HStack {
                    Text(selecting ? "\(selection.count) selected" : "Touch and hold an image for options")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Menu {
                        Picker("Sort", selection: $sort) {
                            ForEach(LibrarySort.allCases, id: \.self) { Label($0.label, systemImage: $0.icon).tag($0) }
                        }
                        Button { selecting.toggle(); selection = [] } label: {
                            Label(selecting ? "Stop selecting" : "Select", systemImage: "checkmark.circle")
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down").font(.caption.weight(.semibold))
                    }
                    .dockMenuStyle()
                    Button("Find duplicates") { findDuplicates() }
                        .font(.caption.weight(.semibold))
                        .disabled(model.poolFiles.count < 2 || findingDuplicates)
                }
                if !model.poolFiles.isEmpty { colorChips }
                grid
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .refreshable { await model.syncPool() }
        .overlay { if model.poolFiles.isEmpty { emptyState } }
        .safeAreaInset(edge: .bottom) { bottomBar }
    }

    private var colorChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                chip(.rainbow) {
                    Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                }
                ForEach(LibraryHue.all, id: \.hue) { h in
                    chip(.hue(h.hue)) { Circle().fill(h.color.gradient) }
                }
                chip(.dark) { Circle().fill(Color(white: 0.12)).overlay(Circle().stroke(.secondary.opacity(0.5))) }
                chip(.light) { Circle().fill(Color(white: 0.96)).overlay(Circle().stroke(.secondary.opacity(0.5))) }
            }
            .padding(.vertical, 4).padding(.horizontal, 3)
        }
    }

    private func chip<C: View>(_ f: LibraryColorFilter, @ViewBuilder _ content: () -> C) -> some View {
        Button {
            colorFilter = colorFilter == f ? nil : f
        } label: {
            content()
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(.primary, lineWidth: colorFilter == f ? 2.5 : 0).padding(-3))
        }
        .buttonStyle(.plain)
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(shownFiles, id: \.self) { file in
                PoolTile(file: file, selected: selecting ? selection.contains(file) : nil)
                    .onTapGesture {
                        if selecting {
                            if selection.contains(file) { selection.remove(file) } else { selection.insert(file) }
                        } else {
                            viewing = PoolItem(url: file)
                        }
                    }
                    .contextMenu {
                        Button {
                            selecting = true
                            selection.insert(file)
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
                        }
                        PoolActions(file: file)
                    }
            }
        }
        .overlay {
            if colorFilter != nil && shownFiles.isEmpty && !model.poolFiles.isEmpty {
                Text("No wallpapers stand out in that colour").foregroundStyle(.secondary).padding(.top, 40)
            }
        }
    }

    /// Back / Set Now / Add Photos, then Save to collection (Android's Library actions).
    /// While selecting, the bar acts on the selection.
    private var bottomBar: some View {
        VStack(spacing: 8) {
            if selecting {
                HStack(spacing: 8) {
                    barButton("Use next", "forward", style: .outline) {
                        for f in selection { model.engine.queue(f, screens: [.home, .lock]) }
                        model.reload()
                        model.showToast("Up next")
                    }
                    .disabled(selection.isEmpty)
                    barButton("Remove", "trash", style: .outline) { confirmRemove = true }
                        .disabled(selection.isEmpty)
                }
            } else {
                HStack(spacing: 8) {
                    barButton("Back", "arrow.uturn.backward", style: .outline) {
                        if model.engine.queuePrevious(for: .home) != nil { model.runShortcut() }
                        else { model.showToast("No earlier wallpaper yet") }
                    }
                    .disabled(model.state.history.count < 2)
                    barButton("Set Now", "photo.on.rectangle", style: .outline) { model.runShortcut() }
                        .disabled(model.poolFiles.isEmpty)
                    PhotosPicker(selection: $picks, matching: .images) {
                        barLabel("Add Photos", "plus", style: .filled)
                    }
                    .buttonStyle(.plain)
                }
            }
            barButton(selecting ? "Save \(selection.count) to collection…" : "Save to collection…", "bookmark", style: .outline) {
                savingToCollection = true
            }
            .disabled(saveTargets.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private enum BarStyle { case outline, filled }

    private func barButton(_ title: String, _ icon: String, style: BarStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) { barLabel(title, icon, style: style) }.buttonStyle(.plain)
    }

    private func barLabel(_ title: String, _ icon: String, style: BarStyle) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(style == .filled ? Color.white : .primary)
            .background(style == .filled ? Color.rotatoAccent : .clear, in: Capsule())
            .overlay(Capsule().stroke(style == .filled ? .clear : Color.secondary.opacity(0.5)))
            .contentShape(Capsule())
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Your Library is empty", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("Turn on rotation for a collection, or add photos. These are the wallpapers your shortcut picks from.")
        }
        .padding(.top, 140)
    }

    // MARK: Data

    private var saveTargets: [URL] { selecting ? Array(selection) : shownFiles }

    private var shownFiles: [URL] {
        var files = model.poolFiles
        if let f = colorFilter, f != .rainbow {
            files = files.filter { file in
                guard let c = colors[file.lastPathComponent] else { return false }
                return f.matches(c)
            }
        }
        switch colorFilter == .rainbow ? .rainbow : sort {
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

    /// Adds pool files to a collection: the original post when the file came from one, otherwise
    /// a copy of the photo.
    private func savePoolFiles(_ files: [URL], to listId: String) -> Int {
        let entries = model.entries
        var new: [CollectionEntry] = []
        for f in files {
            if let e = model.pool.entry(for: f, in: entries) {
                var c = e
                c.id = UUID().uuidString.lowercased()
                c.listId = listId
                c.addedAt = nowMillis()
                new.append(c)
            } else {
                let copy = RotatoPaths.device.appendingPathComponent(f.lastPathComponent)
                if !FileManager.default.fileExists(atPath: copy.path) { try? FileManager.default.copyItem(at: f, to: copy) }
                new.append(CollectionEntry(
                    listId: listId, sourceId: f.deletingPathExtension().lastPathComponent, source: "device",
                    thumbUrl: "device/\(f.lastPathComponent)", fullUrl: "device/\(f.lastPathComponent)"
                ))
            }
        }
        let n = model.collectionsRepo.add(entries: new)
        model.afterCollectionsChange()
        return n
    }
}

enum LibrarySection: CaseIterable {
    case library, history, stats

    var label: String {
        switch self { case .library: "Library"; case .history: "History"; case .stats: "Stats" }
    }

    var icon: String {
        switch self { case .library: "photo.on.rectangle"; case .history: "clock.arrow.circlepath"; case .stats: "chart.bar.fill" }
    }
}

enum LibraryColorFilter: Hashable {
    case rainbow, dark, light
    case hue(Double)

    func matches(_ c: ImageColor) -> Bool {
        switch self {
        case .rainbow: true
        case .dark: c.brightness < 0.25
        case .light: c.brightness > 0.8 && c.saturation < 0.25
        case .hue(let h): !c.isNeutral && ColorAnalysis.hueDistance(c.hue, h) < 0.07
        }
    }
}

/// "Rotating": pool size, last change, the collections feeding it (Android's status card).
struct RotationStatusCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let linked = model.collections.filter(\.useAsRotation).map(\.name)
        let set = model.state.totalRotations > 0
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(set ? "Rotating" : "Not rotating yet").font(.headline)
                Spacer()
                if model.isSyncingPool { ProgressView().controlSize(.small) }
                if !set {
                    NavigationLink { ShortcutsSetupView() } label: {
                        Text("Set up").font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.white.opacity(0.25), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("\(model.poolFiles.count) photos · changed by your \"\(model.settings.shortcutName)\" shortcut")
                .font(.subheadline)
            if let last = model.state.history.first {
                Text("Last set \(Date(timeIntervalSince1970: Double(last.timestamp) / 1000), format: .relative(presentation: .named))")
                    .font(.caption).opacity(0.8)
            } else if let reason = model.state.lastSkipReason {
                Text(reason).font(.caption).opacity(0.8)
            }
            if !linked.isEmpty {
                Label("Linked to \(linked.map { "\"\($0)\"" }.joined(separator: ", "))", systemImage: "link")
                    .font(.caption).opacity(0.8)
                    .lineLimit(2)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rotatoAccent.gradient, in: RoundedRectangle(cornerRadius: 16))
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
            .aspectRatio(0.8, contentMode: .fit)
            .overlay { LocalImage(file, maxPixel: 400).nsfwBlur(model.state.nsfwFileNames.contains(name)) }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .bottomLeading) {
                Text(PoolTile.caption(file))
                    .font(.system(size: 8, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(4)
            }
            .overlay(alignment: .bottomTrailing) {
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

    /// "2894×4092 · 1.3 MB"
    static func caption(_ file: URL) -> String {
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map {
            ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
        } ?? ""
        guard let px = ImageLoader.pixelSize(file) else { return size }
        return "\(Int(px.width))×\(Int(px.height)) · \(size)"
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
