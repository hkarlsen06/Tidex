import Foundation
import Observation
import PDFKit
import Supabase
import UIKit
import os.log

private let kLogger: Logger = Logger(
  subsystem: "com.tidex.app",
  category: "DataSettingsViewModel"
)

// MARK: - Period Preset

/// Period preset options for export
internal enum ExportPeriodPreset: String, CaseIterable, Identifiable {
  case currentMonth = "current_month"
  case currentYear = "current_year"
  case custom = "custom"
  case lastMonth = "last_month"
  case lastYear = "last_year"

  internal var id: String { rawValue }

  /// Resolve the date range for this preset
  internal func resolveDateRange() -> (from: String, to: String)? {
    let now: Date = Date()
    let calendar: Calendar = Calendar.gregorianCurrent

    switch self {
    case .currentMonth:
      guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)
      else {
        return nil
      }
      return (start.toISODateString(), end.toISODateString())

    case .lastMonth:
      guard
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
        let start = calendar.date(byAdding: .month, value: -1, to: thisMonth),
        let end = calendar.date(byAdding: .day, value: -1, to: thisMonth)
      else {
        return nil
      }
      return (start.toISODateString(), end.toISODateString())

    case .currentYear:
      let year: Int = calendar.component(.year, from: now)
      guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
        let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31))
      else {
        return nil
      }
      return (start.toISODateString(), end.toISODateString())

    case .lastYear:
      let year: Int = calendar.component(.year, from: now) - 1
      guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
        let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31))
      else {
        return nil
      }
      return (start.toISODateString(), end.toISODateString())

    case .custom:
      return nil
    }
  }
}

// MARK: - Export Types

/// Export format options
internal enum ExportFormat {
  case csv
  case pdf
}

/// Response from the export API
internal struct ExportResponse: Codable, Sendable {
  internal let generatedAt: Date
  internal let currencySymbol: String
  internal let shifts: [ExportedShift]
}

/// A shift in the export response
internal struct ExportedShift: Codable, Sendable {
  internal struct ShiftCalculation: Codable, Sendable {
    internal let hours: Double
    internal let baseWage: Double
    internal let supplement: Double
    internal let total: Double
  }

  internal let id: String
  internal let date: String
  internal let startTime: String
  internal let endTime: String
  internal let type: Int  // 0 = weekday, 1 = saturday, 2 = sunday or public holiday
  internal let jobName: String
  internal let recurringId: String?
  internal let calc: ShiftCalculation
}

// MARK: - View Model

/// ViewModel for data export settings
@MainActor
@Observable
final class DataSettingsViewModel {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order line_length required_deinit type_body_length
  // MARK: - Observed State

  /// Selected period preset
  var selectedPreset: ExportPeriodPreset?  // swiftlint:disable:this explicit_acl

  /// Custom date range (when preset is .custom)
  var customFromDate: Date = Date()  // swiftlint:disable:this explicit_acl
  var customToDate: Date = Date()  // swiftlint:disable:this explicit_acl

  /// Loading state for PDF export
  var isExportingPdf = false

  /// Loading state for CSV export
  var isExportingCsv = false

  /// Loading state for calendar export - reads straight through to the store, which is
  /// itself observed, so this stays current without a manual mirror/subscription.
  var calendarSubscriptionState: CalendarSubscriptionState { calendarSubscriptionStore.state }
  var isLoadingCalendarSubscription: Bool { calendarSubscriptionStore.isLoading }
  var isUpdatingCalendarSubscription = false
  var calendarSubscriptionFallbackURL: URL? { calendarSubscriptionStore.fallbackHTTPSURL }

  /// Error message
  var errorMessage: String?

  /// URL for share sheet presentation
  var shareURL: URL?

  /// Whether a sync is in progress
  var isSyncing = false

  // MARK: - Private Properties

  @ObservationIgnored private var userId: String?
  private let calendarSubscriptionStore: CalendarSubscriptionStore
  private let calendarSetupIntent: CalendarSubscriptionSetupIntent?
  @ObservationIgnored private var didHandleCalendarSetupIntent = false

  init(
    calendarSetupIntent: CalendarSubscriptionSetupIntent? = nil,
    calendarSubscriptionStore: CalendarSubscriptionStore? = nil
  ) {
    self.calendarSetupIntent = calendarSetupIntent
    self.calendarSubscriptionStore = calendarSubscriptionStore ?? .shared
  }

  // MARK: - Computed Properties

