import Foundation

public enum WallpaperFit: String, Codable, CaseIterable, Sendable {
    case SMART, FILL, FIT

    public var label: String {
        switch self {
        case .SMART: "Smart fill (crop around the subject)"
        case .FILL: "Fill (centre crop)"
        case .FIT: "Fit (letterbox)"
        }
    }
}

public enum VideoPreviewMode: String, Codable, CaseIterable, Sendable {
    case AUTOPLAY, STATIC, OFF

    public var label: String {
        switch self {
        case .AUTOPLAY: "Autoplay previews"
        case .STATIC: "Static thumbnail"
        case .OFF: "Off"
        }
    }

    public var description: String {
        switch self {
        case .AUTOPLAY: "Video posts play muted while scrolling, like a reel"
        case .STATIC: "Video posts show a still frame with a play icon until tapped"
        case .OFF: "Never load video previews in grids — saves data/battery"
        }
    }
}

public enum ThemeMode: String, Codable, CaseIterable, Sendable {
    case SYSTEM, LIGHT, DARK

    public var label: String {
        switch self { case .SYSTEM: "System"; case .LIGHT: "Light"; case .DARK: "Dark" }
    }
}

/// Which screen a Shortcuts run asks for. iOS sets home and lock separately.
public enum WallpaperScreen: String, Codable, CaseIterable, Sendable {
    case home, lock
}

/// Effects baked into the home screen wallpaper so icons stay readable over busy art.
/// `blur` is 0 (off), 1 (soft) or 2 (strong); `dimPercent` darkens by 0–60%.
public struct WallpaperEffects: Codable, Hashable, Sendable {
    public var blur: Int = 0
    public var dimPercent: Int = 0
    public var onLockScreen: Bool = false

    public init(blur: Int = 0, dimPercent: Int = 0, onLockScreen: Bool = false) {
        self.blur = blur; self.dimPercent = dimPercent; self.onLockScreen = onLockScreen
    }

    public var isNone: Bool { blur <= 0 && dimPercent <= 0 }

    enum CodingKeys: String, CodingKey { case blur, dimPercent, onLockScreen }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blur = min(max(c.value(.blur, 0), 0), 2)
        dimPercent = min(max(c.value(.dimPercent, 0), 0), 60)
        onLockScreen = c.value(.onLockScreen, false)
    }
}

public struct AutoPauseSettings: Codable, Hashable, Sendable {
    public var nightEnabled: Bool = false
    public var nightStartHour: Int = 22
    public var nightEndHour: Int = 7

    public init(nightEnabled: Bool = false, nightStartHour: Int = 22, nightEndHour: Int = 7) {
        self.nightEnabled = nightEnabled; self.nightStartHour = nightStartHour; self.nightEndHour = nightEndHour
    }

    public func isInNightWindow(hour: Int) -> Bool {
        guard nightEnabled, nightStartHour != nightEndHour else { return false }
        if nightStartHour > nightEndHour { return hour >= nightStartHour || hour < nightEndHour }
        return hour >= nightStartHour && hour < nightEndHour
    }

    enum CodingKeys: String, CodingKey { case nightEnabled, nightStartHour, nightEndHour }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nightEnabled = c.value(.nightEnabled, false)
        nightStartHour = c.value(.nightStartHour, 22)
        nightEndHour = c.value(.nightEndHour, 7)
    }
}

/// Everything the user configures. One file, `settings.json`.
public struct RotatoSettings: Codable, Hashable, Sendable {
    public var setupDone: Bool = false
    public var shuffleMode: Bool = true
    public var wallpaperFit: WallpaperFit = .SMART
    public var wallpaperEffects = WallpaperEffects()
    public var videoPreviewMode: VideoPreviewMode = .AUTOPLAY
    public var autoPause = AutoPauseSettings()
    /// Night (8pm–7am) favours darker images, daytime brighter ones.
    public var matchTimeOfDay: Bool = false
    public var themeMode: ThemeMode = .SYSTEM

