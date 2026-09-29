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

    XCTAssertEqual(summary.dateText, EventSheetFormatter.longDate("2026-04-20"))
    XCTAssertEqual(
      summary.timeText,
      ShiftCardFormatter.localizedTimeRange(
        start: "09:00",
        end: "11:30",
        locale: Locale.appLocale,
        separator: " – "
      )
    )
  }

  func testScheduleSummaryForMultiDayAllDayEventShowsRangeOnOneLine() {
    let event = TestFixtures.event(
      id: "event-2",
      startDate: "2026-04-20",
      endDate: "2026-04-22",
      isAllDay: true,
      note: "Trip"
    )

    let summary = EventDetailsSummaryBuilder.scheduleSummary(for: event)

    XCTAssertNotEqual(summary.dateText, EventSheetFormatter.longDate("2026-04-20"))
    XCTAssertTrue(summary.dateText.contains("20"))
    XCTAssertTrue(summary.dateText.contains("22"))
    XCTAssertTrue(summary.dateText.contains("2026"))
    XCTAssertEqual(summary.timeText, String(localized: .addShiftEventAllDay))
  }

  func testScheduleSummaryForTimedEventWithoutTimesFallsBackToAllDay() {
    let event = TestFixtures.event(
      id: "event-3",
      startDate: "2026-04-20",
      endDate: "2026-04-20",
      isAllDay: false,
      note: "Reminder"
    )

    let summary = EventDetailsSummaryBuilder.scheduleSummary(for: event)

    XCTAssertEqual(summary.timeText, String(localized: .addShiftEventAllDay))
  }

  func testDateRangeFallsBackToStartDateWhenEndIsBeforeStart() {
    XCTAssertEqual(
      EventSheetFormatter.dateRange(from: "2026-04-22", to: "2026-04-20"),
      EventSheetFormatter.longDate("2026-04-22")
    )
  }
}