  /// The resolved date range based on preset or custom dates
  var resolvedDateRange: (from: String, to: String)? {
    guard let preset = selectedPreset else {
      return nil
    }

    if preset == .custom {
      // Validate custom range
      if customFromDate > customToDate {
        return nil
      }
      return (customFromDate.toISODateString(), customToDate.toISODateString())
    }

    return preset.resolveDateRange()
  }

  /// Whether export is currently possible
  var canExport: Bool {
    resolvedDateRange != nil && !isExportingPdf && !isExportingCsv && !isSyncing
  }

  /// Whether the custom date range is invalid
  var isCustomRangeInvalid: Bool {
    selectedPreset == .custom && customFromDate > customToDate
  }

  // MARK: - Public Methods

  /// Load initial state
  func loadSettings() async {
    userId = await resolveUserIdForLocalData()
    await calendarSubscriptionStore.refreshIfNeeded()
    await handleCalendarSetupIntentIfNeeded()
  }

  /// Export shifts in the specified format
  func exportShifts(format: ExportFormat, locale: Locale) async {
    guard let range = resolvedDateRange, let userId else {
      return
    }

    // Clean up the previous export's temp file before starting a new one. Deletion is
    // deferred to this point (rather than on share dismissal) so the system share sheet
    // has time to read the file after ShareLink hands it off.
    removePreviousShareFile()

    // Set loading state
    switch format {
    case .pdf:
      isExportingPdf = true

    case .csv:
      isExportingCsv = true
    }
    errorMessage = nil

    defer {
      switch format {
      case .pdf:
        isExportingPdf = false

      case .csv:
        isExportingCsv = false
      }
    }

    do {
      // PDF/CSV export is generated from local synced data.
      // Sync first to ensure local changes are pushed to the server
      isSyncing = true
      kLogger.info("Syncing before export...")
      let syncResult = await SyncCoordinator.shared.sync(reason: .localChange, userId: userId)
      isSyncing = false

      if !syncResult.success, let error = syncResult.error {
        kLogger.warning("Sync had issues before export: \(error)")
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
      }

    } catch {
      kLogger.error("Export failed: \(error.localizedDescription)")
      errorMessage = error.localizedDescription
    }
  }

  /// Clear error message
  func clearError() {
    errorMessage = nil
  }

  /// Hide the "ready to share" card. The temp file itself is removed the next time an
  /// export starts (see `removePreviousShareFile`), not here, since the system share
  /// sheet may still be reading it after the user taps ShareLink.
  func dismissShareSheet() {
    shareURL = nil
  }

  private func removePreviousShareFile() {
    guard let url = shareURL else { return }
    try? FileManager.default.removeItem(at: url)
    shareURL = nil
  }

  func setupCalendarSubscription(mode: CalendarSubscriptionContentMode = .shiftsAndEvents) async {
    isUpdatingCalendarSubscription = true
    errorMessage = nil
    defer { isUpdatingCalendarSubscription = false }

    do {
      if !calendarSubscriptionState.isActive {
        do {
          _ = try await calendarSubscriptionStore.create(mode: mode)
        } catch CalendarSubscriptionStoreError.subscriptionAlreadyActive {
          await calendarSubscriptionStore.refresh()
        }
      }

      await calendarSubscriptionStore.openCalendarApp()
      errorMessage = calendarSubscriptionStore.errorMessage
    } catch {
      errorMessage = ErrorTranslations.translate(error)
    }
  }

  func updateCalendarSubscriptionMode(_ mode: CalendarSubscriptionContentMode) async {
    isUpdatingCalendarSubscription = true
    errorMessage = nil
    defer { isUpdatingCalendarSubscription = false }

    do {
      try await calendarSubscriptionStore.setContentMode(mode)
    } catch {
      errorMessage = ErrorTranslations.translate(error)
    }
  }

  func rotateCalendarSubscription() async {
    isUpdatingCalendarSubscription = true
    errorMessage = nil
    defer { isUpdatingCalendarSubscription = false }

    do {
      _ = try await calendarSubscriptionStore.rotate(
        mode: calendarSubscriptionState.metadata?.contentMode
      )
      await calendarSubscriptionStore.openCalendarApp()
      errorMessage = calendarSubscriptionStore.errorMessage
    } catch {
      errorMessage = ErrorTranslations.translate(error)
    }
  }

  func disableCalendarSubscription() async {
    isUpdatingCalendarSubscription = true
    errorMessage = nil
    defer { isUpdatingCalendarSubscription = false }

    do {
      try await calendarSubscriptionStore.disable()
    } catch {
      errorMessage = ErrorTranslations.translate(error)
    }
  }

