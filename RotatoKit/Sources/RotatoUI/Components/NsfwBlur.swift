import RotatoKit
import SwiftUI

/// Posts revealed this session, shared by every grid so a tile stays revealed after it scrolls
/// away and back (NsfwRevealedKeys on Android).
@MainActor
@Observable
final class NsfwRevealed {
    static let shared = NsfwRevealed()
    var keys: Set<String> = []
}

/// Blurs an NSFW image under a dark scrim until tapped, when NSFW blur is on (always on under the
/// content filter). The first tap only reveals; it never reaches the tile's own tap action.
/// `compact` drops the "Tap to reveal" label for small tiles. `exempt` skips the blur
/// (collections marked "Skip NSFW blur").
public struct NsfwBlur: ViewModifier {
    @Environment(AppModel.self) private var model
    let isNsfw: Bool
    let key: String
    let exempt: Bool
    let compact: Bool
    private var revealed = NsfwRevealed.shared

    init(isNsfw: Bool, key: String, exempt: Bool, compact: Bool) {
        self.isNsfw = isNsfw
        self.key = key
        self.exempt = exempt
        self.compact = compact
    }

    public func body(content: Content) -> some View {
        let blurred = isNsfw && !exempt && model.settings.effectiveBlur && !revealed.keys.contains(key)
        content
            .blur(radius: blurred ? 22 : 0, opaque: true)
            .overlay {
                if blurred {
                    ZStack {
                        Color.black.opacity(0.55)
                        VStack(spacing: compact ? 2 : 4) {
                            Image(systemName: "eye.slash.fill").font(compact ? .callout : .title3)
                            if !compact { Text("Tap to reveal").font(.system(size: 11)) }
                        }
                        .foregroundStyle(.white)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { revealed.keys.insert(key) }
                    .accessibilityLabel("NSFW — tap to reveal")
                }
            }
            .clipped()
    }
}

extension View {
    /// `key` identifies the post across grids (defaults to a per-view key when nil).
    public func nsfwBlur(_ isNsfw: Bool, key: String? = nil, exempt: Bool = false, compact: Bool = true) -> some View {
        modifier(NsfwBlur(isNsfw: isNsfw, key: key ?? "anon", exempt: exempt, compact: compact))
    }
}
