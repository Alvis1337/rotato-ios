import RotatoKit
import SwiftUI

/// What's on the home and lock screens now, with Previous and Next.
struct NowShowingCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            thumb(.home)
            thumb(.lock)
            VStack(alignment: .leading, spacing: 10) {
                Text("Now showing").font(.headline)
                if let reason = model.state.lastSkipReason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                } else if let last = model.state.history.first {
                    Text("Changed \(Date(timeIntervalSince1970: Double(last.timestamp) / 1000), format: .relative(presentation: .named))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Nothing yet").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button {
                        if model.engine.queuePrevious(for: .home) != nil { model.runShortcut() }
                        else { model.showToast("No earlier wallpaper yet") }
                    } label: {
                        Image(systemName: "backward.fill")
                    }
                    .buttonStyle(.bordered)
                    Button {
                        model.runShortcut()
                    } label: {
                        Label("Next", systemImage: "forward.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.poolFiles.isEmpty)
                }
                .controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func thumb(_ screen: WallpaperScreen) -> some View {
        let current = model.state.current(for: screen)
        let file = current.flatMap { model.pool.file(named: $0.poolFile) }
        return VStack(spacing: 4) {
            Group {
                if let file {
                    LocalImage(file, maxPixel: 300).nsfwBlur(model.state.nsfwFileNames.contains(file.lastPathComponent))
                } else {
                    Rectangle().fill(.quaternary).overlay(Image(systemName: "iphone").foregroundStyle(.secondary))
                }
            }
            .frame(width: 56, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(screen == .home ? "Home" : "Lock").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Full-screen swipe through pool images, with the same actions as the grid.
struct PoolViewer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let files: [URL]
    @State private var current: URL
    @State private var showPreview = false

    init(files: [URL], start: URL) {
        self.files = files
        _current = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $current) {
                ForEach(files, id: \.self) { f in
                    LocalImage(f, maxPixel: 2400, contentMode: .fit)
                        .nsfwBlur(model.state.nsfwFileNames.contains(f.lastPathComponent))
                        .tag(f)
                }
            }
            .pagingTabs()
            .background(.black)
            .ignoresSafeArea(edges: .bottom)
            .toolbar {
                ToolbarItem(placement: .leadingBar) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                }
                ToolbarItemGroup(placement: .trailingBar) {
                    Button { showPreview = true } label: { Image(systemName: "rectangle.portrait.on.rectangle.portrait") }
                    Menu {
                        PoolActions(file: current) { if files.count <= 1 { dismiss() } }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .inlineTitle()
            .sheet(isPresented: $showPreview) { ScreenPreview(file: current) }
        }
    }
}

/// How an image will be framed on the home and lock screens, using the real renderer.
struct ScreenPreview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let file: URL
    @State private var home: CGImage?
    @State private var lock: CGImage?

    var body: some View {
        NavigationStack {
            HStack(spacing: 16) {
                screen(home, label: "Home Screen", clock: false)
                screen(lock, label: "Lock Screen", clock: true)
            }
            .padding()
            .navigationTitle("Preview")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .trailingBar) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    model.setNow(file)
                    dismiss()
                } label: {
                    Label("Set now", systemImage: "iphone").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
            .task { await render() }
        }
        .presentationDetents([.large])
    }

    private func screen(_ image: CGImage?, label: String, clock: Bool) -> some View {
        VStack {
            ZStack(alignment: .top) {
                if let image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Rectangle().fill(.quaternary).aspectRatio(9.0 / 19.5, contentMode: .fit).overlay(ProgressView())
                }
                if clock {
                    VStack(spacing: 0) {
                        Text(Date(), format: .dateTime.weekday(.wide).day().month())
                            .font(.system(size: 9, weight: .semibold))
                        Text(Date(), format: .dateTime.hour().minute())
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
                    .padding(.top, 22)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.secondary.opacity(0.4), lineWidth: 1))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func render() async {
        var settings = model.settings
        let full = WallpaperRenderer.screenSize(settings)
        // A quarter-size render is plenty for the preview and much faster.
        settings.filters.phoneScreenWidth = Int(full.width / 4)
        settings.filters.phoneScreenHeight = Int(full.height / 4)
        let s = settings, f = file
        let (h, l) = await Task.detached(priority: .userInitiated) { () -> (CGImage?, CGImage?) in
            guard let src = ImageLoader.thumbnail(f, maxPixel: 1200) else { return (nil, nil) }
            let size = WallpaperRenderer.screenSize(s)
            func make(_ screen: WallpaperScreen) -> CGImage {
                let framed = WallpaperRenderer.frame(src, to: size, fit: s.wallpaperFit, screen: screen)
                let fx = s.wallpaperEffects
                guard !fx.isNone, screen == .home || fx.onLockScreen else { return framed }
                return WallpaperRenderer.applyingEffects(framed, fx) ?? framed
            }
            return (make(.home), make(.lock))
        }.value
        home = h
        lock = l
    }
}

/// Wallpapers shown recently, newest first.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(Array(model.state.history.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 12) {
                    Group {
                        if let f = model.pool.file(named: item.poolFile) {
                            LocalImage(f, maxPixel: 200)
                        } else if !item.thumbUrl.isBlank {
                            RemoteImage(item.thumbUrl, maxPixel: 200)
                        } else {
                            Rectangle().fill(.quaternary)
                        }
                    }
                    .frame(width: 44, height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .nsfwBlur(model.state.nsfwFileNames.contains(item.poolFile))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.screen == .home ? "Home Screen" : "Lock Screen").font(.subheadline.weight(.medium))
                        Text(Date(timeIntervalSince1970: Double(item.timestamp) / 1000), format: .dateTime.month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                        if item.source != "local" && !item.source.isBlank {
                            Text(item.source.capitalized).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    if let url = URL(string: item.pageUrl), item.pageUrl.hasPrefix("http") {
                        Link(destination: url) { Image(systemName: "safari") }
                    }
                }
                .swipeActions {
                    if let f = model.pool.file(named: item.poolFile) {
                        Button("Show again") {
                            model.engine.queue(f, screens: [item.screen])
                            model.reload()
                            model.showToast("Up next")
                        }
                        .tint(.accentColor)
                    }
                }
            }
        }
        .overlay {
            if model.state.history.isEmpty {
                ContentUnavailableView("No history yet", systemImage: "clock", description: Text("Wallpapers your shortcut sets appear here."))
            }
        }
        .navigationTitle("History")
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .trailingBar) { Button("Done") { dismiss() } } }
    }
}

