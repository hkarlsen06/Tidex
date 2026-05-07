import XCTest

@testable import Tidex

final class CalendarExportServiceTests: XCTestCase {
  func testAllDayEventScheduleUsesExclusiveCalendarEndDate() throws {
    let event = makeEvent(
      startDate: "2026-05-06",
      endDate: "2026-05-08",
      isAllDay: true
    )

    let schedule = try XCTUnwrap(CalendarExportService.schedule(for: event))

    XCTAssertTrue(schedule.isAllDay)
    XCTAssertEqual(isoDate(schedule.startDate), "2026-05-06")
    XCTAssertEqual(isoDate(schedule.endDate), "2026-05-09")
  }

  func testTimedEventScheduleSupportsExplicitEndDateAndMidnightEndTime() throws {
    let event = makeEvent(
      startDate: "2026-05-06",
      endDate: "2026-05-06",
      isAllDay: false,
      startTime: "22:30",
      endTime: "24:00"
    )

    let schedule = try XCTUnwrap(CalendarExportService.schedule(for: event))

    XCTAssertFalse(schedule.isAllDay)
    XCTAssertEqual(isoDateTime(schedule.startDate), "2026-05-06 22:30")
    XCTAssertEqual(isoDateTime(schedule.endDate), "2026-05-07 00:00")
  }

  func testInvalidTimedEventWithoutTimesHasNoSchedule() {
    let event = makeEvent(
      startDate: "2026-05-06",
      endDate: "2026-05-06",
      isAllDay: false,
      startTime: nil,
      endTime: nil
    )

    XCTAssertNil(CalendarExportService.schedule(for: event))
  }

  private func makeEvent(
    startDate: String,
    endDate: String,
    isAllDay: Bool,
    startTime: String? = nil,
    endTime: String? = nil
  ) -> EventRow {
    EventRow(
      id: "event-1",
      user_id: "user-1",
      start_date: startDate,
      end_date: endDate,
      is_all_day: isAllDay,
      start_time: startTime,
      end_time: endTime,
      note: "Dentist"
    )
  }

  private func isoDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
  }

  private func isoDateTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
  }
}
