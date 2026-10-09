import RotatoKit
import SwiftUI

/// First run: welcome, pick starting sources, and a word on how rotation works on iPhone.
public struct SetupScreen: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var nsfw = false
    @State private var picked: Set<String> = SetupScreen.defaultSources

    /// Safe sources that work without an account.
    static let defaultSources: Set<String> = ["SAFEBOORU", "KONACHAN", "ZEROCHAN", "WALLHAVEN"]

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 0: welcome
                case 1: sources
                default: rotation
                }
            }
            .animation(.default, value: step)
        }
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 88))
                .foregroundStyle(.tint)
            VStack(spacing: 10) {
                Text("Rotato").font(.largeTitle.bold())
                Text("Discover, collect and rotate wallpapers.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 18) {
                feature("sparkles", "Discover", "Swipe a feed from the sources you pick. It learns what you like.")
                feature("bookmark", "Collections", "Save to several collections, build smart ones from tags, lock private ones.")
                feature("arrow.triangle.2.circlepath", "Rotation", "A Shortcuts automation changes your wallpaper on your schedule.")
            }
            .padding(.horizontal, 8)
            Spacer()
            primaryButton("Get started") { step = 1 }
        }
        .padding(24)
    }

    private var sources: some View {
        List {
            Section {
                ForEach(visibleSources) { m in
                    Toggle(isOn: binding(m.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.name)
                            Text(m.description).font(.caption).foregroundStyle(.secondary)
                            if m.requiresCredentials {
                                Label("Needs an API key, add it later in Settings", systemImage: "key")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            } header: {
                Text("Where should wallpapers come from?")
            } footer: {
                Text("You can change sources, add API keys and install more from the plugin store in Settings.")
            }
            Section {
                Toggle("Show adult sources", isOn: $nsfw)
            } footer: {
                Text("Adult sources only load when NSFW mode is on in Settings.")
            }
        }
        .groupedList()
        .navigationTitle("Sources")
        .safeAreaInset(edge: .bottom) {
            primaryButton(picked.isEmpty ? "Pick at least one" : "Continue") { step = 2 }
                .disabled(picked.isEmpty)
                .padding()
                .background(.bar)
        }
    }

    private var rotation: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "square.2.layers.3d.top.filled")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("How rotation works").font(.title.bold())
            Text("iPhone apps can't change the wallpaper on their own. Rotato prepares each wallpaper, and a short shortcut you make in the Shortcuts app sets it, on a schedule you choose.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("You'll find step-by-step setup under Settings → Shortcuts Setup. It takes about a minute.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            primaryButton("Start discovering") {
                model.completeSetup(enable: picked)
            }
        }
        .padding(24)
    }

    private var visibleSources: [PluginManifest] {
        // Reddit needs a subreddit first, so it is added from Settings → Sources.
        PluginCatalog.bundled.filter { (nsfw || !$0.adultOnly) && !$0.isMultiInstance }
    }

    private func binding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { picked.contains(id) },
            set: { on in if on { picked.insert(id) } else { picked.remove(id) } }
        )
    }

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(.tint).frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}
