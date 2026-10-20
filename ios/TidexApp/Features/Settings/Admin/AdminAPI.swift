import Foundation

/// Typed calls to the `admin` module in `backend/convex/admin.ts`.
/// The server checks the admin role on every call.
enum AdminAPI {
  /// Only this account can grant or revoke admin. Matches `SUPERADMIN_USER_ID` in `admin.ts`.
  static let superadminUserID: String = "032d8c2a-9af6-4777-99f0-24e2c4058bf3"

  static func currentUserIsSuperadmin() async -> Bool {
    (try? await AuthSessionManager.shared.getSession().normalizedUserId) == superadminUserID
  }

  // MARK: Users

  static func users(
    page: Int, perPage: Int, search: String?, query: AdminUserQuery = AdminUserQuery()
  ) async throws -> AdminUsersPage {
    var args = query.convexArgs
    args["page"] = .integer(page)
    args["per_page"] = .integer(perPage)
    if let search { args["search"] = .string(search) }
    return try await read("admin:listUsers", args)
  }

  static func setBanned(_ banned: Bool, for user: AdminUser) async throws {
    try await write("admin:setBanned", ["target_user_id": .string(user.id), "ban": .bool(banned)])
  }

  static func setAdmin(_ admin: Bool, for user: AdminUser) async throws {
    try await write("admin:setAdmin", ["target_user_id": .string(user.id), "grant": .bool(admin)])
  }

  static func userStats(id: String) async throws -> AdminUserStats {
    try await read("admin:userStats", ["user_id": .string(id)])
  }

  static func userWageSetup(id: String) async throws -> AdminWageSetup {
    try await read("admin:userWageSetup", ["user_id": .string(id)])
  }

  /// Days follow the admin's own time zone.
  static func activeUsersChart() async throws -> AdminActiveUsersChart {
    try await read("admin:activeUsersChart", ["time_zone": .string(TimeZone.current.identifier)])
  }

  /// Weeks and months follow the admin's own time zone.
  static func stats() async throws -> AdminStats {
    try await read("admin:stats", ["time_zone": .string(TimeZone.current.identifier)])
  }

  // MARK: Feedback

  static func feedback() async throws -> [AdminFeedback] {
    let page: AdminFeedbackPage = try await read("admin:feedback", ["limit": 100])
    return page.feedback
  }

  static func respond(toFeedback id: String, with response: String) async throws {
    try await write(
      "admin:respondFeedback", ["feedback_id": .string(id), "response": .string(response)])
  }

  // MARK: Reports

  static func reports(status: AdminReportStatus?, limit: Int = 100) async throws -> AdminReportsPage
  {
    var args: [String: AnyJSON] = ["limit": .integer(limit)]
    if let status { args["status"] = .string(status.rawValue) }
    return try await read("admin:reports", args)
  }

  /// The messages around the reported one, or around the report time for user reports.
  static func reportMessages(id: String) async throws -> AdminReportMessages {
    try await read("admin:reportMessages", ["report_id": .string(id)])
  }

  static func deleteMessage(id: String) async throws {
    try await write("admin:deleteMessage", ["message_id": .string(id)])
  }

  static func updateReport(id: String, status: AdminReportStatus, reviewerNotes: String)
    async throws
  {
    let notes: String = reviewerNotes.trimmingCharacters(in: .whitespacesAndNewlines)
    var args: [String: AnyJSON] = ["report_id": .string(id), "status": .string(status.rawValue)]
    if !notes.isEmpty { args["reviewer_notes"] = .string(notes) }
    try await write("admin:updateReportStatus", args)
  }

  // MARK: Audit log

  static func auditLog(targetUserID: String?) async throws -> [AdminAuditEntry] {
    var args: [String: AnyJSON] = ["limit": 300]
    if let targetUserID { args["target_filter"] = .string(targetUserID) }
    let page: AdminAuditPage = try await read("admin:auditLog", args)
    return page.entries ?? []
  }

  // MARK: Shares

  static func shares(search: String?) async throws -> AdminSharesPage {
    var args: [String: AnyJSON] = ["page": 1, "page_size": 100]
    if let search { args["search"] = .string(search) }
    return try await read("admin:shares", args)
  }

  static func createShare(ownerID: String, viewerID: String, showEarnings: Bool) async throws {
    try await write(
      "admin:createShare",
      [
        "owner_id": .string(ownerID),
        "viewer_id": .string(viewerID),
        "show_earnings": .bool(showEarnings),
      ])
  }

  static func updateShare(id: String, showEarnings: Bool, blocked: Bool, muted: Bool)
    async throws
  {
    try await write(
      "admin:updateShare",
      [
        "share_id": .string(id),
        "show_earnings": .bool(showEarnings),
        "blocked": .bool(blocked),
        "muted": .bool(muted),
      ])
  }

  static func deleteShare(id: String) async throws {
    try await write("admin:deleteShare", ["share_id": .string(id)])
  }

  // MARK: Broadcasts

  static func broadcasts() async throws -> [AdminBroadcast] {
    let page: AdminBroadcastPage = try await read("admin:broadcastHistory")
    return page.broadcasts
  }

  /// Number of users with a push device that `target` reaches. Excludes the sending admin.
  static func audienceSize(for target: AdminBroadcastTarget) async throws -> Int {
    let result: AdminCount = try await read(
      "admin:previewTarget", ["target": .string(target.rawValue), "include_self": false])
    return result.count
  }

  static func sendBroadcast(_ draft: AdminBroadcastDraft) async throws {
    try await write("admin:sendBroadcast", draft.convexArgs)
  }

  static func broadcastDetail(id: String) async throws -> AdminBroadcastDetail {
    try await read("admin:broadcastDetail", ["broadcast_id": .string(id)])
  }

  // MARK: Transport

  private struct ActionResult: Decodable {
    let success: Bool
    let message: String?
    let error: String?
  }

  private static func read<T: Decodable & Sendable>(
    _ path: String, _ args: [String: AnyJSON] = [:]
  ) async throws -> T {
    do {
      return try await ConvexAPI.app.query(path, args)
    } catch {
      throw AdminError(error)
    }
  }

  /// Runs a mutation that answers `{ success, message?, error? }`.
  private static func write(_ path: String, _ args: [String: AnyJSON]) async throws {
    let result: ActionResult
    do {
      result = try await ConvexAPI.app.mutation(path, args)
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

  /// Pulls the server's own message out of a Convex error.
  init(_ error: Error) {
    switch error {
    case let error as AdminError:
      message = error.message

    default:
      message = error.localizedDescription
    }
  }
}
