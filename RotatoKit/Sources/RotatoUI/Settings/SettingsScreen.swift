import RotatoKit
import SwiftUI

/// Settings, grouped as on Android: rotation & wallpaper, content & privacy, Discover & sources,
/// and about & data. Android-only options (interval, live wallpaper, tiles, foldables) are gone;
/// the schedule lives in the user's Shortcuts automation.
public struct SettingsScreen: View {
    @Environment(AppModel.self) private var model

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ShortcutsSetupView()
                    } label: {
                        row("Shortcuts Setup", "Make rotation automatic", "arrow.triangle.2.circlepath", .orange)
                    }
                }
                Section {
                    NavigationLink { RotationSettingsView() } label: {
                        row("Rotation & Wallpaper", "Order, framing, effects, night pause", "photo.on.rectangle", .blue)
                    }
                    NavigationLink { ContentSettingsView() } label: {
                        row("Content & Privacy", "NSFW, content filter, blocked tags", "eye.slash", .red)
                    }
                    NavigationLink { DiscoverSettingsView() } label: {
                        row("Discover", "Filters, For you, data saver", "sparkles", .purple)
                    }
                    NavigationLink { SourcesScreen() } label: {
                        row("Sources", "\(model.enabledSources.count) enabled", "server.rack", .green)
                    }
                    NavigationLink { PluginStoreScreen() } label: {
                        row("Plugin Store", "Install more sources", "shippingbox", .teal)
                    }
                }
                Section {
                    NavigationLink { AboutDataView() } label: {
                        row("About & Data", "Backup, cache, licences", "info.circle", .gray)
                    }
                }
            }
            .groupedList()
            .navigationTitle("Settings")
        }
    }

    private func row(_ title: String, _ subtitle: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// A Binding into one settings field, written through the model.
@MainActor
func settingBinding<T>(_ model: AppModel, _ keyPath: WritableKeyPath<RotatoSettings, T>) -> Binding<T> {
    Binding(
        get: { model.settings[keyPath: keyPath] },
        set: { v in model.updateSettings { $0[keyPath: keyPath] = v } }
    )
}

// MARK: - Rotation & wallpaper

struct RotationSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Picker("Order", selection: settingBinding(model, \.shuffleMode)) {
                    Text("Shuffle").tag(true)
                    Text("In order").tag(false)
                }
                Toggle("Match time of day", isOn: settingBinding(model, \.matchTimeOfDay))
            } header: {
                Text("Order")
            } footer: {
                Text("Shuffle favours higher-rated wallpapers and never repeats the one showing. Match time of day picks darker images from 8 pm to 7 am and brighter ones in the day.")
            }

            Section {
                Picker("Framing", selection: settingBinding(model, \.wallpaperFit)) {
                    ForEach(WallpaperFit.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Framing")
            } footer: {
                Text("Smart fill crops around the subject and keeps it clear of the lock screen clock.")
            }

            Section {
                Picker("Blur", selection: settingBinding(model, \.wallpaperEffects.blur)) {
                    Text("Off").tag(0)
                    Text("Soft").tag(1)
                    Text("Strong").tag(2)
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading) {
                    Text("Dim \(model.settings.wallpaperEffects.dimPercent)%")
                    Slider(
                        value: Binding(
                            get: { Double(model.settings.wallpaperEffects.dimPercent) },
                            set: { v in model.updateSettings { $0.wallpaperEffects.dimPercent = Int(v) } }
                        ),
                        in: 0...60, step: 5
                    )
                }
                Toggle("Also on lock screen", isOn: settingBinding(model, \.wallpaperEffects.onLockScreen))
            } header: {
                Text("Home screen effects")
            } footer: {
                Text("Keeps icons and widgets readable over busy art.")
            }

            Section {
                Toggle("Pause at night", isOn: settingBinding(model, \.autoPause.nightEnabled))
                if model.settings.autoPause.nightEnabled {
                    Picker("From", selection: settingBinding(model, \.autoPause.nightStartHour)) {
                        ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                    }
                    Picker("Until", selection: settingBinding(model, \.autoPause.nightEndHour)) {
                        ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                    }
                }
            } header: {
                Text("Auto-pause")
            } footer: {
                Text("Your automation still runs, but keeps the current wallpaper during these hours.")
            }
        }
        .navigationTitle("Rotation & Wallpaper")
        .inlineTitle()
    }

    private func hourLabel(_ h: Int) -> String {
        var c = DateComponents()
        c.hour = h
        let date = Calendar.current.date(from: c) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Content & privacy

struct ContentSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var newTag = ""

    var body: some View {
        Form {
            Section {
                Toggle("Content filter", isOn: settingBinding(model, \.nsfwHidden))
            } footer: {
                Text("Hides every NSFW feature, NSFW images and locked collections until you turn it off. Your other settings are kept.")
            }

            if !model.settings.nsfwHidden {
                Section {
                    Toggle("NSFW mode", isOn: settingBinding(model, \.nsfwMode))
                    Toggle("Blur NSFW images", isOn: settingBinding(model, \.nsfwBlurEnabled))
                    Toggle("Keep NSFW off the lock screen", isOn: settingBinding(model, \.nsfwHomeOnly))
                } header: {
                    Text("NSFW")
                } footer: {
                    Text("NSFW mode asks sources for explicit posts only. Sources can opt out individually in Sources. Blurred images show when tapped.")
                }
            }

            Section {
                ForEach(model.settings.globalBlacklist, id: \.self) { tag in
                    Text(tag)
                }
                .onDelete { idx in
                    model.updateSettings { $0.globalBlacklist.remove(atOffsets: idx) }
                }
                HStack {
                    TextField("Add a tag", text: $newTag)
                        .plainTextEntry()
                        .onSubmit(addTag)
                    Button("Add", action: addTag).disabled(newTag.isBlank)
                }
            } header: {
                Text("Blocked tags")
            } footer: {
                Text("Wallpapers with these tags never show in Discover or get added by fills.")
            }

            Section {
                LabeledContent("Blocked images", value: "\(model.state.blockedUrls.count)")
                Button("Unblock all images", role: .destructive) {
                    model.updateState { $0.blockedUrls = [] }
                }
                .disabled(model.state.blockedUrls.isEmpty)
            }
        }
        .navigationTitle("Content & Privacy")
        .inlineTitle()
    }

    private func addTag() {
        let tag = normalizeTag(newTag)
        guard !tag.isEmpty else { return }
        model.updateSettings { if !$0.globalBlacklist.contains(tag) { $0.globalBlacklist.append(tag) } }
        newTag = ""
    }
}

