import Foundation

// MARK: - Admin Session Storage

/// Stored in Keychain when starting impersonation, used to restore admin session when stopping
struct AdminSession: Codable {
    let accessToken: String
    let refreshToken: String
    let userId: String
}

// MARK: - API Response Models

/// Response from POST /functions/v1/impersonation/start
struct ImpersonationStartResponse: Decodable {
    let ok: Bool
    let error: String?
    let impersonated: ImpersonatedSession?
    let session: ImpersonationSessionInfo?
}

/// The session tokens for the impersonated user
struct ImpersonatedSession: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let tokenType: String
    let user: ImpersonatedUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case user
    }
}

/// Basic user info returned with impersonation session
struct ImpersonatedUser: Decodable {
    let id: String
    let email: String?
    let userMetadata: ImpersonatedUserMetadata?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case userMetadata = "user_metadata"
    }

    /// Display name extracted from metadata
    var displayName: String {
        userMetadata?.fullName ?? userMetadata?.name ?? email ?? String(id.prefix(8)) + "..."
    }
}

/// User metadata structure
struct ImpersonatedUserMetadata: Decodable {
    let fullName: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case name
    }
}

/// Info about the impersonation session stored in the database
struct ImpersonationSessionInfo: Decodable {
    let id: String
    let adminUserId: String
    let targetUserId: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case adminUserId = "admin_user_id"
        case targetUserId = "target_user_id"
        case expiresAt = "expires_at"
    }

    /// Parse the ISO8601 date string to a Date
    var expiresAtDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: expiresAt) {
            return date
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: expiresAt)
    }
}

/// Response from POST /functions/v1/impersonation/stop
struct ImpersonationStopResponse: Decodable {
    let ok: Bool
    let error: String?
    let session: EndedSessionInfo?
}

/// Info about the ended session
struct EndedSessionInfo: Decodable {
    let id: String
    let endedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case endedAt = "ended_at"
    }
}

// MARK: - Result Types

/// Result of a successful impersonation start
struct ImpersonationResult {
    let sessionId: String
    let targetUser: ImpersonatedUser
    let expiresAt: Date?
}

// MARK: - Errors

enum ImpersonationError: Error, LocalizedError {
    case notAuthenticated
    case notAdmin
    case noActiveSession
    case adminSessionNotFound
    case serverError(String)
    case reasonTooShort

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be logged in to impersonate"
        case .notAdmin:
            return "Admin privileges required"
        case .noActiveSession:
            return "No active impersonation session"
        case .adminSessionNotFound:
            return "Could not restore admin session"
        case .serverError(let message):
            return message
        case .reasonTooShort:
            return "Reason must be at least 5 characters"
        }
    }
}

