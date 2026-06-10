import XCTest

@testable import Tidex

internal final class SyncErrorTests: XCTestCase {
  internal func testDateParsingFailedProvidesUserFriendlyMessage() {
    let error: SyncError = SyncError.dateParsingFailed(
      table: .userShifts,
      id: "12345678-aaaa-bbbb-cccc-123456789000",
      rawValue: "bad-date"
    )

    XCTAssertTrue(error.userFriendlyMessage.contains("Sync failed"))
    XCTAssertTrue(error.userFriendlyMessage.contains("User Shifts"))
  }

  internal func testNotFoundHasTechnicalDescription() {
    let error: SyncError = SyncError.notFound(table: .wageSnapshots, id: "abc")

    XCTAssertEqual(error.errorDescription, "Wage Snapshots with id abc not found")
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
