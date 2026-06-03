import SwiftUI

struct HandsFreeSlideshowView: View {
    let items: [WallpaperItem]
    let onLoadMore: () async -> Void
    let onDismiss: () -> Void

    @State private var currentIndex = 0
    @State private var isPaused = false
    @State private var intervalSeconds: Int = 5
    @State private var progress: Double = 0

    private let intervalOptions = [3, 5, 10, 30]
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    CachedImageView(url: item.imageURL, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black)
                        .tag(idx)
                        .onTapGesture { isPaused.toggle() }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(.black)
            .ignoresSafeArea()
            .onChange(of: currentIndex) { _, newValue in
                progress = 0
                if newValue >= max(items.count - 3, 0) {
                    Task { await onLoadMore() }
                }
            }

            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .tint(.white)
                    .padding(.horizontal, 16)

                HStack(spacing: 32) {
                    Button {
                        let nextIndex = ((intervalOptions.firstIndex(of: intervalSeconds) ?? 0) + 1) % intervalOptions.count
                        intervalSeconds = intervalOptions[nextIndex]
                        progress = 0
                    } label: {
                        Text("\(intervalSeconds)s")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }

                    Button {
                        isPaused.toggle()
                    } label: {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                .padding(.bottom, 16)
            }
            .padding(.vertical, 12)
            .background(.black.opacity(0.6))
        }
        .onReceive(timer) { _ in
            guard !isPaused, !items.isEmpty else { return }
            progress += 0.1 / Double(intervalSeconds)
            if progress >= 1.0 {
                progress = 0
                let next = currentIndex + 1
                if next < items.count {
                    withAnimation { currentIndex = next }
                } else {
                    currentIndex = 0
                }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}