/// Totals and recent rotation problems.
struct StatsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                LabeledContent("Wallpapers set", value: "\(model.state.totalRotations)")
                LabeledContent("In the Library", value: "\(model.poolFiles.count)")
                LabeledContent("Collections", value: "\(model.collections.count)")
                LabeledContent("Saved wallpapers", value: "\(model.entries.count)")
                LabeledContent("Rated", value: "\(model.state.ratings.count)")
            }
            let sources = Dictionary(grouping: model.state.history, by: \.source).mapValues(\.count)
                .sorted { $0.value > $1.value }.prefix(6)
            if !sources.isEmpty {
                Section("Recently from") {
                    ForEach(sources, id: \.key) { s in
                        LabeledContent(s.key == "local" ? "Your photos" : s.key.capitalized, value: "\(s.value)")
                    }
                }
            }
            Section {
                if model.state.errors.isEmpty {
                    Text("No problems").foregroundStyle(.secondary)
                }
                ForEach(model.state.errors, id: \.self) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.message).font(.subheadline)
                        Text(Date(timeIntervalSince1970: Double(e.timestamp) / 1000), format: .relative(presentation: .named))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !model.state.errors.isEmpty {
                    Button("Clear", role: .destructive) { model.updateState { $0.errors = [] } }
                }
            } header: {
                Text("Rotation problems")
            }
        }
        .navigationTitle("Stats")
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .trailingBar) { Button("Done") { dismiss() } } }
    }
}
