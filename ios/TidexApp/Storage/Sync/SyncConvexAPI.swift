import Foundation

// MARK: - Convex calls for the sync coordinator

/// One page of `sync:pull`. `cursor` is the revision of the last row, and `done` is true when the
/// page held fewer rows than asked for.
internal struct SyncPullPage<Row: Decodable>: Decodable {
  internal let rows: [Row]
  internal let cursor: Int64
  internal let done: Bool
}

/// What an update or remove answered.
internal enum SyncWriteOutcome<Row> {
  /// The write went through. The row is the server row after it.
  case ok(Row)
  /// The row is not at the expected revision, or it is deleted. The row is nil when the server
  /// has no row with this id for this user.
  case conflict(Row?)
}

/// What an insert answered.
internal enum SyncInsertOutcome<Row> {
  /// The row was created. The row is the server row.
  case ok(Row)
  /// A row with this id was already there, usually because an earlier insert committed after
  /// its request timed out. The row is what the server holds.
  case exists(Row)
}

extension SyncTable {
  /// The Convex module that holds this table's write functions.
  fileprivate var convexModule: String {
    switch self {
    case .jobs: "jobs"
    case .userShifts: "userShifts"
    case .events: "events"
    case .recurringShifts: "recurringShifts"
    case .wageSnapshots: "wageSnapshots"
    case .payrollAdjustments: "payrollAdjustments"
    case .userSettings: "userSettings"
    case .notificationPreferences: "notificationPreferences"
    }
  }
}

/// The sync contract of `backend/convex/sync.ts` and `backend/convex/lib/syncWrite.ts`.
internal enum SyncConvex {
  // Swift doesn't allow a type inside a generic function, so this lives here.
  private struct NotificationPreferencesArgs: Encodable, Sendable {
    let shiftRemindersEnabled: Bool
    let shiftReminderMinutesArray: [Int]
    let sharedShiftsEnabled: Bool

    enum CodingKeys: String, CodingKey {
      case shiftRemindersEnabled = "shift_reminders_enabled"
      case shiftReminderMinutesArray = "shift_reminder_minutes_array"
      case sharedShiftsEnabled = "shared_shifts_enabled"
    }
  }

  private struct PullArgs: Encodable, Sendable {
    let table: String
    let after: Int64
    let limit: Int
  }

  private struct InsertArgs: Encodable, Sendable {
    let row: [String: AnyJSON]
  }

  /// `id` is nil for `user_settings`, which is keyed by the user.
  private struct UpdateArgs: Encodable, Sendable {
    let id: String?
    let expectedRevision: Int64
    let set: [String: AnyJSON]
    let clear: [String]?

    enum CodingKeys: String, CodingKey {
      case id, set, clear
      case expectedRevision = "expected_revision"
    }
  }

  private struct RemoveArgs: Encodable, Sendable {
    let id: String
    let expectedRevision: Int64

    enum CodingKeys: String, CodingKey {
      case id
      case expectedRevision = "expected_revision"
    }
  }

  private struct WriteReply<Row: Decodable>: Decodable {
    let status: String
    let row: Row?
  }

  /// The server sets these columns, so a write must not send them.
  private static let serverColumns: Set<String> = [
    "user_id", "created_at", "updated_at", "revision", "deleted_at",
  ]

  private static func isSent(_ column: String) -> Bool {
    !serverColumns.contains(column)
  }

  static func pull<Row: Decodable>(
    _ table: SyncTable, after: Int64, limit: Int
  ) async throws -> SyncPullPage<Row> {
    try await ConvexAPI.app.query(
      "sync:pull", PullArgs(table: table.rawValue, after: after, limit: limit))
  }

