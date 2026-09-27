import XCTest

@testable import Tidex

final class TabErrorDescriptionTests: XCTestCase {
  private struct RawError: LocalizedError {
    var errorDescription: String? { "raw-underlying-detail" }
  }

  func testLoadFailureDescriptionsAreLocalizedAndHideUnderlyingText() {
    let expected = String(localized: .commonErrorLoadFailed)
    let descriptions = [
      DashboardError.dataLoadFailed(underlying: RawError()).errorDescription,
      ShiftsError.dataLoadFailed(underlying: RawError()).errorDescription,
      SharingError.loadFailed(underlying: RawError()).errorDescription,
    ]

    for description in descriptions {
      XCTAssertEqual(description, expected)
      XCTAssertFalse(description?.contains("raw-underlying-detail") ?? true)
    }
  }

  func testExportServerErrorDoesNotExposeServerMessage() {
    let description = ExportError.serverError(code: 500, message: "stack trace").errorDescription

    XCTAssertEqual(description, String(localized: .dataExportErrorFailed))
  }
}
