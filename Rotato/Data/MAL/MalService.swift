import Foundation
import AuthenticationServices
import CryptoKit

@MainActor
final class MalService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = MalService()

    private let clientId = "REPLACE_WITH_MAL_CLIENT_ID"
    private let redirectURI = "rotato://callback"

    // MARK: - OAuth2 PKCE

    func buildAuthURL(settings: AppSettings) -> URL? {
        let verifier = generateCodeVerifier()
        settings.malCodeVerifier = verifier
        let challenge = codeChallenge(from: verifier)

        var comps = URLComponents(string: "https://myanimelist.net/v1/oauth2/authorize")!
        comps.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        return comps.url
    }

    func authenticate(settings: AppSettings) async throws {
        guard let authURL = buildAuthURL(settings: settings) else { throw URLError(.badURL) }
        guard let callbackURL = try? await withCheckedThrowingContinuation({ (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "rotato") { url, error in
                if let url { cont.resume(returning: url) }
                else { cont.resume(throwing: error ?? URLError(.cancelled)) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }) else { throw URLError(.cancelled) }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw URLError(.badServerResponse) }

        try await exchangeCode(code: code, settings: settings)
    }

    private func exchangeCode(code: String, settings: AppSettings) async throws {
        var request = URLRequest(url: URL(string: "https://myanimelist.net/v1/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": clientId,
            "code": code,
            "code_verifier": settings.malCodeVerifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
         .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let tokenResp = try JSONDecoder().decode(MalTokenResponse.self, from: data)
        settings.malAccessToken = tokenResp.access_token
        settings.malRefreshToken = tokenResp.refresh_token
    }

    func refreshToken(settings: AppSettings) async throws {
        var request = URLRequest(url: URL(string: "https://myanimelist.net/v1/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "client_id": clientId,
            "grant_type": "refresh_token",
            "refresh_token": settings.malRefreshToken,
        ].map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let tokenResp = try JSONDecoder().decode(MalTokenResponse.self, from: data)
        settings.malAccessToken = tokenResp.access_token
        settings.malRefreshToken = tokenResp.refresh_token
    }

    // MARK: - Anime list

    func fetchAnimeList(settings: AppSettings) async throws -> [String] {
        guard !settings.malAccessToken.isEmpty else { throw URLError(.userAuthenticationRequired) }
        guard !settings.malFilterStatuses.isEmpty else { return [] }

        var allTitles: [String] = []
        for status in settings.malFilterStatuses {
            var page = 0
            var nextURL: String? = "https://api.myanimelist.net/v2/users/@me/animelist?status=\(status)&fields=list_status&limit=500"
            while let urlStr = nextURL {
                guard let url = URL(string: urlStr) else { break }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(settings.malAccessToken)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: request)
                if (response as? HTTPURLResponse)?.statusCode == 401 {
                    try await refreshToken(settings: settings)
                    request.setValue("Bearer \(settings.malAccessToken)", forHTTPHeaderField: "Authorization")
                    let (retryData, _) = try await URLSession.shared.data(for: request)
                    let decoded = try JSONDecoder().decode(MalAnimeListResponse.self, from: retryData)
                    let minScore = settings.malMinScore
                    allTitles += decoded.data
                        .filter { ($0.list_status?.score ?? 0) >= minScore }
                        .map { $0.node.title }
                    nextURL = nil
                    continue
                }
                let decoded = try JSONDecoder().decode(MalAnimeListResponse.self, from: data)
                let minScore = settings.malMinScore
                allTitles += decoded.data
                    .filter { ($0.list_status?.score ?? 0) >= minScore }
                    .map { $0.node.title }
                nextURL = decoded.paging?.next
                page += 1
                if page > 10 { break }
            }
        }
        return allTitles.uniqued()
    }

    // MARK: - PKCE helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func codeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let digest = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // ASWebAuthenticationSession calls this on the main thread; DispatchQueue.main.sync
        // from main deadlocks. MainActor.assumeIsolated safely asserts we're already on main.
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

private struct MalTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String
}

private struct MalAnimeListResponse: Decodable {
    let data: [MalEntry]
    let paging: MalPaging?
}

private struct MalEntry: Decodable {
    let node: MalNode
    let list_status: MalListStatus?
}

private struct MalNode: Decodable {
    let title: String
}

private struct MalListStatus: Decodable {
    let score: Int?
}

private struct MalPaging: Decodable {
    let next: String?
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
