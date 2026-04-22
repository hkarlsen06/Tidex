import Foundation
import PDFKit
import Supabase
import UIKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "DataSettingsViewModel")

// MARK: - Period Preset

/// Period preset options for export
enum ExportPeriodPreset: String, CaseIterable, Identifiable {
  case lastMonth = "last_month"
  case currentMonth = "current_month"
  case lastYear = "last_year"
  case currentYear = "current_year"
  case custom = "custom"

  var id: String { rawValue }

  /// Resolve the date range for this preset
  func resolveDateRange() -> (from: String, to: String)? {
    let now = Date()
    let calendar = Calendar.current

    switch self {
    case .currentMonth:
      guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)
      else {
        return nil
      }
      return (toISODate(start), toISODate(end))

    case .lastMonth:
      guard
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
        let start = calendar.date(byAdding: .month, value: -1, to: thisMonth),
        let end = calendar.date(byAdding: .day, value: -1, to: thisMonth)
      else {
        return nil
      }
      return (toISODate(start), toISODate(end))

    case .currentYear:
      let year = calendar.component(.year, from: now)
      guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
        let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31))
      else {
        return nil
      }
      return (toISODate(start), toISODate(end))

    case .lastYear:
      let year = calendar.component(.year, from: now) - 1
      guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
        let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31))
      else {
        return nil
      }
      return (toISODate(start), toISODate(end))

    case .custom:
      return nil
    }
  }
}

// MARK: - Export Types

/// Export format options
enum ExportFormat {
  case pdf
  case csv
  case calendar
}

/// Response from the export API
struct ExportResponse: Codable, Sendable {
  let generatedAt: String
  let shifts: [ExportedShift]
}

/// A shift in the export response
struct ExportedShift: Codable, Sendable {
  let id: String
  let date: String
  let startTime: String
  let endTime: String
  let type: Int  // 0 = weekday, 1 = saturday, 2 = sunday
  let recurringId: String?
  let calc: ShiftCalculation

  struct ShiftCalculation: Codable, Sendable {
    let hours: Double
    let baseWage: Double
    let supplement: Double
    let total: Double
  }
}

// MARK: - View Model

/// ViewModel for data export settings
@MainActor
final class DataSettingsViewModel: ObservableObject {
  // MARK: - Published State

  /// Selected period preset
  @Published var selectedPreset: ExportPeriodPreset? = nil

  /// Custom date range (when preset is .custom)
  @Published var customFromDate: Date = Date()
  @Published var customToDate: Date = Date()

  /// Loading state for PDF export
  @Published var isExportingPdf = false

  /// Loading state for CSV export
  @Published var isExportingCsv = false

  /// Loading state for calendar export
  @Published var isExportingCalendar = false

  /// Error message
  @Published var errorMessage: String?

  /// URL for share sheet presentation
  @Published var shareURL: URL?

  /// Whether a sync is in progress
  @Published var isSyncing = false

  // MARK: - Private Properties

  private var userId: String?

  // MARK: - Computed Properties

  /// The resolved date range based on preset or custom dates
  var resolvedDateRange: (from: String, to: String)? {
    guard let preset = selectedPreset else { return nil }

    if preset == .custom {
      // Validate custom range
      if customFromDate > customToDate {
        return nil
      }
      return (toISODate(customFromDate), toISODate(customToDate))
    }

    return preset.resolveDateRange()
  }

  /// Whether export is currently possible
  var canExport: Bool {
    resolvedDateRange != nil && !isExportingPdf && !isExportingCsv && !isExportingCalendar
      && !isSyncing
  }

  /// Whether the custom date range is invalid
  var isCustomRangeInvalid: Bool {
    selectedPreset == .custom && customFromDate > customToDate
  }

  // MARK: - Public Methods

  /// Load initial state
  func loadSettings() async {
    do {
      userId = try await AuthSessionManager.shared.getUserId()
    } catch {
      logger.error("Failed to get user session: \(error.localizedDescription)")
    }
  }

  /// Export shifts in the specified format
  func exportShifts(format: ExportFormat, locale: Locale) async {
    guard let range = resolvedDateRange, let userId = userId else { return }

    // Set loading state
    switch format {
    case .pdf:
      isExportingPdf = true
    case .csv:
      isExportingCsv = true
    case .calendar:
      isExportingCalendar = true
    }
    errorMessage = nil

    defer {
      switch format {
      case .pdf:
        isExportingPdf = false
      case .csv:
        isExportingCsv = false
      case .calendar:
        isExportingCalendar = false
      }
    }

    do {
      // Calendar export uses local data - no network needed
      if format == .calendar {
        try await exportToCalendarFromLocalData(userId: userId, from: range.from, to: range.to)
        return
      }

      // PDF/CSV export is generated from local synced data.
      // Sync first to ensure local changes are pushed to the server
      isSyncing = true
      logger.info("Syncing before export...")
      let syncResult = await SyncCoordinator.shared.sync(reason: .localChange, userId: userId)
      isSyncing = false

      if !syncResult.success, let error = syncResult.error {
        logger.warning("Sync had issues before export: \(error)")
        // Continue with export anyway - user might want old data
      }

      // Build export data from local storage
      let exportData = try await fetchExportData(from: range.from, to: range.to)

      // Handle export based on format
      switch format {
      case .pdf:
        let userName = AppCoordinator.shared.userDisplayName.trimmingCharacters(
          in: .whitespacesAndNewlines
        )
        let session = try? await AuthSessionManager.shared.getSession()
        let userContact = (session?.user.email ?? session?.user.phone ?? "").trimmingCharacters(
          in: .whitespacesAndNewlines
        )
        let fileURL = try await Self.generatePDFOffMain(
          from: exportData,
          range: range,
          localeIdentifier: locale.identifier,
          userName: userName,
          userContact: userContact
        )
        shareURL = fileURL

      case .csv:
        let fileURL = try await Self.generateCSVOffMain(
          from: exportData,
          range: range,
          localeIdentifier: locale.identifier
        )
        shareURL = fileURL

      case .calendar:
        break  // Already handled above
      }

    } catch {
      logger.error("Export failed: \(error.localizedDescription)")
      errorMessage = error.localizedDescription
    }
  }

