import RotatoKit
import SwiftUI

/// The viewer's bottom card (ViewerChrome on Android): the first tag as a title, a tag summary
/// and the five actions. Pull it up (or tap the chevron) for collections, links, the screen
/// preview and every tag.
struct ViewerCard: View {
    @Environment(AppModel.self) private var model
    let wallpaper: Wallpaper
    var position: String?
    @Binding var expanded: Bool
    var onSkip: () -> Void
    var onSearchTag: (String) -> Void
    var onPreview: () -> Void
    /// Extra row for collection context (Remove from collection).
    var extra: AnyView?
    @State private var newCollection = false
    @State private var newName = ""
    @State private var drag: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Capsule().fill(.white.opacity(0.5)).frame(width: 36, height: 5).frame(maxWidth: .infinity)
            header
            if expanded {
                ImageInfoPills(wallpaper: wallpaper, position: nil)
            }
            ViewerActions(wallpaper: wallpaper, onSkip: onSkip)
            if expanded { details }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x0B1033).opacity(0.97), in: RoundedRectangle(cornerRadius: expanded ? 24 : 22))
        .overlay(RoundedRectangle(cornerRadius: expanded ? 24 : 22).stroke(.white.opacity(0.12)))
        .offset(y: max(drag, expanded ? 0 : -40) * 0.4)
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { drag = $0.translation.height }
                .onEnded { v in
                    withAnimation(.spring(duration: 0.35)) {
                        if v.translation.height < -50 { expanded = true } else if v.translation.height > 50 { expanded = false }
                        drag = 0
                    }
                }
        )
        .environment(\.colorScheme, .dark)
        .alert("New collection", isPresented: $newCollection) {
            TextField("Name", text: $newName)
            Button("Create") {
                if let c = model.createCollection(newName) { model.save(wallpaper, to: c.id) }
                newName = ""
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text((wallpaper.tags.first ?? SourceStyle.name(wallpaper.source)).replacingOccurrences(of: "_", with: " "))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !expanded && wallpaper.tags.count > 1 {
                    Text(tagSummary(Array(wallpaper.tags.dropFirst())))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                withAnimation(.spring(duration: 0.35)) { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
    }

    /// Sized to its content, scrolling only when it's taller than the space allows.
    private var details: some View {
        ViewThatFits(in: .vertical) {
            detailsContent
            ScrollView { detailsContent }.scrollIndicators(.hidden)
        }
        .frame(maxHeight: 460)
    }

    private var detailsContent: some View {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Collections").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    FlowLayout(spacing: 8) {
                        ForEach(model.visibleCollections.filter { !$0.isSmartCollection }) { c in
                            let inIt = model.savedListIds[wallpaper.key]?.contains(c.id) ?? false
                            Button { model.toggle(wallpaper, in: c.id) } label: {
                                Label(c.name, systemImage: inIt ? "checkmark" : "plus")
                                    .font(.subheadline)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(inIt ? Color.rotatoAccent.opacity(0.35) : .clear, in: Capsule())
                                    .overlay(Capsule().stroke(.white.opacity(0.35)))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.white)
                        }
                        Button { newCollection = true } label: {
                            Label("New", systemImage: "folder.badge.plus")
                                .font(.subheadline)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .overlay(Capsule().stroke(.white.opacity(0.35)))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }
                }

                HStack(spacing: 10) {
                    if let url = URL(string: wallpaper.pageUrl), wallpaper.pageUrl.hasPrefix("http") {
                        Link(destination: url) { pillButton("Open post", "arrow.up.right.square") }
                    }
                    Button { saveToPhotos(wallpaper, model) } label: { pillButton("Save to Photos", "square.and.arrow.down") }
                        .buttonStyle(.plain)
                }
                Button(action: onPreview) {
                    Label("Preview on my screens", systemImage: "iphone")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(Capsule().stroke(.white.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .disabled(wallpaper.isVideo)

                if let extra { extra }

                if !wallpaper.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags · tap to search, hold for options").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        FlowLayout(spacing: 6) {
                            ForEach(wallpaper.tags, id: \.self) { tag in
                                TagChip(tag: tag, isNsfw: wallpaper.isNsfw) { onSearchTag(tag) }
                            }
                        }
                    }
                }
            }
    }

    private func pillButton(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(Color.rotatoAccent.opacity(0.9), in: Capsule())
    }
}

/// Save, Set, Library, Share, Skip: the viewer's main actions.
struct ViewerActions: View {
    @Environment(AppModel.self) private var model
    let wallpaper: Wallpaper
    var onSkip: () -> Void

