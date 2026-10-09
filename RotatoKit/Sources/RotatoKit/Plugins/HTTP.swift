import Foundation

/// Networking shared by the engines and downloads. Booru APIs answer browser user agents most
/// reliably, and some CDNs want a Referer from their own site.
public enum HTTP {
    public static let browserUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    public static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.httpAdditionalHeaders = ["User-Agent": browserUA]
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// Headers an image host needs: Danbooru and Gelbooru CDNs refuse hotlinks without a Referer.
    public static func imageHeaders(for url: String) -> [String: String] {
        if url.contains("donmai.us") { return ["Referer": "https://danbooru.donmai.us/"] }
        if url.contains("gelbooru.com") { return ["Referer": "https://gelbooru.com/"] }
        if url.contains("zerochan.net") { return ["Referer": "https://www.zerochan.net/"] }
        return [:]
    }

    public static func request(_ url: String, headers: [String: String] = [:]) -> URLRequest? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        return req
    }

    /// Body of a successful (2xx) response, or nil.
    public static func data(_ url: String, headers: [String: String] = [:]) async -> (Data, HTTPURLResponse)? {
        guard let req = request(url, headers: headers) else { return nil }
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            return (data, http)
        } catch {
            return nil
        }
    }

    public static func json(_ url: String, headers: [String: String] = [:]) async -> Any? {
        guard let (data, _) = await data(url, headers: headers) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    public static func jsonObject(_ url: String, headers: [String: String] = [:]) async -> [String: Any]? {
        await json(url, headers: headers) as? [String: Any]
    }

    public static func jsonArray(_ url: String, headers: [String: String] = [:]) async -> [[String: Any]]? {
        await json(url, headers: headers) as? [[String: Any]]
    }
}

extension String {
    /// Percent-encodes for a query value (URLEncoder.encode semantics, spaces as %20).
    var urlEncoded: String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

/// Loose accessors over JSONSerialization output, mirroring org.json's optX().
extension Dictionary where Key == String, Value == Any {
    func str(_ key: String) -> String {
        switch self[key] {
        case let s as String: s
        case let n as NSNumber: n.stringValue
        default: ""
        }
    }

    func int(_ key: String) -> Int {
        switch self[key] {
        case let n as NSNumber: n.intValue
        case let s as String: Int(s) ?? 0
        default: 0
        }
    }

    func bool(_ key: String) -> Bool {
        switch self[key] {
        case let n as NSNumber: n.boolValue
        case let s as String: s == "true"
        default: false
        }
    }

    func obj(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
    func arr(_ key: String) -> [Any]? { self[key] as? [Any] }
    func objs(_ key: String) -> [[String: Any]]? { (self[key] as? [Any])?.compactMap { $0 as? [String: Any] } }
}

/// Normalises a free-text anime title into a single booru compound tag: lowercase, spaces become
/// underscores, punctuation kept ("Fate/Zero" → "fate/zero"). A leading "-" or "~" is dropped.
public func normalizeBooruQuery(_ q: String) -> String {
    var s = q.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    s = String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(Character.init))
    s = s.replacingOccurrences(of: "\\s+", with: "_", options: .regularExpression)
    s = s.replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
    s = s.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    while let f = s.first, f == "-" || f == "~" { s.removeFirst() }
    return s
}

/// Normalises a user search query for booru APIs. Tokens stay space-separated (ANDed tags); each
/// is lowercased with control characters removed and trailing underscores trimmed. "-tag"
/// excludes, "~tag" ORs and "*" wildcards are kept.
public func normalizeUserQuery(_ q: String) -> String {
    q.trimmingCharacters(in: .whitespacesAndNewlines)
        .split(whereSeparator: { $0.isWhitespace })
        .map { token -> String in
            var t = String(String(token).lowercased().unicodeScalars
                .filter { !CharacterSet.controlCharacters.contains($0) }.map(Character.init))
            while t.hasSuffix("_") { t.removeLast() }
            return t
        }
        .filter { !$0.isBlank && $0 != "-" && $0 != "~" }
        .joined(separator: " ")
}

func queryTokens(_ q: String) -> [String] {
    normalizeUserQuery(q).split(separator: " ").map(String.init).filter { !$0.isEmpty }
}

func unescapeHTML(_ s: String) -> String {
    s.replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
}
