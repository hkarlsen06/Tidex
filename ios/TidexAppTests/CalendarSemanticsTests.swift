import XCTest

@testable import Tidex

@MainActor
internal final class CalendarSemanticsTests: XCTestCase {
  private let dateISO = "2026-09-03"
  private let otherDateISO = "2026-09-05"

  private var shiftsOnDay: [ShiftWithComputations] {
    [
      TestFixtures.computedShift(
        id: "tap-test", shiftDate: dateISO, startTime: "09:00", endTime: "17:00", gross: 2_000)
    ]
  }

  // MARK: - Tap and long-press in Schedule

  internal func testTapOutsideSelectionModeOpensDayWithoutSelecting() {
    let viewModel = ShiftsViewModel()

    let opensDay = viewModel.handleDayTapped(dateISO: dateISO, shiftsOnDay: shiftsOnDay)

    XCTAssertTrue(opensDay)
    XCTAssertTrue(viewModel.selectedDates.isEmpty)
    XCTAssertFalse(viewModel.isSelectionModeEnabled)
  }

  internal func testLongPressEntersSelectionModeWithThatDaySelected() {
    let viewModel = ShiftsViewModel()

    viewModel.beginSelection(dateISO: dateISO)

    XCTAssertTrue(viewModel.isSelectionModeEnabled)
    XCTAssertEqual(viewModel.selectedDates, [dateISO])
  }

  internal func testTapInSelectionModeTogglesDays() {
    let viewModel = ShiftsViewModel()
    viewModel.beginSelection(dateISO: dateISO)

    XCTAssertFalse(viewModel.handleDayTapped(dateISO: otherDateISO, shiftsOnDay: shiftsOnDay))
    XCTAssertEqual(viewModel.selectedDates, [dateISO, otherDateISO])

    XCTAssertFalse(viewModel.handleDayTapped(dateISO: dateISO, shiftsOnDay: shiftsOnDay))
    XCTAssertFalse(viewModel.handleDayTapped(dateISO: otherDateISO, shiftsOnDay: shiftsOnDay))
    XCTAssertTrue(viewModel.selectedDates.isEmpty)
    XCTAssertTrue(viewModel.isSelectionModeEnabled, "Deselecting the last day keeps Select on")
  }

  internal func testTapOnEmptyDayInSelectionModeKeepsSelection() {
    let viewModel = ShiftsViewModel()
    viewModel.beginSelection(dateISO: dateISO)

    XCTAssertFalse(viewModel.handleDayTapped(dateISO: otherDateISO, shiftsOnDay: []))
    XCTAssertEqual(viewModel.selectedDates, [dateISO])
  }

  internal func testLeavingSelectionModeClearsSelection() {
    let viewModel = ShiftsViewModel()
    viewModel.beginSelection(dateISO: dateISO)

    viewModel.isSelectionModeEnabled = false

    XCTAssertTrue(viewModel.selectedDates.isEmpty)
  }

  // MARK: - Cell text

  internal func testCompactCurrencyUsesAppLocaleGrouping() {
    let expected = FormatterCache.numberFormatter(includeDecimals: false, locale: .appLocale)
      .string(from: 1_600)
    XCTAssertEqual(CalendarGridHelper.formatCompactCurrency(1_600), expected)
  }

  internal func testOvernightShiftSaysItEndsTheNextDay() {
    let endsNextDay = String(localized: .calendarAccessibilityEndsNextDay)

    let overnight = CalendarGridHelper.shiftTimesAccessibilityText(
      startTime: "22:00:00", endTime: "06:00:00")
    let dayShift = CalendarGridHelper.shiftTimesAccessibilityText(
      startTime: "09:00:00", endTime: "17:00:00")

    XCTAssertTrue(overnight.contains(endsNextDay), overnight)
    XCTAssertTrue(overnight.contains("22"), overnight)
    XCTAssertFalse(dayShift.contains(endsNextDay), dayShift)
  }

  internal func testEarningsLabelNamesAfterAndBeforeTax() {
    let withTax = CalendarEarningsData(net: 1_600, gross: 2_000, hasTaxEnabled: true)
    let withoutTax = CalendarEarningsData(net: 2_000, gross: 2_000, hasTaxEnabled: false)
    let net = CalendarGridHelper.formatCompactCurrency(1_600)
    let gross = CalendarGridHelper.formatCompactCurrency(2_000)

    XCTAssertEqual(
      CalendarGridHelper.earningsAccessibilityText(withTax),
      String(localized: .calendarAccessibilityEarningsAfterBeforeTax(net, gross)))
    XCTAssertEqual(CalendarGridHelper.earningsAccessibilityText(withoutTax), gross)
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
