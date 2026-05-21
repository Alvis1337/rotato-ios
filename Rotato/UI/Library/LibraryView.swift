import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedCollection.name) private var collections: [SavedCollection]
    @State private var showNewCollectionAlert = false
    @State private var newCollectionName = ""
    @State private var collectionToDelete: SavedCollection?
    @State private var collectionToRename: SavedCollection?
    @State private var renameText = ""
    @State private var selectedTab = 0
    @State private var collectionSearch = ""

    private var filteredCollections: [SavedCollection] {
        if collectionSearch.isEmpty { return collections }
        return collections.filter { $0.name.localizedCaseInsensitiveContains(collectionSearch) }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Collections").tag(0)
                    Text("History").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if selectedTab == 0 {
                    collectionsView
                } else {
                    HistoryView()
                }
            }
            .navigationTitle(selectedTab == 0 ? "Library" : "History")
            .toolbar {
                if selectedTab == 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showNewCollectionAlert = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .alert("New Collection", isPresented: $showNewCollectionAlert) {
                TextField("Name", text: $newCollectionName)
                Button("Create") {
                    let col = SavedCollection(name: newCollectionName.isEmpty ? "Untitled" : newCollectionName)
                    modelContext.insert(col)
                    try? modelContext.save()
                    newCollectionName = ""
                }
                Button("Cancel", role: .cancel) { newCollectionName = "" }
            }
            .alert("Rename Collection", isPresented: Binding(
                get: { collectionToRename != nil },
                set: { if !$0 { collectionToRename = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Rename") {
                    if let col = collectionToRename {
                        col.name = renameText.trimmingCharacters(in: .whitespaces).isEmpty ? col.name : renameText.trimmingCharacters(in: .whitespaces)
                        try? modelContext.save()
                    }
                    collectionToRename = nil
                }
                Button("Cancel", role: .cancel) { collectionToRename = nil }
            }
            .confirmationDialog(
                "Delete \"\(collectionToDelete?.name ?? "")\"?",
                isPresented: Binding(get: { collectionToDelete != nil }, set: { if !$0 { collectionToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete Collection", role: .destructive) {
                    if let col = collectionToDelete {
                        deleteCollection(col)
                        collectionToDelete = nil
                    }
                }
            }
        }
    }

    private var collectionsView: some View {
        Group {
            if collections.isEmpty {
                ContentUnavailableView(
                    "No Collections",
                    systemImage: "photo.stack",
                    description: Text("Tap + to create your first collection, then save wallpapers from Discover.")
                )
            } else if filteredCollections.isEmpty {
                ContentUnavailableView.search(text: collectionSearch)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredCollections) { col in
                            NavigationLink(destination: CollectionDetailView(collection: col)) {
                                CollectionCard(collection: col)
                            }
                            .contextMenu {
                                Button {
                                    renameText = col.name
                                    collectionToRename = col
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    collectionToDelete = col
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(12)
                }
                .searchable(text: $collectionSearch, prompt: "Search collections…")
            }
        }
    }

    private func deleteCollection(_ col: SavedCollection) {
        let id = col.id
        let descriptor = FetchDescriptor<SavedEntry>(predicate: #Predicate { $0.collectionId == id })
        if let entries = try? modelContext.fetch(descriptor) {
            entries.forEach { modelContext.delete($0) }
        }
        modelContext.delete(col)
        try? modelContext.save()
    }
}

private struct CollectionCard: View {
    let collection: SavedCollection
    @Environment(\.modelContext) private var modelContext
    @State private var entryCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if collection.coverImageURL.isEmpty {
                    Rectangle()
                        .fill(Color(.systemFill))
                        .overlay(Image(systemName: "photo.stack").font(.largeTitle).foregroundStyle(.secondary))
                } else {
                    CachedImageView(url: URL(string: collection.coverImageURL), contentMode: .fill)
                }
            }
            .aspectRatio(1.5, contentMode: .fill)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Text("\(entryCount) wallpaper\(entryCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .onAppear { fetchCount() }
    }

    private func fetchCount() {
        let id = collection.id
        let descriptor = FetchDescriptor<SavedEntry>(predicate: #Predicate { $0.collectionId == id })
        entryCount = (try? modelContext.fetchCount(descriptor)) ?? 0
    }
}
