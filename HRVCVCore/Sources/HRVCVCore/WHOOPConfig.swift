import Foundation

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
    static let scopes       = "offline read:recovery read:sleep"

    // Optional token broker. When non-empty (e.g. "https://your-app.vercel.app/api"),
    // the app posts the auth code / refresh token to your backend, which holds the
    // client secret and talks to WHOOP: so shared builds don't embed the secret.
    // Empty = talk to WHOOP directly using the embedded clientSecret (local/dev).
    static let brokerBaseURL = ""
}
