import Foundation

// MARK: - API Response Models

/// Response from `impersonation:start`
struct ImpersonationStartResponse: Decodable {
  let ok: Bool
  let session: ImpersonationSessionInfo?
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

// MARK: - Result Types

/// Result of a successful impersonation start
struct ImpersonationResult {
  let sessionId: String
  let targetName: String
  let expiresAt: Date?
}

// MARK: - Errors

enum ImpersonationError: Error, LocalizedError {
  case notAuthenticated
  case notAdmin
  case noActiveSession
  case serverError(String)
  case reasonTooShort

  /// Uses the server's message for a Convex error, such as a rate limit or a missing admin role.
  init(_ error: Error) {
    if case ConvexAPI.Failure.server(_, let message) = error {
      self = .serverError(message)
    } else if let error = error as? Self {
      self = error
    } else {
      self = .serverError(error.localizedDescription)
    }
  }

  var errorDescription: String? {
    switch self {
    case .notAuthenticated:
      return "You must be logged in to impersonate"

    case .notAdmin:
      return "Admin privileges required"

    case .noActiveSession:
      return "No active impersonation session"

    case .serverError(let message):
      return message

    case .reasonTooShort:
      return "Reason must be at least 5 characters"
    }
  }
}
