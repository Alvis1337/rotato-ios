import SwiftUI

struct ZoomableImageView: View {
    let url: URL?

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        CachedImageView(url: url, contentMode: .fit)
            .scaleEffect(scale)
            .offset(offset)
            .clipped()
            .gesture(magnifyGesture)
            .simultaneousGesture(dragGesture)
            .onTapGesture(count: 2) { handleDoubleTap() }
            .onChange(of: url) { reset() }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let delta = value.magnification / lastScale
                lastScale = value.magnification
                scale = (scale * delta).clamped(to: 1.0...8.0)
            }
            .onEnded { _ in
                lastScale = 1.0
                if scale < 1.0 { withAnimation(.spring) { scale = 1.0; offset = .zero } }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.0 else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
                if scale <= 1.0 { withAnimation(.spring) { offset = .zero; lastOffset = .zero } }
            }
    }

    private func handleDoubleTap() {
        withAnimation(.spring(duration: 0.3)) {
            if scale > 1.0 {
                scale = 1.0
                offset = .zero
                lastOffset = .zero
            } else {
                scale = 2.5
            }
        }
    }

    func reset() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
