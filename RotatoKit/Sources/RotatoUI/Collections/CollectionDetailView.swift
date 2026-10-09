import PhotosUI
import RotatoKit
import SwiftUI

enum EntrySort: String, CaseIterable {
    case dateAdded, source, resolution

    var label: String {
        switch self { case .dateAdded: "Date added"; case .source: "Source"; case .resolution: "Resolution" }
    }
}

/// One collection's wallpapers (WallpaperGridContent on Android).
struct CollectionDetailView: View {
    @Environment(AppModel.self) private var model
    let collectionId: String
    var onSearchDiscover: (String) -> Void

    @AppStorage("collectionSort") private var sort: EntrySort = .dateAdded
    @State private var search = ""
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var viewer: ViewerStart?
    @State private var picks: [PhotosPickerItem] = []
    @State private var filling = false
    @State private var fillRunning = false
    @State private var lastFill: Set<String> = []
    @State private var moveMode: MoveMode?
    @State private var showSettings = false
    @State private var confirmRemove = false

    enum MoveMode: String, Identifiable { case move, copy; var id: String { rawValue } }

    var body: some View {
        if let c = model.collections.first(where: { $0.id == collectionId }) {
            content(c)
        } else {
            ContentUnavailableView("Collection deleted", systemImage: "trash")
        }
    }

