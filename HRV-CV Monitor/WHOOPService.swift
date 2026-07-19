import Foundation
import Combine
import AppKit
import AuthenticationServices
import CryptoKit
import Security

// MARK: - Configuration
// Your WHOOP Developer App credentials live in the git-ignored Secrets.swift
// (see Secrets.swift.example). Register at: https://developer.whoop.com with
// redirect URI: hrvcv://callback
enum WHOOPConfig {
    static let clientId     = Secrets.whoopClientId
    static let clientSecret = Secrets.whoopClientSecret
    static let redirectURI  = "hrvcv://callback"
    static let authBaseURL  = "https://api.prod.whoop.com/oauth/oauth2/auth"
    static let tokenURL     = "https://api.prod.whoop.com/oauth/oauth2/token"
    static let apiBase      = "https://api.prod.whoop.com/developer/v2"
    static let scopes       = "offline read:recovery"

    // Optional token broker. When non-empty (e.g. "https://your-app.vercel.app/api"),
    // the app posts the auth code / refresh token to your backend, which holds the
    // client secret and talks to WHOOP: so shared builds don't embed the secret.
    // Empty = talk to WHOOP directly using the embedded clientSecret (local/dev).
    static let brokerBaseURL = ""
}

// MARK: - Keychain
enum Keychain {
    private static func query(for key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrAccount as String: key,
         kSecAttrService as String: "com.hrvcv.whoop"]
    }

    static func save(_ value: String, for key: String) {
        guard let data = value.data(using: .utf8) else { return }
        var q = query(for: key)
        SecItemDelete(q as CFDictionary)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load(_ key: String) -> String? {
        var q = query(for: key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete(query(for: key) as CFDictionary)
    }
}

// MARK: - Token Storage
// All tokens live in ONE keychain item, so the OS prompts at most once
// (rather than once per field) to read them.
final class TokenStore {
    static let shared = TokenStore()

    private let key = "whoop_tokens"

    private struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String?
        var expiry: Double        // timeIntervalSince1970
    }

    private var cache: Tokens?
    private var loaded = false

    private func current() -> Tokens? {
        if !loaded {
            loaded = true
            if let json = Keychain.load(key), let data = json.data(using: .utf8) {
                cache = try? JSONDecoder().decode(Tokens.self, from: data)
            }
        }
        return cache
    }

    var accessToken: String?  { current()?.accessToken }
    var refreshToken: String? { current()?.refreshToken }
    var expiry: Date?         { current().map { Date(timeIntervalSince1970: $0.expiry) } }

    var isValid: Bool {
        guard let t = current() else { return false }
        return Date() < Date(timeIntervalSince1970: t.expiry).addingTimeInterval(-300)
    }

    func save(accessToken: String, refreshToken: String?, expiry: Date) {
        let tokens = Tokens(accessToken: accessToken,
                            refreshToken: refreshToken ?? cache?.refreshToken,
                            expiry: expiry.timeIntervalSince1970)
        cache = tokens
        loaded = true
        if let data = try? JSONEncoder().encode(tokens),
           let json = String(data: data, encoding: .utf8) {
            Keychain.save(json, for: key)
        }
    }

    func clear() {
        cache = nil
        loaded = true
        Keychain.delete(key)
    }
}

// MARK: - WHOOP API Models
struct RecoveryCollection: Decodable {
    let records: [Recovery]
}

struct Recovery: Decodable, Identifiable {
    let cycleId: Int
    let createdAt: String
    let scoreState: String
    let score: RecoveryScore?

    var id: Int { cycleId }

    struct RecoveryScore: Decodable {
        let recoveryScore: Int?
        let hrvRmssdMilli: Double?
    }

    enum CodingKeys: String, CodingKey {
        case cycleId = "cycle_id"
        case createdAt = "created_at"
        case scoreState = "score_state"
        case score
    }
}

extension Recovery.RecoveryScore {
    enum CodingKeys: String, CodingKey {
        case recoveryScore = "recovery_score"
        case hrvRmssdMilli = "hrv_rmssd_milli"
    }
}

struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

// MARK: - Auth Errors
enum WHOOPError: LocalizedError {
    case noToken, unauthorized, invalidCallback, tokenRejected(String), network(String)

    var errorDescription: String? {
        switch self {
        case .noToken:              return "Not signed in."
        case .unauthorized:         return "Session expired. Please sign in again."
        case .invalidCallback:      return "OAuth callback was invalid."
        case .tokenRejected(let m): return m
        case .network(let msg):     return msg
        }
    }
}

// MARK: - WHOOP Service
@MainActor
final class WHOOPService: NSObject, ObservableObject {
    static let shared = WHOOPService()

    private let store = TokenStore.shared
    private var authSession: ASWebAuthenticationSession?

    var isAuthenticated: Bool { store.accessToken != nil }

    // MARK: OAuth

    func startAuth() async throws {
        let verifier  = pkceVerifier()
        let challenge = pkceChallenge(from: verifier)
        let state     = UUID().uuidString

        var comps = URLComponents(string: WHOOPConfig.authBaseURL)!
        comps.queryItems = [
            .init(name: "client_id",             value: WHOOPConfig.clientId),
            .init(name: "redirect_uri",           value: WHOOPConfig.redirectURI),
            .init(name: "response_type",          value: "code"),
            .init(name: "scope",                  value: WHOOPConfig.scopes),
            .init(name: "state",                  value: state),
            .init(name: "code_challenge",         value: challenge),
            .init(name: "code_challenge_method",  value: "S256"),
        ]

        // Present WHOOP's login in an in-process auth sheet. It captures the
        // hrvcv://callback redirect directly: no browser tab left hanging, no
        // double-submit, and (ephemeral) no stale WHOOP cookie to trip over.
        let callbackURL: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: comps.url!,
                callbackURLScheme: "hrvcv"
            ) { url, error in
                if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        cont.resume(throwing: CancellationError())   // user closed the sheet
                    } else {
                        cont.resume(throwing: error)
                    }
                } else if let url {
                    cont.resume(returning: url)
                } else {
                    cont.resume(throwing: WHOOPError.invalidCallback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            self.authSession = session
            if !session.start() {
                cont.resume(throwing: WHOOPError.network("Couldn't start the WHOOP sign-in window."))
            }
        }

        let code = try extractCode(from: callbackURL, expectedState: state)
        try await exchangeCode(code, verifier: verifier)
    }

    /// Validates the OAuth callback URL and returns the authorization code.
    private func extractCode(from url: URL, expectedState: String) throws -> String {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw WHOOPError.invalidCallback
        }
        let items = comps.queryItems ?? []

        // WHOOP reported an error instead of a code (e.g. access_denied).
        if let err = items.first(where: { $0.name == "error" })?.value {
            let desc = items.first(where: { $0.name == "error_description" })?.value ?? err
            throw WHOOPError.network("WHOOP authorization failed: \(desc)")
        }
        // Validate state to guard against CSRF / stale callbacks.
        guard let returnedState = items.first(where: { $0.name == "state" })?.value,
              returnedState == expectedState else {
            throw WHOOPError.invalidCallback
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw WHOOPError.invalidCallback
        }
        return code
    }

    private func exchangeCode(_ code: String, verifier: String) async throws {
        let req = WHOOPConfig.brokerBaseURL.isEmpty
            ? directTokenRequest(["grant_type": "authorization_code",
                                  "code": code,
                                  "redirect_uri": WHOOPConfig.redirectURI,
                                  "code_verifier": verifier])
            : brokerRequest(path: "token", json: ["code": code,
                                                  "code_verifier": verifier,
                                                  "redirect_uri": WHOOPConfig.redirectURI])
        let token = try await fetchToken(request: req)
        storeToken(token)
    }

    func refreshIfNeeded() async throws {
        guard !store.isValid else { return }
        guard let refresh = store.refreshToken else { throw WHOOPError.noToken }

        let req = WHOOPConfig.brokerBaseURL.isEmpty
            ? directTokenRequest(["grant_type": "refresh_token", "refresh_token": refresh])
            : brokerRequest(path: "refresh", json: ["refresh_token": refresh])

        do {
            let token = try await fetchToken(request: req)
            storeToken(token)
        } catch let error as WHOOPError {
            if case .tokenRejected = error {
                // Refresh token is expired/revoked: genuine re-auth needed.
                store.clear()
                throw WHOOPError.unauthorized
            }
            throw error   // transient (network / 5xx): keep tokens so a blip doesn't sign us out
        }
    }

    // Direct mode: form-encoded to WHOOP, with the embedded client credentials.
    private func directTokenRequest(_ params: [String: String]) -> URLRequest {
        var req = URLRequest(url: URL(string: WHOOPConfig.tokenURL)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var full = params
        full["client_id"]     = WHOOPConfig.clientId
        full["client_secret"] = WHOOPConfig.clientSecret
        req.httpBody = full.asFormEncoded()
        return req
    }

    // Broker mode: JSON to our backend, which adds the client credentials server-side.
    private func brokerRequest(path: String, json: [String: String]) -> URLRequest {
        var req = URLRequest(url: URL(string: "\(WHOOPConfig.brokerBaseURL)/\(path)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: json)
        return req
    }

    private func fetchToken(request: URLRequest) async throws -> TokenResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WHOOPError.network("No response from WHOOP.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = Self.parseOAuthError(data)
            // 400/401 mean the code/secret/refresh-token was rejected → re-auth.
            if http.statusCode == 400 || http.statusCode == 401 {
                throw WHOOPError.tokenRejected(detail ?? "WHOOP rejected the sign-in request.")
            }
            throw WHOOPError.network(detail ?? "WHOOP returned HTTP \(http.statusCode).")
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw WHOOPError.network("Couldn't read WHOOP's token response.")
        }
    }

    /// Parses an OAuth 2.0 error body: {"error": "...", "error_description": "..."}.
    private static func parseOAuthError(_ data: Data) -> String? {
        struct OAuthError: Decodable {
            let error: String?
            let errorDescription: String?
            enum CodingKeys: String, CodingKey {
                case error
                case errorDescription = "error_description"
            }
        }
        guard let e = try? JSONDecoder().decode(OAuthError.self, from: data) else { return nil }
        if let d = e.errorDescription, !d.isEmpty { return d }
        if let x = e.error, !x.isEmpty { return "WHOOP error: \(x)" }
        return nil
    }

    private func storeToken(_ t: TokenResponse) {
        store.save(accessToken: t.accessToken,
                   refreshToken: t.refreshToken,
                   expiry: Date().addingTimeInterval(Double(t.expiresIn)))
    }

    // MARK: API

    func fetchRecovery(limit: Int = 10) async throws -> [Recovery] {
        try await refreshIfNeeded()
        guard let token = store.accessToken else { throw WHOOPError.noToken }

        var comps = URLComponents(string: "\(WHOOPConfig.apiBase)/recovery")!
        comps.queryItems = [.init(name: "limit", value: "\(min(max(limit, 1), 25))")]  // WHOOP caps limit at 25

        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 401 {
            store.clear()
            throw WHOOPError.unauthorized
        }
        guard (200..<300).contains(status) else {
            throw WHOOPError.network("WHOOP API error (HTTP \(status)).")
        }

        do {
            return try JSONDecoder().decode(RecoveryCollection.self, from: data).records
        } catch {
            throw WHOOPError.network("Couldn't read WHOOP's recovery data.")
        }
    }

    func signOut() { store.clear() }

    // MARK: PKCE

    private func pkceVerifier() -> String {
        var buf = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buf.count, &buf)
        return Data(buf).base64URLEncoded()
    }

    private func pkceChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()
    }
}

// MARK: - Web Auth Presentation
extension WHOOPService: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
        }
    }
}

// MARK: - Helpers
private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension Dictionary where Key == String, Value == String {
    func asFormEncoded() -> Data? {
        map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
    }
}
