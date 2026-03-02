import XCTest

@testable import Tidex

final class SyncErrorTests: XCTestCase {
  func testDateParsingFailedProvidesUserFriendlyMessage() {
    let error = SyncError.dateParsingFailed(
      table: .userShifts,
      id: "12345678-aaaa-bbbb-cccc-123456789000",
      rawValue: "bad-date"
    )

    XCTAssertTrue(error.userFriendlyMessage.contains("Sync failed"))
    XCTAssertTrue(error.userFriendlyMessage.contains("User Shifts"))
  }

  func testNotFoundHasTechnicalDescription() {
    let error = SyncError.notFound(table: .wageSnapshots, id: "abc")

    XCTAssertEqual(error.errorDescription, "Wage Snapshots with id abc not found")
  }
}