    // Content
    public var nsfwMode: Bool = false
    /// Content filter: hides every NSFW feature, locked collections and NSFW images.
    public var nsfwHidden: Bool = false
    public var nsfwBlurEnabled: Bool = true
    /// NSFW-tagged wallpapers never go to the lock screen.
    public var nsfwHomeOnly: Bool = false
    public var globalBlacklist: [String] = []

    // Discover
    public var filters = DiscoverFilters()
    public var discoverBatchSize: Int = 20
    public var discoverDataSaver: Bool = false
    public var forYouEnabled: Bool = true
    public var pinnedSearches: [String] = []
    public var discoverHintSeen: Bool = false

    /// Name of the user's Shortcuts shortcut that Rotato runs for "Set now".
    public var shortcutName: String = "Rotato"

    public init() {}

    /// Effective NSFW mode: always off while the content filter hides NSFW features.
    public var effectiveNsfw: Bool { nsfwMode && !nsfwHidden }
    /// Blur stays on as a safety net while NSFW features are hidden.
    public var effectiveBlur: Bool { nsfwBlurEnabled || nsfwHidden }

    enum CodingKeys: String, CodingKey {
        case setupDone, shuffleMode, wallpaperFit, wallpaperEffects, videoPreviewMode, autoPause, matchTimeOfDay, themeMode
        case nsfwMode, nsfwHidden, nsfwBlurEnabled, nsfwHomeOnly, globalBlacklist
        case filters, discoverBatchSize, discoverDataSaver, forYouEnabled, pinnedSearches, discoverHintSeen
        case shortcutName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RotatoSettings()
        setupDone = c.value(.setupDone, d.setupDone)
        shuffleMode = c.value(.shuffleMode, d.shuffleMode)
        wallpaperFit = c.value(.wallpaperFit, d.wallpaperFit)
        wallpaperEffects = c.value(.wallpaperEffects, d.wallpaperEffects)
        videoPreviewMode = c.value(.videoPreviewMode, d.videoPreviewMode)
        autoPause = c.value(.autoPause, d.autoPause)
        matchTimeOfDay = c.value(.matchTimeOfDay, d.matchTimeOfDay)
        themeMode = c.value(.themeMode, d.themeMode)
        nsfwMode = c.value(.nsfwMode, d.nsfwMode)
        nsfwHidden = c.value(.nsfwHidden, d.nsfwHidden)
        nsfwBlurEnabled = c.value(.nsfwBlurEnabled, d.nsfwBlurEnabled)
        nsfwHomeOnly = c.value(.nsfwHomeOnly, d.nsfwHomeOnly)
        globalBlacklist = c.value(.globalBlacklist, d.globalBlacklist)
        filters = c.value(.filters, d.filters)
        discoverBatchSize = c.value(.discoverBatchSize, d.discoverBatchSize)
        discoverDataSaver = c.value(.discoverDataSaver, d.discoverDataSaver)
        forYouEnabled = c.value(.forYouEnabled, d.forYouEnabled)
        pinnedSearches = c.value(.pinnedSearches, d.pinnedSearches)
        discoverHintSeen = c.value(.discoverHintSeen, d.discoverHintSeen)
        shortcutName = c.value(.shortcutName, d.shortcutName)
    }
}

public struct HistoryItem: Codable, Hashable, Sendable {
    public var thumbUrl: String
    public var sampleUrl: String
    public var fullUrl: String
    public var source: String
    public var timestamp: Int64
    public var tags: [String]
    public var pageUrl: String
    /// Pool file shown, so the widget and "previous" can find it.
    public var poolFile: String
    public var screen: WallpaperScreen

    public init(
        thumbUrl: String, sampleUrl: String = "", fullUrl: String, source: String, timestamp: Int64,
        tags: [String] = [], pageUrl: String = "", poolFile: String, screen: WallpaperScreen
    ) {
        self.thumbUrl = thumbUrl; self.sampleUrl = sampleUrl; self.fullUrl = fullUrl; self.source = source
        self.timestamp = timestamp; self.tags = tags; self.pageUrl = pageUrl; self.poolFile = poolFile; self.screen = screen
    }

