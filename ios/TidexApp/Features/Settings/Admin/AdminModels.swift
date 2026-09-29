import Foundation
import Supabase

// Response types for the admin RPCs in AdminAPI.

// MARK: - Models

/// Parses the Postgres timestamps the admin RPCs return.
private func adminDate(_ value: String?) -> Date? {
  value.flatMap(ISO8601Timestamp.date(from:))
}

/// Parses a Postgres `date` such as "2026-09-28" as midnight in the device's time zone.
private func adminDay(_ value: String?) -> Date? {
  guard let value else { return nil }
  return try? Date.ISO8601FormatStyle(timeZone: .current).year().month().day().parse(value)
}

/// "3.2 (146)", or whichever part is present.
private func adminVersion(_ version: String?, _ build: String?) -> String? {
  let text: String = [version, build.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
  return text.isEmpty ? nil : text
}

struct AdminUser: Decodable, Identifiable, Hashable, Sendable {
  let id: String
  let email: String?
  let phone: String?
  let name: String?
  let avatarUrl: String?
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

/// Usage numbers from `admin_get_user_stats_api`. Deleted shifts, jobs and messages are excluded.
struct AdminUserStats: Decodable, Sendable {
  let shiftCount: Int
  let shiftsLast30Days: Int
  let upcomingShiftCount: Int
  let firstShiftDate: String?
  let latestShiftDate: String?
  let lastShiftAddedAt: String?
  let jobCount: Int
  let recurringScheduleCount: Int
  let eventCount: Int
  let sharesTheirShiftsWith: Int
  let seesShiftsFrom: Int
  let messagesSent: Int
  let messagesLast30Days: Int
  let feedbackCount: Int
  let reportsFiled: Int
  let reportsReceived: Int
  let hasCalendarFeed: Bool
  let calendarFeedLastUsedAt: String?
  /// Nil until the user opens a build that records app opens.
  let appActivity: AppActivity?
  let devices: [Device]

  /// The app build and device from the user's latest app open.
  struct AppActivity: Decodable, Sendable {
    let firstActiveAt: String?
    let lastActiveAt: String?
    let openCount: Int
    /// Days with at least one open, counted in Norwegian time.
    let activeDays: Int?
    let appVersion: String?
    let buildNumber: String?
    let previousAppVersion: String?
    let previousBuildNumber: String?
    let osVersion: String?
    /// Hardware identifier such as "iPhone17,1".
    let deviceModel: String?
    let locale: String?
    /// The language the app's UI shows, such as "nb".
    let appLanguage: String?
    let timeZone: String?
    /// "authorized", "denied", "not_determined", "provisional" or "ephemeral".
    let notificationPermission: String?
    /// "available", "denied" or "restricted".
    let backgroundRefresh: String?
    /// Kinds of the widgets on the user's screens. Nil when the app couldn't read them.
    let widgetKinds: [String]?
    /// "light" or "dark".
    let appearance: String?
    /// Dynamic Type size such as "L" or "AccessibilityXL".
    let textSize: String?
    let reduceMotion: Bool?

    var firstActive: Date? { adminDate(firstActiveAt) }
    var lastActive: Date? { adminDate(lastActiveAt) }
    var version: String? { adminVersion(appVersion, buildNumber) }
    var previousVersion: String? { adminVersion(previousAppVersion, previousBuildNumber) }
  }

  struct Device: Decodable, Identifiable, Sendable {
    let id: String
    let platform: String?
    let appVersion: String?
    let timeZone: String?
    let lastSeenAt: String?

    var lastSeen: Date? { adminDate(lastSeenAt) }
  }

  var firstShift: Date? { adminDay(firstShiftDate) }
  var latestShift: Date? { adminDay(latestShiftDate) }
  var lastShiftAdded: Date? { adminDate(lastShiftAddedAt) }
  var calendarFeedLastUsed: Date? { adminDate(calendarFeedLastUsedAt) }
}

/// Distinct users with an app open, from `admin_get_active_users_chart_api`.
/// Only counts builds that record app opens.
struct AdminActiveUsersChart: Decodable, Sendable {
  /// The last 24 hours, oldest first. The last bucket is the current hour.
  let hours: [Bucket]
  /// The last 30 days in the requested time zone, oldest first. The last bucket is today.
  let days: [Bucket]

  struct Bucket: Decodable, Identifiable, Sendable {
    /// Hour buckets have `start`, a timestamp. Day buckets have `date`, a Postgres date.
    let start: String?
    let date: String?
    let users: Int

    var id: String { start ?? date ?? "" }
    var time: Date? { adminDate(start) ?? adminDay(date) }
  }
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

/// The conversation around a report, in the `list_thread_messages` row shape.
struct AdminReportMessages: Decodable, Sendable {
  let messages: [MessagingMessageRow]
  let reportedAvatarUrl: String?

  var friendMessages: [FriendMessage] { messages.map { $0.toFriendMessage() } }
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
