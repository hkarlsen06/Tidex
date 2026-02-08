import Foundation
import PDFKit
import Supabase
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "DataSettingsViewModel")

// MARK: - Period Preset

/// Period preset options for export
enum ExportPeriodPreset: String, CaseIterable, Identifiable {
  case lastMonth = "last_month"
  case currentMonth = "current_month"
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
struct ExportResponse: Codable {
  let generatedAt: String
  let shifts: [ExportedShift]
}

/// A shift in the export response
struct ExportedShift: Codable {
  let id: String
  let date: String
  let startTime: String
  let endTime: String
  let type: Int  // 0 = weekday, 1 = saturday, 2 = sunday
  let recurringId: String?
  let calc: ShiftCalculation

  struct ShiftCalculation: Codable {
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

  /// Shared URLSession from factory (long-running timeout: 60s request, 120s resource)
  private let urlSession = URLSessionFactory.longRunning
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

      // PDF/CSV export still uses API for calculation consistency
      // Sync first to ensure local changes are pushed to the server
      isSyncing = true
      logger.info("Syncing before export...")
      let syncResult = await SyncCoordinator.shared.sync(reason: .localChange, userId: userId)
      isSyncing = false

      if !syncResult.success, let error = syncResult.error {
        logger.warning("Sync had issues before export: \(error)")
        // Continue with export anyway - user might want old data
      }

      // Fetch export data from API
      let exportData = try await fetchExportData(from: range.from, to: range.to)

      // Handle export based on format
      switch format {
      case .pdf:
        let fileURL = try generatePDF(from: exportData, range: range, locale: locale)
        shareURL = fileURL

      case .csv:
        let fileURL = try generateCSV(from: exportData, range: range, locale: locale)
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

  /// Fetch export data from the API
  private func fetchExportData(from: String, to: String) async throws -> ExportResponse {
    // Get auth token
    let session = try await AuthSessionManager.shared.getSession()
    let accessToken = session.accessToken

    // Build URL
    guard
      var components = URLComponents(
        url: APIConfiguration.webAppBaseURL.appendingPathComponent("/api/settings/data/export"),
        resolvingAgainstBaseURL: false
      )
    else {
      throw ExportError.invalidURL
    }
    components.queryItems = [
      URLQueryItem(name: "from", value: from),
      URLQueryItem(name: "to", value: to),
    ]

    guard let url = components.url else {
      throw ExportError.invalidURL
    }

    // Build request with Bearer token auth
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    logger.info("Fetching export data from \(url.absoluteString)")

    // Execute request
    let (data, response) = try await urlSession.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      throw ExportError.networkError
    }

    switch httpResponse.statusCode {
    case 200:
      break
    case 401:
      throw ExportError.unauthorized
    default:
      let message = String(data: data, encoding: .utf8) ?? "Unknown error"
      throw ExportError.serverError(code: httpResponse.statusCode, message: message)
    }

    // Decode response
    let decoder = JSONDecoder()
    return try decoder.decode(ExportResponse.self, from: data)
  }

  /// Generate PDF from export data
  private func generatePDF(
    from data: ExportResponse,
    range: (from: String, to: String),
    locale: Locale
  ) throws -> URL {
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

    let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

    let pdfData = renderer.pdfData { context in
      context.beginPage()

      // Margins
      let margin: CGFloat = 40
      var yPosition: CGFloat = margin

      // Title
      let titleFont = UIFont.boldSystemFont(ofSize: 18)
      let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: UIColor.black,
      ]

      let title = "Tidex · " + String(localized: .dataExportPdfDocumentTitle)
      title.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: titleAttributes)
      yPosition += 30

      // Metadata
      let metaFont = UIFont.systemFont(ofSize: 10)
      let metaAttributes: [NSAttributedString.Key: Any] = [
        .font: metaFont,
        .foregroundColor: UIColor.darkGray,
      ]

      let exportedLabel = String(localized: .dataExportPdfExportedLabel)
      let periodLabel = String(localized: .dataExportPdfPeriodLabel)

      let dateFormatter = DateFormatter()
      dateFormatter.dateStyle = .short
      dateFormatter.locale = locale

      let exportDate = dateFormatter.string(from: Date())
      "\(exportedLabel) \(exportDate)".draw(
        at: CGPoint(x: margin, y: yPosition), withAttributes: metaAttributes)
      yPosition += 15

