import Foundation

public enum PluginProtocol: String, Codable, CaseIterable, Sendable {
    case GELBOORU, DANBOORU, MOEBOORU, WALLHAVEN, REDDIT, ZEROCHAN

    static func from(_ s: String) -> PluginProtocol? {
        allCases.first { $0.rawValue.caseInsensitiveCompare(s) == .orderedSame }
    }
}

public enum PluginAuth: Hashable, Sendable {
    case none
    case apiKey(label: String, required: Bool)
    case apiKeyUserId(keyLabel: String, userLabel: String, required: Bool)
}

public enum ConfigFieldType: String, Codable, Sendable { case TEXT, PASSWORD, URL, TOGGLE, TAGS }

public struct PluginConfigField: Codable, Hashable, Sendable {
    public var key: String
    public var label: String
    public var type: ConfigFieldType
    public var placeholder: String
    public var required: Bool
    public var hint: String
}

/// Declarative description of a wallpaper source, parsed from JSON (bundled or a remote URL).
/// The engine for `protocol` does the fetching. The JSON shape matches the Android app's, so the
/// same plugin store index and manifests work on both.
public struct PluginManifest: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var version: String
    public var author: String
    public var description: String
    public var `protocol`: PluginProtocol
    public var defaultBaseUrl: String
    public var instanceUrlConfigurable: Bool
    public var safeContent: Bool
    public var isPremium: Bool
    public var auth: PluginAuth
    /// URL this manifest was loaded from; nil for bundled manifests.
    public var sourceUrl: String?
    /// Protocol-specific options engines read to handle API variants.
    public var extras: [String: String]
    public var versionCode: Int
    public var configFields: [PluginConfigField]
    /// Maximum number of tags this source supports in a single query.
    public var maxTagCount: Int

    /// Adult-only sites (Rule34): their "safe" ratings aren't reliable, so they never load with NSFW off.
    public var adultOnly: Bool { extras["adultOnly"] == "true" || id == "RULE34" }

    public var needsApiKey: Bool {
        switch auth { case .none: false; default: true }
    }

    public var needsApiUser: Bool {
        if case .apiKeyUserId = auth { return true }
        return false
    }

    public var apiKeyLabel: String {
        switch auth {
        case .apiKey(let label, _): label
        case .apiKeyUserId(let keyLabel, _, _): keyLabel
        case .none: "API Key"
        }
    }

    public var apiUserLabel: String {
        if case .apiKeyUserId(_, let userLabel, _) = auth { return userLabel }
        return "User ID"
    }

    public var requiresCredentials: Bool {
        switch auth {
        case .apiKey(_, let r): r
        case .apiKeyUserId(_, _, let r): r
        case .none: false
        }
    }

    /// Reddit sources are per-subreddit rows instead of one row per plugin.
    public var isMultiInstance: Bool { `protocol` == .REDDIT }

    // MARK: JSON

    enum CodingKeys: String, CodingKey {
        case id, name, version, author, description, `protocol`, defaultBaseUrl, instanceUrlConfigurable
        case safeContent, isPremium, auth, sourceUrl, extras, versionCode, configFields, maxTagCount
    }

    enum AuthKeys: String, CodingKey { case type, keyLabel, userLabel, required }
    enum FieldKeys: String, CodingKey { case key, label, type, placeholder, required, hint }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        guard !id.isBlank, !name.isBlank,
              let proto = PluginProtocol.from(c.value(.protocol, "")) else {
            throw DecodingError.dataCorruptedError(forKey: .protocol, in: c, debugDescription: "Unknown protocol")
        }
        `protocol` = proto
        defaultBaseUrl = c.value(.defaultBaseUrl, "")
        if defaultBaseUrl.isBlank {
            throw DecodingError.dataCorruptedError(forKey: .defaultBaseUrl, in: c, debugDescription: "Missing base URL")
        }
        version = c.value(.version, "1.0")
        author = c.value(.author, "Unknown")
        description = c.value(.description, "")
        instanceUrlConfigurable = c.value(.instanceUrlConfigurable, false)
        safeContent = c.value(.safeContent, true)
        isPremium = c.value(.isPremium, false)
        sourceUrl = (c.optionalValue(.sourceUrl) as String?)?.nilIfBlank
        extras = Self.decodeExtras(c)
        versionCode = c.value(.versionCode, 1)
        maxTagCount = c.value(.maxTagCount, Int.max)

        if let a = try? c.nestedContainer(keyedBy: AuthKeys.self, forKey: .auth) {
            let required = a.value(.required, false)
            switch a.value(.type, "none") {
            case "api_key":
                auth = .apiKey(label: a.value(.keyLabel, "API Key"), required: required)
            case "api_key_user_id":
                auth = .apiKeyUserId(keyLabel: a.value(.keyLabel, "API Key"), userLabel: a.value(.userLabel, "User ID"), required: required)
            default:
                auth = .none
            }
        } else {
            auth = .none
        }

        var fields: [PluginConfigField] = []
        if var arr = try? c.nestedUnkeyedContainer(forKey: .configFields) {
            while !arr.isAtEnd {
                guard let f = try? arr.nestedContainer(keyedBy: FieldKeys.self) else { break }
                let key = f.value(.key, ""), label = f.value(.label, "")
                guard !key.isBlank, !label.isBlank else { continue }
                fields.append(PluginConfigField(
                    key: key, label: label,
                    type: ConfigFieldType(rawValue: f.value(.type, "TEXT").uppercased()) ?? .TEXT,
                    placeholder: f.value(.placeholder, ""), required: f.value(.required, false), hint: f.value(.hint, "")
                ))
            }
        }
        configFields = fields
    }

    /// Extras are strings in the Android format, but tolerate numbers and booleans too.
    private static func decodeExtras(_ c: KeyedDecodingContainer<CodingKeys>) -> [String: String] {
        guard let raw = try? c.decodeIfPresent([String: JSONScalar].self, forKey: .extras) else { return [:] }
        return raw.mapValues(\.stringValue)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(version, forKey: .version)
        try c.encode(author, forKey: .author)
        try c.encode(description, forKey: .description)
        try c.encode(`protocol`.rawValue, forKey: .protocol)
        try c.encode(defaultBaseUrl, forKey: .defaultBaseUrl)
        try c.encode(instanceUrlConfigurable, forKey: .instanceUrlConfigurable)
        try c.encode(safeContent, forKey: .safeContent)
        try c.encode(isPremium, forKey: .isPremium)
        var a = c.nestedContainer(keyedBy: AuthKeys.self, forKey: .auth)
        switch auth {
        case .none:
            try a.encode("none", forKey: .type)
        case .apiKey(let label, let required):
            try a.encode("api_key", forKey: .type)
            try a.encode(label, forKey: .keyLabel)
            try a.encode(required, forKey: .required)
        case .apiKeyUserId(let keyLabel, let userLabel, let required):
            try a.encode("api_key_user_id", forKey: .type)
            try a.encode(keyLabel, forKey: .keyLabel)
            try a.encode(userLabel, forKey: .userLabel)
            try a.encode(required, forKey: .required)
        }
        try c.encodeIfPresent(sourceUrl, forKey: .sourceUrl)
        if !extras.isEmpty { try c.encode(extras, forKey: .extras) }
        try c.encode(versionCode, forKey: .versionCode)
        if maxTagCount != Int.max { try c.encode(maxTagCount, forKey: .maxTagCount) }
        if !configFields.isEmpty { try c.encode(configFields, forKey: .configFields) }
    }
}

