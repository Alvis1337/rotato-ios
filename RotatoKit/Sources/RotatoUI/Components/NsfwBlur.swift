import RotatoKit
import SwiftUI

/// Blurs NSFW images until tapped, when the user has NSFW blur on (always on under the content
/// filter). `exempt` skips it (collections marked "don't blur").
public struct NsfwBlur: ViewModifier {
    @Environment(AppModel.self) private var model
    let isNsfw: Bool
    let exempt: Bool
    @State private var revealed = false

    public func body(content: Content) -> some View {
        let blur = isNsfw && !exempt && !revealed && model.settings.effectiveBlur
        content
            .blur(radius: blur ? 24 : 0, opaque: true)
            .overlay {
                if blur {
                    Image(systemName: "eye.slash.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(10)
                        .background(.black.opacity(0.35), in: Circle())
                }
            }
            .clipped()
            .simultaneousGesture(TapGesture().onEnded { if blur { revealed = true } }, including: blur ? .all : .subviews)
    }
}

extension View {
    public func nsfwBlur(_ isNsfw: Bool, exempt: Bool = false) -> some View {
        modifier(NsfwBlur(isNsfw: isNsfw, exempt: exempt))
    }
}