      let fromDate = parseISODate(range.from).map { dateFormatter.string(from: $0) } ?? range.from
      let toDate = parseISODate(range.to).map { dateFormatter.string(from: $0) } ?? range.to
      "\(periodLabel) \(fromDate) - \(toDate)".draw(
        at: CGPoint(x: margin, y: yPosition), withAttributes: metaAttributes)
      yPosition += 30

      // Summary
      let summaryTitleFont = UIFont.boldSystemFont(ofSize: 14)
      let summaryTitleAttributes: [NSAttributedString.Key: Any] = [
        .font: summaryTitleFont,
        .foregroundColor: UIColor.black,
      ]

      let summaryTitle = String(localized: .dataExportPdfSummary)
      summaryTitle.draw(
        at: CGPoint(x: margin, y: yPosition), withAttributes: summaryTitleAttributes)
      yPosition += 20

      let summaryFont = UIFont.systemFont(ofSize: 10)
      let summaryAttributes: [NSAttributedString.Key: Any] = [
        .font: summaryFont,
        .foregroundColor: UIColor.black,
      ]

      // Calculate totals
      let totalHours = data.shifts.reduce(0.0) { $0 + $1.calc.hours }
      let totalBaseWage = data.shifts.reduce(0.0) { $0 + $1.calc.baseWage }
      let totalSupplement = data.shifts.reduce(0.0) { $0 + $1.calc.supplement }
      let totalWage = data.shifts.reduce(0.0) { $0 + $1.calc.total }

      let weekdayCount = data.shifts.filter { $0.type == 0 }.count
      let saturdayCount = data.shifts.filter { $0.type == 1 }.count
      let sundayCount = data.shifts.filter { $0.type == 2 }.count

      let currencySymbol = "kr"
      let hoursUnit = String(localized: .commonHours)

      let summaryLines = [
        String(localized: .dataExportPdfTotalShifts) + " \(data.shifts.count)",
        String(localized: .dataExportPdfTotalHours)
          + " \(formatNumber(totalHours, decimals: 2, locale: locale)) \(hoursUnit)",
        String(localized: .dataExportPdfTotalBasePay)
          + " \(formatNumber(totalBaseWage, decimals: 0, locale: locale)) \(currencySymbol)",
        String(localized: .dataExportPdfTotalSupplements)
          + " \(formatNumber(totalSupplement, decimals: 0, locale: locale)) \(currencySymbol)",
        String(localized: .dataExportPdfTotalPay)
          + " \(formatNumber(totalWage, decimals: 0, locale: locale)) \(currencySymbol)",
        "",
        String(localized: .dataExportPdfShiftsByType),
        "  " + String(localized: .dataExportPdfWeekdays) + " \(weekdayCount)",
        "  " + String(localized: .dataExportPdfSaturdays) + " \(saturdayCount)",
        "  " + String(localized: .dataExportPdfSundaysHolidays) + " \(sundayCount)",
      ]

      for line in summaryLines {
        line.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: summaryAttributes)
        yPosition += line.isEmpty ? 10 : 15
      }

      yPosition += 20

      // Table header
      let tableHeaderFont = UIFont.boldSystemFont(ofSize: 9)
      let tableHeaderAttributes: [NSAttributedString.Key: Any] = [
        .font: tableHeaderFont,
        .foregroundColor: UIColor.black,
      ]

      let headers = [
        String(localized: .dataExportTableDate),
        String(localized: .dataExportTableDay),
        String(localized: .dataExportTableStart),
        String(localized: .dataExportTableEnd),
        String(localized: .dataExportTableHours),
        String(localized: .dataExportTableBase),
        String(localized: .dataExportTableSupplement),
        String(localized: .dataExportTableTotal),
      ]

      let columnWidths: [CGFloat] = [70, 35, 45, 45, 45, 55, 55, 55]
      var xPosition = margin

      for (index, header) in headers.enumerated() {
        header.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: tableHeaderAttributes)
        xPosition += columnWidths[index]
      }

      yPosition += 15