  /// Export shifts to the device calendar using local data
  private func exportToCalendarFromLocalData(userId: String, from: String, to: String) async throws
  {
    logger.info("Exporting to calendar from local data: \(from) to \(to)")

    // Parse date range
    guard let startDate = parseISODate(from),
      let endDate = parseISODate(to)
    else {
      throw CalendarExportError.invalidDate
    }

    // Fetch regular shifts from local storage
    let regularShifts = ShiftsRepository.shared.getShifts(
      for: userId,
      startDate: startDate,
      endDate: endDate
    )
    logger.info("Found \(regularShifts.count) regular shifts in local storage")

    // Fetch recurring shifts from local storage
    let recurringShifts = RecurringShiftsRepository.shared.getRecurringShifts(for: userId)
    logger.info("Found \(recurringShifts.count) recurring shift patterns")

    // Generate virtual shifts from recurring patterns
    var virtualShifts: [ExportedShift] = []

    let calendar = Calendar.current
    let startYear = calendar.component(.year, from: startDate)
    let startMonth = calendar.component(.month, from: startDate)
    let endYear = calendar.component(.year, from: endDate)
    let endMonth = calendar.component(.month, from: endDate)

    // Track real shifts by date+time to detect duplicates from materialized recurring shifts
    let realShiftKeys = Set(
      regularShifts.map { "\($0.shift_date)|\($0.start_time)|\($0.end_time)" })

    for recurring in recurringShifts {
      var currentYear = startYear
      var currentMonth = startMonth

      while currentYear < endYear || (currentYear == endYear && currentMonth <= endMonth) {
        let generatedShifts = RecurringShiftGenerator.generateVirtualShiftsForMonth(
          year: currentYear,
          month: currentMonth,
          recurring: recurring
        )

        for virtualShift in generatedShifts {
          // Skip if outside the date range
          guard virtualShift.date >= from && virtualShift.date <= to else { continue }

          // Skip if a real shift with matching times exists (materialized recurring shift)
          let key = "\(virtualShift.date)|\(recurring.cleanStartTime)|\(recurring.cleanEndTime)"
          guard !realShiftKeys.contains(key) else { continue }

          // Convert to ExportedShift
          virtualShifts.append(
            ExportedShift(
              id: "virtual-\(recurring.id)-\(virtualShift.date)",
              date: virtualShift.date,
              startTime: recurring.start_time,
              endTime: recurring.end_time,
              type: getShiftType(dateISO: virtualShift.date),
              recurringId: recurring.id,
              calc: ExportedShift.ShiftCalculation(hours: 0, baseWage: 0, supplement: 0, total: 0)
            ))
        }

        // Move to next month
        currentMonth += 1
        if currentMonth > 12 {
          currentMonth = 1
          currentYear += 1
        }
      }
    }

    logger.info("Generated \(virtualShifts.count) virtual shifts from recurring patterns")

    // Convert regular shifts to ExportedShift format
    let exportedRegularShifts = regularShifts.map { shift in
      ExportedShift(
        id: shift.id,
        date: shift.shift_date,
        startTime: shift.start_time,
        endTime: shift.end_time,
        type: getShiftType(dateISO: shift.shift_date),
        recurringId: shift.recurring_id,
        calc: ExportedShift.ShiftCalculation(hours: 0, baseWage: 0, supplement: 0, total: 0)
      )
    }

    // Combine and sort all shifts
    let allShifts = (exportedRegularShifts + virtualShifts).sorted { $0.date < $1.date }

    logger.info("Total shifts to export to calendar: \(allShifts.count)")

    guard !allShifts.isEmpty else {
      throw CalendarExportError.noShifts
    }

    let calendarName = String(localized: .dataExportCalendarCalendarName)
    let eventTitle = String(localized: .dataExportCalendarEventTitle)

    try await CalendarExportService.shared.exportShifts(
      allShifts,
      calendarName: calendarName,
      eventTitle: eventTitle
    )

    Haptics.play(.success)
  }

