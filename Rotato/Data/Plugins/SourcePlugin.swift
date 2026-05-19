import Foundation

protocol SourcePlugin: Sendable {
    var id: String { get }
    var displayName: String { get }
    var sfSymbol: String { get }
    var requiresApiKey: Bool { get }
    var supportsSearch: Bool { get }

    func fetch(query: String, page: Int, config: SourceConfig, nsfw: Bool) async throws -> [WallpaperItem]
}

enum SourceError: LocalizedError {
    case networkError(Error)
    case badStatus(Int)
    case decodingError
    case unauthorized
    case noResults
    case invalidConfig(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let e): return "Network error: \(e.localizedDescription)"
        case .badStatus(let code): return "Server returned \(code)"
        case .decodingError: return "Failed to parse response"
        case .unauthorized: return "Invalid API key"
        case .noResults: return "No results found"
        case .invalidConfig(let msg): return msg
        }
    }
}

extension URLSession {
    func decodedData<T: Decodable>(_ type: T.Type, from request: URLRequest) async throws -> T {
        let (data, response) = try await data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            throw SourceError.unauthorized
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SourceError.badStatus(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw SourceError.decodingError
        }
    }
}

// MARK: - Shared helpers

func browserRequest(url: URL) -> URLRequest {
    var r = URLRequest(url: url)
    r.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
    return r
}

func normalizeBooruQuery(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespaces)
        .components(separatedBy: .whitespaces)
        .filter { !$0.isEmpty }
        .map { $0.replacingOccurrences(of: " ", with: "_") }
        .joined(separator: " ")
}
