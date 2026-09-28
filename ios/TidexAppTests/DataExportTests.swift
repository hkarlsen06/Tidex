import XCTest

@testable import Tidex

internal final class DataExportTests: XCTestCase {
  internal func testPublicHolidayCountsAsSundayOrHoliday() {
    // 2026-05-17 is a Sunday; 2026-05-14 (Ascension Day) is a Thursday.
    XCTAssertEqual(DataSettingsViewModel.shiftType(dateISO: "2026-05-14"), 2)
    XCTAssertEqual(DataSettingsViewModel.shiftType(dateISO: "2026-05-17"), 2)
    XCTAssertEqual(DataSettingsViewModel.shiftType(dateISO: "2026-05-16"), 1)
    XCTAssertEqual(DataSettingsViewModel.shiftType(dateISO: "2026-05-13"), 0)
  }

  internal func testCSVIncludesJobColumn() throws {
    let shift: ExportedShift = ExportedShift(
      id: "shift-1",
      date: "2026-05-13",
      startTime: "16:00",
      endTime: "22:00",
      type: 0,
      jobName: "Rema Majorstuen",
      recurringId: nil,
      calc: ExportedShift.ShiftCalculation(hours: 6, baseWage: 1_200, supplement: 150, total: 1_350)
    )
    let data: ExportResponse = ExportResponse(
      generatedAt: Date(),
      currencySymbol: "kr",
      shifts: [shift]
    )

    let url: URL = try DataSettingsViewModel.generateCSV(
      from: data,
      range: (from: "2026-05-01", to: "2026-05-31"),
      localeIdentifier: "en"
    )
    let lines: [String] = try String(contentsOf: url, encoding: .utf8)
      .split(separator: "\n")
      .map(String.init)

    let header: [String] = lines[0].components(separatedBy: ";")
    let row: [String] = lines[1].components(separatedBy: ";")
    let jobIndex: Int = try XCTUnwrap(header.firstIndex(of: String(localized: .dataExportTableJob)))
    XCTAssertEqual(row[jobIndex], "Rema Majorstuen")
    XCTAssertEqual(header.count, row.count)
    XCTAssertEqual(header.count, lines[2].components(separatedBy: ";").count)
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