/// A JSON string, number or bool read as a string.
struct JSONScalar: Decodable {
    let stringValue: String

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { stringValue = s }
        else if let b = try? c.decode(Bool.self) { stringValue = b ? "true" : "false" }
        else if let i = try? c.decode(Int.self) { stringValue = String(i) }
        else if let d = try? c.decode(Double.self) { stringValue = String(d) }
        else { stringValue = "" }
    }
}

/// The user's configuration for one installed plugin (LocalSource on Android).
public struct SourceConfig: Codable, Hashable, Identifiable, Sendable {
    public var pluginId: String
    /// For multi-instance sources (Reddit): the subreddit name. Empty for all other sources.
    public var instanceId: String
    public var enabled: Bool
    public var apiKey: String
    public var apiUser: String
    public var tags: String
    /// Wallhaven only: purity bitmask string (sfw/sketchy/nsfw).
    public var wallhavenPurity: String
    /// nil follows the global NSFW mode; false forces this source SFW.
    public var nsfwEnabled: Bool?
    /// Optional base URL override. Blank = use manifest default.
    public var baseUrl: String
    public var extraConfig: [String: String]

    public init(
        pluginId: String, instanceId: String = "", enabled: Bool = false, apiKey: String = "", apiUser: String = "",
        tags: String = "", wallhavenPurity: String = "110", nsfwEnabled: Bool? = nil, baseUrl: String = "",
        extraConfig: [String: String] = [:]
    ) {
        self.pluginId = pluginId; self.instanceId = instanceId; self.enabled = enabled; self.apiKey = apiKey
        self.apiUser = apiUser; self.tags = tags; self.wallhavenPurity = wallhavenPurity
        self.nsfwEnabled = nsfwEnabled; self.baseUrl = baseUrl; self.extraConfig = extraConfig
    }

