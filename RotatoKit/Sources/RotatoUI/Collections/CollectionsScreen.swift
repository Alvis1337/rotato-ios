import RotatoKit
import SwiftUI

/// All collections as cards (BrowseScreen on Android). Collections without a cover show a
/// mosaic of their newest images.
public struct CollectionsScreen: View {
    @Environment(AppModel.self) private var model
    var onSearchDiscover: (String) -> Void
    @State private var creating = false
    @State private var search = ""
    @State private var renaming: WallpaperCollection?
    @State private var merging: WallpaperCollection?
    @State private var deleting: WallpaperCollection?
    @State private var editingSettings: WallpaperCollection?

    public init(onSearchDiscover: @escaping (String) -> Void = { _ in }) {
        self.onSearchDiscover = onSearchDiscover
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                if model.lockedHiddenCount > 0 && !model.settings.nsfwHidden { lockedBanner }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3), spacing: 12) {
                    ForEach(shown) { list in
                        CollectionCard(collection: list) { menu(for: list) }
                            .contextMenu { menu(for: list) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }
            .overlay {
                if model.visibleCollections.isEmpty {
                    ContentUnavailableView {
                        Label("No collections yet", systemImage: "bookmark")
                    } description: {
                        Text("Save wallpapers from Discover, or make a collection to fill from your sources.")
                    } actions: {
                        Button("New collection") { creating = true }.buttonStyle(.borderedProminent)
                    }
                } else if shown.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .searchable(text: $search, prompt: "Collections")
            .navigationTitle("Collections")
            .navigationDestination(for: String.self) { id in
                CollectionDetailView(collectionId: id, onSearchDiscover: onSearchDiscover)
            }
            .toolbar {
                ToolbarItem(placement: .trailingBar) {
                    Button { creating = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $creating) { NewCollectionSheet() }
            .sheet(item: $editingSettings) { c in CollectionSettingsSheet(collectionId: c.id) }
            .sheet(item: $merging) { c in
                CollectionPicker(title: "Merge \"\(c.name)\" into…", excluding: [c.id]) { target in
                    let moved = model.collectionsRepo.merge(c.id, into: target.id)
                    model.afterCollectionsChange()
                    model.showToast("Merged \(moved) into \(target.name)")
                }
            }
            .alert("Rename collection", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                RenameField(initial: renaming?.name ?? "") { name in
                    if let c = renaming, !model.collectionsRepo.rename(c.id, to: name) {
                        model.showToast("That name is taken")
                    }
                    model.reload()
                    renaming = nil
                }
            }
            .confirmationDialog(
                "Delete \"\(deleting?.name ?? "")\"?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let c = deleting { model.deleteCollection(c.id) }
                    deleting = nil
                }
            } message: {
                Text("Its \(deleting.map { model.entries(in: $0.id).count } ?? 0) wallpapers are removed from the collection.")
            }
        }
    }

    private var shown: [WallpaperCollection] {
        let all = model.visibleCollections
        guard !search.isBlank else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var lockedBanner: some View {
        Button {
            Task { _ = await model.unlockLocked() }
        } label: {
            Label("\(model.lockedHiddenCount) locked collection\(model.lockedHiddenCount == 1 ? "" : "s") hidden. Tap to unlock.", systemImage: "lock.fill")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding([.horizontal, .top])
    }

    @ViewBuilder
    private func menu(for list: WallpaperCollection) -> some View {
        Button {
            model.modifyCollection(list.id) { $0.useAsRotation.toggle() }
            model.showToast(list.useAsRotation ? "Removed from rotation" : "Added to rotation")
        } label: {
            Label(list.useAsRotation ? "Stop rotating" : "Use for rotation", systemImage: "arrow.triangle.2.circlepath")
        }
        Button { editingSettings = list } label: { Label("Settings", systemImage: "slider.horizontal.3") }
        Button { renaming = list } label: { Label("Rename", systemImage: "pencil") }
        Menu {
            Button { model.collectionsRepo.move(list.id, by: -1); model.reload() } label: { Label("Earlier", systemImage: "arrow.left") }
            Button { model.collectionsRepo.move(list.id, by: 1); model.reload() } label: { Label("Later", systemImage: "arrow.right") }
        } label: {
            Label("Move", systemImage: "arrow.left.arrow.right")
        }
        Button { merging = list } label: { Label("Merge into…", systemImage: "arrow.triangle.merge") }
            .disabled(model.visibleCollections.count < 2)
        Divider()
        Button(role: .destructive) { deleting = list } label: { Label("Delete", systemImage: "trash") }
    }
}

/// A collection's cover with its name, count and rotation link underneath, plus a rotation
/// toggle and a menu (CollectionCard on Android).
struct CollectionCard<Menu: View>: View {
    @Environment(AppModel.self) private var model
    let collection: WallpaperCollection
    @ViewBuilder var menuItems: () -> Menu

    var body: some View {
        let entries = model.entries(in: collection.id)
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: collection.id) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { cover(entries) }
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 4) {
                            if collection.isSmartCollection { badge("wand.and.stars") }
                            if collection.isLocked { badge("lock.fill") }
                        }
                        .padding(5)
                    }
            }
            .buttonStyle(.plain)
            HStack(alignment: .top, spacing: 2) {
                NavigationLink(value: collection.id) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(collection.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("\(entries.count) image\(entries.count == 1 ? "" : "s")").font(.caption2).foregroundStyle(.secondary)
                        if collection.useAsRotation {
                            Text("Linked to Library").font(.caption2).foregroundStyle(Color.rotatoAccent)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Button {
                    model.modifyCollection(collection.id) { $0.useAsRotation.toggle() }
                    model.showToast(collection.useAsRotation ? "Unlinked from Library" : "Linked to Library")
                } label: {
                    Image(systemName: collection.useAsRotation ? "photo.on.rectangle.angled.fill" : "photo.on.rectangle.angled")
                        .font(.system(size: 13))
                        .foregroundStyle(collection.useAsRotation ? Color.rotatoAccent : .secondary)
                        .frame(width: 24, height: 26)
                }
                .buttonStyle(.plain)
                SwiftUI.Menu { menuItems() } label: {
                    Image(systemName: "ellipsis").rotationEffect(.degrees(90))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 26)
                }
                .dockMenuStyle()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func cover(_ entries: [CollectionEntry]) -> some View {
        if !collection.coverUrl.isBlank {
            RemoteImage(collection.coverUrl, maxPixel: 500)
                .nsfwBlur(entries.first { $0.thumbUrl == collection.coverUrl || $0.fullUrl == collection.coverUrl }?.isNsfw ?? false, exempt: collection.blurExempt)
        } else if entries.isEmpty {
            Rectangle().fill(.quaternary)
                .overlay(Image(systemName: collection.isSmartCollection ? "wand.and.stars" : "photo.stack").font(.largeTitle).foregroundStyle(.secondary))
        } else {
            let newest = Array(entries.prefix(4))
            if newest.count < 4 {
                tile(newest[0])
            } else {
                Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                    GridRow { tile(newest[0]); tile(newest[1]) }
                    GridRow { tile(newest[2]); tile(newest[3]) }
                }
            }
        }
    }

    private func tile(_ e: CollectionEntry) -> some View {
        Color.clear.overlay {
            RemoteImage(e.thumbUrl.ifBlank(e.sampleUrl), maxPixel: 300).nsfwBlur(e.isNsfw, exempt: collection.blurExempt)
        }
        .clipped()
    }

    private func badge(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(.black.opacity(0.45), in: Circle())
    }
}

/// Text field + buttons for a rename alert.
struct RenameField: View {
    let initial: String
    let save: (String) -> Void
    @State private var text = ""

    var body: some View {
        TextField("Name", text: $text).onAppear { text = initial }
        Button("Save") { save(text) }
        Button("Cancel", role: .cancel) {}
    }
}

/// Pick a collection (for move, copy, merge, save).
struct CollectionPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let title: String
    var excluding: Set<String> = []
    let pick: (WallpaperCollection) -> Void
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.visibleCollections.filter { !excluding.contains($0.id) }) { c in
                        Button {
                            pick(c)
                            dismiss()
                        } label: {
                            HStack {
                                Text(c.name).foregroundStyle(.primary)
                                Spacer()
                                Text("\(model.entries(in: c.id).count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("New collection") {
                    HStack {
                        TextField("Name", text: $newName)
                        Button("Create") {
                            if let c = model.createCollection(newName) {
                                pick(c)
                                dismiss()
                            }
                        }
                        .disabled(newName.isBlank)
                    }
                }
            }
            .navigationTitle(title)
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// New plain or smart collection.
struct NewCollectionSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var smart = false
    @State private var rule = SmartRule()
    @State private var rotate = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Toggle("Use for rotation", isOn: $rotate)
                } footer: {
                    Text("Rotation collections are downloaded into your Library for your shortcut to pick from.")
                }
                Section {
                    Toggle("Smart collection", isOn: $smart)
                } footer: {
                    Text("Smart collections fill themselves with saved wallpapers that match tag rules.")
                }
                if smart { RuleFields(rule: $rule) }
            }
            .navigationTitle("New Collection")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if model.createCollection(name, useAsRotation: rotate, smartRule: smart && !rule.isEmpty ? rule : nil) != nil {
                            dismiss()
                        }
                    }
                    .disabled(name.isBlank)
                }
            }
        }
    }
}