  /// Every row of a table for the signed-in user, deleted rows included. Pages until the server
  /// says it is done, so a table with more than one page of rows is read in full.
  static func pullAll<Row: Decodable>(_ table: SyncTable, pageSize: Int = 500) async throws -> [Row] {
    var rows: [Row] = []
    var cursor: Int64 = 0
    while true {
      let page: SyncPullPage<Row> = try await pull(table, after: cursor, limit: pageSize)
      rows += page.rows
      // A page that does not move the cursor would repeat for ever.
      if page.done || page.cursor <= cursor { return rows }
      cursor = page.cursor
    }
  }

  /// Convex rejects `null` for an optional field, so a nil value leaves its key out.
  static func insert<Row: Decodable>(
    _ table: SyncTable, row: [String: AnyJSON]
  ) async throws -> SyncInsertOutcome<Row> {
    let sent = row.filter { isSent($0.key) && $0.value != .null }
    let reply: WriteReply<Row> = try await ConvexAPI.app.mutation(
      "\(table.convexModule):insert", InsertArgs(row: sent))
    switch (reply.status, reply.row) {
    case ("ok", .some(let saved)): return .ok(saved)
    case ("exists", .some(let existing)): return .exists(existing)
    default: throw unexpected(reply.status)
    }
  }

  /// A column set to `null` goes in `clear`, because Convex has no `null` for optional fields.
  static func update<Row: Decodable>(
    _ table: SyncTable, id: String?, expectedRevision: Int64, data: [String: AnyJSON]
  ) async throws -> SyncWriteOutcome<Row> {
    let columns = data.filter { isSent($0.key) }
    let cleared = columns.filter { $0.value == .null }.map { $0.key }.sorted()
    let args = UpdateArgs(
      id: id,
      expectedRevision: expectedRevision,
      set: columns.filter { $0.value != .null },
      clear: cleared.isEmpty ? nil : cleared)
    let reply: WriteReply<Row> = try await ConvexAPI.app.mutation(
      "\(table.convexModule):update", args)
    return try outcome(reply)
  }

  /// Soft deletes the row.
  static func remove<Row: Decodable>(
    _ table: SyncTable, id: String, expectedRevision: Int64
  ) async throws -> SyncWriteOutcome<Row> {
    let reply: WriteReply<Row> = try await ConvexAPI.app.mutation(
      "\(table.convexModule):remove", RemoveArgs(id: id, expectedRevision: expectedRevision))
    return try outcome(reply)
  }

  /// Sends the whole row. The last write wins, as with the old upsert on `user_id`.
  static func upsertNotificationPreferences<Row: Decodable>(
    shiftRemindersEnabled: Bool, shiftReminderMinutesArray: [Int], sharedShiftsEnabled: Bool
  ) async throws -> Row {
    try await ConvexAPI.app.mutation(
      "notificationPreferences:upsert",
      NotificationPreferencesArgs(
        shiftRemindersEnabled: shiftRemindersEnabled,
        shiftReminderMinutesArray: shiftReminderMinutesArray,
        sharedShiftsEnabled: sharedShiftsEnabled))
  }

  /// The server row for `id`, deleted or not, or nil when the user has none. The backend has
  /// no query for one row, so this sends an empty update with a revision no row has. That
  /// always ends as a conflict, which carries the row, and it changes nothing.
  static func currentRow<Row: Decodable>(_ table: SyncTable, id: String?) async throws -> Row? {
    let outcome: SyncWriteOutcome<Row> = try await update(
      table, id: id, expectedRevision: -1, data: [:])
    if case .conflict(let row) = outcome { return row }
    return nil
  }

  private static func outcome<Row: Decodable>(_ reply: WriteReply<Row>) throws
    -> SyncWriteOutcome<Row>
  {
    switch (reply.status, reply.row) {
    case ("ok", .some(let saved)): return .ok(saved)
    case ("conflict", let current): return .conflict(current)
    default: throw unexpected(reply.status)
    }
  }

  private static func unexpected(_ status: String) -> ConvexAPI.Failure {
    .server(code: nil, message: "Unexpected sync reply \"\(status)\"")
  }
}
