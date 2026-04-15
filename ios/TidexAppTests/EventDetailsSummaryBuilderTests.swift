import XCTest

@testable import Tidex

final class EventDetailsSummaryBuilderTests: XCTestCase {
  func testScheduleSummaryForSingleDayTimedEventIncludesDateAndTimeFooter() {
    let event = TestFixtures.event(
      id: "event-1",
      startDate: "2026-04-20",
      endDate: "2026-04-20",
      isAllDay: false,
      startTime: "09:00",
      endTime: "11:30",
      note: "Meeting"
    )

    let summary = EventDetailsSummaryBuilder.scheduleSummary(for: event)

    XCTAssertEqual(summary.rows.count, 1)
    XCTAssertEqual(summary.rows.first?.title, String(localized: .addShiftEventDate))
    XCTAssertEqual(summary.rows.first?.value, EventSheetFormatter.longDate("2026-04-20"))
    XCTAssertEqual(summary.footerIcon, "clock")
    XCTAssertEqual(
      summary.footerText,
      ShiftCardFormatter.localizedTimeRange(
        start: "09:00",
        end: "11:30",
        locale: Locale.appLocale,
        separator: " – "
      )
    )
  }

  func testScheduleSummaryForMultiDayAllDayEventIncludesStartAndEndRows() {
    let event = TestFixtures.event(
      id: "event-2",
      startDate: "2026-04-20",
      endDate: "2026-04-22",
      isAllDay: true,
      note: "Trip"
    )

    let summary = EventDetailsSummaryBuilder.scheduleSummary(for: event)

    XCTAssertEqual(summary.rows.count, 2)
    XCTAssertEqual(summary.rows[0].title, String(localized: .addShiftEventStartDate))
    XCTAssertEqual(summary.rows[0].value, EventSheetFormatter.longDate("2026-04-20"))
    XCTAssertEqual(summary.rows[1].title, String(localized: .addShiftEventEndDate))
    XCTAssertEqual(summary.rows[1].value, EventSheetFormatter.longDate("2026-04-22"))
    XCTAssertEqual(summary.footerIcon, "calendar")
    XCTAssertEqual(summary.footerText, String(localized: .addShiftEventAllDay))
  }
}