/// Require-all / any / exclude tag lists for a smart rule.
struct RuleFields: View {
    @Binding var rule: SmartRule

    var body: some View {
        Section {
            TagListField(title: "Has all of", tags: $rule.requireAll)
            TagListField(title: "Has any of", tags: $rule.requireAny)
            TagListField(title: "Has none of", tags: $rule.excludeAny)
        } header: {
            Text("Rules")
        } footer: {
            Text("Separate tags with spaces or commas. Source names (wallhaven, reddit…) count as tags.")
        }
    }
}

struct TagListField: View {
    let title: String
    @Binding var tags: [String]
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("tags", text: $text)
                .plainTextEntry()
                .onAppear { text = tags.joined(separator: " ") }
                .onChange(of: text) { _, t in
                    tags = t.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init).filter { !$0.isEmpty }
                }
        }
    }
}

/// Rotation, privacy and rule settings for one collection.
struct CollectionSettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let collectionId: String
    @State private var rule = SmartRule()

    var body: some View {
        NavigationStack {
            if let c = model.collections.first(where: { $0.id == collectionId }) {
                Form {
                    Section {
                        Toggle("Use for rotation", isOn: bind(c.useAsRotation) { $0.useAsRotation = $1 })
                        if c.useAsRotation {
                            Picker("Screens", selection: bind(c.rotationTarget) { $0.rotationTarget = $1 }) {
                                ForEach(ScreenRotationTarget.allCases, id: \.self) { Text($0.label).tag($0) }
                            }
                            Picker("At most every", selection: bind(c.rotationIntervalMinutes) { $0.rotationIntervalMinutes = $1 }) {
                                Text("Every run").tag(Int?.none)
                                ForEach([60, 180, 360, 720, 1440], id: \.self) { m in
                                    Text(m < 1440 ? "\(m / 60) hours" : "Day").tag(Int?.some(m))
                                }
                            }
                        }
                    } header: {
                        Text("Rotation")
                    } footer: {
                        Text("Home only or Lock only collections feed that screen when your shortcut gets each screen separately. A minimum gap keeps this collection from showing more often.")
                    }

                    if !model.settings.nsfwHidden {
                        Section {
                            Toggle("Lock with Face ID", isOn: bind(c.isLocked) { $0.isLocked = $1 })
                            Toggle("Don't blur NSFW here", isOn: bind(c.blurExempt) { $0.blurExempt = $1 })
                        } header: {
                            Text("Privacy")
                        } footer: {
                            Text("Locked collections are hidden until you unlock them, and never show while the content filter is on.")
                        }
                    }

                    if c.isSmartCollection {
                        RuleFields(rule: $rule)
                        Section {
                            Button("Save rules") {
                                model.modifyCollection(c.id) { $0.smartRule = rule.isEmpty ? nil : rule }
                                model.showToast("Rules saved")
                            }
                        }
                    }

                    if !c.coverUrl.isBlank {
                        Section {
                            Button("Use a mosaic cover") { model.modifyCollection(c.id) { $0.coverUrl = "" } }
                        }
                    }
                }
                .navigationTitle(c.name)
                .inlineTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onAppear { rule = c.smartRule ?? SmartRule() }
            }
        }
    }

    private func bind<T>(_ value: T, _ set: @escaping (inout WallpaperCollection, T) -> Void) -> Binding<T> {
        Binding(get: { value }, set: { v in model.modifyCollection(collectionId) { set(&$0, v) } })
    }
}