// MARK: - Discover

struct DiscoverSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                Picker("Minimum resolution", selection: settingBinding(model, \.filters.minResolution)) {
                    ForEach(MinResolution.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Aspect ratio", selection: settingBinding(model, \.filters.aspectRatio)) {
                    ForEach(AspectRatio.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Filters")
            } footer: {
                Text("\"My Phone\" matches this iPhone's screen (\(model.settings.filters.phoneScreenWidth)×\(model.settings.filters.phoneScreenHeight)).")
            }

            Section {
                Toggle("For you", isOn: settingBinding(model, \.forYouEnabled))
                Button("Reset what Discover learned", role: .destructive) {
                    model.updateState { $0.learnedWeights = [:] }
                    model.showToast("Learned taste reset")
                }
                .disabled(model.state.learnedWeights.isEmpty)
            } header: {
                Text("For you")
            } footer: {
                Text("Discover learns from what you save, set, skip and block, and ranks the feed toward your taste. Everything stays on this iPhone.")
            }

            Section {
                Stepper("Load \(model.settings.discoverBatchSize) at a time", value: settingBinding(model, \.discoverBatchSize), in: 10...60, step: 10)
                Toggle("Data saver", isOn: settingBinding(model, \.discoverDataSaver))
                Picker("Video previews", selection: settingBinding(model, \.videoPreviewMode)) {
                    ForEach(VideoPreviewMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Feed")
            } footer: {
                Text(model.settings.videoPreviewMode.description + ". Data saver loads smaller previews.")
            }

            Section {
                LabeledContent("Seen wallpapers", value: "\(model.state.seenKeys.count)")
                Button("Show seen wallpapers again") {
                    model.updateState { $0.seenKeys = [] }
                    model.showToast("Seen history cleared")
                }
                .disabled(model.state.seenKeys.isEmpty)
            } footer: {
                Text("Discover skips wallpapers you've already scrolled past.")
            }
        }
        .navigationTitle("Discover")
        .inlineTitle()
    }
}

// MARK: - About & data

struct AboutDataView: View {
    @Environment(AppModel.self) private var model
    @State private var exportURL: URL?
    @State private var importing = false
    @State private var confirmClearLibrary = false

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: settingBinding(model, \.themeMode)) {
                    ForEach(ThemeMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }

            Section {
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Share backup file", systemImage: "square.and.arrow.up") }
                } else {
                    Button { exportURL = try? BackupService.export(db: model.db) } label: {
                        Label("Make a backup", systemImage: "archivebox")
                    }
                }
                Button { importing = true } label: { Label("Restore a backup", systemImage: "arrow.down.doc") }
            } header: {
                Text("Backup")
            } footer: {
                Text("Settings, sources (including API keys), collections and their wallpapers. Library photos aren't included.")
            }

            Section("Storage") {
                LabeledContent("Library", value: "\(model.poolFiles.count) wallpapers")
                Button("Clear image cache") {
                    ImagePipeline.clearDiskCache()
                    model.showToast("Image cache cleared")
                }
                Button("Remove everything from the Library", role: .destructive) { confirmClearLibrary = true }
                    .disabled(model.poolFiles.isEmpty)
                if !RotatoPaths.usesAppGroup {
                    Label("App Group unavailable: the widget can't see your wallpapers with this signing setup.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                Link("Source code", destination: URL(string: "https://github.com/Alvis1337/rotato")!)
                Link("Privacy policy", destination: URL(string: "https://github.com/Alvis1337/rotato/blob/main/docs/privacy/index.html")!)
                Link("Terms", destination: URL(string: "https://github.com/Alvis1337/rotato/blob/main/docs/terms/index.html")!)
            }
        }
        .navigationTitle("About & Data")
        .inlineTitle()
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let summary = try BackupService.restore(from: url, db: model.db)
                model.afterCollectionsChange()
                model.showToast(summary)
            } catch {
                model.showToast("That isn't a Rotato backup")
            }
        }
        .confirmationDialog("Remove all \(model.poolFiles.count) wallpapers from the Library?", isPresented: $confirmClearLibrary, titleVisibility: .visible) {
            Button("Remove all", role: .destructive) { model.removeFromPool(model.poolFiles) }
        } message: {
            Text("Collections keep their wallpapers; rotation collections download them again.")
        }
    }
}
