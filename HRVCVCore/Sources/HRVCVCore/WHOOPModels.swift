import Foundation

// MARK: - WHOOP API Models
struct RecoveryCollection: Decodable {
    let records: [Recovery]
}

public struct Recovery: Decodable {
    let cycleId: Int
    let createdAt: String
    let scoreState: String
    let score: RecoveryScore?

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
public enum WHOOPError: LocalizedError {
    case noToken, unauthorized, invalidCallback, tokenRejected(String), network(String)

    public var errorDescription: String? {
        switch self {
        case .noToken:              return "Not signed in."
        case .unauthorized:         return "Session expired. Please sign in again."
        case .invalidCallback:      return "OAuth callback was invalid."
        case .tokenRejected(let m): return m
        case .network(let msg):     return msg
        }
    }
}
