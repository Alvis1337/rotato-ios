import AVKit
import RotatoKit
import SwiftUI

/// Full-screen swipeable viewer shared by Discover and Collections (FullscreenImage and
/// ViewerChrome on Android). `collectionId` is set when opened from a collection, which adds
/// "Remove from collection". Tap toggles the chrome.
public struct WallpaperViewer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let items: [Wallpaper]
    let collectionId: String?
    @State private var index: Int
    @State private var chrome = true
    #if DEBUG
    @State private var expanded = ProcessInfo.processInfo.environment["ROTATO_OPEN_VIEWER"] == "2"
    #else
    @State private var expanded = false
    #endif
    @State private var preview: Wallpaper?

    public init(items: [Wallpaper], startIndex: Int, collectionId: String? = nil) {
        self.items = items
        self.collectionId = collectionId
        _index = State(initialValue: min(max(startIndex, 0), max(items.count - 1, 0)))
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, wp in
                    WallpaperPage(wallpaper: wp, isCurrent: i == index, exemptBlur: blurExempt)
                        .tag(i)
                }
            }
            .pagingTabs()
            .ignoresSafeArea()
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expanded { expanded = false } else { chrome.toggle() }
                }
            }

            if chrome, items.indices.contains(index) {
                let wp = items[index]
                VStack(alignment: .leading, spacing: 0) {
                    topBar(wp)
                    Spacer()
                    ViewerCard(
                        wallpaper: wp,
                        position: position,
                        expanded: $expanded,
                        onSkip: skip,
                        onSearchTag: { tag in
                            DiscoverSearchRequest.shared.send(tag)
                            dismiss()
                        },
                        onPreview: { preview = wp },
                        extra: collectionId.map { listId in
                            AnyView(Button(role: .destructive) {
                                removeFromCollection(listId)
                            } label: {
                                Label("Remove from this collection", systemImage: "trash")
                                    .font(.subheadline.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .overlay(Capsule().stroke(.red.opacity(0.6)))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red))
                        }
                    )
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
                .transition(.opacity)
            }
        }
        .statusBarHiddenCompat(!chrome)
        .preferredColorScheme(.dark)
        .sheet(item: $preview) { wp in ScreenPreview(wallpaper: wp) }
    }

    private var position: String? { items.count > 1 ? "\(index + 1) / \(items.count)" : nil }

    private func skip() {
        guard items.indices.contains(index) else { return }
        LearnedTaste.record(items[index].tags, .skipped, db: model.db)
        if index < items.count - 1 { withAnimation { index += 1 } } else { dismiss() }
    }

    private func topBar(_ wp: Wallpaper) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ImageInfoPills(wallpaper: wp, position: position)
            Spacer(minLength: 0)
            Button { dismiss() } label: { circleIcon("xmark") }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private var blurExempt: Bool {
        collectionId.flatMap { id in model.collections.first { $0.id == id }?.blurExempt } ?? false
    }

    private func removeFromCollection(_ listId: String) {
        let wp = items[index]
        model.collectionsRepo.remove(wp, from: listId)
        model.afterCollectionsChange()
        model.showToast("Removed")
        if items.count <= 1 { dismiss() }
    }
}

func circleIcon(_ name: String) -> some View {
    Image(systemName: name)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 40, height: 40)
        .background(.ultraThinMaterial, in: Circle())
}

/// One page: a zoomable image or a looping video.
struct WallpaperPage: View {
    @Environment(AppModel.self) private var model
    let wallpaper: Wallpaper
    let isCurrent: Bool
    var exemptBlur = false

    var body: some View {
        Group {
            if wallpaper.isVideo, let url = URL(string: wallpaper.fullUrl) {
                LoopingVideo(url: url, playing: isCurrent)
            } else {
                ZoomableImage(url: wallpaper.fullUrl.ifBlank(wallpaper.sampleUrl), preview: wallpaper.gridUrl)
            }
        }
        .nsfwBlur(wallpaper.isNsfw, exempt: exemptBlur)
    }
}

/// Pinch to zoom, double-tap to toggle 2.5×, drag to pan when zoomed.
struct ZoomableImage: View {
    let url: String
    let preview: String
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        RemoteImage(url, preview: preview, maxPixel: 3000, contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { v in scale = min(max(lastScale * v.magnification, 1), 6) }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1.01 { reset() }
                    }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: scale > 1 ? 0 : 10000)
                    .onChanged { v in
                        offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height)
                    }
                    .onEnded { _ in lastOffset = offset }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(duration: 0.3)) {
                    if scale > 1 { reset() } else { scale = 2.5; lastScale = 2.5 }
                }
            }
    }

    private func reset() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }
}

/// A muted, looping video that plays only while visible.
struct LoopingVideo: View {
    let url: URL
    let playing: Bool
    var muted = false
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear(perform: setUp)
            .onDisappear { player?.pause() }
            .onChange(of: playing) { _, p in if p { player?.play() } else { player?.pause() } }
    }

    private func setUp() {
        guard player == nil else { if playing { player?.play() }; return }
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": HTTP.imageHeaders(for: url.absoluteString)]))
        let p = AVQueuePlayer()
        p.isMuted = muted
        looper = AVPlayerLooper(player: p, templateItem: item)
        player = p
        if playing { p.play() }
    }
}
