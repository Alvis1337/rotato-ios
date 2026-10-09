import RotatoKit
import SwiftUI

/// The floating action dock (Save, Set, Photos, Details, More), shared by the viewer and the
/// Discover feed. Long-press Save to pick collections.
struct WallpaperActionsDock: View {
    @Environment(AppModel.self) private var model
    let wallpaper: Wallpaper
    var onDetails: () -> Void
    var onPickCollections: () -> Void
    /// Extra items for the More menu (e.g. Remove from collection).
    var extra: AnyView?
    /// Discover's Skip and Block.
    var onSkip: (() -> Void)?
    var onBlock: (() -> Void)?

    var body: some View {
        let saved = model.isSaved(wallpaper)
        HStack(spacing: 4) {
            dockButton(saved ? "star.fill" : "star", saved ? "Saved" : "Save", tint: saved ? .yellow : .white) {
                Haptics.tap()
                if saved { onPickCollections() } else { model.quickSave(wallpaper) }
            }
            .simultaneousGesture(LongPressGesture().onEnded { _ in onPickCollections() })

            Menu {
                Button("Home & Lock") { set([.home, .lock]) }
                Button("Home Screen") { set([.home]) }
                Button("Lock Screen") { set([.lock]) }
            } label: {
                dockLabel("iphone", "Set", tint: .white)
            }
            .disabled(wallpaper.isVideo)
            .opacity(wallpaper.isVideo ? 0.4 : 1)

            if let onSkip {
                dockButton("forward.fill", "Skip", tint: .white, action: onSkip)
            } else {
                dockButton("square.and.arrow.down", "Photos", tint: .white) { saveToPhotos() }
            }

            dockButton("info.circle", "Details", tint: .white, action: onDetails)

            Menu {
                Button { onPickCollections() } label: { Label("Save to collections…", systemImage: "bookmark") }
                if onSkip != nil {
                    Button { saveToPhotos() } label: { Label("Save to Photos", systemImage: "square.and.arrow.down") }
                }
                if let url = URL(string: wallpaper.pageUrl), wallpaper.pageUrl.hasPrefix("http") {
                    Link(destination: url) { Label("Open source page", systemImage: "safari") }
                }
                if !wallpaper.shareLink.isEmpty {
                    Button { Pasteboard.copy(wallpaper.shareLink); model.showToast("Link copied") } label: {
                        Label("Copy link", systemImage: "link")
                    }
                }
                if let onBlock {
                    Divider()
                    Button(role: .destructive, action: onBlock) { Label("Block this image", systemImage: "hand.raised") }
                }
                if let extra { Divider(); extra }
            } label: {
                dockLabel("ellipsis", "More", tint: .white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    private func set(_ screens: Set<WallpaperScreen>) {
        Task { await model.setNow(wallpaper, screens: screens) }
    }

    private func saveToPhotos() {
        let wp = wallpaper
        Task {
            guard let data = await ImagePipeline.shared.cachedData(wp.fullUrl) else {
                model.showToast("Couldn't download it")
                return
            }
            LearnedTaste.record(wp.tags, .downloaded, db: model.db)
            model.showToast(await PhotoLibrary.save(data) ? "Saved to Photos" : "Couldn't save to Photos")
        }
    }

    private func dockButton(_ icon: String, _ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { dockLabel(icon, label, tint: tint) }
            .buttonStyle(.plain)
    }

    private func dockLabel(_ icon: String, _ label: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 19, weight: .semibold))
            Text(label).font(.caption2)
        }
        .foregroundStyle(tint)
        .frame(width: 58, height: 46)
        .contentShape(Rectangle())
    }
}

/// Toggle a wallpaper in and out of each collection, or make a new one.
struct SaveToCollectionsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let wallpaper: Wallpaper
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.visibleCollections.filter { !$0.isSmartCollection }) { c in
                        let inIt = model.savedListIds[wallpaper.key]?.contains(c.id) ?? false
                        Button {
                            model.toggle(wallpaper, in: c.id)
                        } label: {
                            HStack {
                                Image(systemName: inIt ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(inIt ? Color.accentColor : .secondary)
                                Text(c.name).foregroundStyle(.primary)
                                Spacer()
                                if c.useAsRotation {
                                    Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary).font(.caption)
                                }
                            }
                        }
                    }
                }
                Section("New collection") {
                    HStack {
                        TextField("Name", text: $newName)
                        Button("Create") {
                            if let c = model.createCollection(newName) {
                                model.save(wallpaper, to: c.id)
                                newName = ""
                            }
                        }
                        .disabled(newName.isBlank)
                    }
                }
            }
            .navigationTitle("Save to")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Source, resolution, tags (tap to search, hold to block or rank) and links.