      // Draw header line
      let linePath = UIBezierPath()
      linePath.move(to: CGPoint(x: margin, y: yPosition))
      linePath.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition))
      UIColor.gray.setStroke()
      linePath.lineWidth = 0.5
      linePath.stroke()

      yPosition += 5

      // Table rows
      let rowFont = UIFont.systemFont(ofSize: 9)
      let rowAttributes: [NSAttributedString.Key: Any] = [
        .font: rowFont,
        .foregroundColor: UIColor.black,
      ]

      let weekdayFormatter = DateFormatter()
      weekdayFormatter.dateFormat = "EEE"
      weekdayFormatter.locale = locale

      for shift in data.shifts {
        // Check if we need a new page
        if yPosition > pageHeight - 60 {
          context.beginPage()
          yPosition = margin
        }

        let shiftDate = parseISODate(shift.date)
        let dateStr = shiftDate.map { dateFormatter.string(from: $0) } ?? shift.date
        let dayStr = shiftDate.map { weekdayFormatter.string(from: $0) } ?? ""

        let rowValues = [
          dateStr,
          dayStr,
          shift.startTime,
          shift.endTime,
          formatNumber(shift.calc.hours, decimals: 2, locale: locale),
          formatNumber(shift.calc.baseWage, decimals: 0, locale: locale),
          formatNumber(shift.calc.supplement, decimals: 0, locale: locale),
          formatNumber(shift.calc.total, decimals: 0, locale: locale),
        ]

        xPosition = margin
        for (index, value) in rowValues.enumerated() {
          value.draw(at: CGPoint(x: xPosition, y: yPosition), withAttributes: rowAttributes)
          xPosition += columnWidths[index]
        }

        yPosition += 12
      }

      // Footer
      yPosition += 10
      let footerPath = UIBezierPath()
      footerPath.move(to: CGPoint(x: margin, y: yPosition))
      footerPath.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition))
      UIColor.gray.setStroke()
      footerPath.lineWidth = 0.5
      footerPath.stroke()

      yPosition += 5

      // Totals row
      let totalAttributes: [NSAttributedString.Key: Any] = [
        .font: tableHeaderFont,
        .foregroundColor: UIColor.black,
      ]

      let sumLabel = String(localized: .dataExportPdfSumLabel)
      sumLabel.draw(at: CGPoint(x: margin, y: yPosition), withAttributes: totalAttributes)

      xPosition = margin + columnWidths[0] + columnWidths[1] + columnWidths[2] + columnWidths[3]
      formatNumber(totalHours, decimals: 2, locale: locale).draw(
        at: CGPoint(x: xPosition, y: yPosition), withAttributes: totalAttributes)
      xPosition += columnWidths[4]
      formatNumber(totalBaseWage, decimals: 0, locale: locale).draw(
        at: CGPoint(x: xPosition, y: yPosition), withAttributes: totalAttributes)
      xPosition += columnWidths[5]
      formatNumber(totalSupplement, decimals: 0, locale: locale).draw(
        at: CGPoint(x: xPosition, y: yPosition), withAttributes: totalAttributes)
      xPosition += columnWidths[6]
      formatNumber(totalWage, decimals: 0, locale: locale).draw(
        at: CGPoint(x: xPosition, y: yPosition), withAttributes: totalAttributes)
    }

    // Save to temp file
    let filename = buildFilename(range: range, format: .pdf, locale: locale)
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    try pdfData.write(to: tempURL)

    return tempURL
  }

  /// Generate CSV from export data
  private func generateCSV(
    from data: ExportResponse,
    range: (from: String, to: String),
    locale: Locale
  ) throws -> URL {
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

      csvContent += row.map { escapeCSV($0) }.joined(separator: ";") + "\n"
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
    let filename = buildFilename(range: range, format: .csv, locale: locale)
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)

    return tempURL
  }

  /// Build filename for export
  private func buildFilename(
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
  private func escapeCSV(_ value: String) -> String {
    if value.contains(";") || value.contains("\"") || value.contains("\n") {
      return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
    return value
  }

  /// Format a number with locale-appropriate separators
  private func formatNumber(_ value: Double, decimals: Int, locale: Locale) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = decimals
    formatter.maximumFractionDigits = decimals
    formatter.locale = locale
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(decimals)f", value)
  }
}

// MARK: - Export Errors

enum ExportError: LocalizedError {
  case invalidURL
  case networkError
  case unauthorized
  case serverError(code: Int, message: String)
  case pdfGenerationFailed
  case csvGenerationFailed

  var errorDescription: String? {
    switch self {
    case .invalidURL:
      return "Invalid URL"
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
