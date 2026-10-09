import SwiftUI

struct ToastOverlay: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message = model.toast {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 8, y: 2)
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        withAnimation { model.toast = nil }
                    }
                    .onTapGesture { withAnimation { model.toast = nil } }
            }
        }
        .animation(.spring(duration: 0.3), value: model.toast)
    }
}

extension View {
    public func toastOverlay() -> some View { modifier(ToastOverlay()) }
}
