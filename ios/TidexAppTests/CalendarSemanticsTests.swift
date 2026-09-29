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

  internal func testDragSelectionEntersSelectionModeWithThoseDaysSelected() {
    let viewModel = ShiftsViewModel()

    viewModel.applyDragSelection([dateISO])

    XCTAssertTrue(viewModel.isSelectionModeEnabled)
    XCTAssertEqual(viewModel.selectedDates, [dateISO])
  }

  internal func testEmptyDragSelectionDoesNotEnterSelectionMode() {
    let viewModel = ShiftsViewModel()

    viewModel.applyDragSelection([])

    XCTAssertFalse(viewModel.isSelectionModeEnabled)
  }

  // MARK: - Long press + drag selection

  internal func testDragSelectsEligibleRangeAndRestoresDaysOnDragBack() {
    let days = CalendarGridHelper.daysInMonth(year: 2_026, month: 9)
    let baseline: Set<String> = ["2026-09-01"]
    var drag = CalendarDragSelection(anchor: "2026-09-03", baseline: baseline)

    drag.hover = "2026-09-06"
    XCTAssertEqual(
      drag.selection(in: days) { $0 != "2026-09-05" },
      ["2026-09-01", "2026-09-03", "2026-09-04", "2026-09-06"])

    drag.hover = "2026-09-02"
    XCTAssertEqual(
      drag.selection(in: days) { _ in true }, ["2026-09-01", "2026-09-02", "2026-09-03"])
  }

  internal func testDragFromSelectedDayDeselects() {
    let days = CalendarGridHelper.daysInMonth(year: 2_026, month: 9)
    var drag = CalendarDragSelection(
      anchor: "2026-09-03", baseline: ["2026-09-03", "2026-09-04", "2026-09-10"])

    drag.hover = "2026-09-04"

    XCTAssertFalse(drag.isSelecting)
    XCTAssertEqual(drag.selection(in: days) { _ in true }, ["2026-09-10"])
  }

  internal func testTapInSelectionModeTogglesDays() {
    let viewModel = ShiftsViewModel()
    viewModel.applyDragSelection([dateISO])

    XCTAssertFalse(viewModel.handleDayTapped(dateISO: otherDateISO, shiftsOnDay: shiftsOnDay))
    XCTAssertEqual(viewModel.selectedDates, [dateISO, otherDateISO])

    XCTAssertFalse(viewModel.handleDayTapped(dateISO: dateISO, shiftsOnDay: shiftsOnDay))
    XCTAssertFalse(viewModel.handleDayTapped(dateISO: otherDateISO, shiftsOnDay: shiftsOnDay))
    XCTAssertTrue(viewModel.selectedDates.isEmpty)
    XCTAssertFalse(viewModel.isSelectionModeEnabled, "Deselecting the last day ends selection mode")
  }

  internal func testTapOnEmptyDayInSelectionModeKeepsSelection() {
    let viewModel = ShiftsViewModel()
    viewModel.applyDragSelection([dateISO])

    XCTAssertFalse(viewModel.handleDayTapped(dateISO: otherDateISO, shiftsOnDay: []))
    XCTAssertEqual(viewModel.selectedDates, [dateISO])
  }

  internal func testClearingSelectionEndsSelectionMode() {
    let viewModel = ShiftsViewModel()
    viewModel.applyDragSelection([dateISO])

    viewModel.clearSelection()

    XCTAssertTrue(viewModel.selectedDates.isEmpty)
    XCTAssertFalse(viewModel.isSelectionModeEnabled)
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

final class RecurringAnchorCellAccessibilityTests: XCTestCase {
  private func label(
    isToday: Bool = false,
    isAnchor: Bool = false,
    isProjected: Bool = false,
    hasConflict: Bool = false,
    hasExistingShift: Bool = false,
    hours: HoursData? = nil
  ) -> String {
    RecurringAnchorCellAccessibility.label(
      dateISO: "2026-03-16",
      isToday: isToday,
      isAnchor: isAnchor,
      isProjected: isProjected,
      hasConflict: hasConflict,
      hasExistingShift: hasExistingShift,
      hours: hours
    )
  }

  private func parts(of label: String) -> [String] {
    label.components(separatedBy: ", ")
  }

  func testPlainDayIsOnlyTheDate() {
    let plain = label()

    XCTAssertEqual(plain, RecurringAnchorCellAccessibility.dateText(dateISO: "2026-03-16"))
    XCTAssertTrue(plain.contains("16"))
  }

  func testAnchorAddsOnePart() {
    XCTAssertEqual(parts(of: label(isAnchor: true)).count, parts(of: label()).count + 1)
  }

  func testAnchorWinsOverProjected() {
    XCTAssertEqual(label(isAnchor: true, isProjected: true), label(isAnchor: true))
  }

  func testConflictIsSpokenAfterTheDayState() {
    let conflicted = label(isProjected: true, hasConflict: true)

    XCTAssertEqual(parts(of: conflicted).count, parts(of: label()).count + 2)
    XCTAssertTrue(conflicted.hasPrefix(label(isProjected: true)))
  }

  func testExistingHoursReplaceTheGenericExistingShiftText() {
    let hours = HoursData(start: "09:00", end: "17:00", crossesMidnight: false)
    let withHours = label(hasExistingShift: true, hours: hours)

    XCTAssertTrue(withHours.contains("09:00"))
    XCTAssertTrue(withHours.contains("17:00"))
    XCTAssertEqual(parts(of: withHours).count, parts(of: label()).count + 1)
  }

  func testInvalidDateFallsBackToTheRawString() {
    let invalid = RecurringAnchorCellAccessibility.label(
      dateISO: "not-a-date", isToday: false, isAnchor: false, isProjected: false,
      hasConflict: false, hasExistingShift: false, hours: nil)

    XCTAssertEqual(invalid, "not-a-date")
  }
}

final class CalendarDragSelectionHitTestTests: XCTestCase {
  // swiftlint:disable:next number_separator
  private let days = CalendarGridHelper.daysInMonth(year: 2026, month: 3)
  private let width: CGFloat = 370

  private var cellWidth: CGFloat {
    let spacing = CalendarGridHelper.cellSpacing
    let columns = CGFloat(CalendarGridHelper.columnCount)
    return (width - spacing * (columns - 1)) / columns
  }

  /// A grid whose rows are `cellHeight` tall, like the grid at an accessibility text size.
  private func gridSize(cellHeight: CGFloat) -> CGSize {
    let rows = CGFloat(days.count / CalendarGridHelper.columnCount)
    return CGSize(
      width: width, height: rows * cellHeight + (rows - 1) * CalendarGridHelper.cellSpacing)
  }

  private func center(row: Int, column: Int, cellHeight: CGFloat) -> CGPoint {
    let spacing = CalendarGridHelper.cellSpacing
    return CGPoint(
      x: CGFloat(column) * (cellWidth + spacing) + cellWidth / 2,
      y: CGFloat(row) * (cellHeight + spacing) + cellHeight / 2
    )
  }

  func testDefaultCellHeightMapsToTheDayUnderThePoint() {
    let cellHeight = cellWidth / CalendarGridHelper.cellAspectRatio
    let row = 2
    let column = 3

    let result = CalendarDragSelection.dateISO(
      at: center(row: row, column: column, cellHeight: cellHeight),
      gridSize: gridSize(cellHeight: cellHeight),
      days: days
    )

    XCTAssertEqual(result, days[row * CalendarGridHelper.columnCount + column].dateISO)
  }

  func testTallerCellsMapToTheDayUnderThePoint() {
    let cellHeight = cellWidth / CalendarGridHelper.cellAspectRatio * 1.6
    let row = 4
    let column = 1

    let result = CalendarDragSelection.dateISO(
      at: center(row: row, column: column, cellHeight: cellHeight),
      gridSize: gridSize(cellHeight: cellHeight),
      days: days
    )

    XCTAssertEqual(result, days[row * CalendarGridHelper.columnCount + column].dateISO)
  }

  func testGapBetweenRowsMapsToNoDay() {
    let cellHeight = cellWidth * 1.5
    let gapY = cellHeight + CalendarGridHelper.cellSpacing / 2

    let result = CalendarDragSelection.dateISO(
      at: CGPoint(x: cellWidth / 2, y: gapY),
      gridSize: gridSize(cellHeight: cellHeight),
      days: days
    )

    XCTAssertNil(result)
  }
}
