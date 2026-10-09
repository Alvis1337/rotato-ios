import RotatoKit
import SwiftUI

/// Installed sources and their settings (LocalSourcesScreen on Android).
public struct SourcesScreen: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        List {
            Section {
                ForEach(visiblePlugins) { m in
                    NavigationLink {
                        SourceDetailView(pluginId: m.id)
                    } label: {
                        SourceRow(manifest: m)
                    }
                }
            } footer: {
                Text("Discover mixes posts from every enabled source.")
            }

            let missing = model.catalog.missingBundled.filter { !model.settings.nsfwHidden || !$0.adultOnly }
            if !missing.isEmpty {
                Section("Built-in, not installed") {
                    ForEach(missing) { m in
                        Button {
                            model.catalog.installBundled(m.id)
                            model.reload()
                        } label: {
                            Label("Reinstall \(m.name)", systemImage: "arrow.down.circle")
                        }
                    }
                }
            }

            Section {
                NavigationLink { PluginStoreScreen() } label: {
                    Label("Get more sources", systemImage: "shippingbox")
                }
            }
        }
        .groupedList()
        .navigationTitle("Sources")
        .inlineTitle()
    }

    private var visiblePlugins: [PluginManifest] {
        model.plugins
            .filter { !model.settings.nsfwHidden || !$0.adultOnly }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct SourceRow: View {
    @Environment(AppModel.self) private var model
    let manifest: PluginManifest

    var body: some View {
        let rows = model.sources.filter { $0.pluginId == manifest.id }
        let enabled = rows.contains(where: \.enabled)
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(manifest.name)
                HStack(spacing: 6) {
                    if manifest.isMultiInstance {
                        Text(rows.isEmpty ? "No subreddits" : rows.map { "r/\($0.instanceId)" }.joined(separator: ", "))
                    } else {
                        Text(enabled ? "On" : "Off")
                    }
                    if missingCredentials(rows) {
                        Label("Needs API key", systemImage: "key.fill").foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            PluginBadges(safe: manifest.safeContent, adult: manifest.adultOnly, needsKey: manifest.requiresCredentials)
        }
    }

    private func missingCredentials(_ rows: [SourceConfig]) -> Bool {
        guard manifest.requiresCredentials, let r = rows.first else { return false }
        return r.apiKey.isBlank || (manifest.needsApiUser && r.apiUser.isBlank)
    }
}

/// Small capsules: SFW / NSFW / key.
struct PluginBadges: View {
    let safe: Bool
    var adult = false
    var needsKey = false

    var body: some View {
        HStack(spacing: 4) {
            if adult { badge("18+", .red) } else if safe { badge("SFW", .green) } else { badge("Mixed", .indigo) }
            if needsKey { badge("Key", .orange) }
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

/// One plugin's settings: enable, credentials, overrides, subreddits.
struct SourceDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pluginId: String
    @State private var newSubreddit = ""
    @State private var confirmUninstall = false

    var body: some View {
        if let m = model.plugins.first(where: { $0.id == pluginId }) {
            Form {
                Section {
                    Text(m.description).font(.subheadline).foregroundStyle(.secondary)
                    LabeledContent("By", value: m.author)
                    LabeledContent("Version", value: m.version)
                    if m.maxTagCount != Int.max {
                        LabeledContent("Tags per search", value: "\(m.maxTagCount)")
                    }
                } footer: {
                    if m.maxTagCount != Int.max {
                        Text("Searches with more tags than this skip \(m.name).")
                    }
                }

                if m.isMultiInstance {
                    subredditSection(m)
                } else if let source = row {
                    settings(m, source)
                }

                Section {
                    Button("Uninstall \(m.name)", role: .destructive) { confirmUninstall = true }
                }
            }
            .navigationTitle(m.name)
            .inlineTitle()
            .onAppear { model.sourcesRepo.ensureRows(for: [m.id]); model.reload() }
            .confirmationDialog("Uninstall \(m.name)?", isPresented: $confirmUninstall, titleVisibility: .visible) {
                Button("Uninstall", role: .destructive) {
                    model.catalog.uninstall(m.id)
                    model.reload()
                    dismiss()
                }
            } message: {
                Text("Its settings and API keys are removed. Saved wallpapers stay in your collections.")
            }
        }
    }

    private var row: SourceConfig? { model.sources.first { $0.pluginId == pluginId && $0.instanceId.isEmpty } }

    @ViewBuilder
    private func settings(_ m: PluginManifest, _ s: SourceConfig) -> some View {
        Section {
            Toggle("Enabled", isOn: Binding(get: { s.enabled }, set: { v in model.modifySource(s) { $0.enabled = v } }))
            if !model.settings.nsfwHidden && !m.safeContent {
                Toggle("Allow NSFW from this source", isOn: Binding(
                    get: { s.nsfwEnabled != false },
                    set: { v in model.modifySource(s) { $0.nsfwEnabled = v ? nil : false } }
                ))
            }
        } footer: {
            if !m.safeContent && !model.settings.nsfwHidden {
                Text("NSFW mode is a ceiling: this can keep the source safe while NSFW mode is on, never the reverse.")
            }
        }

        if m.needsApiKey {
            Section {
                if m.needsApiUser {
                    FieldRow(title: m.apiUserLabel, value: s.apiUser, secure: false) { v in model.modifySource(s) { $0.apiUser = v } }
                }
                FieldRow(title: m.apiKeyLabel, value: s.apiKey, secure: true) { v in model.modifySource(s) { $0.apiKey = v } }
            } header: {
                Text("Account")
            } footer: {
                Text(m.requiresCredentials ? "\(m.name) only works with an API key." : "Optional. An account can unlock more results.")
            }
        }

        if m.protocol == .WALLHAVEN {
            Section {
                purityToggle(s, index: 0, "General")
                purityToggle(s, index: 1, "Sketchy")
            } header: {
                Text("Wallhaven content")
            } footer: {
                Text("NSFW posts follow NSFW mode and need an API key.")
            }
        }

        if m.instanceUrlConfigurable {
            Section("Server") {
                FieldRow(title: "Base URL", value: s.baseUrl, placeholder: m.defaultBaseUrl, secure: false, url: true) { v in
                    model.modifySource(s) { $0.baseUrl = v }
                }
            }
        }

        if !m.configFields.isEmpty {
            Section("Options") {
                ForEach(m.configFields, id: \.key) { f in
                    if f.type == .TOGGLE {
                        Toggle(f.label, isOn: Binding(
                            get: { s.extraConfig[f.key] == "true" },
                            set: { v in model.modifySource(s) { $0.extraConfig[f.key] = v ? "true" : "false" } }
                        ))
                    } else {
                        FieldRow(title: f.label, value: s.extraConfig[f.key] ?? "", placeholder: f.placeholder, secure: f.type == .PASSWORD, url: f.type == .URL) { v in
                            model.modifySource(s) { $0.extraConfig[f.key] = v }
                        }
                    }
                }
            }
        }
    }

    private func purityToggle(_ s: SourceConfig, index: Int, _ label: String) -> some View {
        let bits = Array(s.wallhavenPurity.count == 3 ? s.wallhavenPurity : "110")
        return Toggle(label, isOn: Binding(
            get: { bits[index] == "1" },
            set: { on in
                var b = bits
                b[index] = on ? "1" : "0"
                model.modifySource(s) { $0.wallhavenPurity = String(b) }
            }
        ))
    }

    @ViewBuilder
    private func subredditSection(_ m: PluginManifest) -> some View {
        let rows = model.sources.filter { $0.pluginId == m.id && !$0.instanceId.isEmpty }
        Section {
            ForEach(rows) { s in
                Toggle("r/\(s.instanceId)", isOn: Binding(get: { s.enabled }, set: { v in model.modifySource(s) { $0.enabled = v } }))
            }
            .onDelete { idx in
                for i in idx { model.sourcesRepo.removeInstance(pluginId: m.id, instanceId: rows[i].instanceId) }
                model.reload()
            }
            HStack {
                Text("r/").foregroundStyle(.secondary)
                TextField("subreddit", text: $newSubreddit)
                    .plainTextEntry()
                    .onSubmit { addSubreddit(m) }
                Button("Add") { addSubreddit(m) }.disabled(newSubreddit.isBlank)
            }
        } header: {
            Text("Subreddits")
        } footer: {
            Text("Top image posts of the month from each subreddit. Try Animewallpaper, iWallpaper or Amoledbackgrounds.")
        }
    }

    private func addSubreddit(_ m: PluginManifest) {
        var name = newSubreddit.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasPrefix("r/") { name = String(name.dropFirst(2)) }
        guard !name.isEmpty else { return }
        model.sourcesRepo.addInstance(pluginId: m.id, instanceId: name)
        model.reload()
        newSubreddit = ""
    }
}

/// A text field that saves when editing ends.
struct FieldRow: View {
    let title: String
    let value: String
    var placeholder = ""
    let secure: Bool
    var url = false
    let save: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(title) {
            Group {
                if secure {
                    SecureField(placeholder.isEmpty ? "Required" : placeholder, text: $text)
                } else if url {
                    TextField(placeholder, text: $text).urlKeyboard()
                } else {
                    TextField(placeholder.isEmpty ? title : placeholder, text: $text).plainTextEntry()
                }
            }
            .multilineTextAlignment(.trailing)
            .focused($focused)
            .onSubmit { commit() }
        }
        .onAppear { text = value }
        .onChange(of: focused) { _, f in if !f { commit() } }
        .onDisappear { commit() }
    }

    private func commit() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t != value { save(t) }
    }
}
