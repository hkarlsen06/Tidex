import XCTest

@testable import Tidex

final class ShiftDateBoundaryRegressionTests: XCTestCase {
  // MARK: - Recurring end condition

  func testMonthsEndConditionIncludesOccurrenceOnTheEndDate() {
    // Weekly on Mondays from 2 Feb 2026 for one month ends on Monday 2 Mar 2026.
    let recurring = RecurringShiftRow(
      id: "weekly", user_id: "user-1", job_id: nil,
      start_time: "08:00", end_time: "16:00", repeat_interval_weeks: 0,
      selected_days: ["1": "2026-02-02"], end_condition: .months(value: 1), exclusions: nil,
      date_specific_pause_windows: nil, date_specific_supplements: nil
    )

    let march = RecurringShiftGenerator.generateVirtualShiftsForMonth(
      year: 2_026, month: 3, recurring: recurring)

    XCTAssertEqual(march.map(\.date), ["2026-03-02"])
  }

  // MARK: - 24:00 time fields

  func testEndTimeOf2400ParsesForEditingAndRoundTrips() throws {
    let day = try XCTUnwrap(Date.fromISODateString("2026-09-27"))
    let midnight = try XCTUnwrap(ShiftTimeFieldFormat.pickerDate(from: "24:00:00", on: day))
    let calendar = Calendar(identifier: .gregorian)

    XCTAssertEqual(calendar.component(.hour, from: midnight), 0)
    XCTAssertEqual(calendar.component(.minute, from: midnight), 0)
    XCTAssertEqual(ShiftTimeFieldFormat.storedTime(from: midnight, original: "24:00"), "24:00")
    XCTAssertEqual(ShiftTimeFieldFormat.storedTime(from: midnight, original: "16:00"), "00:00")
  }

  func testEditedTimeReplacesStored2400() throws {
    let day = try XCTUnwrap(Date.fromISODateString("2026-09-27"))
    let edited = try XCTUnwrap(ShiftTimeFieldFormat.pickerDate(from: "22:30", on: day))

    XCTAssertEqual(ShiftTimeFieldFormat.storedTime(from: edited, original: "24:00"), "22:30")
    XCTAssertNil(ShiftTimeFieldFormat.pickerDate(from: "25:00", on: day))
  }

  // MARK: - Wage timeline dates

  func testWageTimelineEndsPreviousPeriodTheDayBeforeTheNextStarts() {
    let entries = WageTimelineProcessor.processSnapshots(
      [
        TestFixtures.wageSnapshot(id: "baseline"),
        TestFixtures.wageSnapshot(id: "march", fromDate: "2026-03-01"),
      ],
      locale: Locale(identifier: "en_US"),
      currency: "kr"
    )

    XCTAssertEqual(entries.first { $0.id == "baseline" }?.endDate, "2026-02-28")
  }
}