    private func content(_ c: WallpaperCollection) -> some View {
        let items = shown
        return ScrollView {
            if c.isLocked && !model.lockedUnlocked {
                ContentUnavailableView("Locked", systemImage: "lock.fill")
            } else {
                header(c)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 6)], spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, e in
                        EntryTile(entry: e, exemptBlur: c.blurExempt, selected: selecting ? selection.contains(e.id) : nil)
                            .onTapGesture {
                                if selecting { toggle(e.id) } else { viewer = ViewerStart(index: i) }
                            }
                            .contextMenu { entryMenu(e, c) }
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .overlay {
            if items.isEmpty && (!c.isLocked || model.lockedUnlocked) {
                if search.isBlank { emptyState(c) } else { ContentUnavailableView.search(text: search) }
            }
        }
        .searchable(text: $search, prompt: "Tags or source")
        .navigationTitle(c.name)
        .inlineTitle()
        .toolbar { toolbar(c) }
        .safeAreaInset(edge: .bottom) { if selecting { selectionBar } }
        .overlay(alignment: .bottom) { if fillRunning { fillProgress } }
        .onChange(of: picks) { _, items in importPhotos(items, into: c) }
        .fullScreen(item: $viewer) { start in
            WallpaperViewer(items: items.map(\.wallpaper), startIndex: start.index, collectionId: c.id)
        }
        .sheet(isPresented: $filling) {
            FillSheet(collection: c) { tags, count, pluginId, instanceId in
                Task { await fill(c, tags: tags, count: count, pluginId: pluginId, instanceId: instanceId) }
            }
        }
        .sheet(isPresented: $showSettings) { CollectionSettingsSheet(collectionId: c.id) }
        .sheet(item: $moveMode) { mode in
            CollectionPicker(title: mode == .move ? "Move to…" : "Copy to…", excluding: [c.id]) { target in
                let n = mode == .move ? model.collectionsRepo.move(entryIds: selection, to: target.id)
                    : model.collectionsRepo.copy(entryIds: selection, to: target.id)
                model.afterCollectionsChange()
                model.showToast("\(mode == .move ? "Moved" : "Copied") \(n) to \(target.name)")
                selection = []
                selecting = false
            }
        }
        .confirmationDialog("Remove \(selection.count) from \(c.name)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                model.collectionsRepo.remove(entryIds: selection)
                model.afterCollectionsChange()
                selection = []
                selecting = false
            }
        }
        .task {
            if c.isLocked && !model.lockedUnlocked { _ = await model.unlockLocked() }
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func header(_ c: WallpaperCollection) -> some View {
        let count = model.entries(in: c.id).count
        HStack(spacing: 8) {
            Text("\(count) wallpaper\(count == 1 ? "" : "s")").foregroundStyle(.secondary)
            if c.useAsRotation {
                Label(c.rotationTarget.label, systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.tint)
            }
            if c.isSmartCollection { Label("Smart", systemImage: "wand.and.stars").foregroundStyle(.purple) }
            Spacer()
            if !lastFill.isEmpty {
                Button("Undo fill") {
                    model.collectionsRepo.remove(entryIds: lastFill)
                    model.afterCollectionsChange()
                    model.showToast("Removed \(lastFill.count) from \(c.name)")
                    lastFill = []
                }
                .font(.subheadline)
            }
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.top, 6)
    }

    private func emptyState(_ c: WallpaperCollection) -> some View {
        ContentUnavailableView {
            Label("Nothing here yet", systemImage: c.isSmartCollection ? "wand.and.stars" : "photo.stack")
        } description: {
            Text(c.isSmartCollection
                 ? "Saved wallpapers that match the rules appear here. Fill it from your sources with the rule's tags."
                 : "Save wallpapers from Discover, add photos, or fill it from your sources.")
        } actions: {
            Button("Fill from sources") { filling = true }.buttonStyle(.borderedProminent)
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ c: WallpaperCollection) -> some ToolbarContent {
        ToolbarItemGroup(placement: .trailingBar) {
            if selecting {
                Button("Done") { selecting = false; selection = [] }
            } else {
                Menu {
                    Button { filling = true } label: { Label("Fill from sources", systemImage: "arrow.down.circle") }
                    PhotosPicker(selection: $picks, matching: .images) { Label("Add photos", systemImage: "photo.badge.plus") }
                    Button { selecting = true } label: { Label("Select", systemImage: "checkmark.circle") }
                    Picker("Sort", selection: $sort) {
                        ForEach(EntrySort.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    Divider()
                    Button {
                        model.modifyCollection(c.id) { $0.useAsRotation.toggle() }
                    } label: {
                        Label(c.useAsRotation ? "Stop rotating" : "Use for rotation", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button { showSettings = true } label: { Label("Collection settings", systemImage: "slider.horizontal.3") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 22) {
            Button(selection.count == shown.count ? "None" : "All") {
                selection = selection.count == shown.count ? [] : Set(shown.map(\.id))
            }
            Spacer()
            Button { moveMode = .move } label: { Image(systemName: "folder") }
            Button { moveMode = .copy } label: { Image(systemName: "plus.square.on.square") }
            Button { saveSelectedToPhotos() } label: { Image(systemName: "square.and.arrow.down") }
            Button(role: .destructive) { confirmRemove = true } label: { Image(systemName: "trash") }
        }
        .disabled(selection.isEmpty)
        .padding()
        .background(.bar)
    }

    private var fillProgress: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Filling from your sources…").font(.subheadline)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private func entryMenu(_ e: CollectionEntry, _ c: WallpaperCollection) -> some View {
        Button {
            Task { await model.setNow(e.wallpaper) }
        } label: {
            Label("Set now", systemImage: "iphone")
        }
        .disabled(e.isVideo)
        Button {
            model.modifyCollection(c.id) { $0.coverUrl = e.thumbUrl.ifBlank(e.sampleUrl) }
        } label: {
            Label("Use as cover", systemImage: "photo.artframe")
        }
        if let first = e.tags.first(where: { !$0.isBlank }) {
            Button { onSearchDiscover(first) } label: { Label("More like \"\(first)\"", systemImage: "sparkles") }
        }
        if let url = URL(string: e.pageUrl), e.pageUrl.hasPrefix("http") {
            Link(destination: url) { Label("Open source page", systemImage: "safari") }
        }
        Button {
            selecting = true
            selection = [e.id]
        } label: {
            Label("Select", systemImage: "checkmark.circle")
        }
        Divider()
        Button(role: .destructive) {
            model.collectionsRepo.remove(entryIds: [e.id])
            model.afterCollectionsChange()
        } label: {
            Label("Remove", systemImage: "trash")
        }
    }

    // MARK: Data

    private var shown: [CollectionEntry] {
        var items = model.entries(in: collectionId)
        if !search.isBlank {
            let q = normalizeTag(search)
            items = items.filter { e in e.source.lowercased().contains(q) || e.tags.contains { normalizeTag($0).contains(q) } }
        }
        switch sort {
        case .dateAdded:
            return items
        case .source:
            return items.sorted { ($0.source.lowercased(), -$0.addedAt) < ($1.source.lowercased(), -$1.addedAt) }
        case .resolution:
            func px(_ e: CollectionEntry) -> Int { parseResolution(e.resolution).map { $0.width * $0.height } ?? 0 }
            return items.sorted { px($0) > px($1) }
        }
    }

    private func parseResolution(_ s: String) -> (width: Int, height: Int)? {
        let p = s.lowercased().split(separator: "x").compactMap { Int($0) }
        return p.count == 2 ? (p[0], p[1]) : nil
    }

    private func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    private func fill(_ c: WallpaperCollection, tags: String, count: Int, pluginId: String?, instanceId: String?) async {
        fillRunning = true
        defer { fillRunning = false }
        lastFill = await model.fill(c, tags: tags, count: count, pluginId: pluginId, instanceId: instanceId)
    }

    private func importPhotos(_ items: [PhotosPickerItem], into c: WallpaperCollection) {
        guard !items.isEmpty else { return }
        Task {
            var n = 0
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let name = "\(UUID().uuidString.lowercased()).\(imageExt(data))"
                do {
                    try data.write(to: RotatoPaths.device.appendingPathComponent(name), options: .atomic)
                    model.collectionsRepo.addDeviceImage(fileName: name, to: c.id)
                    n += 1
                } catch {}
            }
            picks = []
            model.afterCollectionsChange()
            model.showToast("Added \(n) photo\(n == 1 ? "" : "s")")
        }
    }

    private func imageExt(_ d: Data) -> String {
        let b = [UInt8](d.prefix(12))
        if b.count >= 2, b[0] == 0x89, b[1] == 0x50 { return "png" }
        if b.count >= 8, b[4] == 0x66, b[5] == 0x74, b[6] == 0x79, b[7] == 0x70 { return "heic" }
        return "jpg"
    }

    private func saveSelectedToPhotos() {
        let picked = model.entries.filter { selection.contains($0.id) && !$0.isVideo }
        Task {
            var saved = 0
            for e in picked {
                if let data = await ImagePipeline.shared.cachedData(e.fullUrl),
                   await PhotoLibrary.save(data) { saved += 1 }
            }
            model.showToast("Saved \(saved) to Photos")
        }
    }
}

struct ViewerStart: Identifiable {
    let index: Int
    var id: Int { index }
}

/// A collection grid tile.
struct EntryTile: View {
    let entry: CollectionEntry
    let exemptBlur: Bool
    let selected: Bool?

    var body: some View {
        Color.clear
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                RemoteImage(entry.sampleUrl.ifBlank(entry.thumbUrl), preview: entry.thumbUrl, maxPixel: 400)
                    .nsfwBlur(entry.isNsfw, key: "\(entry.source):\(entry.sourceId)", exempt: exemptBlur)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottomLeading) {
                if entry.isVideo {
                    Image(systemName: "play.fill").font(.caption).foregroundStyle(.white).padding(6).shadow(radius: 2)
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
            .contentShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Tags, count and source for a fill (FetchFromSourcesDialog on Android).
struct FillSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let collection: WallpaperCollection
    let start: (String, Int, String?, String?) -> Void
    @State private var tags = ""
    @State private var count = 25
    @State private var sourceKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Tags (blank for anything)", text: $tags).plainTextEntry()
                } footer: {
                    Text("Space-separated tags, like on the source sites. Sources that allow fewer tags are skipped.")
                }
                Section {
                    Stepper("\(count) wallpapers", value: $count, in: 5...200, step: 5)
                    Picker("From", selection: $sourceKey) {
                        Text("All enabled sources").tag("")
                        ForEach(model.enabledSources) { s in
                            Text(label(s)).tag(s.id)
                        }
                    }
                }
            }
            .navigationTitle("Fill \(collection.name)")
            .inlineTitle()
            .onAppear {
                // Smart collections suggest their own rule's tags.
                if tags.isEmpty, let rule = collection.smartRule { tags = rule.requireAll.joined(separator: " ") }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fill") {
                        let s = model.sources.first { $0.id == sourceKey }
                        start(tags, count, s?.pluginId, s.map { $0.instanceId })
                        dismiss()
                    }
                    .disabled(model.enabledSources.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func label(_ s: SourceConfig) -> String {
        let name = model.manifest(for: s)?.name ?? s.pluginId.capitalized
        return s.instanceId.isEmpty ? name : "\(name) r/\(s.instanceId)"
    }
}
