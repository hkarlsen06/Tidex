import XCTest

@testable import Tidex

final class EventReminderPlannerTests: XCTestCase {
  func testTimedEventSchedulesReminderFromStartTime() {
    let referenceDate = Date.fromDateAndTime("2026-03-10", time: "08:00") ?? Date()
    let event = EventRow(
      id: "event-1",
      user_id: "user-1",
      start_date: "2026-03-10",
      end_date: "2026-03-10",
      is_all_day: false,
      start_time: "10:00",
      end_time: "11:00",
      note: "Doctor",
      notification_minutes_array: [60]
    )

    let schedules = EventReminderPlanner.reminderSchedules(for: event, referenceDate: referenceDate)

    XCTAssertEqual(schedules.count, 1)
    XCTAssertEqual(schedules.first?.minutesBefore, 60)
    XCTAssertEqual(
      schedules.first?.fireDate,
      Date.fromDateAndTime("2026-03-10", time: "09:00")
    )
  }

  func testTimedEventAcceptsDatabaseTimeWithSeconds() {
    let referenceDate = Date.fromDateAndTime("2026-03-10", time: "08:00") ?? Date()
    let event = EventRow(
      id: "event-seconds",
      user_id: "user-1",
      start_date: "2026-03-10",
      end_date: "2026-03-10",
      is_all_day: false,
      start_time: "10:00:00",
      end_time: "11:00:00",
      note: "Doctor",
      notification_minutes_array: [60]
    )

    let schedules = EventReminderPlanner.reminderSchedules(for: event, referenceDate: referenceDate)

    XCTAssertEqual(schedules.count, 1)
    XCTAssertEqual(
      schedules.first?.fireDate,
      Date.fromDateAndTime("2026-03-10", time: "09:00")
    )
  }

  func testInvalidTimedEventDoesNotScheduleAtMidnight() {
    let referenceDate = Date.fromDateAndTime("2026-03-10", time: "08:00") ?? Date()
    let event = EventRow(
      id: "event-invalid-time",
      user_id: "user-1",
      start_date: "2026-03-10",
      end_date: "2026-03-10",
      is_all_day: false,
      start_time: "invalid",
      end_time: "11:00",
      note: "Doctor",
      notification_minutes_array: [60]
    )

    let schedules = EventReminderPlanner.reminderSchedules(for: event, referenceDate: referenceDate)

    XCTAssertTrue(schedules.isEmpty)
  }

  func testInvalidDateDoesNotNormalizeIntoDifferentDay() {
    XCTAssertNil(Date.fromDateAndTime("2026-02-31", time: "09:00"))
  }

  func testAllDayEventUsesAnchorTime() {
    let referenceDate = Date.fromDateAndTime("2026-03-10", time: "07:00") ?? Date()
    let event = EventRow(
      id: "event-2",
      user_id: "user-1",
      start_date: "2026-03-11",
      end_date: "2026-03-12",
      is_all_day: true,
      start_time: nil,
      end_time: nil,
      note: "Conference",
      notification_minutes_array: [120],
      notification_anchor_time: "09:30"
    )

    let schedules = EventReminderPlanner.reminderSchedules(for: event, referenceDate: referenceDate)

    XCTAssertEqual(schedules.count, 1)
    XCTAssertEqual(
      schedules.first?.fireDate,
      Date.fromDateAndTime("2026-03-11", time: "07:30")
    )
  }

  func testAllDayEventSupportsSameDayReminderAtAnchorTime() {
    let referenceDate = Date.fromDateAndTime("2026-03-11", time: "07:00") ?? Date()
    let event = EventRow(
      id: "event-same-day",
      user_id: "user-1",
      start_date: "2026-03-11",
      end_date: "2026-03-11",
      is_all_day: true,
      start_time: nil,
      end_time: nil,
      note: "Holiday",
      notification_minutes_array: [0],
      notification_anchor_time: "09:30"
    )

    let schedules = EventReminderPlanner.reminderSchedules(for: event, referenceDate: referenceDate)

    XCTAssertEqual(schedules.count, 1)
    XCTAssertEqual(
      schedules.first?.fireDate,
      Date.fromDateAndTime("2026-03-11", time: "09:30")
    )
  }

  func testPastEventReturnsNoSchedules() {
    let referenceDate = Date.fromDateAndTime("2026-03-12", time: "00:30") ?? Date()
    let event = EventRow(
      id: "event-3",
      user_id: "user-1",
      start_date: "2026-03-10",
      end_date: "2026-03-11",
      is_all_day: true,
      start_time: nil,
      end_time: nil,
      note: "Trip",
      notification_minutes_array: [60],
      notification_anchor_time: "09:00"
    )

    XCTAssertTrue(EventReminderPlanner.hasEventPassed(event, referenceDate: referenceDate))
    XCTAssertTrue(
      EventReminderPlanner.reminderSchedules(for: event, referenceDate: referenceDate).isEmpty
    )
  }

  func testPrioritizedSchedulesCapsToEarliestSixteenAcrossEvents() {
    let referenceDate = Date.fromDateAndTime("2026-03-10", time: "07:00") ?? Date()
    let events = (0..<17).map { index in
      EventRow(
        id: "event-\(index)",
        user_id: "user-1",
        start_date: "2026-03-10",
        end_date: "2026-03-10",
        is_all_day: false,
        start_time: String(format: "09:%02d", index),
        end_time: String(format: "10:%02d", index),
        note: "Event \(index)",
        notification_minutes_array: [60]
      )
    }

    let schedules = EventReminderPlanner.prioritizedSchedules(
      for: events,
      referenceDate: referenceDate
    )

    XCTAssertEqual(schedules.count, EventReminderPlanner.maxScheduledNotifications)
    XCTAssertEqual(schedules.first?.event.id, "event-0")
    XCTAssertEqual(schedules.last?.event.id, "event-15")
    XCTAssertFalse(schedules.contains { $0.event.id == "event-16" })
  }
}