    enum CodingKeys: String, CodingKey { case thumbUrl, sampleUrl, fullUrl, source, timestamp, tags, pageUrl, poolFile, screen }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        thumbUrl = c.value(.thumbUrl, "")
        sampleUrl = c.value(.sampleUrl, "")
        fullUrl = c.value(.fullUrl, "")
        source = c.value(.source, "")
        timestamp = c.value(.timestamp, 0)
        tags = c.value(.tags, [])
        pageUrl = c.value(.pageUrl, "")
        poolFile = c.value(.poolFile, "")
        screen = c.value(.screen, .home)
    }
}

public enum RotationErrorType: String, Codable, Sendable {
    case POOL_EMPTY, IMAGE_MISSING, IMAGE_CORRUPT, RENDER_FAILED
}

public struct RotationError: Codable, Hashable, Sendable {
    public var type: RotationErrorType
    public var message: String
    public var timestamp: Int64

    public init(_ type: RotationErrorType, _ message: String, timestamp: Int64 = nowMillis()) {
        self.type = type; self.message = message; self.timestamp = timestamp
    }
}

public enum TagTier: String, Codable, CaseIterable, Sendable {
    case LOVE, LIKE, NEUTRAL, DISLIKE, NEVER
}

/// Rotation bookkeeping and learned signals, written by the app, Shortcuts and the widget.
/// One file, `state.json`.
public struct RotatoState: Codable, Hashable, Sendable {
    public var currentIndex: Int = 0
    /// Sequential mode keeps a separate place in the pool for the lock screen.
    public var lockIndex: Int = 0
    public var history: [HistoryItem] = []
    /// Wallpapers the user picked to show next ("Set now" / "Use next").
    public var queuedNext: [QueuedWallpaper] = []
    /// 1–5 star ratings by pool file name; rated images come up more in shuffle.
    public var ratings: [String: Int] = [:]
    /// Pool files known to be NSFW (the files carry no other metadata).
    public var nsfwFileNames: Set<String> = []
    public var blockedUrls: Set<String> = []
    public var seenKeys: [String] = []
    public var totalRotations: Int64 = 0
    public var lastSkipReason: String?
    public var errors: [RotationError] = []
    /// Learned tag weights for "For you" ordering.
    public var learnedWeights: [String: Double] = [:]
    public var sfwTagTiers: [String: TagTier] = [:]
    public var nsfwTagTiers: [String: TagTier] = [:]

    public init() {}

    public static let historyCap = 200
    public static let seenCap = 2000

    public func current(for screen: WallpaperScreen) -> HistoryItem? {
        history.first { $0.screen == screen }
    }

    enum CodingKeys: String, CodingKey {
        case currentIndex, lockIndex, history, queuedNext, ratings, nsfwFileNames, blockedUrls, seenKeys, totalRotations
        case lastSkipReason, errors, learnedWeights, sfwTagTiers, nsfwTagTiers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currentIndex = c.value(.currentIndex, 0)
        lockIndex = c.value(.lockIndex, 0)
        history = (c.optionalValue(.history) as LossyArray<HistoryItem>?)?.elements ?? []
        queuedNext = c.value(.queuedNext, [])
        ratings = c.value(.ratings, [:])
        nsfwFileNames = c.value(.nsfwFileNames, [])
        blockedUrls = c.value(.blockedUrls, [])
        seenKeys = c.value(.seenKeys, [])
        totalRotations = c.value(.totalRotations, 0)
        lastSkipReason = c.optionalValue(.lastSkipReason)
        errors = c.value(.errors, [])
        learnedWeights = c.value(.learnedWeights, [:])
        sfwTagTiers = c.value(.sfwTagTiers, [:])
        nsfwTagTiers = c.value(.nsfwTagTiers, [:])
    }

    public mutating func addError(_ e: RotationError) {
        errors.insert(e, at: 0)
        if errors.count > 50 { errors.removeLast(errors.count - 50) }
    }

    public mutating func recordShown(_ item: HistoryItem) {
        history.insert(item, at: 0)
        if history.count > Self.historyCap { history.removeLast(history.count - Self.historyCap) }
    }
}
