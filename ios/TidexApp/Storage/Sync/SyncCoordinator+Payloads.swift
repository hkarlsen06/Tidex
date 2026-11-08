import Foundation
import Observation
import Synchronization
import os.log

extension SyncCoordinator {

  // MARK: - Helpers

  /// Whether the server or the local encoder rejected one row's data.
  /// The push loops mark such a row as conflicted and move on to the next row. Every other
  /// error, such as network, auth, or cancellation errors, still stops the sync.
  static func isRowRejection(_ error: Error) -> Bool {
    if error is SyncEncodingError {
      return true
    }
    // The sync functions throw a `ConvexError` with a code when a row breaks a rule, such as
    // `invalid_row` or `job_has_active_dependents`. A missing sign-in is `.notSignedIn`, a
    // network failure is a `URLError`, and an unexpected server error has no code.
    guard let failure = error as? ConvexAPI.Failure, case .server(let code, _) = failure else {
      return false
    }
    return code != nil && !isWrongUser(error)
  }

  /// Whether the server refused a row because it belongs to another user than the one signed in,
  /// as when this sync started before an account switch. The row is fine and stays queued for
  /// its owner, so the sync stops without touching it.
  static func isWrongUser(_ error: Error) -> Bool {
    (error as? ConvexAPI.Failure)?.code == "wrong_user"
  }

  enum ApplyResult {
    case inserted
    case updated
    case noChange
    case autoMerged
    case conflict
  }

  /// Whether the error means one server row holds data the app cannot read, such as a bad
  /// timestamp or date. Local store and network errors are not row errors.
  static func isUnreadableRowError(_ error: Error) -> Bool {
    if error is SyncEncodingError {
      return true
    }
    if let syncError = error as? SyncError, case .dateParsingFailed = syncError {
      return true
    }
    return false
  }

  /// Applies one pulled row. A row with unreadable data is logged and skipped, so it cannot keep
  /// the cursor from advancing and block every later row. Other errors still stop the pull.
  func applyIsolated(
    table: SyncTable,
    id: String,
    _ apply: () async throws -> ApplyResult
  ) async throws -> ApplyResult? {
    do {
      return try await apply()
    } catch where Self.isUnreadableRowError(error) {
      syncCoordinatorLogger.error(
        "Skipping unreadable \(table.displayName) row \(id.prefix(8)): \(error.localizedDescription)"
      )
      return nil
    }
  }

  /// Parse ISO8601 date string to Date
  func parseISO8601(_ string: String) -> Date? {
    ISO8601Timestamp.date(from: string)
  }

  /// Parse ISO8601 updated_at with warning log on failure
  /// For sync cursor timestamps where fallback to Date() is acceptable but should be visible
  func parseUpdatedAt(_ string: String, table: SyncTable, id: String) -> Date {
    if let date = parseISO8601(string) {
      return date
    }
    syncCoordinatorLogger.warning(
      "Failed to parse updated_at '\(string)' for \(table.displayName) \(id.prefix(8)), using current date as fallback"
    )
    return Date()
  }

  func savePulledPage(storeActor: LocalStoreActor, table: SyncTable) async throws {
    if let errorDescription = await storeActor.saveErrorDescription() {
      throw SyncError.localSaveFailed(table: table, message: errorDescription)
    }
  }

  /// Parse ISO8601 date string to Date, throwing on failure
  /// Use this for cursor-affecting code paths to prevent data loss
  /// - Parameters:
  ///   - string: The ISO8601 date string to parse
  ///   - table: The table being synced (for error context)
  ///   - id: The row ID (for error context)
  /// - Returns: Parsed Date
  /// - Throws: SyncError.dateParsingFailed if parsing fails
  func requireISO8601(_ string: String, table: SyncTable, id: String) throws -> Date {
    if let date = parseISO8601(string) {
      return date
    }
    syncCoordinatorLogger.error("Failed to parse updated_at for \(table.displayName) id=\(id): '\(string)'")
    throw SyncError.dateParsingFailed(table: table, id: id, rawValue: string)
  }

  func requireAnyJSON(
    _ data: Data,
    table: SyncTable,
    id: String,
    field: String
  ) throws -> AnyJSON {
    do {
      return try AnyJSON.decoder.decode(AnyJSON.self, from: data)
    } catch {
      syncCoordinatorLogger.error("Failed to decode \(table.displayName) field=\(field) id=\(id)")
      throw SyncEncodingError.payloadDecodingFailed(
        type: "\(table.rawValue).\(field)",
        underlyingError: error
      )
    }
  }

  func requireNonEmptyUpdate(
    _ updateData: [String: AnyJSON],
    table: SyncTable,
    id: String
  ) throws {
    guard !updateData.isEmpty else {
      syncCoordinatorLogger.error("Empty update payload for \(table.displayName) id=\(id)")
      throw SyncEncodingError.emptyUpdatePayload(type: "\(table.rawValue).\(id)")
    }
  }

  /// Formats a date for the server, with milliseconds.
  func formatTimestamp(_ date: Date) -> String {
    ISO8601Timestamp.string(from: date)
  }
}
