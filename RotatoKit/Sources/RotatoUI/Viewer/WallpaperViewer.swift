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
    @State private var details: Wallpaper?
    @State private var saving: Wallpaper?

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
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { chrome.toggle() } }

            if chrome, items.indices.contains(index) {
                VStack {
                    topBar
                    Spacer()
                    WallpaperActionsDock(
                        wallpaper: items[index],
                        onDetails: { details = items[index] },
                        onPickCollections: { saving = items[index] },
                        extra: collectionId.map { listId in
                            AnyView(Button(role: .destructive) {
                                removeFromCollection(listId)
                            } label: {
                                Label("Remove from collection", systemImage: "trash")
                            })
                        }
                    )
                    .padding(.bottom, 8)
                }
                .transition(.opacity)
            }
        }
        .statusBarHiddenCompat(!chrome)
        .preferredColorScheme(.dark)
        .sheet(item: $details) { wp in
            WallpaperDetailsSheet(wallpaper: wp) { tag in
                DiscoverSearchRequest.shared.send(tag)
                dismiss()
            }
        }
        .sheet(item: $saving) { wp in SaveToCollectionsSheet(wallpaper: wp) }
    }

    private var blurExempt: Bool {
        collectionId.flatMap { id in model.collections.first { $0.id == id }?.blurExempt } ?? false
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: { circleIcon("xmark") }
            Spacer()
            if items.count > 1 {
                Text("\(index + 1) of \(items.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer()
            if let link = URL(string: items[index].shareLink), !items[index].shareLink.isEmpty {
                ShareLink(item: link) { circleIcon("square.and.arrow.up") }
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal)
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
