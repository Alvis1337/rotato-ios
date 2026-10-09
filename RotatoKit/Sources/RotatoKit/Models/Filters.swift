import Foundation

public enum MinResolution: String, Codable, CaseIterable, Sendable {
    case ANY, HD, FHD, QHD, UHD, MY_PHONE

    public var label: String {
        switch self {
        case .ANY: "Any"
        case .HD: "HD (1280×720)"
        case .FHD: "FHD (1920×1080)"
        case .QHD: "QHD (2560×1440)"
        case .UHD: "4K (3840×2160)"
        case .MY_PHONE: "My Phone"
        }
    }

    public var width: Int {
        switch self { case .ANY: 0; case .HD: 1280; case .FHD: 1920; case .QHD: 2560; case .UHD: 3840; case .MY_PHONE: -1 }
    }

    public var height: Int {
        switch self { case .ANY: 0; case .HD: 720; case .FHD: 1080; case .QHD: 1440; case .UHD: 2160; case .MY_PHONE: -1 }
    }
}

public enum AspectRatio: String, Codable, CaseIterable, Sendable {
    case ANY, ULTRAWIDE, WIDE, WIDE_10, STANDARD, PORTRAIT, MY_PHONE

    public var label: String {
        switch self {
        case .ANY: "Any"
        case .ULTRAWIDE: "Ultrawide (21:9)"
        case .WIDE: "Wide (16:9)"
        case .WIDE_10: "Wide (16:10)"
        case .STANDARD: "Standard (4:3)"
        case .PORTRAIT: "Portrait (9:16)"
        case .MY_PHONE: "My Phone"
        }
    }

    public var wallhavenKey: String {
        switch self {
        case .ANY, .MY_PHONE: ""
        case .ULTRAWIDE: "21x9"
        case .WIDE: "16x9"
        case .WIDE_10: "16x10"
        case .STANDARD: "4x3"
        case .PORTRAIT: "9x16"
        }
    }

    public var parts: (w: Int, h: Int) {
        switch self {
        case .ANY: (0, 0)
        case .ULTRAWIDE: (21, 9)
        case .WIDE: (16, 9)
        case .WIDE_10: (16, 10)
        case .STANDARD: (4, 3)
        case .PORTRAIT: (9, 16)
        case .MY_PHONE: (-1, -1)
        }
    }
}

/// Discover / fill filters (BrainrotFilters on Android).
public struct DiscoverFilters: Codable, Hashable, Sendable {
    public var minResolution: MinResolution = .ANY
    public var aspectRatio: AspectRatio = .ANY
    /// Screen size in pixels, recorded by the app at launch for "My Phone".
    public var phoneScreenWidth: Int = 0
    public var phoneScreenHeight: Int = 0
    /// General-purpose sources (Wallhaven) search their anime category only.
    public var animeOnly: Bool = false
    /// Space-separated tags are OR'd (any match) instead of AND'd.
    public var matchAny: Bool = false

    public init(
        minResolution: MinResolution = .ANY, aspectRatio: AspectRatio = .ANY,
        phoneScreenWidth: Int = 0, phoneScreenHeight: Int = 0,
        animeOnly: Bool = false, matchAny: Bool = false
    ) {
        self.minResolution = minResolution; self.aspectRatio = aspectRatio
        self.phoneScreenWidth = phoneScreenWidth; self.phoneScreenHeight = phoneScreenHeight
        self.animeOnly = animeOnly; self.matchAny = matchAny
    }

    /// Smallest image that still looks sharp on the screen: 10% under it.
    public var phoneMinWidth: Int { Int(Double(phoneScreenWidth) * 0.9) }
    public var phoneMinHeight: Int { Int(Double(phoneScreenHeight) * 0.9) }

    /// Returns true if the image dimensions satisfy the resolution and ratio filters.
    public func matches(width: Int, height: Int) -> Bool {
        if width <= 0 || height <= 0 { return true } // unknown dimensions: let it through
        switch minResolution {
        case .ANY: break
        case .MY_PHONE:
            if phoneScreenWidth > 0, phoneScreenHeight > 0, width < phoneMinWidth || height < phoneMinHeight { return false }
        default:
            if width < minResolution.width || height < minResolution.height { return false }
        }
        let actual = Double(width) / Double(height)
        switch aspectRatio {
        case .ANY: break
        case .MY_PHONE:
            if phoneScreenWidth > 0, phoneScreenHeight > 0 {
                let expected = Double(phoneScreenWidth) / Double(phoneScreenHeight)
                if abs(actual - expected) / expected > 0.05 { return false }
            }
        default:
            let expected = Double(aspectRatio.parts.w) / Double(aspectRatio.parts.h)
            if abs(actual - expected) / expected > 0.05 { return false }
        }
        return true
    }

    enum CodingKeys: String, CodingKey { case minResolution, aspectRatio, phoneScreenWidth, phoneScreenHeight, animeOnly, matchAny }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minResolution = c.value(.minResolution, .ANY)
        aspectRatio = c.value(.aspectRatio, .ANY)
        phoneScreenWidth = c.value(.phoneScreenWidth, 0)
        phoneScreenHeight = c.value(.phoneScreenHeight, 0)
        animeOnly = c.value(.animeOnly, false)
        matchAny = c.value(.matchAny, false)
    }
}
