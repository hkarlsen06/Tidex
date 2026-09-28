import Foundation
import Supabase

// Response types for the admin RPCs in AdminAPI.

// MARK: - Models

/// Parses the Postgres timestamps the admin RPCs return.
private func adminDate(_ value: String?) -> Date? {
  value.flatMap(ISO8601Timestamp.date(from:))
}

struct AdminUser: Decodable, Identifiable, Hashable, Sendable {
  let id: String
  let email: String?
  let phone: String?
  let name: String?
  let lastSignInAt: String?
  let createdAt: String
  var isBanned: Bool
  var isAdmin: Bool
  let isSuperAdmin: Bool
  /// "no" or "en", the language this user gets broadcasts in.
  var language: String?
  var lastActiveAt: String?

  var broadcastLanguage: AdminLanguage { language == "no" ? .norwegian : .english }

  var displayName: String {
    [name, email, phone].lazy.compactMap { $0?.nilIfBlank }.first ?? String(id.prefix(8))
  }

  /// Email or phone, when it adds something the display name doesn't show.
  var contact: String? {
    [email, phone].lazy.compactMap { $0?.nilIfBlank }.first { $0 != displayName }
  }

  var lastSignIn: Date? { adminDate(lastSignInAt) }
  var lastActive: Date? { adminDate(lastActiveAt) }
  var created: Date? { adminDate(createdAt) }
}

/// Matches `p_sort` in `admin_list_users_api`.
enum AdminUserSort: String, CaseIterable, Identifiable, Sendable {
  case name
  case newest
  case lastSignIn = "last_sign_in"
  case lastActive = "last_active"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .name: return "Name"
    case .newest: return "Signed up"
    case .lastSignIn: return "Last sign-in"
    case .lastActive: return "Last active"
    }
  }
}

/// Matches `p_filter` in `admin_list_users_api`.
enum AdminUserFilter: String, CaseIterable, Identifiable, Sendable {
  case all
  case active
  case new
  case admins
  case banned
  case norwegian
  case english

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all: return "All users"
    case .active: return "Active in last 7 days"
    case .new: return "Signed up in last 7 days"
    case .admins: return "Admins"
    case .banned: return "Banned"
    case .norwegian: return "Norwegian"
    case .english: return "English"
    }
  }
}

/// Broadcast languages. Users with a Norwegian locale get Norwegian; everyone else gets English.
enum AdminLanguage: String, CaseIterable, Identifiable, Sendable {
  case english = "en"
  case norwegian = "no"

  var id: String { rawValue }

  var title: String { self == .english ? "English" : "Norwegian" }
  var code: String { self == .english ? "EN" : "NO" }
}

struct AdminUsersPage: Decodable, Sendable {
  let users: [AdminUser]
  let totalCount: Int
}

struct AdminFeedback: Decodable, Identifiable, Hashable, Sendable {
  let id: String
  let userId: String
  let message: String
  let userEmail: String
  let userName: String?
  let userProfilePicture: String?
  let createdAt: String
  let response: String?
  let respondedAt: String?

  var senderName: String { userName?.nilIfBlank ?? userEmail }
  var isAnswered: Bool { response?.nilIfBlank != nil }
  var created: Date? { adminDate(createdAt) }
  var responded: Date? { adminDate(respondedAt) }
}

struct AdminFeedbackPage: Decodable, Sendable {
  let feedback: [AdminFeedback]
}

enum AdminReportStatus: String, Decodable, CaseIterable, Identifiable, Sendable {
  case open
  case inReview = "in_review"
  case actioned
  case dismissed

  var id: String { rawValue }

  var title: String {
    switch self {
    case .open: return "Open"
    case .inReview: return "In review"
    case .actioned: return "Actioned"
    case .dismissed: return "Dismissed"
    }
  }
}

struct AdminReport: Decodable, Identifiable, Hashable, Sendable {
  let id: String
  let reporterUserId: String
  let reporterName: String?
  let reporterEmail: String?
  let reportedUserId: String
  let reportedName: String?
  let reportedEmail: String?
  let threadId: String
  let messageId: String?
  let reason: String
  let note: String?
  let status: AdminReportStatus
  let reviewerNotes: String?
  let reviewedAt: String?
  let createdAt: String