  func openCalendarSubscription() async {
    isUpdatingCalendarSubscription = true
    errorMessage = nil
    defer { isUpdatingCalendarSubscription = false }

    await calendarSubscriptionStore.openCalendarApp()
    errorMessage = calendarSubscriptionStore.errorMessage
  }

  func copyCalendarSubscriptionFallbackURL() {
    calendarSubscriptionStore.copyFallbackURL()
  }

  // MARK: - Private Methods

  private func resolveUserIdForLocalData() async -> String? {
    do {
      return try await AuthSessionManager.shared.getUserId()
    } catch {
      if AuthSessionManager.shared.isTransientSessionResolutionError(error),
        let offlineUserId = AuthSessionManager.shared.offlineUserIdFallback()
      {
        kLogger.info("Using offline user id fallback for data exports")
        return offlineUserId
      }

      kLogger.error("Failed to get user session: \(error.localizedDescription)")
      return nil
    }
  }

  private func handleCalendarSetupIntentIfNeeded() async {
    guard !didHandleCalendarSetupIntent, let calendarSetupIntent else {
      return
    }
    didHandleCalendarSetupIntent = true

    switch calendarSetupIntent {
    case .setup(let mode, let autoOpen):
      guard autoOpen else {
        return
      }
      await setupCalendarSubscription(mode: mode)
    }
  }

