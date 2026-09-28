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

  static func users(
    page: Int, perPage: Int, search: String?, sort: AdminUserSort = .name,
    filter: AdminUserFilter = .all
  ) async throws -> AdminUsersPage {
    try await rpc(
      "admin_list_users_api",
      [
        "p_page": .integer(page),
        "p_per_page": .integer(perPage),
        "p_search": search.map(AnyJSON.string) ?? .null,
        "p_sort": .string(sort.rawValue),
        "p_filter": .string(filter.rawValue),
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

  static func userStats(id: String) async throws -> AdminUserStats {
    try await rpc("admin_get_user_stats_api", ["p_user_id": .string(id)])
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

  static func broadcastDetail(id: String) async throws -> AdminBroadcastDetail {
    try await rpc("admin_get_broadcast_detail_api", ["p_broadcast_id": .string(id)])
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
