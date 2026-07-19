import Foundation
import Security

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
