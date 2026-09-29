import PDFKit
import XCTest

@testable import Tidex

internal final class DataExportTests: XCTestCase {
  @MainActor
  internal func testDefaultsToLastMonthSoExportIsReady() {
    let viewModel: DataSettingsViewModel = DataSettingsViewModel()

    XCTAssertEqual(viewModel.selectedPreset, .lastMonth)
    XCTAssertEqual(viewModel.resolvedDateRange?.from, ExportPeriodPreset.lastMonth.resolveDateRange()?.from)
    XCTAssertTrue(viewModel.canExport)
  }

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

  internal func testExportFileNameStartsWithUserName() throws {
    XCTAssertEqual(DataSettingsViewModel.fileNamePrefix(userName: "Jørgen  Ås"), "jørgen-ås")
    XCTAssertEqual(DataSettingsViewModel.fileNamePrefix(userName: "../../etc/passwd"), "etc-passwd")
    XCTAssertEqual(DataSettingsViewModel.fileNamePrefix(userName: " "), "tidex")

    let data: ExportResponse = ExportResponse(generatedAt: Date(), currencySymbol: "kr", shifts: [])
    let url: URL = try DataSettingsViewModel.generateCSV(
      from: data,
      range: (from: "2026-01-01", to: "2026-01-31"),
      localeIdentifier: "en",
      userName: "Ola Nordmann"
    )
    XCTAssertEqual(url.lastPathComponent, "ola-nordmann_jan-2026.csv")
  }

  internal func testPDFShowsSummaryAndRepeatsMonthOnNextPage() throws {
    // Two shifts a day for all of September fills more than one page.
    let shifts: [ExportedShift] = (1...30).flatMap { day in
      (0..<2).map { index in
        ExportedShift(
          id: "shift-\(day)-\(index)",
          date: String(format: "2026-09-%02d", day),
          startTime: index == 0 ? "08:00" : "16:00",
          endTime: index == 0 ? "12:00" : "20:00",
          type: 0,
          jobName: "Rema Majorstuen",
          recurringId: nil,
          calc: ExportedShift.ShiftCalculation(hours: 4, baseWage: 800, supplement: 0, total: 800)
        )
      }
    }
    let data: ExportResponse = ExportResponse(generatedAt: Date(), currencySymbol: "kr", shifts: shifts)

    let url: URL = try DataSettingsViewModel.generatePDF(
      from: data,
      range: (from: "2026-09-01", to: "2026-09-30"),
      localeIdentifier: "en_US",
      userName: "Ola Nordmann",
      userContact: "ola@example.com"
    )
    let document: PDFDocument = try XCTUnwrap(PDFDocument(url: url))

    XCTAssertGreaterThan(document.pageCount, 1)
    let firstPage: String = try XCTUnwrap(document.page(at: 0)?.string)
    XCTAssertTrue(firstPage.contains("Tidex"))
    XCTAssertTrue(firstPage.contains("Ola Nordmann"))
    XCTAssertTrue(firstPage.contains("48,000 kr"), "Total pay should be in the summary card")
    // Rows only show the day number, so a continued month needs its header again. The
    // period in the continuation line accounts for one of the two matches.
    let secondPage: String = try XCTUnwrap(document.page(at: 1)?.string)
    XCTAssertEqual(secondPage.components(separatedBy: "September 2026").count - 1, 2)
  }

  deinit {
    // Required by SwiftLint for XCTestCase subclasses.
  }
}
