import SwiftUI
import SwiftData

enum CollectionSortOrder: String, CaseIterable {
    case dateAdded = "Date Added"
    case rating = "Rating"
    case source = "Source"
}

struct CollectionDetailView: View {
    let collection: SavedCollection

    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @State private var entries: [SavedEntry] = []
    @State private var selectedEntry: SavedEntry?
    @State private var editMode = false
    @State private var selectedForDelete = Set<UUID>()
    @State private var showDeleteConfirm = false
    @State private var sortOrder: CollectionSortOrder = .dateAdded
    @State private var sortAscending = false
    @State private var searchQuery = ""

    private var filteredEntries: [SavedEntry] {
        var result = entries
        if !searchQuery.isEmpty {
            let q = searchQuery.lowercased()
            result = result.filter { e in
                e.tags.contains(where: { $0.localizedCaseInsensitiveContains(q) }) ||
                e.sourcePluginId.localizedCaseInsensitiveContains(q)
            }
        }
        switch sortOrder {
        case .dateAdded:
            result.sort { sortAscending ? $0.savedAt < $1.savedAt : $0.savedAt > $1.savedAt }
        case .rating:
            result.sort {
                let r0 = settings.rating(for: $0.id.uuidString)
                let r1 = settings.rating(for: $1.id.uuidString)
                return sortAscending ? r0 < r1 : r0 > r1
            }
        case .source:
            result.sort { sortAscending ? $0.sourcePluginId < $1.sourcePluginId : $0.sourcePluginId > $1.sourcePluginId }
        }
        return result
    }

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Empty Collection",
                    systemImage: "photo.badge.plus",
                    description: Text("Save wallpapers from Discover to fill this collection.")
                )
            } else {
                ScrollView {
                    if filteredEntries.isEmpty {
                        ContentUnavailableView.search(text: searchQuery)
                            .padding(.top, 60)
                    } else {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { idx, entry in
                            CollectionEntryThumb(
                                entry: entry,
                                settings: settings,
                                editMode: editMode,
                                isSelected: selectedForDelete.contains(entry.id)
                            )
                            .onTapGesture {
                                if editMode {
                                    if selectedForDelete.contains(entry.id) {
                                        selectedForDelete.remove(entry.id)
                                    } else {
                                        selectedForDelete.insert(entry.id)
                                    }
                                } else {
                                    selectedEntry = entry
                                }
                            }
                        }
                    }
                    }
                }
                .searchable(text: $searchQuery, prompt: "Search tags, source…")
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section("Sort By") {
                            ForEach(CollectionSortOrder.allCases, id: \.self) { order in
                                Button {
                                    if sortOrder == order { sortAscending.toggle() }
                                    else { sortOrder = order; sortAscending = false }
                                } label: {
                                    HStack {
                                        Text(order.rawValue)
                                        if sortOrder == order {
                                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode ? "Done" : "Select") {
                        withAnimation { editMode.toggle() }
                        if !editMode { selectedForDelete.removeAll() }
                    }
                }
            }
            if editMode && !selectedForDelete.isEmpty {
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("Delete \(selectedForDelete.count)", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        }
        .confirmationDialog(
            "Delete \(selectedForDelete.count) wallpaper\(selectedForDelete.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelected() }
        } message: {
            Text("This cannot be undone.")
        }
        .fullScreenCover(item: $selectedEntry) { entry in
            entryPreview(entry: entry)
        }
        .onAppear { fetchEntries() }
    }

    private func entryPreview(entry: SavedEntry) -> some View {
        // Build wallpapers array and track the index of `entry` simultaneously,
        // so that entries with invalid URLs removed by compactMap don't cause an
        // index-out-of-bounds crash in FullscreenPreviewView.
        var targetIdx = 0
        var wallpapers: [WallpaperItem] = []
        for e in filteredEntries {
            guard let img = e.imageURL, let thumb = e.thumbnailURL else { continue }
            if e.id == entry.id { targetIdx = wallpapers.count }
            wallpapers.append(WallpaperItem(id: e.id.uuidString, imageURL: img, thumbnailURL: thumb,
                                            sourceId: e.sourcePluginId, tags: e.tags,
                                            width: e.width, height: e.height, rating: e.rating))
        }
        return FullscreenPreviewView(
            items: wallpapers,
            initialIndex: wallpapers.isEmpty ? 0 : min(targetIdx, wallpapers.count - 1),
            onDismiss: { selectedEntry = nil }
        )
    }

    private func fetchEntries() {
        let id = collection.id
        let descriptor = FetchDescriptor<SavedEntry>(
            predicate: #Predicate { $0.collectionId == id },
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )
        entries = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func deleteSelected() {
        entries
            .filter { selectedForDelete.contains($0.id) }
            .forEach { modelContext.delete($0) }
        try? modelContext.save()
        selectedForDelete.removeAll()
        editMode = false
        fetchEntries()
        // Sync cover: clear if no entries remain, otherwise keep it pointing at the first
        if entries.isEmpty {
            collection.coverImageURL = ""
        } else {
            collection.coverImageURL = entries.first?.thumbnailURL?.absoluteString ?? ""
        }
        try? modelContext.save()
    }
}

private struct CollectionEntryThumb: View {
    let entry: SavedEntry
    let settings: AppSettings
    let editMode: Bool
    let isSelected: Bool

    var body: some View {
        ZStack {
            CachedImageView(url: entry.thumbnailURL, contentMode: .fill)
                .blur(radius: entry.isNSFW && !settings.nsfwEnabled ? 18 : 0)

            if entry.isNSFW && !settings.nsfwEnabled {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if editMode {
                Color.black.opacity(0.25)
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(isSelected ? .blue : .white)
                            .shadow(radius: 2)
                            .padding(4)
                    }
                    Spacer()
                }
            }

            // Star badge
            let stars = settings.rating(for: entry.id.uuidString)
            if stars > 0 {
                VStack {
                    Spacer()
                    HStack {
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
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }
}
