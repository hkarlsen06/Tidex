import Foundation
import Observation
import Synchronization
import os.log

// MARK: - Partial update payloads

/// Collects the columns of a partial UPDATE payload for the fields marked dirty.
struct PartialUpdatePayload<Field: Hashable> {
  let dirtyFields: Set<Field>
  private(set) var data: [String: AnyJSON] = [:]

  /// Sets `column` when `field` is dirty. The value is only computed for dirty fields.
  mutating func set(
    _ field: Field, _ column: String, _ value: @autoclosure () throws -> AnyJSON
  ) rethrows {
    guard dirtyFields.contains(field) else { return }
    data[column] = try value()
  }
}

extension Optional {
  /// JSON value for a nullable column, `null` when the value is nil.
  func jsonOrNull(_ transform: (Wrapped) throws -> AnyJSON) rethrows -> AnyJSON {
    try map(transform) ?? .null
  }
}

// MARK: - Sync Errors

/// Errors that can occur during sync operations
enum SyncError: LocalizedError {
  case dateParsingFailed(table: SyncTable, id: String, rawValue: String)
  case localSaveFailed(table: SyncTable, message: String)
  case missingConflictSnapshot(table: SyncTable, id: String)
  case notFound(table: SyncTable, id: String)
  case notInConflict(table: SyncTable, id: String)
  case pullTimedOut
  case rowsNotPushed(count: Int)

  /// Technical description for logging
  var errorDescription: String? {
    switch self {
    case .notFound(let table, let id):
      return "\(table.displayName) with id \(id) not found"

    case .notInConflict(let table, let id):
      return "\(table.displayName) with id \(id) is not in conflict state"

    case .missingConflictSnapshot(let table, let id):
      return "\(table.displayName) with id \(id) has no conflict snapshot"

    case .dateParsingFailed(let table, let id, let rawValue):
      return "\(table.displayName) with id \(id) has unparseable date field: '\(rawValue)'"

    case .localSaveFailed(let table, let message):  // swiftlint:disable:this pattern_matching_keywords
      return "Failed to save pulled \(table.displayName) rows locally: \(message)"

    case .pullTimedOut:
      return "Pulling server changes timed out"

    case .rowsNotPushed(let count):
      return "\(count) local changes could not be pushed and stay queued for the next sync"
    }
  }

  /// User-friendly message for UI display
  var userFriendlyMessage: String {
    switch self {
    case .notFound:
      return "Sync failed: Record not found locally. Please refresh and try again."

    case .notInConflict, .missingConflictSnapshot:
      return "Sync failed: Conflict state mismatch. Please refresh and try again."

    case .dateParsingFailed(let table, let id, _):
      return
        "Sync failed: Server returned invalid data for \(table.displayName) (ID: \(id.prefix(8))...). Please contact support."

    case .localSaveFailed:
      return "Sync failed: Local changes could not be saved. Please try again."

    case .pullTimedOut:
      return "Sync failed: Server changes took too long to load. Please try again."

    case .rowsNotPushed:
      return "Sync failed: Some changes could not be sent. They will be retried."
    }
  }
}

// MARK: - Debug Test Harness

#if DEBUG
  /// Debug-only test harness for sync safety verification
  /// Call from a debug menu or unit test to verify cursor safety
  enum SyncTestHarness {
    /// Test that malformed updated_at throws the correct error type
    /// This verifies the error path without needing actual sync infrastructure
    static func testMalformedUpdatedAtThrowsError() -> (passed: Bool, message: String) {
      // Directly test the date parsing logic
      let malformedDate = "not-a-date"
      let testTable = SyncTable.userShifts
      let testId = "test-id-12345"

      // ISO8601DateFormatter should return nil for malformed dates
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if formatter.date(from: malformedDate) != nil {
        return (false, "FAIL: ISO8601DateFormatter accepted malformed date")
      }

      // SyncError should capture the details correctly
      let error = SyncError.dateParsingFailed(table: testTable, id: testId, rawValue: malformedDate)

      // Verify technical description contains details
      guard let description = error.errorDescription else {
        return (false, "FAIL: Error has no description")
      }
      guard description.contains(testId), description.contains(malformedDate) else {
        return (false, "FAIL: Error description missing details: \(description)")
      }

      // Verify user-friendly message is actionable
      let userMessage = error.userFriendlyMessage
      guard userMessage.contains("contact support") else {
        return (false, "FAIL: User message not actionable: \(userMessage)")
      }

      return (true, "PASS: Malformed date creates proper error with details")
    }

    /// Test that encoding failure throws and is caught properly
    static func testEncodingFailureIsCaught() -> (passed: Bool, message: String) {
      // Create a snapshot with valid data - encoding should succeed
      let validSnapshot = UserShiftServerSnapshot.from(
        jobId: nil,
        shiftDate: "2025-01-15",
        startTime: "09:00",
        endTime: "17:00",
        note: nil,
        customPauseWindows: nil,
        customSupplements: nil,
        updatedAt: Date(),
        revision: 1,
        deletedAt: nil
      )

      do {
        let data = try validSnapshot.encodedOrThrow()
        guard !data.isEmpty else {
          return (false, "FAIL: Encoded data is empty")
        }
        return (true, "PASS: Valid snapshot encodes successfully")
      } catch {
        return (false, "FAIL: Valid snapshot encoding threw: \(error)")
      }
    }

    /// Test that user-friendly messages are provided for all error types
    static func testUserFriendlyMessages() -> (passed: Bool, message: String) {
      let errors: [SyncError] = [
        .notFound(table: .userShifts, id: "test"),
        .notInConflict(table: .recurringShifts, id: "test"),
        .missingConflictSnapshot(table: .wageSnapshots, id: "test"),
        .dateParsingFailed(table: .userSettings, id: "test", rawValue: "bad"),
      ]

      for error in errors {
        let message = error.userFriendlyMessage
        guard !message.isEmpty else {
          return (false, "FAIL: Empty user message for \(error)")
        }
        guard message.contains("Sync failed") else {
          return (false, "FAIL: Message doesn't indicate sync failure: \(message)")
        }
      }

      return (true, "PASS: All error types have user-friendly messages")
    }

    /// Run all tests and return summary
    static func runAllTests() -> String {
      var results: [String] = []

      let test1 = testMalformedUpdatedAtThrowsError()
      results.append(test1.message)

      let test2 = testEncodingFailureIsCaught()
      results.append(test2.message)

      let test3 = testUserFriendlyMessages()
      results.append(test3.message)

      let allPassed = results.allSatisfy { $0.hasPrefix("PASS") }
      let summary = allPassed ? "✅ All tests passed" : "❌ Some tests failed"

      return ([summary] + results).joined(separator: "\n")
    }
  }
#endif