    public var id: String { "\(pluginId):\(instanceId)" }

    enum CodingKeys: String, CodingKey {
        case pluginId, type, instanceId, enabled, apiKey, apiUser, tags, wallhavenPurity, nsfwEnabled, baseUrl, extraConfig
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Older Android backups stored "type" instead of "pluginId".
        let pid = c.value(.pluginId, "").ifBlank(c.value(.type, ""))
        guard !pid.isBlank else {
            throw DecodingError.dataCorruptedError(forKey: .pluginId, in: c, debugDescription: "Missing pluginId")
        }
        pluginId = pid
        instanceId = c.value(.instanceId, "")
        enabled = c.value(.enabled, false)
        apiKey = c.value(.apiKey, "")
        apiUser = c.value(.apiUser, "")
        tags = c.value(.tags, "")
        wallhavenPurity = c.value(.wallhavenPurity, "110")
        if let b: Bool = c.optionalValue(.nsfwEnabled) { nsfwEnabled = b }
        else if let s: String = c.optionalValue(.nsfwEnabled) { nsfwEnabled = Bool(s) }
        else { nsfwEnabled = nil }
        baseUrl = c.value(.baseUrl, "")
        extraConfig = c.value(.extraConfig, [:])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pluginId, forKey: .pluginId)
        try c.encode(instanceId, forKey: .instanceId)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(apiKey, forKey: .apiKey)
        try c.encode(apiUser, forKey: .apiUser)
        try c.encode(tags, forKey: .tags)
        try c.encode(wallhavenPurity, forKey: .wallhavenPurity)
        try c.encode(nsfwEnabled, forKey: .nsfwEnabled)
        if !baseUrl.isBlank { try c.encode(baseUrl, forKey: .baseUrl) }
        if !extraConfig.isEmpty { try c.encode(extraConfig, forKey: .extraConfig) }
    }
}

/// An entry in a plugin store index.
public struct PluginStoreEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var description: String
    public var author: String
    public var version: String
    public var versionCode: Int
    public var manifestUrl: String
    public var tags: [String]
    public var isBundled: Bool
    public var safeContent: Bool
    /// Index URL and display name of the store this entry came from (set after fetching).
    public var storeSource: String = ""
    public var storeName: String = ""

    enum CodingKeys: String, CodingKey {
        case id, name, description, author, version, versionCode, manifestUrl, tags, isBundled, safeContent, storeSource, storeName
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        manifestUrl = try c.decode(String.self, forKey: .manifestUrl)
        guard !id.isBlank, !manifestUrl.isBlank else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Missing id or manifestUrl")
        }
        name = c.value(.name, id)
        description = c.value(.description, "")
        author = c.value(.author, "Unknown")
        version = c.value(.version, "1.0")
        versionCode = c.value(.versionCode, 1)
        tags = c.value(.tags, [])
        isBundled = c.value(.isBundled, PluginCatalog.bundledIds.contains(id))
        safeContent = c.value(.safeContent, true)
        storeSource = c.value(.storeSource, "")
        storeName = c.value(.storeName, "")
    }
}