struct WallpaperDetailsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let wallpaper: Wallpaper
    var onSearchTag: ((String) -> Void)?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Source", value: wallpaper.source.capitalized)
                    if !wallpaper.resolution.isBlank && wallpaper.resolution != "0x0" {
                        LabeledContent("Resolution", value: wallpaper.resolution.replacingOccurrences(of: "x", with: " × "))
                    }
                    if wallpaper.isNsfw { LabeledContent("Rating", value: "NSFW") }
                    if let url = URL(string: wallpaper.pageUrl), wallpaper.pageUrl.hasPrefix("http") {
                        Link(destination: url) { Label("Open on \(wallpaper.source.capitalized)", systemImage: "safari") }
                    }
                }
                if !wallpaper.tags.isEmpty {
                    Section {
                        FlowLayout(spacing: 6) {
                            ForEach(wallpaper.tags, id: \.self) { tag in tagChip(tag) }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("Tags")
                    } footer: {
                        Text("Tap a tag to search it. Touch and hold for more.")
                    }
                }
            }
            .navigationTitle("Details")
            .inlineTitle()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func tagChip(_ tag: String) -> some View {
        let tier = tierOf(tag)
        return Button {
            dismiss()
            onSearchTag?(tag)
        } label: {
            Text(tag.replacingOccurrences(of: "_", with: " "))
                .font(.subheadline)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(chipColor(tier).opacity(0.18), in: Capsule())
                .foregroundStyle(chipColor(tier) == .secondary ? Color.primary : chipColor(tier))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { Pasteboard.copy(tag) } label: { Label("Copy", systemImage: "doc.on.doc") }
            Menu {
                ForEach(TagTier.allCases, id: \.self) { t in
                    Button(t.rawValue.capitalized) { setTier(tag, t) }
                }
            } label: {
                Label("Rank tag", systemImage: "slider.horizontal.3")
            }
            Button(role: .destructive) {
                let t = normalizeTag(tag)
                model.updateSettings { if !$0.globalBlacklist.contains(t) { $0.globalBlacklist.append(t) } }
                model.showToast("\"\(tag)\" blocked")
            } label: {
                Label("Block tag", systemImage: "hand.raised")
            }
        }
    }

    private func tierOf(_ tag: String) -> TagTier {
        let t = normalizeTag(tag)
        return (wallpaper.isNsfw ? model.state.nsfwTagTiers[t] : nil) ?? model.state.sfwTagTiers[t] ?? .NEUTRAL
    }

    private func setTier(_ tag: String, _ tier: TagTier) {
        let t = normalizeTag(tag), nsfw = wallpaper.isNsfw
        model.updateState { s in
            if nsfw { s.nsfwTagTiers[t] = tier == .NEUTRAL ? nil : tier } else { s.sfwTagTiers[t] = tier == .NEUTRAL ? nil : tier }
        }
    }

    private func chipColor(_ tier: TagTier) -> Color {
        switch tier {
        case .LOVE: .pink
        case .LIKE: .green
        case .NEUTRAL: .secondary
        case .DISLIKE: .orange
        case .NEVER: .red
        }
    }
}

/// Wraps children onto new lines (tag chips).
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
