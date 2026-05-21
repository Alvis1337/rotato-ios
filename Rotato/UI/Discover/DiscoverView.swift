import SwiftUI
import SwiftData

struct DiscoverView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext

    @State private var vm: DiscoverViewModel?
    @State private var selectedItem: WallpaperItem?
    @State private var selectedItemIndex = 0
    @State private var showSearchField = false
    @FocusState private var searchFocused: Bool

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if let vm {
                    content(vm: vm)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarItems }
            .task {
                if vm == nil {
                    let v = DiscoverViewModel(settings: settings)
                    vm = v
                    await v.load()
                }
            }
        }
        .fullScreenCover(item: $selectedItem) { item in
            if let vm {
                FullscreenPreviewView(
                    items: vm.items,
                    initialIndex: selectedItemIndex,
                    onDismiss: { selectedItem = nil }
                )
            }
        }
    }

    @ViewBuilder
    private func content(vm: DiscoverViewModel) -> some View {
        if vm.isLoading && vm.items.isEmpty {
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = vm.errorMessage, vm.items.isEmpty {
            errorView(message: err, vm: vm)
        } else if vm.noResults {
            noResultsView(vm: vm)
        } else {
            VStack(spacing: 0) {
                // Source chips live OUTSIDE the scrollable area to avoid bounce conflicts
                sourceChips(vm: vm)

                ScrollView {
                    if showSearchField {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Search tags…", text: Binding(
                                get: { vm.searchQuery },
                                set: { vm.searchQuery = $0 }
                            ))
                            .focused($searchFocused)
                            .submitLabel(.search)
                            .onSubmit { Task { await vm.search() } }
                            if !vm.searchQuery.isEmpty {
                                Button { vm.clearSearch(); showSearchField = false } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 12).padding(.top, 4)
                        .onAppear { searchFocused = true }
                    }

                    // MAL tag banner
                    if vm.searchQuery.isEmpty, !vm.items.isEmpty, !vm.currentMalTag.isEmpty {
                        let mal = vm.currentMalTag
                        HStack(spacing: 6) {
                            Image(systemName: "list.star")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("MAL: \(mal)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 4)
                    }

                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(Array(vm.items.enumerated()), id: \.element.id) { idx, item in
                            WallpaperThumb(item: item)
                                .onTapGesture {
                                    selectedItemIndex = idx
                                    selectedItem = item
                                }
                                .onAppear {
                                    if idx == vm.items.count - 8 {
                                        Task { await vm.loadMore() }
                                    }
                                }
                        }
                    }

                    if vm.isLoadingMore {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("Loading more…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                    }
                }
                .refreshable { await vm.load() }
            }
        }
    }

    @ViewBuilder
    private func sourceChips(vm: DiscoverViewModel) -> some View {
        let enabledPlugins = PluginRegistry.all.filter { settings.config(for: $0.id).enabled }
        if enabledPlugins.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(enabledPlugins, id: \.id) { plugin in
                        let isActive = vm.activeSourceIds.isEmpty || vm.activeSourceIds.contains(plugin.id)
                        Button {
                            vm.toggleSource(plugin.id)
                        } label: {
                            Label(plugin.displayName, systemImage: plugin.sfSymbol)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(isActive ? Color.accentColor : Color(.systemFill), in: Capsule())
                                .foregroundStyle(isActive ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .animation(.easeInOut(duration: 0.15), value: isActive)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 6)
        }
    }

    private func errorView(message: String, vm: DiscoverViewModel) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 48)).foregroundStyle(.secondary)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Retry") { Task { await vm.load() } }.buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func noResultsView(vm: DiscoverViewModel) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.exclamationmark").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No wallpapers found").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            if !vm.searchQuery.isEmpty {
                Text("Searching: \"\(vm.searchQuery)\"").font(.caption).foregroundStyle(.tertiary)
                Button("Clear Search") { vm.clearSearch() }.buttonStyle(.bordered)
            }
            NavigationLink("Configure Sources") {
                SourceSettingsView()
            }.buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation { showSearchField.toggle() }
                if !showSearchField { vm?.clearSearch() }
            } label: {
                Image(systemName: showSearchField ? "xmark" : "magnifyingglass")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { Task { await vm?.load() } } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
    }
}

// MARK: - Thumbnail cell

private struct WallpaperThumb: View {
    let item: WallpaperItem
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            CachedImageView(url: item.thumbnailURL, contentMode: .fill)
                .blur(radius: item.isNSFW && !settings.nsfwEnabled ? 18 : 0)

            if item.isNSFW && !settings.nsfwEnabled {
                Image(systemName: "eye.slash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Source badge
            Text(sourceLabel(for: item.sourceId))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 3))
                .padding(4)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
    }

    private func sourceLabel(for id: String) -> String {
        switch id {
        case "GELBOORU": return "GEL"
        case "DANBOORU": return "DAN"
        case "WALLHAVEN": return "WLH"
        case "REDDIT": return "RDT"
        case "RULE34": return "R34"
        case "ZEROCHAN": return "ZRC"
        case "ANIMEPICTURES": return "ANP"
        case "KONACHAN": return "KON"
        default: return String(id.prefix(3))
        }
    }
}

// MARK: - Save to collection sheet

struct SaveToCollectionSheet: View {
    let item: WallpaperItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var collections: [SavedCollection]
    @State private var showNewCollectionAlert = false
    @State private var newCollectionName = ""

    var body: some View {
        NavigationStack {
            List {
                if collections.isEmpty {
                    ContentUnavailableView("No Collections", systemImage: "photo.stack",
                                          description: Text("Create a collection to save wallpapers."))
                } else {
                    ForEach(collections) { col in
                        Button {
                            save(to: col)
                        } label: {
                            Label(col.name, systemImage: "photo.stack")
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Save to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New") { showNewCollectionAlert = true }
                }
            }
            .alert("New Collection", isPresented: $showNewCollectionAlert) {
                TextField("Name", text: $newCollectionName)
                Button("Create") {
                    let col = SavedCollection(name: newCollectionName.isEmpty ? "Untitled" : newCollectionName)
                    modelContext.insert(col)
                    save(to: col)
                    newCollectionName = ""
                }
                Button("Cancel", role: .cancel) { newCollectionName = "" }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save(to collection: SavedCollection) {
        let entry = SavedEntry(collectionId: collection.id, from: item)
        modelContext.insert(entry)
        if collection.coverImageURL.isEmpty {
            collection.coverImageURL = item.thumbnailURL.absoluteString
        }
        try? modelContext.save()
        dismiss()
    }
}