  /// Calculate shift type based on date
  /// 0 = weekday (Mon-Fri), 1 = Saturday, 2 = Sunday/holiday
  private func getShiftType(dateISO: String) -> Int {
    guard let date = parseISODate(dateISO) else { return 0 }
    let calendar = Calendar.current
    let weekday = calendar.component(.weekday, from: date)

    switch weekday {
    case 1: return 2  // Sunday
    case 7: return 1  // Saturday
    default: return 0  // Weekday
    }
  }

  /// Clear error message
  func clearError() {
    errorMessage = nil
  }

  /// Dismiss share sheet
  func dismissShareSheet() {
    // Clean up temp file
    if let url = shareURL {
      try? FileManager.default.removeItem(at: url)
    }
    shareURL = nil
  }

  // MARK: - Private Methods

  /// Build export data from local storage.
  private func fetchExportData(from: String, to: String) async throws -> ExportResponse {
    guard let userId else {
      throw ExportError.unauthorized
    }
    guard let startDate = parseISODate(from), let endDate = parseISODate(to) else {
      throw ExportError.invalidDateRange
    }

    logger.info("Building export data locally for \(from) to \(to)")

    let regularShifts = await ShiftsRepository.shared.getShiftsOffMain(
      for: userId,
      startDate: startDate,
      endDate: endDate
    )
    let recurringShifts = RecurringShiftsRepository.shared.getRecurringShifts(for: userId)
    let snapshotsRepository = SnapshotsRepository.shared

    var exportedShifts = regularShifts.map { shift in
      makeExportedShift(
        from: shift,
        snapshot: snapshotsRepository.snapshotForDate(
          shift.shift_date,
          userId: userId,
          jobId: shift.job_id
        )
      )
    }

    let calendar = Calendar.current
    let startYear = calendar.component(.year, from: startDate)
    let startMonth = calendar.component(.month, from: startDate)
    let endYear = calendar.component(.year, from: endDate)
    let endMonth = calendar.component(.month, from: endDate)

    let realShiftKeys = Set(
      regularShifts.map { "\($0.shift_date)|\($0.start_time)|\($0.end_time)" }
    )

    for recurring in recurringShifts {
      var currentYear = startYear
      var currentMonth = startMonth

      while currentYear < endYear || (currentYear == endYear && currentMonth <= endMonth) {
        let generatedShifts = RecurringShiftGenerator.generateVirtualShiftsForMonth(
          year: currentYear,
          month: currentMonth,
          recurring: recurring
        )

        for virtualShift in generatedShifts {
          guard virtualShift.date >= from && virtualShift.date <= to else { continue }

          let key = "\(virtualShift.date)|\(recurring.cleanStartTime)|\(recurring.cleanEndTime)"
          guard !realShiftKeys.contains(key) else { continue }

          let virtualRow = recurring.makeVirtualShift(
            date: virtualShift.date,
            weekday: virtualShift.weekday,
            userId: userId
          )

          exportedShifts.append(
            makeExportedShift(
              from: virtualRow,
              snapshot: snapshotsRepository.snapshotForDate(
                virtualShift.date,
                userId: userId,
                jobId: recurring.job_id
              )
            )
          )
        }

        currentMonth += 1
        if currentMonth > 12 {
          currentMonth = 1
          currentYear += 1
        }
      }
    }

    exportedShifts.sort {
      if $0.date == $1.date {
        return $0.startTime < $1.startTime
      }
      return $0.date < $1.date
    }

    return ExportResponse(
      generatedAt: ISO8601DateFormatter().string(from: Date()),
      shifts: exportedShifts
    )
  }

  private func makeExportedShift(from shift: ShiftRow, snapshot: WageSnapshot?) -> ExportedShift {
    let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)

