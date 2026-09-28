import Foundation
import Supabase

/// Typed calls to the admin RPCs in `supabase/sql/functions/admin/mobile_admin_api.sql`
/// and the `admin-user-ban` and `admin-user-role` Edge Functions.
/// The server checks the admin role and aal2 on every call.
enum AdminAPI {
  /// Only this account can grant or revoke admin. Matches `is_super_admin` in `admin_list_users_api`.
  static let superadminUserID: String = "032d8c2a-9af6-4777-99f0-24e2c4058bf3"

  static func currentUserIsSuperadmin() async -> Bool {
    (try? await AuthSessionManager.shared.getSession().normalizedUserId) == superadminUserID
  }

  // MARK: Users

  static func users(page: Int, perPage: Int, search: String?) async throws -> AdminUsersPage {
    try await rpc(
      "admin_list_users_api",
      [
        "p_page": .integer(page),
        "p_per_page": .integer(perPage),
        "p_search": search.map(AnyJSON.string) ?? .null,
      ])
  }

  static func setBanned(_ banned: Bool, for user: AdminUser) async throws {
    try await edgeAction(
      "admin-user-ban",
      [
        "targetUserId": .string(user.id), "targetEmail": .string(user.email ?? ""),
        "ban": .bool(banned),
      ])
  }

  static func setAdmin(_ admin: Bool, for user: AdminUser) async throws {
    try await edgeAction(
      "admin-user-role",
      [
        "targetUserId": .string(user.id), "targetEmail": .string(user.email ?? ""),
        "grant": .bool(admin),
      ])
  }

  // MARK: Feedback

  static func feedback() async throws -> [AdminFeedback] {
    let page: AdminFeedbackPage = try await rpc("admin_get_feedback_api", ["p_limit": 100])
    return page.feedback
  }

  static func respond(toFeedback id: String, with response: String) async throws {
    try await action(
      "admin_respond_feedback_api", ["p_feedback_id": .string(id), "p_response": .string(response)])
  }

  // MARK: Reports

  static func reports(status: AdminReportStatus?, limit: Int = 100) async throws -> AdminReportsPage
  {
    try await rpc(
      "admin_get_reports_api",
      [
        "p_limit": .integer(limit),
        "p_offset": 0,
        "p_status": status.map { .string($0.rawValue) } ?? .null,
      ])
  }

  static func updateReport(id: String, status: AdminReportStatus, reviewerNotes: String)
    async throws
  {
    let notes: String = reviewerNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    try await action(
      "admin_update_report_status_api",
      [
        "p_report_id": .string(id),
        "p_status": .string(status.rawValue),
        "p_reviewer_notes": notes.isEmpty ? .null : .string(notes),
      ])
  }

  // MARK: Audit log

  static func auditLog(targetUserID: String?) async throws -> [AdminAuditEntry] {
    let page: AdminAuditPage = try await rpc(
      "admin_get_audit_log_api",
      ["p_limit": 300, "p_target_filter": targetUserID.map(AnyJSON.string) ?? .null])
    return page.entries ?? []
  }

  // MARK: Shares

  static func shares(search: String?) async throws -> AdminSharesPage {
    try await rpc(
      "admin_get_shares_api",
      ["p_search": search.map(AnyJSON.string) ?? .null, "p_page": 1, "p_page_size": 100])
  }

  static func createShare(ownerID: String, viewerID: String, showEarnings: Bool) async throws {
    try await action(
      "admin_create_share_api",
      [
        "p_owner_id": .string(ownerID),
        "p_viewer_id": .string(viewerID),
        "p_show_earnings": .bool(showEarnings),
      ])
  }

  static func deleteShare(id: String) async throws {
    try await action("admin_delete_share_api", ["p_share_id": .string(id)])
  }

  // MARK: Broadcasts

  static func broadcasts() async throws -> [AdminBroadcast] {
    let page: AdminBroadcastPage = try await rpc("admin_get_broadcast_history_api")
    return page.broadcasts
  }

  /// Number of users with a push device that `target` reaches. Excludes the sending admin.
  static func audienceSize(for target: AdminBroadcastTarget) async throws -> Int {
    let result: AdminCount = try await rpc(
      "admin_preview_notification_target_api",
      ["p_target": .string(target.rawValue), "p_include_self": false])
    return result.count
  }

  static func sendBroadcast(_ draft: AdminBroadcastDraft) async throws {
    try await action("admin_send_broadcast_api", draft.rpcParams)
  }

  // MARK: Transport

  private struct ActionResult: Decodable {
    let success: Bool
    let message: String?
    let error: String?
  }

  private static func rpc<T: Decodable & Sendable>(
    _ name: String, _ params: [String: AnyJSON] = [:]
  ) async throws -> T {
    do {
      return try await supabase.rpc(name, params: params).single().execute().value
    } catch {
      throw AdminError(error)
    }
  }

  private static func action(_ name: String, _ params: [String: AnyJSON]) async throws {
    let result: ActionResult = try await rpc(name, params)
    guard result.success else {
      throw AdminError(message: result.error ?? result.message ?? "The server rejected the action")
    }
  }

  private static func edgeAction(_ name: String, _ body: [String: AnyJSON]) async throws {
    let result: ActionResult
    do {
      result = try await supabase.functions.invoke(name, options: FunctionInvokeOptions(body: body))
    } catch {
      throw AdminError(error)
    }
    guard result.success else {
      throw AdminError(message: result.error ?? result.message ?? "The server rejected the action")
    }
  }
}

// MARK: - Errors

struct AdminError: LocalizedError {
  let message: String

  var errorDescription: String? { message }

  init(message: String) {
    self.message = message
  }

  /// Pulls the server's own message out of Postgrest and Edge Function errors.
  init(_ error: Error) {
    switch error {
    case let error as AdminError:
      message = error.message

    case let error as PostgrestError:
      message = error.message

    case let error as FunctionsError:
      guard case .httpError(let code, let data) = error else {
        message = error.localizedDescription
        return
      }
      let body: [String: AnyJSON]? = try? JSONDecoder().decode([String: AnyJSON].self, from: data)
      message =
        body?["error"]?.stringValue ?? body?["message"]?.stringValue ?? "Request failed (\(code))"

    default:
      message = error.localizedDescription
    }
  }
}

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

  var displayName: String {
    [name, email, phone].lazy.compactMap { $0?.nilIfBlank }.first ?? String(id.prefix(8))
  }

  /// Email or phone, when it adds something the display name doesn't show.
  var contact: String? {
    [email, phone].lazy.compactMap { $0?.nilIfBlank }.first { $0 != displayName }
  }

  var lastSignIn: Date? { adminDate(lastSignInAt) }
  var created: Date? { adminDate(createdAt) }
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

private struct AdminFeedbackPage: Decodable, Sendable {
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

private struct AdminAuditPage: Decodable, Sendable {
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

private struct AdminBroadcastPage: Decodable, Sendable {
  let broadcasts: [AdminBroadcast]
}

private struct AdminCount: Decodable, Sendable {
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
