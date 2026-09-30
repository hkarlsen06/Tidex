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

  // MARK: - Locale/calendar independence

  /// A machine "yyyy-MM-dd" formatter built from the device's current locale/calendar (the bug
  /// this guards against) misinterprets the year under a Thai locale with the Buddhist calendar,
  /// because BE year 2026 is CE year 1483. `Date.fromISODateString` must keep parsing "2026-09-28"
  /// as Gregorian 2026 regardless.
  func testISODateParsingIsIndependentOfDeviceCalendar() throws {
    let buggyFormatter = DateFormatter()
    buggyFormatter.locale = Locale(identifier: "th_TH")
    buggyFormatter.calendar = Calendar(identifier: .buddhist)
    buggyFormatter.dateFormat = "yyyy-MM-dd"
    let buggyParsed = try XCTUnwrap(buggyFormatter.date(from: "2026-09-28"))
    var gregorian = Calendar(identifier: .gregorian)
    gregorian.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
    XCTAssertNotEqual(gregorian.component(.year, from: buggyParsed), 2_026)

    let fixedParsed = try XCTUnwrap(
      Date.fromISODateString("2026-09-28", in: try XCTUnwrap(TimeZone(identifier: "UTC"))))
    XCTAssertEqual(gregorian.component(.year, from: fixedParsed), 2_026)
    XCTAssertEqual(fixedParsed.toISODateString(in: try XCTUnwrap(TimeZone(identifier: "UTC"))), "2026-09-28")
  }

  /// A machine "HH:mm" formatter built from an Arabic locale renders native-script digits, so the
  /// resulting string no longer round-trips as "14:30". `FormatterCache.hourMinuteFormatter`
  /// (POSIX locale) must always produce Western digits for storage/comparison.
  func testHourMinuteFormattingIsIndependentOfDeviceLocale() throws {
    let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
    let time = try XCTUnwrap(FormatterCache.hourMinuteFormatter(timeZone: timeZone).date(from: "14:30"))

    let buggyFormatter = DateFormatter()
    buggyFormatter.locale = Locale(identifier: "ar_SA")
    buggyFormatter.calendar = Calendar(identifier: .gregorian)
    buggyFormatter.timeZone = timeZone
    buggyFormatter.dateFormat = "HH:mm"
    XCTAssertNotEqual(buggyFormatter.string(from: time), "14:30")

    XCTAssertEqual(time.toHourMinuteString(in: timeZone), "14:30")
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