    var body: some View {
        let saved = model.isSaved(wallpaper)
        let inPool = model.pool.file(for: wallpaper.source, sourceId: wallpaper.id, in: model.poolFiles) != nil
        HStack {
            action(saved ? "bookmark.fill" : "bookmark", "Save", highlighted: saved) {
                Haptics.tap()
                model.quickSave(wallpaper)
            }
            Spacer()
            Menu {
                Button("Home & Lock") { set([.home, .lock]) }
                Button("Home Screen") { set([.home]) }
                Button("Lock Screen") { set([.lock]) }
            } label: {
                circle("photo.on.rectangle", "Set", highlighted: false)
            }
            .dockMenuStyle()
            .disabled(wallpaper.isVideo)
            .opacity(wallpaper.isVideo ? 0.4 : 1)
            Spacer()
            action(inPool ? "checkmark" : "arrow.down.to.line", "Library", highlighted: inPool) {
                Task {
                    if await model.addToPool(wallpaper) != nil {
                        LearnedTaste.record(wallpaper.tags, .downloaded, db: model.db)
                        model.showToast("Added to Library")
                    } else {
                        model.showToast("Couldn't download it")
                    }
                }
            }
            .disabled(wallpaper.isVideo || inPool)
            Spacer()
            if let link = URL(string: wallpaper.shareLink), !wallpaper.shareLink.isEmpty {
                ShareLink(item: link) { circle("square.and.arrow.up", "Share", highlighted: false) }
                    .buttonStyle(.plain)
            } else {
                circle("square.and.arrow.up", "Share", highlighted: false).opacity(0.4)
            }
            Spacer()
            action("forward.end.fill", "Skip", highlighted: false, perform: onSkip)
        }
    }

    private func set(_ screens: Set<WallpaperScreen>) {
        Task { await model.setNow(wallpaper, screens: screens) }
    }

    private func action(_ icon: String, _ label: String, highlighted: Bool, perform: @escaping () -> Void) -> some View {
        Button(action: perform) { circle(icon, label, highlighted: highlighted) }.buttonStyle(.plain)
    }

    private func circle(_ icon: String, _ label: String, highlighted: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(highlighted ? .black : .white)
                .frame(width: 46, height: 46)
                .background(highlighted ? Color.rotatoAccent : .white.opacity(0.12), in: Circle())
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// Downloads the original and saves it to the photo library.
@MainActor
func saveToPhotos(_ wp: Wallpaper, _ model: AppModel) {
    Task {
        guard let data = await ImagePipeline.shared.cachedData(wp.fullUrl) else {
            model.showToast("Couldn't download it")
            return
        }
        LearnedTaste.record(wp.tags, .downloaded, db: model.db)
        model.showToast(await PhotoLibrary.save(data) ? "Saved to Photos" : "Couldn't save to Photos")
    }
}

/// A tag: tap to search, hold to copy, rank or block.
struct TagChip: View {
    @Environment(AppModel.self) private var model
    let tag: String
    let isNsfw: Bool
    let onTap: () -> Void

    var body: some View {
        let tier = tierOf()
        Button(action: onTap) {
            Text(tag.replacingOccurrences(of: "_", with: " "))
                .font(.subheadline)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(color(tier).opacity(tier == .NEUTRAL ? 0.14 : 0.3), in: Capsule())
                .foregroundStyle(tier == .NEUTRAL ? Color.primary : color(tier))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { Pasteboard.copy(tag) } label: { Label("Copy", systemImage: "doc.on.doc") }
            Menu {
                ForEach(TagTier.allCases, id: \.self) { t in Button(t.rawValue.capitalized) { setTier(t) } }
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

    private func tierOf() -> TagTier {
        let t = normalizeTag(tag)
        return (isNsfw ? model.state.nsfwTagTiers[t] : nil) ?? model.state.sfwTagTiers[t] ?? .NEUTRAL
    }

    private func setTier(_ tier: TagTier) {
        let t = normalizeTag(tag), nsfw = isNsfw
        model.updateState { s in
            if nsfw { s.nsfwTagTiers[t] = tier == .NEUTRAL ? nil : tier } else { s.sfwTagTiers[t] = tier == .NEUTRAL ? nil : tier }
        }
    }

    private func color(_ tier: TagTier) -> Color {
        switch tier {
        case .LOVE: .pink
        case .LIKE: .green
        case .NEUTRAL: .gray
        case .DISLIKE: .orange
        case .NEVER: .red
        }
    }
}

extension View {
    /// A menu that looks like the dock's other buttons: no border or chevron on any platform.
    @ViewBuilder
    func dockMenuStyle() -> some View {
        #if os(macOS)
        menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        #else
        menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        #endif
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
