import SwiftUI
import Photos
import SwiftData

struct FullscreenPreviewView: View {
    let items: [WallpaperItem]
    let initialIndex: Int
    let onDismiss: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @State private var currentIndex: Int
    @State private var showOverlay = true
    @State private var dragOffset: CGFloat = 0
    @State private var isDismissing = false
    @State private var saveToast: String?
    @State private var showSaveSheet = false

    init(items: [WallpaperItem], initialIndex: Int = 0, onDismiss: @escaping () -> Void) {
        self.items = items
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: initialIndex)
    }

    var current: WallpaperItem { items[currentIndex] }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    ZoomableImageView(url: item.imageURL)
                        .tag(idx)
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showOverlay.toggle() } }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: dragOffset)
            .opacity(Double(1.0 - abs(dragOffset) / 400.0).clamped(to: 0...1))
            .gesture(swipeDownGesture)

            if showOverlay {
                overlayView
                    .transition(.opacity)
            }

            if let toast = saveToast {
                VStack {
                    Spacer()
                    Text(toast)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
        .statusBarHidden(!showOverlay)
        .onAppear { settings.addToHistory(current) }
        .onChange(of: currentIndex) { settings.addToHistory(current) }
        .sheet(isPresented: $showSaveSheet) {
            SaveToCollectionSheet(item: current)
        }
    }

    private var overlayView: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                Spacer()
                if items.count > 1 {
                    Text("\(currentIndex + 1) / \(items.count)")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                Spacer()
                Text(current.sourceId.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)

            Spacer()

            // Bottom bar
            VStack(alignment: .leading, spacing: 12) {
                // Tags
                if !current.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(current.tags.prefix(20), id: \.self) { tag in
                                Text(tag.replacingOccurrences(of: "_", with: " "))
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.ultraThinMaterial, in: Capsule())
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                // Resolution + rating badge
                HStack(spacing: 8) {
                    if !current.resolution.isEmpty {
                        Text(current.resolution)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4))
                    }
                    if current.isNSFW {
                        Text("NSFW")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 16)

                // Star rating row
                StarRatingRow(itemId: current.id, settings: settings)
                    .padding(.horizontal, 16)

                // Action buttons
                HStack(spacing: 20) {
                    actionButton(icon: "bookmark", label: "Save") { showSaveSheet = true }
                    actionButton(icon: "square.and.arrow.down", label: "Save to Photos") { saveToPhotos() }
                    actionButton(icon: "square.and.arrow.up", label: "Share") { share() }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.75)],
                               startPoint: .top, endPoint: .bottom)
            )
        }
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var swipeDownGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard value.translation.height > 0 else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                if value.translation.height > 150 {
                    withAnimation(.easeIn(duration: 0.2)) { dragOffset = 600 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onDismiss() }
                } else {
                    withAnimation(.spring) { dragOffset = 0 }
                }
            }
    }

    private func saveToPhotos() {
        guard let url = current.imageURL as URL? else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let img = UIImage(data: data) else { return }
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: img)
                }
                await showToast("Saved to Photos — open Photos to set as wallpaper")
            } catch {
                await showToast("Failed to save")
            }
        }
    }

    private func share() {
        guard let url = current.imageURL as URL? else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let img = UIImage(data: data) else { return }
                await MainActor.run {
                    let av = UIActivityViewController(activityItems: [img], applicationActivities: nil)
                    // Traverse the presentation chain to find the topmost presented controller
                    if let vc = topPresentedViewController() {
                        vc.present(av, animated: true)
                    }
                }
            } catch {
                await showToast("Failed to share")
            }
        }
    }

    private func topPresentedViewController() -> UIViewController? {
        var vc = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }

    @MainActor
    private func showToast(_ message: String) {
        withAnimation { saveToast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { saveToast = nil }
        }
    }
}

// MARK: - Star Rating Row

struct StarRatingRow: View {
    let itemId: String
    let settings: AppSettings

    private var current: Int { settings.rating(for: itemId) }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    let newRating = (current == star) ? 0 : star  // tap same star to clear
                    settings.setRating(newRating, for: itemId)
                } label: {
                    Image(systemName: star <= current ? "star.fill" : "star")
                        .font(.system(size: 20))
                        .foregroundStyle(star <= current ? Color.yellow : Color.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
