import SwiftUI

struct SourceSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var showAddRedditAlert = false
    @State private var newSubreddit = ""

    var body: some View {
        Form {
            Section {
                Text("Enable the sources you want wallpapers from. Some sources require API keys for full access or higher rate limits.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Image Boards") {
                ForEach(imageBoardPlugins, id: \.id) { plugin in
                    SourceRow(plugin: plugin)
                }
            }

            Section("Reddit") {
                ForEach(settings.redditSubreddits, id: \.self) { sub in
                    HStack {
                        Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(.secondary)
                        Text("r/\(sub)")
                        Spacer()
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            settings.redditSubreddits.removeAll { $0 == sub }
                        } label: { Label("Remove", systemImage: "trash") }
                    }
                }

                let redditPlugin = RedditPlugin()
                let redditEnabled = settings.config(for: redditPlugin.id).enabled
                Toggle("Reddit Enabled", isOn: Binding(
                    get: { redditEnabled },
                    set: { var c = settings.config(for: redditPlugin.id); c.enabled = $0; settings.setConfig(c, for: redditPlugin.id) }
                ))

                Button("+ Add Subreddit") { showAddRedditAlert = true }
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Add Subreddit", isPresented: $showAddRedditAlert) {
            TextField("e.g. wallpapers", text: $newSubreddit)
            Button("Add") {
                let trimmed = newSubreddit.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "r/", with: "")
                if !trimmed.isEmpty { settings.redditSubreddits.append(trimmed) }
                newSubreddit = ""
            }
            Button("Cancel", role: .cancel) { newSubreddit = "" }
        }
    }

    private var imageBoardPlugins: [any SourcePlugin] {
        PluginRegistry.all.filter { $0.id != "REDDIT" }
    }
}

private struct SourceRow: View {
    let plugin: any SourcePlugin
    @Environment(AppSettings.self) private var settings
    @State private var expanded = false

    var body: some View {
        // Explicit read so @Observable tracks sourceConfigs changes for this view
        let currentConfig = settings.config(for: plugin.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: plugin.sfSymbol).foregroundStyle(.secondary).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.displayName)
                    Text(plugin.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { currentConfig.enabled },
                    set: { var c = settings.config(for: plugin.id); c.enabled = $0; settings.setConfig(c, for: plugin.id) }
                ))
                .labelsHidden()
                Button { withAnimation { expanded.toggle() } } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider().padding(.vertical, 4)

                    ExpandedSourceFields(plugin: plugin)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: expanded)
    }
}

private struct ExpandedSourceFields: View {
    let plugin: any SourcePlugin
    @Environment(AppSettings.self) private var settings
    @State private var apiKey = ""
    @State private var apiUser = ""
    @State private var tags = ""
    @State private var purity = ""
    @State private var nsfwOverrideEnabled = false
    @State private var nsfwOverrideValue = false

    // Sources that have SFW-only content don't need a per-source NSFW override
    private var supportsNsfwOverride: Bool {
        !["SAFEBOORU"].contains(plugin.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Default Tags").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            TextField("e.g. 1girl solo highres", text: $tags)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if plugin.requiresApiKey {
                if plugin.requiresApiUser {
                    TextField("Username / User ID", text: $apiUser)
                        .textFieldStyle(.roundedBorder).font(.caption)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                SecureField("API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder).font(.caption)
            }

            if plugin.id == "WALLHAVEN" {
                HStack {
                    Text("Purity").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("SFW  Sketchy  NSFW").font(.caption2).foregroundStyle(.tertiary)
                }
                PurityToggleRow(purity: $purity)
            }

            if supportsNsfwOverride {
                Divider()
                Toggle(isOn: $nsfwOverrideEnabled) {
                    Text("Override global NSFW setting").font(.caption)
                }
                .toggleStyle(.switch)
                .onChange(of: nsfwOverrideEnabled) { _, enabled in
                    if !enabled { nsfwOverrideValue = false }
                }
                if nsfwOverrideEnabled {
                    Toggle(isOn: $nsfwOverrideValue) {
                        Text("Allow NSFW for this source").font(.caption)
                    }
                    .toggleStyle(.switch)
                }
            }

            Button("Save") {
                saveConfig()
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
        .padding(.top, 2)
        .onAppear {
            let c = settings.config(for: plugin.id)
            tags = c.tags
            apiKey = c.apiKey
            apiUser = c.apiUser
            purity = c.extraParam.isEmpty ? "100" : c.extraParam
            nsfwOverrideEnabled = c.nsfwOverride != nil
            nsfwOverrideValue = c.nsfwOverride ?? false
        }
        .onDisappear {
            saveConfig()
        }
    }

    private func saveConfig() {
        var config = settings.config(for: plugin.id)
        config.tags = tags
        config.apiKey = apiKey
        config.apiUser = apiUser
        if plugin.id == "WALLHAVEN" { config.extraParam = purity }
        config.nsfwOverride = nsfwOverrideEnabled ? nsfwOverrideValue : nil
        settings.setConfig(config, for: plugin.id)
    }
}

private struct PurityToggleRow: View {
    @Binding var purity: String

    private var sfw: Bool { purity.count > 0 && purity[purity.startIndex] == "1" }
    private var sketchy: Bool { purity.count > 1 && purity[purity.index(purity.startIndex, offsetBy: 1)] == "1" }
    private var nsfw: Bool { purity.count > 2 && purity[purity.index(purity.startIndex, offsetBy: 2)] == "1" }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("SFW", isOn: Binding(get: { sfw }, set: { v in update(sfw: v) }))
                .toggleStyle(.button).font(.caption2)
            Toggle("Sketchy", isOn: Binding(get: { sketchy }, set: { v in update(sketchy: v) }))
                .toggleStyle(.button).font(.caption2)
            Toggle("NSFW", isOn: Binding(get: { nsfw }, set: { v in update(nsfw: v) }))
                .toggleStyle(.button).font(.caption2)
        }
    }

    private func update(sfw: Bool? = nil, sketchy: Bool? = nil, nsfw: Bool? = nil) {
        let s = sfw ?? self.sfw
        let sk = sketchy ?? self.sketchy
        let n = nsfw ?? self.nsfw
        let result = "\(s ? "1" : "0")\(sk ? "1" : "0")\(n ? "1" : "0")"
        purity = result == "000" ? "100" : result
    }
}
