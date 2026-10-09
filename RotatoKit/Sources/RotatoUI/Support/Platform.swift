import SwiftUI

// RotatoUI targets iOS, but also builds for macOS so it can be type-checked without Xcode.
// iOS-only modifiers go through these shims, which do nothing on macOS.

extension View {
    /// `.navigationBarTitleDisplayMode(.inline)` on iOS.
    @ViewBuilder
    public func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// `.navigationBarTitleDisplayMode(.large)` on iOS.
    @ViewBuilder
    public func largeTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    /// A full-screen cover on iOS, a sheet elsewhere.
    @ViewBuilder
    public func fullScreen<Item: Identifiable, Content: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(item: item, content: content)
        #else
        sheet(item: item, content: content)
        #endif
    }

    @ViewBuilder
    public func fullScreen<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }

    /// Plain-text entry: no autocapitalization or autocorrection (tags, URLs, API keys).
    @ViewBuilder
    public func plainTextEntry() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        autocorrectionDisabled()
        #endif
    }

    @ViewBuilder
    public func urlKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self
        #endif
    }

    @ViewBuilder
    public func numberKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }

    /// Hides the status bar (immersive viewer).
    @ViewBuilder
    public func statusBarHiddenCompat(_ hidden: Bool = true) -> some View {
        #if os(iOS)
        statusBarHidden(hidden)
        #else
        self
        #endif
    }

    /// Hides the navigation bar's background (immersive feed) on iOS.
    @ViewBuilder
    public func navigationBarBackgroundHidden(_ hidden: Bool) -> some View {
        #if os(iOS)
        toolbarBackground(hidden ? .hidden : .automatic, for: .navigationBar)
        #else
        self
        #endif
    }

    /// `.listStyle(.insetGrouped)` on iOS.
    @ViewBuilder
    public func groupedList() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }

    /// Horizontal paging TabView style on iOS.
    @ViewBuilder
    public func pagingTabs() -> some View {
        #if os(iOS)
        tabViewStyle(.page(indexDisplayMode: .never))
        #else
        self
        #endif
    }
}

extension ToolbarItemPlacement {
    /// Trailing navigation bar slot.
    public static var trailingBar: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }

    /// Leading navigation bar slot.
    public static var leadingBar: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    public static var bottomBarCompat: ToolbarItemPlacement {
        #if os(iOS)
        .bottomBar
        #else
        .automatic
        #endif
    }
}

public enum Haptics {
    public static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    public static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

public enum Pasteboard {
    public static func copy(_ s: String) {
        #if os(iOS)
        UIPasteboard.general.string = s
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        #endif
    }
}

/// Saving images to the photo library (iOS only; no-op elsewhere).
public enum PhotoLibrary {
    public static func save(_ data: Data) async -> Bool {
        #if os(iOS)
        return await PhotoLibrarySaver.save(data)
        #else
        return false
        #endif
    }
}

#if os(iOS)
import Photos

enum PhotoLibrarySaver {
    static func save(_ data: Data) async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
            return true
        } catch {
            return false
        }
    }
}
#endif
