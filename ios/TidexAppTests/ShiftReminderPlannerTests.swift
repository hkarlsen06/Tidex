import XCTest

@testable import Tidex

final class ShiftReminderPlannerTests: XCTestCase {
  func testPrioritizedSchedulesCapsToEarliestFireDatesWhenInputIsUnsorted() {
    let referenceDate = Date.fromDateAndTime("2026-03-10", time: "08:00") ?? Date()
    let shifts = (0..<17).map { index in
      makeShift(
        id: "shift-\(index)",
        date: String(format: "2026-03-%02d", 10 + index),
        startTime: "10:00"
      )
    }.reversed()

    let schedules = ShiftReminderPlanner.prioritizedSchedules(
      for: Array(shifts),
      reminderMinutes: [60],
      referenceDate: referenceDate
    )

    XCTAssertEqual(schedules.count, ShiftReminderPlanner.maxScheduledNotifications)
    XCTAssertEqual(schedules.first?.shift.shiftId, "shift-0")
    XCTAssertEqual(schedules.last?.shift.shiftId, "shift-15")
    XCTAssertFalse(schedules.contains { $0.shift.shiftId == "shift-16" })
  }

  func testReducedCoverageUsesShortestReminderTime() {
    let referenceDate = Date.fromDateAndTime("2026-03-10", time: "08:00") ?? Date()
    let shift = makeShift(id: "shift-far", date: "2026-03-30", startTime: "10:00")

    let schedules = ShiftReminderPlanner.reminderSchedules(
      for: shift,
      reminderMinutes: [300, 60],
      referenceDate: referenceDate
    )

    XCTAssertEqual(schedules.count, 1)
    XCTAssertEqual(schedules.first?.minutesBefore, 60)
    XCTAssertEqual(
      schedules.first?.fireDate,
      Date.fromDateAndTime("2026-03-30", time: "09:00")
    )
  }

  func testInvalidShiftStartDoesNotScheduleAtMidnight() {
    let referenceDate = Date.fromDateAndTime("2026-03-10", time: "08:00") ?? Date()
    let shift = makeShift(id: "shift-invalid", date: "2026-02-31", startTime: "10:00")

    let schedules = ShiftReminderPlanner.reminderSchedules(
      for: shift,
      reminderMinutes: [60],
      referenceDate: referenceDate
    )

    XCTAssertTrue(schedules.isEmpty)
  }

  private func makeShift(
    id: String,
    date: String,
    startTime: String
  ) -> StoredShift {
    StoredShift(
      shiftId: id,
      shiftDate: date,
      startTime: startTime,
      endTime: "18:00",
      hourlyWage: 200,
      supplementRatePerHour: 0,
      totalGrossEstimate: 1_600,
      currencySymbol: "kr",
      taxRate: nil
    )
  }
}