    return ExportedShift(
      id: shift.id,
      date: shift.shift_date,
      startTime: shift.start_time,
      endTime: shift.end_time,
      type: getShiftType(dateISO: shift.shift_date),
      recurringId: shift.recurring_id,
      calc: ExportedShift.ShiftCalculation(
        hours: computed.paidHours,
        baseWage: computed.basePay,
        supplement: computed.supplementPay,
        total: computed.gross
      )
    )
  }

  /// Generate PDF from export data in a detached task.
  private static func generatePDFOffMain(
    from data: ExportResponse,
    range: (from: String, to: String),
    localeIdentifier: String,
    userName: String,
    userContact: String
  ) async throws -> URL {
    try await Task.detached(priority: .userInitiated) {
      try generatePDF(
        from: data,
        range: range,
        localeIdentifier: localeIdentifier,
        userName: userName,
        userContact: userContact
      )
    }.value
  }

  /// Generate CSV from export data in a detached task.
  private static func generateCSVOffMain(
    from data: ExportResponse,
    range: (from: String, to: String),
    localeIdentifier: String
  ) async throws -> URL {
    try await Task.detached(priority: .utility) {
      try generateCSV(from: data, range: range, localeIdentifier: localeIdentifier)
    }.value
  }

  /// Generate PDF from export data
  private nonisolated static func generatePDF(
    from data: ExportResponse,
    range: (from: String, to: String),
    localeIdentifier: String,
    userName: String,
    userContact: String
  ) throws -> URL {
    let locale = Locale(identifier: localeIdentifier)
    let pdfMetaData = [
      kCGPDFContextCreator: "Tidex",
      kCGPDFContextAuthor: "Tidex",
      kCGPDFContextTitle: "Shift Export",
    ]

    let format = UIGraphicsPDFRendererFormat()
    format.documentInfo = pdfMetaData as [String: Any]

    // A4 size in points (72 points = 1 inch)
    let pageWidth: CGFloat = 595.0
    let pageHeight: CGFloat = 842.0
    let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
    let margin: CGFloat = 40
    let contentWidth = pageWidth - (margin * 2)
    let footerHeight: CGFloat = 22
    let bottomLimit = pageHeight - margin - footerHeight

    let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
    let totalHours = data.shifts.reduce(0.0) { $0 + $1.calc.hours }
    let totalBaseWage = data.shifts.reduce(0.0) { $0 + $1.calc.baseWage }
    let totalSupplement = data.shifts.reduce(0.0) { $0 + $1.calc.supplement }
    let totalWage = data.shifts.reduce(0.0) { $0 + $1.calc.total }

    let weekdayCount = data.shifts.filter { $0.type == 0 }.count
    let saturdayCount = data.shifts.filter { $0.type == 1 }.count
    let sundayCount = data.shifts.filter { $0.type == 2 }.count

    let title = String(localized: .dataExportPdfDocumentTitle)
    let logoImage = UIImage(named: "TidexLogo")
    let exportedLabel = String(localized: .dataExportPdfExportedLabel)
    let summaryTitle = String(localized: .dataExportPdfSummary)
    let currencySymbol = "kr"
    let hoursUnit = String(localized: .commonHours)

    let detailDateFormatter = DateFormatter()
    detailDateFormatter.dateStyle = .medium
    detailDateFormatter.timeStyle = .none
    detailDateFormatter.locale = locale

    let tableDateFormatter = DateFormatter()
    tableDateFormatter.dateStyle = .short
    tableDateFormatter.timeStyle = .none
    tableDateFormatter.locale = locale

    let generatedAtFormatter = DateFormatter()
    generatedAtFormatter.dateStyle = .medium
    generatedAtFormatter.timeStyle = .short
    generatedAtFormatter.locale = locale

    let monthFormatter = DateFormatter()
    monthFormatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
    monthFormatter.locale = locale

    let weekdayFormatter = DateFormatter()
    weekdayFormatter.setLocalizedDateFormatFromTemplate("EEE")
    weekdayFormatter.locale = locale

    let generatedAtText =
      "\(exportedLabel) \(Self.formatExportTimestamp(data.generatedAt, formatter: generatedAtFormatter))"
    let fromDate =
      parseISODate(range.from).map { detailDateFormatter.string(from: $0) } ?? range.from
    let toDate = parseISODate(range.to).map { detailDateFormatter.string(from: $0) } ?? range.to
    let periodText = "\(fromDate) - \(toDate)"

    let summaryRows: [(String, String)] = [
      (String(localized: .dataExportPdfTotalShifts), "\(data.shifts.count)"),
      (
        String(localized: .dataExportPdfTotalHours),
        "\(Self.formatNumber(totalHours, decimals: 2, locale: locale)) \(hoursUnit)"
      ),
      (
        String(localized: .dataExportPdfTotalBasePay),
        "\(Self.formatNumber(totalBaseWage, decimals: 0, locale: locale)) \(currencySymbol)"
      ),
      (
        String(localized: .dataExportPdfTotalSupplements),
        "\(Self.formatNumber(totalSupplement, decimals: 0, locale: locale)) \(currencySymbol)"
      ),
      (
        String(localized: .dataExportPdfTotalPay),
        "\(Self.formatNumber(totalWage, decimals: 0, locale: locale)) \(currencySymbol)"
      ),
    ]

    let shiftTypeRows: [(String, String)] = [
      (String(localized: .dataExportPdfWeekdays), "\(weekdayCount)"),
      (String(localized: .dataExportPdfSaturdays), "\(saturdayCount)"),
      (String(localized: .dataExportPdfSundaysHolidays), "\(sundayCount)"),
    ]

    let columns: [PDFColumn] = [
      .init(title: String(localized: .dataExportTableDate), width: 84, alignment: .left),
      .init(title: String(localized: .dataExportTableDay), width: 40, alignment: .left),
      .init(title: String(localized: .dataExportTableStart), width: 48, alignment: .center),
      .init(title: String(localized: .dataExportTableEnd), width: 48, alignment: .center),
      .init(title: String(localized: .dataExportTableHours), width: 60, alignment: .right),
      .init(title: String(localized: .dataExportTableBase), width: 75, alignment: .right),
      .init(title: String(localized: .dataExportTableSupplement), width: 80, alignment: .right),
      .init(title: String(localized: .dataExportTableTotal), width: 80, alignment: .right),
    ]

    let pdfData = renderer.pdfData { context in
      let titleFont = UIFont.systemFont(ofSize: 18, weight: .bold)
      let headerNameFont = UIFont.systemFont(ofSize: 12, weight: .semibold)
      let metaFont = UIFont.systemFont(ofSize: 10, weight: .regular)
      let sectionFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
      let bodyFont = UIFont.systemFont(ofSize: 10, weight: .regular)
      let tableHeaderFont = UIFont.systemFont(ofSize: 9, weight: .semibold)
      let tableRowFont = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
      let totalFont = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)

      let textColor = UIColor.black
      let secondaryTextColor = UIColor(white: 0.18, alpha: 1)
      let lineColor = UIColor(white: 0.68, alpha: 1)
      let tableHeaderLineColor = UIColor(white: 0.42, alpha: 1)

      let headerHeight: CGFloat = 70
      let summaryRowHeight: CGFloat = 16
      let tableHeaderHeight: CGFloat = 22
      let firstMonthHeaderHeight: CGFloat = 14
      let monthHeaderHeight: CGFloat = 24
      let tableRowHeight: CGFloat = 18
      let totalsHeight: CGFloat = 24
      let footerY = pageHeight - margin - 2
      let pageNumberWidth: CGFloat = 30
      let cellPadding: CGFloat = 6
      let headerColumnGap: CGFloat = 16
      let headerRightColumnWidth: CGFloat = 210
      let logoMaxWidth: CGFloat = 132
      let logoHeight: CGFloat = 30
      let summaryRowStyle = PDFLabelValueRowStyle(
        labelFont: bodyFont,
        valueFont: bodyFont,
        color: textColor
      )

      var pageNumber = 0
      var yPosition: CGFloat = 0
      var lastRenderedMonthKey: String?

      func drawPageFooter() {
        Self.drawPDFText(
          "\(pageNumber)",
          in: CGRect(
            x: pageWidth - margin - pageNumberWidth,
            y: footerY,
            width: pageNumberWidth,
            height: 12
          ),
          font: metaFont,
          color: secondaryTextColor,
          alignment: .right
        )
      }

      func drawDocumentHeader() {
        let leftColumnWidth = contentWidth - headerRightColumnWidth - headerColumnGap
        let rightColumnX = margin + leftColumnWidth + headerColumnGap

        Self.drawPDFText(
          title,
          in: CGRect(x: margin, y: margin, width: contentWidth - logoMaxWidth - 12, height: 20),
          font: titleFont,
          color: textColor
        )
        if let logoImage {
          let aspectRatio = logoImage.size.width / max(logoImage.size.height, 1)
          let logoWidth = min(logoMaxWidth, logoHeight * aspectRatio)
          logoImage.draw(
            in: CGRect(
              x: pageWidth - margin - logoWidth,
              y: margin - 1,
              width: logoWidth,
              height: logoHeight
            )
          )
        }

        if !userName.isEmpty {
          let nameLine = NSMutableAttributedString(
            string: "for ",
            attributes: [
              .font: metaFont,
              .foregroundColor: secondaryTextColor,
            ]
          )
          nameLine.append(
            NSAttributedString(
              string: userName,
              attributes: [
                .font: headerNameFont,
                .foregroundColor: textColor,
              ]
            )
          )
          Self.drawPDFAttributedText(
            nameLine,
            in: CGRect(x: margin, y: margin + 26, width: leftColumnWidth, height: 14)
          )
        }
        if !userContact.isEmpty {
          Self.drawPDFText(
            userContact,
            in: CGRect(x: margin, y: margin + 44, width: leftColumnWidth, height: 12),
            font: metaFont,
            color: secondaryTextColor
          )
        }
        Self.drawPDFText(
          periodText,
          in: CGRect(x: rightColumnX, y: margin + 26, width: headerRightColumnWidth, height: 12),
          font: headerNameFont,
          color: textColor,
          alignment: .right
        )
        Self.drawPDFText(
          generatedAtText,
          in: CGRect(x: rightColumnX, y: margin + 44, width: headerRightColumnWidth, height: 12),
          font: metaFont,
          color: secondaryTextColor,
          alignment: .right
        )
        yPosition = margin + headerHeight + 14
      }

      func drawSummarySection() {
        Self.drawPDFText(
          summaryTitle,
          in: CGRect(x: margin, y: yPosition, width: contentWidth, height: 14),
          font: sectionFont,
          color: textColor
        )
        yPosition += 18

        for (label, value) in summaryRows {
          Self.drawLabelValueRow(
            label: label,
            value: value,
            in: CGRect(x: margin, y: yPosition, width: contentWidth, height: summaryRowHeight),
            style: summaryRowStyle
          )
          yPosition += summaryRowHeight
        }

        yPosition += 4
        Self.drawPDFText(
          String(localized: .dataExportPdfShiftsByType),
          in: CGRect(x: margin, y: yPosition, width: contentWidth, height: 14),
          font: sectionFont,
          color: textColor
        )
        yPosition += summaryRowHeight

        for (label, value) in shiftTypeRows {
          Self.drawLabelValueRow(
            label: label,
            value: value,
            in: CGRect(x: margin, y: yPosition, width: contentWidth, height: summaryRowHeight),
            style: summaryRowStyle
          )
          yPosition += summaryRowHeight
        }

        yPosition += 18
      }

      func drawTableHeader() {
        var xPosition = margin
        for column in columns {
          Self.drawPDFText(
            column.title,
            in: CGRect(
              x: xPosition + cellPadding,
              y: yPosition,
              width: column.width - (cellPadding * 2),
              height: tableHeaderHeight
            ),
            font: tableHeaderFont,
            color: textColor,
            alignment: column.alignment
          )
          xPosition += column.width
        }

        let dividerY = yPosition + tableHeaderHeight
        Self.drawLine(
          from: CGPoint(x: margin, y: dividerY),
          to: CGPoint(x: pageWidth - margin, y: dividerY),
          color: tableHeaderLineColor,
          width: 0.8
        )
        yPosition = dividerY + 4
      }

      func drawMonthSeparator(title: String, height: CGFloat) {
        let titleY = yPosition + height - tableHeaderFont.lineHeight - 2
        Self.drawPDFText(
          title,
          in: CGRect(
            x: margin,
            y: titleY,
            width: contentWidth,
            height: tableHeaderFont.lineHeight
          ),
          font: tableHeaderFont,
          color: textColor
        )

        let dividerY = yPosition + height
        Self.drawLine(
          from: CGPoint(x: margin, y: dividerY),
          to: CGPoint(x: pageWidth - margin, y: dividerY),
          color: lineColor,
          width: 0.6
        )
        yPosition += height
      }

      func beginPage(includeSummary: Bool) {
        context.beginPage()
        pageNumber += 1
        drawDocumentHeader()
        if includeSummary {
          drawSummarySection()
        }
        drawTableHeader()
        drawPageFooter()
      }

      beginPage(includeSummary: true)

      for shift in data.shifts {
        let shiftDate = parseISODate(shift.date)
        let monthKey: String
        let monthTitle: String

        if let shiftDate {
          let components = Calendar.current.dateComponents([.year, .month], from: shiftDate)
          monthKey = "\(components.year ?? 0)-\(components.month ?? 0)"
          monthTitle = monthFormatter.string(from: shiftDate)
        } else {
          monthKey = String(shift.date.prefix(7))
          monthTitle = shift.date
        }

        let shouldDrawMonthSeparator = monthKey != lastRenderedMonthKey
        let separatorHeight =
          lastRenderedMonthKey == nil ? firstMonthHeaderHeight : monthHeaderHeight
        let requiredHeight = tableRowHeight + (shouldDrawMonthSeparator ? separatorHeight : 0)

        if yPosition + requiredHeight > bottomLimit {
          beginPage(includeSummary: false)
        }

        if shouldDrawMonthSeparator {
          let separatorHeight =
            lastRenderedMonthKey == nil ? firstMonthHeaderHeight : monthHeaderHeight
          drawMonthSeparator(title: monthTitle, height: separatorHeight)
          lastRenderedMonthKey = monthKey
        }

        let rowValues = [
          shiftDate.map { tableDateFormatter.string(from: $0) } ?? shift.date,
          shiftDate.map { weekdayFormatter.string(from: $0) } ?? "",
          shift.startTime,
          shift.endTime,
          Self.formatNumber(shift.calc.hours, decimals: 2, locale: locale),
          Self.formatNumber(shift.calc.baseWage, decimals: 0, locale: locale),
          Self.formatNumber(shift.calc.supplement, decimals: 0, locale: locale),
          Self.formatNumber(shift.calc.total, decimals: 0, locale: locale),
        ]

        var xPosition = margin
        for (column, value) in zip(columns, rowValues) {
          Self.drawPDFText(
            value,
            in: CGRect(
              x: xPosition + cellPadding,
              y: yPosition,
              width: column.width - (cellPadding * 2),
              height: tableRowHeight
            ),
            font: tableRowFont,
            color: textColor,
            alignment: column.alignment
          )
          xPosition += column.width
        }

        Self.drawLine(
          from: CGPoint(x: margin, y: yPosition + tableRowHeight),
          to: CGPoint(x: pageWidth - margin, y: yPosition + tableRowHeight),
          color: lineColor,
          width: 0.45
        )
        yPosition += tableRowHeight
      }

      if yPosition + totalsHeight > bottomLimit {
        beginPage(includeSummary: false)
      }

      let totalsTop = yPosition
      Self.drawLine(
        from: CGPoint(x: margin, y: totalsTop),
        to: CGPoint(x: pageWidth - margin, y: totalsTop),
        color: tableHeaderLineColor,
        width: 0.8
      )

      let totalValues = [
        String(localized: .dataExportPdfSumLabel),
        "",
        "",
        "",
        Self.formatNumber(totalHours, decimals: 2, locale: locale),
        Self.formatNumber(totalBaseWage, decimals: 0, locale: locale),
        Self.formatNumber(totalSupplement, decimals: 0, locale: locale),
        Self.formatNumber(totalWage, decimals: 0, locale: locale),
      ]

      var xPosition = margin
      for (index, column) in columns.enumerated() {
        let text = totalValues[index]
        let drawWidth = index == 0 ? columns.prefix(4).reduce(0) { $0 + $1.width } : column.width
        let alignment: NSTextAlignment = index == 0 ? .left : column.alignment

        if index == 0 || index >= 4 {
          Self.drawPDFTextTopAligned(
            text,
            in: CGRect(
              x: xPosition + cellPadding,
              y: totalsTop + 2,
              width: drawWidth - (cellPadding * 2),
              height: totalsHeight
            ),
            font: totalFont,
            color: textColor,
            alignment: alignment
          )
        }

        xPosition += column.width
      }
    }

    // Save to temp file
    let filename = Self.buildFilename(range: range, format: .pdf, locale: locale)
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    try pdfData.write(to: tempURL)

    return tempURL
  }

  /// Generate CSV from export data
  private nonisolated static func generateCSV(
    from data: ExportResponse,
    range: (from: String, to: String),
    localeIdentifier: String
  ) throws -> URL {
    let locale = Locale(identifier: localeIdentifier)
    var csvContent = ""

    // Headers
    let headers = [
      String(localized: .dataExportTableDate),
      String(localized: .dataExportTableDay),
      String(localized: .dataExportTableStart),
      String(localized: .dataExportTableEnd),
      String(localized: .dataExportTableHours),
      String(localized: .dataExportCsvBasePay),
      String(localized: .dataExportTableSupplement),
      String(localized: .dataExportTableTotal),
    ]

    csvContent += headers.joined(separator: ";") + "\n"

    // Date formatter
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .short
    dateFormatter.locale = locale

    let weekdayFormatter = DateFormatter()
    weekdayFormatter.dateFormat = "EEE"
    weekdayFormatter.locale = locale

    // Data rows
    for shift in data.shifts {
      let shiftDate = parseISODate(shift.date)
      let dateStr = shiftDate.map { dateFormatter.string(from: $0) } ?? shift.date
      let dayStr = shiftDate.map { weekdayFormatter.string(from: $0) } ?? ""

      let row = [
        dateStr,
        dayStr,
        shift.startTime,
        shift.endTime,
        String(format: "%.2f", shift.calc.hours),
        String(format: "%.2f", shift.calc.baseWage),
        String(format: "%.2f", shift.calc.supplement),
        String(format: "%.2f", shift.calc.total),
      ]

      csvContent += row.map { Self.escapeCSV($0) }.joined(separator: ";") + "\n"
    }

    // Totals row
    let totalHours = data.shifts.reduce(0.0) { $0 + $1.calc.hours }
    let totalBaseWage = data.shifts.reduce(0.0) { $0 + $1.calc.baseWage }
    let totalSupplement = data.shifts.reduce(0.0) { $0 + $1.calc.supplement }
    let totalWage = data.shifts.reduce(0.0) { $0 + $1.calc.total }

    let sumLabel = String(localized: .dataExportPdfSumLabel).replacingOccurrences(of: ":", with: "")
    let totalsRow = [
      sumLabel,
      "",
      "",
      "",
      String(format: "%.2f", totalHours),
      String(format: "%.2f", totalBaseWage),
      String(format: "%.2f", totalSupplement),
      String(format: "%.2f", totalWage),
    ]
    csvContent += totalsRow.joined(separator: ";") + "\n"

    // Save to temp file
    let filename = Self.buildFilename(range: range, format: .csv, locale: locale)
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)

    return tempURL
  }

  /// Build filename for export
  private nonisolated static func buildFilename(
    range: (from: String, to: String),
    format: ExportFormat,
    locale: Locale
  ) -> String {
    let ext = format == .pdf ? "pdf" : "csv"

    // Parse dates
    guard let fromDate = parseISODate(range.from),
      let toDate = parseISODate(range.to)
    else {
      return "tidex_export.\(ext)"
    }

    let calendar = Calendar.current
    let monthFormatter = DateFormatter()
    monthFormatter.dateFormat = "MMM"
    monthFormatter.locale = locale

    let isFirstOfMonth = calendar.component(.day, from: fromDate) == 1
    let isSameMonth = calendar.isDate(fromDate, equalTo: toDate, toGranularity: .month)
    let lastDayOfMonth = calendar.range(of: .day, in: .month, for: toDate)?.count ?? 31
    let isLastOfMonth = calendar.component(.day, from: toDate) == lastDayOfMonth

    let fromMonth = monthFormatter.string(from: fromDate).lowercased()
    let toMonth = monthFormatter.string(from: toDate).lowercased()
    let fromYear = calendar.component(.year, from: fromDate)
    let toYear = calendar.component(.year, from: toDate)

    if isFirstOfMonth && isSameMonth && isLastOfMonth {
      // Full month: tidex_jan-2026.pdf
      return "tidex_\(fromMonth)-\(fromYear).\(ext)"
    } else if isSameMonth {
      // Same month range: tidex_01-15jan-2026.pdf
      let fromDay = String(format: "%02d", calendar.component(.day, from: fromDate))
      let toDay = String(format: "%02d", calendar.component(.day, from: toDate))
      return "tidex_\(fromDay)-\(toDay)\(fromMonth)-\(fromYear).\(ext)"
    } else if fromYear == toYear {
      // Cross-month same year: tidex_01jan-15feb-2026.pdf
      let fromDay = String(format: "%02d", calendar.component(.day, from: fromDate))
      let toDay = String(format: "%02d", calendar.component(.day, from: toDate))
      return "tidex_\(fromDay)\(fromMonth)-\(toDay)\(toMonth)-\(fromYear).\(ext)"
    } else {
      // Cross-year: tidex_dec2025-jan2026.pdf
      return "tidex_\(fromMonth)\(fromYear)-\(toMonth)\(toYear).\(ext)"
    }
  }

  /// Escape a value for CSV
  private nonisolated static func escapeCSV(_ value: String) -> String {
    if value.contains(";") || value.contains("\"") || value.contains("\n") {
      return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return value
  }

  /// Format a number with locale-appropriate separators
  private nonisolated static func formatNumber(_ value: Double, decimals: Int, locale: Locale)
    -> String
  {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = decimals
    formatter.maximumFractionDigits = decimals
    formatter.locale = locale
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(decimals)f", value)
  }

  private nonisolated static func formatExportTimestamp(_ value: String, formatter: DateFormatter)
    -> String
  {
    if let date = Self.parseISO8601Date(value) {
      return formatter.string(from: date)
    }
    return formatter.string(from: Date())
  }

  private nonisolated static func parseISO8601Date(_ value: String) -> Date? {
    let preciseFormatter = ISO8601DateFormatter()
    preciseFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    if let date = preciseFormatter.date(from: value) {
      return date
    }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }

  private nonisolated static func drawPDFText(
    _ text: String,
    in rect: CGRect,
    font: UIFont,
    color: UIColor,
    alignment: NSTextAlignment = .left
  ) {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = alignment
    paragraphStyle.lineBreakMode = .byTruncatingTail
    let verticalInset = max(0, floor((rect.height - font.lineHeight) / 2))
    let centeredRect = CGRect(
      x: rect.minX,
      y: rect.minY + verticalInset,
      width: rect.width,
      height: max(font.lineHeight, rect.height - verticalInset)
    )

    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: paragraphStyle,
    ]

    (text as NSString).draw(
      with: centeredRect,
      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
      attributes: attributes,
      context: nil
    )
  }

  private nonisolated static func drawPDFAttributedText(
    _ text: NSAttributedString,
    in rect: CGRect
  ) {
    let measuredRect = text.boundingRect(
      with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      context: nil
    )
    let verticalInset = max(0, floor((rect.height - ceil(measuredRect.height)) / 2))
    let centeredRect = CGRect(
      x: rect.minX,
      y: rect.minY + verticalInset,
      width: rect.width,
      height: max(ceil(measuredRect.height), rect.height - verticalInset)
    )
    text.draw(
      with: centeredRect,
      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
      context: nil
    )
  }

  private nonisolated static func drawPDFTextTopAligned(
    _ text: String,
    in rect: CGRect,
    font: UIFont,
    color: UIColor,
    alignment: NSTextAlignment = .left
  ) {
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = alignment
    paragraphStyle.lineBreakMode = .byTruncatingTail

    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: paragraphStyle,
    ]

    (text as NSString).draw(
      with: rect,
      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
      attributes: attributes,
      context: nil
    )
  }

  private nonisolated static func drawLine(
    from start: CGPoint,
    to end: CGPoint,
    color: UIColor,
    width: CGFloat
  ) {
    let path = UIBezierPath()
    path.move(to: start)
    path.addLine(to: end)
    path.lineWidth = width
    color.setStroke()
    path.stroke()
  }

  private nonisolated static func drawLabelValueRow(
    label: String,
    value: String,
    in rect: CGRect,
    style: PDFLabelValueRowStyle
  ) {
    let totalWidth = rect.width
    let valueWidth = min(max(totalWidth * 0.42, 150), 220)
    let labelWidth = totalWidth - valueWidth - 12

    Self.drawPDFText(
      label,
      in: CGRect(x: rect.minX, y: rect.minY, width: labelWidth, height: rect.height),
      font: style.labelFont,
      color: style.color
    )
    Self.drawPDFText(
      value,
      in: CGRect(
        x: rect.maxX - valueWidth,
        y: rect.minY,
        width: valueWidth,
        height: rect.height
      ),
      font: style.valueFont,
      color: style.color,
      alignment: .right
    )
  }
}

