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
    @State private var showRulesSheet = false
    @State private var showFillSheet = false
    @State private var fillRequest = CollectionFillRequest()
    @State private var isFilling = false
    @State private var fillProgressMessage = ""
    @State private var toastMessage: String?

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
                let key0 = $0.originalItemId.isEmpty ? $0.id.uuidString : $0.originalItemId
                let key1 = $1.originalItemId.isEmpty ? $1.id.uuidString : $1.originalItemId
                let r0 = settings.rating(for: key0)
                let r1 = settings.rating(for: key1)
                return sortAscending ? r0 < r1 : r0 > r1
            }
        case .source:
            result.sort { sortAscending ? $0.sourcePluginId < $1.sourcePluginId : $0.sourcePluginId > $1.sourcePluginId }
        }
        return result
    }

    private var sourceOptions: [SourceOption] {
        PluginRegistry.all
            .map { SourceOption(id: $0.id, displayName: $0.displayName, sfSymbol: $0.sfSymbol) }
            .sorted { $0.displayName < $1.displayName }
    }

    private var fillSourceOptions: [SourceOption] {
        sourceOptions.filter { settings.config(for: $0.id).enabled }
    }

    private var emptyDescription: Text {
        if collection.isSmartCollection {
            Text("Use Auto-fill to pull matching saved wallpapers, or tap Fill to fetch more from your sources.")
        } else {
            Text("Save wallpapers from Discover or tap Fill to fetch more from your sources.")
        }
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
                    systemImage: collection.isSmartCollection ? "sparkles.square.filled.on.square" : "photo.badge.plus",
                    description: emptyDescription
                )
            } else {
                ScrollView {
                    if filteredEntries.isEmpty {
                        ContentUnavailableView.search(text: searchQuery)
                            .padding(.top, 60)
                    } else {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(filteredEntries) { entry in
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
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fill") {
                    showFillSheet = true
                }
                .disabled(isFilling)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("Collection") {
                        Button {
                            showRulesSheet = true
                        } label: {
                            Label(collection.isSmartCollection ? "Edit Rules" : "Add Rules", systemImage: "slider.horizontal.3")
                        }

                        Button {
                            Task { await autoFillSmartCollection() }
                        } label: {
                            Label("Auto-fill", systemImage: "sparkles")
                        }
                        .disabled(collection.smartRules.isEmpty || isFilling)
                    }

                    if !entries.isEmpty {
                        Section("Sort By") {
                            ForEach(CollectionSortOrder.allCases, id: \.self) { order in
                                Button {
                                    if sortOrder == order {
                                        sortAscending.toggle()
                                    } else {
                                        sortOrder = order
                                        sortAscending = false
                                    }
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
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(isFilling)
            }
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
        .sheet(isPresented: $showRulesSheet) {
            SmartRulesEditorSheet(
                collectionName: collection.name,
                sourceOptions: sourceOptions,
                initialRules: collection.smartRules
            ) { rules in
                collection.smartRules = rules
                try? modelContext.save()
                showToast(rules.isEmpty ? "Smart rules cleared" : "Saved \(rules.count) smart rule\(rules.count == 1 ? "" : "s")")
            }
        }
        .sheet(isPresented: $showFillSheet) {
            FillFromSourcesSheet(
                request: $fillRequest,
                sourceOptions: fillSourceOptions,
                isLoading: isFilling,
                progressMessage: fillProgressMessage,
                onFill: startFill
            )
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.8), in: Capsule())
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastMessage)
        .onAppear { fetchEntries() }
    }

    private func entryPreview(entry: SavedEntry) -> some View {
        var targetIdx = 0
        var wallpapers: [WallpaperItem] = []
        for e in filteredEntries {
            guard let wallpaper = e.wallpaperItem else { continue }
            if e.id == entry.id { targetIdx = wallpapers.count }
            wallpapers.append(wallpaper)
        }
        guard !wallpapers.isEmpty else {
            return AnyView(Color.clear.onAppear { selectedEntry = nil })
        }
        return AnyView(FullscreenPreviewView(
            items: wallpapers,
            initialIndex: min(targetIdx, wallpapers.count - 1),
            onDismiss: { selectedEntry = nil }
        ))
    }

    private func fetchEntries() {
        let id = collection.id
        let descriptor = FetchDescriptor<SavedEntry>(
            predicate: #Predicate { $0.collectionId == id },
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )
        entries = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func syncCoverImage() {
        collection.coverImageURL = entries.first?.thumbnailURLString ?? ""
        try? modelContext.save()
    }

    private func deleteSelected() {
        entries
            .filter { selectedForDelete.contains($0.id) }
            .forEach { modelContext.delete($0) }
        try? modelContext.save()
        selectedForDelete.removeAll()
        editMode = false
        fetchEntries()
        syncCoverImage()
    }

    private func startFill(_ request: CollectionFillRequest) {
        Task { await fillFromSources(request) }
    }

    @MainActor
    private func autoFillSmartCollection() async {
        let rules = collection.smartRules
        guard !rules.isEmpty else {
            showToast("Add smart rules first")
            return
        }

        let existingKeys = Set(entries.map(\.dedupeKey))
        let descriptor = FetchDescriptor<SavedEntry>(sortBy: [SortDescriptor(\.savedAt, order: .reverse)])
        let allEntries = (try? modelContext.fetch(descriptor)) ?? []

        var seenKeys = existingKeys
        var added = 0
        var firstAddedThumbnail: String?

        for entry in allEntries where rules.matches(entry) {
            guard !seenKeys.contains(entry.dedupeKey) else { continue }
            let cloned = SavedEntry(collectionId: collection.id, cloning: entry)
            modelContext.insert(cloned)
            seenKeys.insert(cloned.dedupeKey)
            firstAddedThumbnail = firstAddedThumbnail ?? cloned.thumbnailURLString
            added += 1
        }

        try? modelContext.save()
        fetchEntries()
        if entries.isEmpty {
            collection.coverImageURL = ""
        } else if collection.coverImageURL.isEmpty, let firstAddedThumbnail {
            collection.coverImageURL = firstAddedThumbnail
        }
        try? modelContext.save()

        showToast(
            added > 0
                ? "Auto-fill added \(added) image\(added == 1 ? "" : "s")"
                : "No new matches found"
        )
    }

    @MainActor
    private func fillFromSources(_ request: CollectionFillRequest) async {
        guard !isFilling else { return }
        let trimmedTags = request.trimmedTags
        guard !trimmedTags.isEmpty else { return }

        if request.useMalFilter && settings.malAnimeList.isEmpty {
            showToast("Load your MAL list first")
            return
        }

        let enabledPlugins = PluginRegistry.all.filter { plugin in
            settings.config(for: plugin.id).enabled && (request.sourceId == nil || request.sourceId == plugin.id)
        }

        guard !enabledPlugins.isEmpty else {
            showToast("No enabled sources available")
            return
        }

        isFilling = true
        fillProgressMessage = "Preparing requests…"

        var existingKeys = Set(entries.map(\.dedupeKey))
        let normalizedMalTitles = Set(settings.malAnimeList.map(normalizeCollectionMatchToken).filter { !$0.isEmpty })
        let maxPages = max(1, min((request.count / 25) + 2, 5))
        var added = 0
        var firstAddedThumbnail: String?

        defer {
            isFilling = false
            fillProgressMessage = ""
            showFillSheet = false
            fetchEntries()
            if collection.coverImageURL.isEmpty, let firstAddedThumbnail {
                collection.coverImageURL = firstAddedThumbnail
                try? modelContext.save()
            }
        }

        for plugin in enabledPlugins {
            if added >= request.count { break }

            var config = settings.config(for: plugin.id)
            if plugin.id == "REDDIT", !settings.redditSubreddits.isEmpty {
                config.extraParam = settings.redditSubreddits.randomElement() ?? config.extraParam
            }

            let effectiveQuery = plugin.supportsSearch
                ? collectionFetchQuery(for: plugin.id, rawTags: trimmedTags, matchAny: request.matchAny)
                : ""
            let effectiveNsfw = request.nsfwOverride ?? config.nsfwOverride ?? settings.nsfwEnabled

            for page in 0..<maxPages {
                if added >= request.count { break }
                fillProgressMessage = "Fetching \(plugin.displayName)…"

                let fetched: [WallpaperItem]
                do {
                    fetched = try await plugin.fetch(
                        query: effectiveQuery,
                        page: page,
                        config: config,
                        nsfw: effectiveNsfw
                    )
                } catch {
                    break
                }

                if fetched.isEmpty {
                    break
                }

                for item in fetched where request.minResolution.matches(item) {
                    if added >= request.count { break }
                    if request.useMalFilter,
                       !matchesMalFilter(item, normalizedMalTitles: normalizedMalTitles) {
                        continue
                    }

                    let dedupeKey = item.id.isEmpty ? item.imageURL.absoluteString : item.id
                    guard !existingKeys.contains(dedupeKey) else { continue }

                    let entry = SavedEntry(collectionId: collection.id, from: item)
                    modelContext.insert(entry)
                    existingKeys.insert(entry.dedupeKey)
                    firstAddedThumbnail = firstAddedThumbnail ?? entry.thumbnailURLString
                    added += 1
                }
            }
        }

        try? modelContext.save()
        showToast(
            added > 0
                ? "Added \(added) image\(added == 1 ? "" : "s") to \"\(collection.name)\""
                : "No new images found — try different tags or sources"
        )
    }

    private func matchesMalFilter(_ item: WallpaperItem, normalizedMalTitles: Set<String>) -> Bool {
        guard !normalizedMalTitles.isEmpty else { return false }
        let normalizedTags = item.tags.map(normalizeCollectionMatchToken)
        return normalizedTags.contains { tag in
            normalizedMalTitles.contains { title in
                tag == title || tag.contains(title)
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard toastMessage == message else { return }
            withAnimation { toastMessage = nil }
        }
    }
}

private func collectionFetchQuery(for pluginId: String, rawTags: String, matchAny: Bool) -> String {
    let tokens = normalizeBooruQuery(rawTags)
        .split(separator: " ")
        .map(String.init)
        .filter { !$0.isEmpty }

    guard !tokens.isEmpty else { return "" }
    guard matchAny, tokens.count > 1 else { return tokens.joined(separator: " ") }

    switch pluginId {
    case "DANBOORU", "SAFEBOORU":
        return tokens.map { "~\($0)" }.joined(separator: " ")
    case "GELBOORU", "RULE34", "YANDERE", "KONACHAN":
        return "( \(tokens.joined(separator: " ~ ")) )"
    default:
        return tokens.first ?? ""
    }
}

private func normalizeCollectionMatchToken(_ raw: String) -> String {
    raw.lowercased()
        .replacingOccurrences(of: "&", with: "and")
        .replacingOccurrences(of: "-", with: "_")
        .replacingOccurrences(of: " ", with: "_")
        .components(separatedBy: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "_")))
        .joined()
        .replacingOccurrences(of: "__", with: "_")
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
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

            let stars = settings.rating(for: entry.originalItemId.isEmpty ? entry.id.uuidString : entry.originalItemId)
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
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
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
