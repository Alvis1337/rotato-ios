import RotatoKit
import SwiftUI

/// Browse plugin stores (the official index plus any added ones) and install sources.
public struct PluginStoreScreen: View {
    @Environment(AppModel.self) private var model
    @State private var stores: [(url: String, result: StoreResult)] = []
    @State private var loading = false
    @State private var busy: Set<String> = []
    @State private var addingStore = false
    @State private var installingURL = false
    @State private var input = ""

    public init() {}

    public var body: some View {
        List {
            if loading && stores.isEmpty {
                HStack { Spacer(); ProgressView("Loading stores…"); Spacer() }
            }
            ForEach(stores, id: \.url) { store in
                switch store.result {
                case .success(let name, let entries):
                    Section {
                        let shown = entries.filter { !model.settings.nsfwHidden || $0.safeContent }
                        if shown.isEmpty { Text("Nothing here yet").foregroundStyle(.secondary) }
                        ForEach(shown) { e in entryRow(e, updates: model.catalog.updatesAvailable(in: entries)) }
                    } header: {
                        storeHeader(name, url: store.url)
                    }
                case .failure(let name, let error):
                    Section {
                        Label(error, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
                    } header: {
                        storeHeader(name, url: store.url)
                    }
                }
            }
        }
        .groupedList()
        .navigationTitle("Plugin Store")
        .inlineTitle()
        .refreshable { await load() }
        .task { if stores.isEmpty { await load() } }
        .toolbar {
            ToolbarItem(placement: .trailingBar) {
                Menu {
                    Button { input = ""; addingStore = true } label: { Label("Add a store", systemImage: "plus.rectangle.on.folder") }
                    Button { input = ""; installingURL = true } label: { Label("Install from URL", systemImage: "link") }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Add a plugin store", isPresented: $addingStore) {
            TextField("https://…/index.json", text: $input).urlKeyboard()
            Button("Add") { Task { await addStore() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The URL of a Rotato plugin index.")
        }
        .alert("Install a plugin", isPresented: $installingURL) {
            TextField("https://…/plugin.json", text: $input).urlKeyboard()
            Button("Install") { Task { await install(url: input, id: input) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The URL of a plugin manifest.")
        }
    }

    private func storeHeader(_ name: String, url: String) -> some View {
        HStack {
            Text(name)
            Spacer()
            if url != PluginCatalog.storeIndexURL {
                Button("Remove") {
                    model.catalog.removeCustomStore(url)
                    stores.removeAll { $0.url == url }
                }
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ e: PluginStoreEntry, updates: Set<String>) -> some View {
        let installed = model.plugins.contains { $0.id == e.id }
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(e.name).font(.headline)
                    PluginBadges(safe: e.safeContent, adult: !e.safeContent && e.tags.contains("nsfw"))
                }
                Text(e.description).font(.subheadline).foregroundStyle(.secondary)
                Text("\(e.author) · v\(e.version)").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            if busy.contains(e.id) {
                ProgressView()
            } else if updates.contains(e.id) {
                Button("Update") { Task { await install(url: e.manifestUrl, id: e.id, bundled: e.isBundled) } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            } else if installed {
                Text("Installed").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Get") { Task { await install(url: e.manifestUrl, id: e.id, bundled: e.isBundled) } }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        loading = true
        stores = await model.catalog.fetchAllStores()
        loading = false
    }

    private func install(url: String, id: String, bundled: Bool = false) async {
        busy.insert(id)
        defer { busy.remove(id) }
        do {
            let m = try await model.catalog.install(fromURL: url.trimmingCharacters(in: .whitespacesAndNewlines))
            model.reload()
            model.showToast("Installed \(m.name). Turn it on in Sources.")
        } catch {
            // Built-in plugins install offline when the network copy can't be fetched.
            if bundled, PluginCatalog.bundled.contains(where: { $0.id == id }) {
                model.catalog.installBundled(id)
                model.reload()
                model.showToast("Installed")
            } else {
                model.showToast(error.localizedDescription)
            }
        }
    }

    private func addStore() async {
        do {
            let name = try await model.catalog.addCustomStore(input)
            model.showToast("Added \(name)")
            await load()
        } catch {
            model.showToast(error.localizedDescription)
        }
    }
}