private struct PDFColumn {
  let title: String
  let width: CGFloat
  let alignment: NSTextAlignment
}

private struct PDFLabelValueRowStyle {
  let labelFont: UIFont
  let valueFont: UIFont
  let color: UIColor
}

// MARK: - Export Errors

enum ExportError: LocalizedError {
  case invalidURL
  case invalidDateRange
  case networkError
  case unauthorized
  case serverError(code: Int, message: String)
  case pdfGenerationFailed
  case csvGenerationFailed

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Invalid URL"
    case .invalidDateRange:
      return "Invalid date range"
    case .networkError:
      return "Network error"
    case .unauthorized:
      return "Not authenticated"
    case .serverError(let code, let message):
      return "Server error (\(code)): \(message)"
    case .pdfGenerationFailed:
      return "Failed to generate PDF"
    case .csvGenerationFailed:
      return "Failed to generate CSV"
    }
  }
}

// MARK: - Helper Functions

/// Convert a Date to ISO date string (YYYY-MM-DD)
private func toISODate(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd"
  formatter.timeZone = TimeZone.current
  return formatter.string(from: date)
}

/// Parse an ISO date string to Date
private func parseISODate(_ string: String) -> Date? {
  let formatter = DateFormatter()
  formatter.dateFormat = "yyyy-MM-dd"
  formatter.timeZone = TimeZone.current
  return formatter.date(from: string)
}
