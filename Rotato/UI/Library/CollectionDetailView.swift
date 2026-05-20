import SwiftUI
import SwiftData

struct CollectionDetailView: View {
    let collection: SavedCollection

    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @State private var entries: [SavedEntry] = []
    @State private var selectedEntry: SavedEntry?
    @State private var selectedIndex = 0
    @State private var editMode = false
    @State private var selectedForDelete = Set<UUID>()
    @State private var showDeleteConfirm = false

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
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                            ZStack {
                                CachedImageView(url: entry.thumbnailURL, contentMode: .fill)
                                    .aspectRatio(1, contentMode: .fill)
                                    .clipped()
                                if entry.isNSFW && !settings.nsfwEnabled {
                                    Rectangle()
                                        .fill(.ultraThinMaterial)
                                    Image(systemName: "eye.slash.fill")
                                        .foregroundStyle(.white)
                                        .font(.title3)
                                }
                                if editMode {
                                    Color.black.opacity(0.25)
                                    VStack {
                                        HStack {
                                            Spacer()
                                            Image(systemName: selectedForDelete.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 20))
                                                .foregroundStyle(selectedForDelete.contains(entry.id) ? .blue : .white)
                                                .shadow(radius: 2)
                                                .padding(4)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                            .clipped()
                            .onTapGesture {
                                if editMode {
                                    if selectedForDelete.contains(entry.id) {
                                        selectedForDelete.remove(entry.id)
                                    } else {
                                        selectedForDelete.insert(entry.id)
                                    }
                                } else {
                                    selectedIndex = idx
                                    selectedEntry = entry
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !entries.isEmpty {
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
        let wallpapers: [WallpaperItem] = entries.compactMap { e in
            guard let img = e.imageURL, let thumb = e.thumbnailURL else { return nil }
            return WallpaperItem(id: e.id.uuidString, imageURL: img, thumbnailURL: thumb,
                                 sourceId: e.sourcePluginId, tags: e.tags,
                                 width: e.width, height: e.height, rating: e.rating)
        }
        return FullscreenPreviewView(
            items: wallpapers,
            initialIndex: selectedIndex,
            onDismiss: { selectedEntry = nil },
            onSave: nil
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
        // Update cover if we deleted it
        if let first = entries.first {
            collection.coverImageURL = first.thumbnailURL?.absoluteString ?? ""
        }
    }
}