  /// Build export data from local storage.
  private func fetchExportData(from: String, to: String) async throws -> ExportResponse {
    guard let userId else {
      throw ExportError.unauthorized
    }
    guard let startDate = Date.fromISODateString(from), let endDate = Date.fromISODateString(to) else {
      throw ExportError.invalidDateRange
    }

    kLogger.info("Building export data locally for \(from) to \(to)")

    // Use the same engine as the app so overtime and conflict exclusion match its totals.
    let readService = MonthlyPayrollReadService.shared
    let context = await readService.loadContextOffMain(for: userId)
    let rows = await readService.loadShiftRows(for: userId, startDate: startDate, endDate: endDate)
    let calendar = Calendar.gregorianCurrent
    let computed = PayrollEngine.computeShiftsForMonth(
      PayrollEngine.MonthComputationRequest(
        year: calendar.component(.year, from: startDate),
        month: calendar.component(.month, from: startDate),
        shifts: rows,
        recurring: context.recurringShifts,
        snapshots: context.snapshots,
        settings: context.settings,
        visibleRange: (start: startDate, end: endDate),
        jobs: context.jobs
      )
    )
    let included = ConflictExclusion.partition(shifts: computed).includedShifts
    let currency = JobCurrencyAggregateResolver.resolve(
      shifts: included,
      jobs: context.jobs,
      fallbackCurrency: context.settings?.currency ?? "kr",
      referenceDate: Date()
    ).primary.currency

    let jobNames = Dictionary(
      context.jobs.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

    return ExportResponse(
      generatedAt: Date(),
      currencySymbol: currency,
      shifts: included.map { makeExportedShift(from: $0, jobNames: jobNames) }
    )
  }

  private func makeExportedShift(from shift: ShiftWithComputations, jobNames: [String: String])
    -> ExportedShift
  {
    ExportedShift(
      id: shift.id,
      date: shift.shiftDate,
      startTime: shift.startTime,
      endTime: shift.endTime,
      type: Self.shiftType(dateISO: shift.shiftDate),
      jobName: shift.shift.job_id.flatMap { jobNames[$0] } ?? "",
      recurringId: shift.shift.recurring_id,
      calc: ExportedShift.ShiftCalculation(
        hours: shift.computed.paidHours,
        baseWage: shift.computed.basePay,
        supplement: shift.computed.supplementPay,
        total: shift.computed.gross
      )
    )
  }

  nonisolated static func shiftType(dateISO: String) -> Int {
    guard let date = Date.fromISODateString(dateISO) else {
      return 0
    }
    if NorwegianHolidays.isPublicHoliday(date) {
      return 2
    }
    let calendar: Calendar = Calendar.gregorianCurrent
    let weekday: Int = calendar.component(.weekday, from: date)

    switch weekday {
    case 1:
      return 2

    case 7:
      return 1

    default:
      return 0
    }
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
    let currencySymbol = data.currencySymbol
    let hoursUnit = String(localized: .commonHours)

    let detailDateFormat = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
      .calendar(.gregorian)
    let tableDateFormat = Date.FormatStyle(date: .numeric, time: .omitted).locale(locale)
      .calendar(.gregorian)
    let generatedAtFormat = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)
      .calendar(.gregorian)
    let monthFormat = Date.FormatStyle.dateTime.year().month(.wide).locale(locale).calendar(.gregorian)
    let weekdayFormat = Date.FormatStyle.dateTime.weekday(.abbreviated).locale(locale)
      .calendar(.gregorian)

    let generatedAtText = "\(exportedLabel) \(data.generatedAt.formatted(generatedAtFormat))"
    let fromDate =
      Date.fromISODateString(range.from).map { $0.formatted(detailDateFormat) } ?? range.from
    let toDate =
      Date.fromISODateString(range.to).map { $0.formatted(detailDateFormat) } ?? range.to
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
        let shiftDate = Date.fromISODateString(shift.date)
        let monthKey: String
        let monthTitle: String

        if let shiftDate {
          let components = Calendar.gregorianCurrent.dateComponents([.year, .month], from: shiftDate)
          monthKey = "\(components.year ?? 0)-\(components.month ?? 0)"
          monthTitle = shiftDate.formatted(monthFormat)
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
          shiftDate.map { $0.formatted(tableDateFormat) } ?? shift.date,
          shiftDate.map { $0.formatted(weekdayFormat) } ?? "",
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
  nonisolated static func generateCSV(
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
      String(localized: .dataExportTableJob),
      String(localized: .dataExportTableStart),
      String(localized: .dataExportTableEnd),
      String(localized: .dataExportTableHours),
      String(localized: .dataExportCsvBasePay),
      String(localized: .dataExportTableSupplement),
      String(localized: .dataExportTableTotal),
    ]

    csvContent += headers.joined(separator: ";") + "\n"

    // Date formats
    let dateFormat = Date.FormatStyle(date: .numeric, time: .omitted).locale(locale).calendar(.gregorian)
    let weekdayFormat = Date.FormatStyle.dateTime.weekday(.abbreviated).locale(locale)
      .calendar(.gregorian)

    // Data rows
    for shift in data.shifts {
      let shiftDate = Date.fromISODateString(shift.date)
      let dateStr = shiftDate.map { $0.formatted(dateFormat) } ?? shift.date
      let dayStr = shiftDate.map { $0.formatted(weekdayFormat) } ?? ""

      let row = [
        dateStr,
        dayStr,
        shift.jobName,
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
    guard let fromDate = Date.fromISODateString(range.from),
      let toDate = Date.fromISODateString(range.to)
    else {
      return "tidex_export.\(ext)"
    }

    let calendar = Calendar.gregorianCurrent
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

    if isFirstOfMonth, isSameMonth, isLastOfMonth {
      // Full month: tidex_jan-2026.pdf
      return "tidex_\(fromMonth)-\(fromYear).\(ext)"
    }
    if isSameMonth {
      // Same month range: tidex_01-15jan-2026.pdf
      let fromDay = String(format: "%02d", calendar.component(.day, from: fromDate))
      let toDay = String(format: "%02d", calendar.component(.day, from: toDate))
      return "tidex_\(fromDay)-\(toDay)\(fromMonth)-\(fromYear).\(ext)"
    }
    if fromYear == toYear {
      // Cross-month same year: tidex_01jan-15feb-2026.pdf
      let fromDay = String(format: "%02d", calendar.component(.day, from: fromDate))
      let toDay = String(format: "%02d", calendar.component(.day, from: toDate))
      return "tidex_\(fromDay)\(fromMonth)-\(toDay)\(toMonth)-\(fromYear).\(ext)"
    }
    // Cross-year: tidex_dec2025-jan2026.pdf
    return "tidex_\(fromMonth)\(fromYear)-\(toMonth)\(toYear).\(ext)"
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
    value.formatted(.number.precision(.fractionLength(decimals)).locale(locale))
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

internal enum ExportError: LocalizedError {
  case csvGenerationFailed
  case invalidDateRange
  case invalidURL
  case networkError
  case pdfGenerationFailed
  case serverError(code: Int, message: String)
  case unauthorized

  internal var errorDescription: String? {
    switch self {
    case .csvGenerationFailed:
      return String(localized: .dataExportErrorCsvFailed)

    case .invalidDateRange:
      return String(localized: .dataExportErrorInvalidPeriod)

    case .invalidURL, .serverError:
      return String(localized: .dataExportErrorFailed)

    case .networkError:
      return String(localized: .dataExportErrorNetwork)

    case .pdfGenerationFailed:
      return String(localized: .dataExportErrorPdfFailed)

    case .unauthorized:
      return String(localized: .commonErrorNotAuthenticated)
    }
  }
}  // swiftlint:disable:this file_length
