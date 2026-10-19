import XCTest

@testable import Tidex

final class RecurringAnchorSelectionTests: XCTestCase {
  func testWeekdayKeyMatchesJavaScriptWeekdayConvention() {
    XCTAssertEqual(RecurringAnchorSelection.weekdayKey(for: "2026-03-15"), "0")
    XCTAssertEqual(RecurringAnchorSelection.weekdayKey(for: "2026-03-16"), "1")
  }

  func testToggleKeepsLastAnchorWhenAtLeastOneIsRequired() {
    let updated = RecurringAnchorSelection.toggledSelectedDays(
      ["1": "2026-03-16"],
      dateISO: "2026-03-16",
      requiresAtLeastOneAnchor: true
    )

    XCTAssertEqual(updated, ["1": "2026-03-16"])
  }

  func testToggleReplacesAnchorForSameWeekday() {
    let updated = RecurringAnchorSelection.toggledSelectedDays(
      ["1": "2026-03-16"],
      dateISO: "2026-03-23",
      requiresAtLeastOneAnchor: true
    )

    XCTAssertEqual(updated, ["1": "2026-03-23"])
  }
}
