import SwiftUI
import XCTest

@testable import Tidex

internal final class CalendarDayCellIndicatorPlacementTests: XCTestCase {
  internal func testEventIndicatorUsesOneSegmentForSingleEvent() {
    XCTAssertEqual(
      CalendarDayCell<EmptyView>.eventIndicatorSegmentCount(for: 1),
      1
    )
  }

  internal func testEventIndicatorUsesTwoSegmentsForTwoEvents() {
    XCTAssertEqual(
      CalendarDayCell<EmptyView>.eventIndicatorSegmentCount(for: 2),
      2
    )
  }

  internal func testEventIndicatorCapsAtThreeSegments() {
    XCTAssertEqual(
      CalendarDayCell<EmptyView>.eventIndicatorSegmentCount(for: 4),
      3
    )
  }

  internal func testTodayBadgePromotesOverlapIndicatorIntoBadge() {
    XCTAssertEqual(
      CalendarDayCell<EmptyView>.indicatorPlacement(
        showsTodayBadge: true,
        showOverlapIndicator: true,
        showSingleUserIndicator: false
      ),
      .todayBadge
    )
  }

  internal func testTodayBadgePromotesSingleUserIndicatorIntoBadge() {
    XCTAssertEqual(
      CalendarDayCell<EmptyView>.indicatorPlacement(
        showsTodayBadge: true,
        showOverlapIndicator: false,
        showSingleUserIndicator: true
      ),
      .todayBadge
    )
  }

  internal func testNonTodayCellsKeepIndicatorInLeadingMarkerSlot() {
    XCTAssertEqual(
      CalendarDayCell<EmptyView>.indicatorPlacement(
        showsTodayBadge: false,
        showOverlapIndicator: true,
        showSingleUserIndicator: false
      ),
      .leadingMarker
    )
  }

  internal func testCellsWithoutIndicatorsDoNotReserveBadgePlacement() {
    XCTAssertEqual(
      CalendarDayCell<EmptyView>.indicatorPlacement(
        showsTodayBadge: true,
        showOverlapIndicator: false,
        showSingleUserIndicator: false
      ),
      .none
    )
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
