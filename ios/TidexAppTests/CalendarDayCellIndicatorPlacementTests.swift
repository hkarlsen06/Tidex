import SwiftUI
import XCTest

@testable import Tidex

final class CalendarDayCellIndicatorPlacementTests: XCTestCase {
  func testTodayBadgePromotesOverlapIndicatorIntoBadge() {
    XCTAssertEqual(
      CalendarDayCell<EmptyView>.indicatorPlacement(
        showsTodayBadge: true,
        showOverlapIndicator: true,
        showSingleUserIndicator: false
      ),
      .todayBadge
    )
  }

  func testTodayBadgePromotesSingleUserIndicatorIntoBadge() {
    XCTAssertEqual(
      CalendarDayCell<EmptyView>.indicatorPlacement(
        showsTodayBadge: true,
        showOverlapIndicator: false,
        showSingleUserIndicator: true
      ),
      .todayBadge
    )
  }

  func testNonTodayCellsKeepIndicatorInLeadingMarkerSlot() {
    XCTAssertEqual(
      CalendarDayCell<EmptyView>.indicatorPlacement(
        showsTodayBadge: false,
        showOverlapIndicator: true,
        showSingleUserIndicator: false
      ),
      .leadingMarker
    )
  }

  func testCellsWithoutIndicatorsDoNotReserveBadgePlacement() {
    XCTAssertEqual(
      CalendarDayCell<EmptyView>.indicatorPlacement(
        showsTodayBadge: true,
        showOverlapIndicator: false,
        showSingleUserIndicator: false
      ),
      .none
    )
  }
}