  var reporterDisplayName: String {
    reporterName?.nilIfBlank ?? reporterEmail ?? String(reporterUserId.prefix(8))
  }

  var reportedDisplayName: String {
    reportedName?.nilIfBlank ?? reportedEmail ?? String(reportedUserId.prefix(8))
  }

  var reasonTitle: String { reason.adminHumanized }
  var created: Date? { adminDate(createdAt) }
  var reviewed: Date? { adminDate(reviewedAt) }
}

struct AdminReportsPage: Decodable, Sendable {
  let reports: [AdminReport]
  let total: Int
}

struct AdminAuditEntry: Decodable, Identifiable, Hashable, Sendable {
  let id: String
  let adminEmail: String?
  let action: String
  let targetUserId: String?
  let targetEmail: String?
  let metadata: [String: AnyJSON]?
  let createdAt: String

  var created: Date? { adminDate(createdAt) }

  struct Detail: Hashable {
    let key: String
    let value: String
  }

  /// Metadata as sorted key/value text, skipping nulls.
  var metadataRows: [Detail] {
    (metadata ?? [:])
      .filter { $0.value != .null }
      .map {
        Detail(key: $0.key.adminHumanized, value: $0.value.stringValue ?? $0.value.description)
      }
      .sorted { $0.key < $1.key }
  }
}

struct AdminAuditPage: Decodable, Sendable {
  let entries: [AdminAuditEntry]?
}

struct AdminShare: Decodable, Identifiable, Hashable, Sendable {
  let id: String
  let ownerId: String
  let ownerEmail: String?
  let ownerName: String?
  let viewerId: String
  let viewerEmail: String?
  let viewerName: String?
  let createdAt: String
  let showEarnings: Bool
  let blocked: Bool
  let muted: Bool

  var ownerDisplayName: String { ownerName?.nilIfBlank ?? ownerEmail ?? String(ownerId.prefix(8)) }
  var viewerDisplayName: String {
    viewerName?.nilIfBlank ?? viewerEmail ?? String(viewerId.prefix(8))
  }
  var created: Date? { adminDate(createdAt) }
}

struct AdminSharesPage: Decodable, Sendable {
  let shares: [AdminShare]?
  let totalCount: Int?
}

struct AdminBroadcast: Decodable, Identifiable, Hashable, Sendable {
  let id: String
  let title: String
  let body: String
  let target: String
  let targetCount: Int
  let status: String
  let createdAt: String
  let sentCount: Int
  let failedCount: Int
  let pendingCount: Int

  var created: Date? { adminDate(createdAt) }
}

struct AdminBroadcastDetail: Decodable, Sendable {
  let id: String
  let title: String?
  let body: String?
  let deeplink: String?
  let titleNo: String?
  let bodyNo: String?
  let deeplinkNo: String?
  let target: String
  let targetCount: Int
  let status: String
  let createdAt: String
  let adminEmail: String?
  let recipients: [Recipient]

  /// One delivery row. The server deletes sent rows after 30 days and the rest after 6 weeks.
  struct Recipient: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let userId: String
    let name: String?
    let email: String?
    let phone: String?
    let status: String
    let title: String
    let deeplink: String?
    let attempts: Int
    let errorMessage: String?
    let processedAt: String?

    var displayName: String {
      [name, email, phone].lazy.compactMap { $0?.nilIfBlank }.first ?? String(userId.prefix(8))
    }

    var processed: Date? { adminDate(processedAt) }
  }

  var created: Date? { adminDate(createdAt) }
}

struct AdminBroadcastPage: Decodable, Sendable {
  let broadcasts: [AdminBroadcast]
}

struct AdminCount: Decodable, Sendable {
  let count: Int
}

// MARK: - Helpers

extension String {
  var nilIfBlank: String? {
    trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
  }

  /// "shift_share_created" becomes "Shift share created".
  var adminHumanized: String {
    let words: String = replacingOccurrences(of: "_", with: " ")
    return words.prefix(1).uppercased() + words.dropFirst()
  }
}
