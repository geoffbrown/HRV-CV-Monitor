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
        let restingHeartRate: Double?
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
        case restingHeartRate = "resting_heart_rate"
    }
}

struct SleepCollection: Decodable {
    let records: [Sleep]
}

public struct Sleep: Decodable {
    let createdAt: String
    let nap: Bool
    let scoreState: String
    let score: SleepScore?

    struct SleepScore: Decodable {
        // WHOOP's own night-to-night sleep consistency score (0-100): how
        // similar sleep/wake timing has been, distinct from duration or
        // performance. This is what we average for the "Sleep consistency"
        // signal, rather than deriving our own duration-variability metric.
        let sleepConsistencyPercentage: Double?
    }

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case nap
        case scoreState = "score_state"
        case score
    }
}

extension Sleep.SleepScore {
    enum CodingKeys: String, CodingKey {
        case sleepConsistencyPercentage = "sleep_consistency_percentage"
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
