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

  /// Selected period preset. Last month is the usual payroll export.
  var selectedPreset: ExportPeriodPreset? = .lastMonth  // swiftlint:disable:this explicit_acl

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

      let userName = AppCoordinator.shared.userDisplayName.trimmingCharacters(
        in: .whitespacesAndNewlines
      )

      // Handle export based on format
      switch format {
      case .pdf:
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
          localeIdentifier: locale.identifier,
          userName: userName
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

  /// Generate PDF from export data. The layout puts the totals people look for first in
  /// one row under the header, then lists shifts grouped by month.
  nonisolated static func generatePDF(
    from data: ExportResponse,
    range: (from: String, to: String),
    localeIdentifier: String,
    userName: String,
    userContact: String
  ) throws -> URL {
    let locale = Locale(identifier: localeIdentifier)
    let title = String(localized: .dataExportPdfDocumentTitle)
    let pdfMetaData = [
      kCGPDFContextCreator: "Tidex",
      kCGPDFContextAuthor: userName.isEmpty ? "Tidex" : userName,
      kCGPDFContextTitle: title,
    ]

    let format = UIGraphicsPDFRendererFormat()
    format.documentInfo = pdfMetaData as [String: Any]

    // A4 size in points (72 points = 1 inch)
    let pageWidth: CGFloat = 595.0
    let pageHeight: CGFloat = 842.0
    let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
    let margin: CGFloat = 40
    let contentWidth = pageWidth - (margin * 2)
    let footerY = pageHeight - 30
    let bottomLimit = pageHeight - 50

    let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
    let totalHours = data.shifts.reduce(0.0) { $0 + $1.calc.hours }
    let totalBaseWage = data.shifts.reduce(0.0) { $0 + $1.calc.baseWage }
    let totalSupplement = data.shifts.reduce(0.0) { $0 + $1.calc.supplement }
    let totalWage = data.shifts.reduce(0.0) { $0 + $1.calc.total }

    let weekdayCount = data.shifts.filter { $0.type == 0 }.count
    let saturdayCount = data.shifts.filter { $0.type == 1 }.count
    let sundayCount = data.shifts.filter { $0.type == 2 }.count

    // Month subtotals only help when the export spans more than one month.
    // Sums in table column order: hours, base, supplement, total.
    let monthTotals = Dictionary(grouping: data.shifts) { String($0.date.prefix(7)) }
      .mapValues { shifts in
        [
          shifts.reduce(0.0) { $0 + $1.calc.hours },
          shifts.reduce(0.0) { $0 + $1.calc.baseWage },
          shifts.reduce(0.0) { $0 + $1.calc.supplement },
          shifts.reduce(0.0) { $0 + $1.calc.total },
        ]
      }
    let showsMonthTotals = monthTotals.count > 1
    let showsJob = Set(data.shifts.map(\.jobName).filter { !$0.isEmpty }).count > 1

    // Paper is always white, so resolve brand assets for light appearance.
    let lightTraits = UITraitCollection(userInterfaceStyle: .light)
    let logoImage = UIImage(named: "TidexLogo", in: nil, compatibleWith: lightTraits)
    let brandColor = (UIColor(named: "TidexBlue") ?? .systemBlue).resolvedColor(with: lightTraits)
    let brandTint = brandColor.withAlphaComponent(0.07)
    let textColor = UIColor(white: 0.08, alpha: 1)
    let secondaryTextColor = UIColor(white: 0.38, alpha: 1)
    let zebraColor = UIColor(white: 0.965, alpha: 1)
    let lineColor = UIColor(white: 0.8, alpha: 1)

    let currencySymbol = data.currencySymbol
    let nameLabel = String(localized: .dataExportPdfNameLabel)
    let periodLabel = String(localized: .dataExportPdfPeriodLabel)
    let exportedLabel = Self.pdfLabel(.dataExportPdfExportedLabel)
    let totalPayLabel = Self.pdfLabel(.dataExportPdfTotalPay)
    let basePayLabel = String(localized: .dataExportPdfBasePay)
    let supplementsLabel = String(localized: .dataExportPdfSupplements)
    let sumLabel = Self.pdfLabel(.dataExportPdfSumLabel)

    let generatedAtFormat = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)
      .calendar(.gregorian)
    let monthFormat = Date.FormatStyle.dateTime.year().month(.wide).locale(locale).calendar(.gregorian)
    let weekdayFormat = Date.FormatStyle.dateTime.weekday(.abbreviated).locale(locale)
      .calendar(.gregorian)

    func money(_ value: Double) -> String {
      "\(Self.formatNumber(value, decimals: 0, locale: locale)) \(currencySymbol)"
    }

    let periodText = Self.pdfPeriodText(range: range, locale: locale)
    let shiftTypeText = [
      "\(String(localized: .dataExportPdfWeekdays)) \(weekdayCount)",
      "\(String(localized: .dataExportPdfSaturdays)) \(saturdayCount)",
      "\(String(localized: .dataExportPdfSundaysHolidays)) \(sundayCount)",
    ].joined(separator: "   ·   ")

    // Widths add up to the 515 pt content width. Without a job column, the time column
    // takes the spare width so the money columns stay against the right edge.
    let jobColumnWidth: CGFloat = 81
    let jobColumns: [PDFColumn] =
      showsJob
      ? [.init(title: String(localized: .dataExportTableJob), width: jobColumnWidth, alignment: .left)]
      : []
    let columns: [PDFColumn] =
      [
        .init(title: String(localized: .dataExportTableDate), width: 60, alignment: .left),
        .init(
          title: "\(String(localized: .dataExportTableStart))–\(String(localized: .dataExportTableEnd))",
          width: showsJob ? 80 : 80 + jobColumnWidth,
          alignment: .left
        ),
      ] + jobColumns + [
        .init(title: String(localized: .dataExportTableHours), width: 54, alignment: .right),
        .init(title: String(localized: .dataExportTableBase), width: 78, alignment: .right),
        .init(title: String(localized: .dataExportTableSupplement), width: 78, alignment: .right),
        .init(title: String(localized: .dataExportTableTotal), width: 84, alignment: .right),
      ]
    let hoursColumn = columns.count - 4
    let totalColumn = columns.count - 1
    let columnX: [CGFloat] = columns.indices.map { index in
      margin + columns.prefix(index).reduce(0) { $0 + $1.width }
    }

    let pdfData = renderer.pdfData { context in
      let titleFont = UIFont.systemFont(ofSize: 17, weight: .bold)
      let wordmarkFont = UIFont.systemFont(ofSize: 13, weight: .semibold)
      let valueFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
      let metaFont = UIFont.systemFont(ofSize: 9, weight: .regular)
      let labelFont = UIFont.systemFont(ofSize: 8, weight: .semibold)
      let figureFont = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium)
      let figureStrongFont = UIFont.monospacedDigitSystemFont(ofSize: 14, weight: .bold)
      let monthFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
      let rowFont = UIFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)
      let rowStrongFont = UIFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
      let totalFont = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)

      let cellPadding: CGFloat = 6
      let tableHeaderHeight: CGFloat = 22
      let monthHeaderHeight: CGFloat = 26
      let rowHeight: CGFloat = 18
      let totalsHeight: CGFloat = 30

      var pageNumber = 0
      var yPosition: CGFloat = 0

      func cellRect(_ column: Int, height: CGFloat) -> CGRect {
        CGRect(
          x: columnX[column] + cellPadding,
          y: yPosition,
          width: columns[column].width - (cellPadding * 2),
          height: height
        )
      }

      func drawPageChrome() {
        Self.drawPDFText(
          title,
          in: CGRect(x: margin, y: margin, width: contentWidth - 140, height: 24),
          font: titleFont,
          color: textColor
        )

        // Logo and wordmark sit top right, the way a letterhead carries a company mark.
        let wordmark = "Tidex"
        let wordmarkWidth = ceil((wordmark as NSString).size(withAttributes: [.font: wordmarkFont]).width) + 2
        var markX = pageWidth - margin - wordmarkWidth
        Self.drawPDFText(
          wordmark,
          in: CGRect(x: markX, y: margin, width: wordmarkWidth, height: 24),
          font: wordmarkFont,
          color: brandColor
        )
        if let logoImage {
          let logoHeight: CGFloat = 15
          let logoWidth = logoHeight * logoImage.size.width / max(logoImage.size.height, 1)
          markX -= logoWidth + 5
          logoImage.draw(in: CGRect(x: markX, y: margin + 4.5, width: logoWidth, height: logoHeight))
        }

        Self.drawLine(
          from: CGPoint(x: margin, y: margin + 34),
          to: CGPoint(x: pageWidth - margin, y: margin + 34),
          color: lineColor,
          width: 0.75
        )

        Self.drawPDFText(
          "tidex.no",
          in: CGRect(x: margin, y: footerY, width: 200, height: 12),
          font: metaFont,
          color: secondaryTextColor
        )
        Self.drawPDFText(
          "\(pageNumber)",
          in: CGRect(x: pageWidth - margin - 60, y: footerY, width: 60, height: 12),
          font: metaFont,
          color: secondaryTextColor,
          alignment: .right
        )
      }

      func drawDetails() {
        let top = margin + 50
        let nameValue = userName.isEmpty ? userContact : userName
        let nameDetail = userName.isEmpty || userContact.isEmpty ? nil : userContact
        var fields: [PDFField] = [
          .init(label: periodLabel, value: periodText, width: 205),
          .init(label: exportedLabel, value: data.generatedAt.formatted(generatedAtFormat), width: 140),
        ]
        if !nameValue.isEmpty {
          fields.insert(.init(label: nameLabel, value: nameValue, detail: nameDetail, width: 170), at: 0)
        }

        var xPosition = margin
        for field in fields {
          let width = field.width - 12
          Self.drawPDFText(
            field.label.uppercased(with: locale),
            in: CGRect(x: xPosition, y: top, width: width, height: 12),
            font: labelFont,
            color: secondaryTextColor
          )
          Self.drawPDFText(
            field.value,
            in: CGRect(x: xPosition, y: top + 14, width: width, height: 16),
            font: valueFont,
            color: textColor
          )
          if let detail = field.detail {
            Self.drawPDFText(
              detail,
              in: CGRect(x: xPosition, y: top + 30, width: width, height: 12),
              font: metaFont,
              color: secondaryTextColor
            )
          }
          xPosition += field.width
        }
        yPosition = top + 60
      }

      func drawTotals() {
        let top = yPosition
        let height: CGFloat = 52
        for lineY in [top, top + height] {
          Self.drawLine(
            from: CGPoint(x: margin, y: lineY),
            to: CGPoint(x: pageWidth - margin, y: lineY),
            color: lineColor,
            width: 0.75
          )
        }

        // Widths add up to the content width and leave room for six-figure amounts.
        let figures: [PDFField] = [
          .init(label: totalPayLabel, value: money(totalWage), width: 125),
          .init(label: basePayLabel, value: money(totalBaseWage), width: 125),
          .init(label: supplementsLabel, value: money(totalSupplement), width: 110),
          .init(
            label: String(localized: .statsHours),
            value: Self.formatNumber(totalHours, decimals: 2, locale: locale),
            width: 85
          ),
          .init(label: String(localized: .statsShifts), value: "\(data.shifts.count)", width: 70),
        ]
        var xPosition = margin
        for (index, figure) in figures.enumerated() {
          let inset: CGFloat = index == 0 ? 0 : 12
          if index > 0 {
            Self.drawLine(
              from: CGPoint(x: xPosition, y: top + 12),
              to: CGPoint(x: xPosition, y: top + height - 12),
              color: lineColor,
              width: 0.75
            )
          }
          let width = figure.width - inset - 6
          Self.drawPDFText(
            figure.label.uppercased(with: locale),
            in: CGRect(x: xPosition + inset, y: top + 11, width: width, height: 12),
            font: labelFont,
            color: secondaryTextColor
          )
          Self.drawPDFText(
            figure.value,
            in: CGRect(x: xPosition + inset, y: top + 25, width: width, height: 18),
            font: index == 0 ? figureStrongFont : figureFont,
            color: textColor
          )
          xPosition += figure.width
        }

        yPosition = top + height + 8
        Self.drawPDFText(
          shiftTypeText,
          in: CGRect(x: margin, y: yPosition, width: contentWidth, height: 14),
          font: metaFont,
          color: secondaryTextColor
        )
        yPosition += 34
      }

      func drawTableHeader() {
        for index in columns.indices {
          Self.drawPDFText(
            columns[index].title.uppercased(with: locale),
            in: cellRect(index, height: tableHeaderHeight - 4),
            font: labelFont,
            color: secondaryTextColor,
            alignment: columns[index].alignment
          )
        }
        Self.drawLine(
          from: CGPoint(x: margin, y: yPosition + tableHeaderHeight - 4),
          to: CGPoint(x: pageWidth - margin, y: yPosition + tableHeaderHeight - 4),
          color: lineColor,
          width: 0.75
        )
        yPosition += tableHeaderHeight
      }

      func drawMonthHeader(title monthTitle: String, key: String) {
        yPosition += 4
        let bandHeight = monthHeaderHeight - 6
        Self.fillPDFRect(
          CGRect(x: margin, y: yPosition, width: contentWidth, height: bandHeight),
          color: brandTint,
          cornerRadius: 4
        )
        Self.drawPDFText(
          monthTitle,
          in: CGRect(x: margin + cellPadding, y: yPosition, width: 220, height: bandHeight),
          font: monthFont,
          color: textColor
        )
        if showsMonthTotals, let totals = monthTotals[key] {
          for (offset, value) in totals.enumerated() {
            Self.drawPDFText(
              Self.formatNumber(value, decimals: offset == 0 ? 2 : 0, locale: locale),
              in: cellRect(hoursColumn + offset, height: bandHeight),
              font: rowStrongFont,
              color: textColor,
              alignment: .right
            )
          }
        }
        yPosition += monthHeaderHeight - 4
      }

      func beginPage() {
        context.beginPage()
        pageNumber += 1
        drawPageChrome()
        if pageNumber == 1 {
          drawDetails()
          drawTotals()
        } else {
          let continuation = userName.isEmpty ? periodText : "\(userName)  ·  \(periodText)"
          Self.drawPDFText(
            continuation,
            in: CGRect(x: margin, y: margin + 44, width: contentWidth, height: 14),
            font: metaFont,
            color: secondaryTextColor
          )
          yPosition = margin + 72
        }
        drawTableHeader()
      }

      beginPage()

      // Month on the current page. Reset on a page break so the month header repeats and
      // day-only dates keep their context.
      var pageMonthKey: String?
      var rowInMonth = 0

      for shift in data.shifts {
        let shiftDate = Date.fromISODateString(shift.date)
        let monthKey = String(shift.date.prefix(7))
        let requiredHeight = rowHeight + (monthKey != pageMonthKey ? monthHeaderHeight : 0)

        if yPosition + requiredHeight > bottomLimit {
          beginPage()
          pageMonthKey = nil
        }

        if monthKey != pageMonthKey {
          drawMonthHeader(title: shiftDate?.formatted(monthFormat) ?? monthKey, key: monthKey)
          pageMonthKey = monthKey
          rowInMonth = 0
        }

        if rowInMonth % 2 == 1 {
          Self.fillPDFRect(
            CGRect(x: margin, y: yPosition, width: contentWidth, height: rowHeight),
            color: zebraColor,
            cornerRadius: 3
          )
        }

        // Day number right-aligned, weekday after it, so the column scans cleanly.
        let dateRect = cellRect(0, height: rowHeight)
        Self.drawPDFText(
          shiftDate.map { "\(Calendar.gregorianCurrent.component(.day, from: $0))" } ?? shift.date,
          in: CGRect(x: dateRect.minX, y: dateRect.minY, width: 16, height: rowHeight),
          font: rowStrongFont,
          color: textColor,
          alignment: .right
        )
        Self.drawPDFText(
          shiftDate.map { $0.formatted(weekdayFormat) } ?? "",
          in: CGRect(x: dateRect.minX + 22, y: dateRect.minY, width: dateRect.width - 22, height: rowHeight),
          font: rowFont,
          color: secondaryTextColor
        )

        var values = ["\(shift.startTime)–\(shift.endTime)"]
        if showsJob {
          values.append(shift.jobName)
        }
        values += [
          Self.formatNumber(shift.calc.hours, decimals: 2, locale: locale),
          Self.formatNumber(shift.calc.baseWage, decimals: 0, locale: locale),
          shift.calc.supplement == 0
            ? "–" : Self.formatNumber(shift.calc.supplement, decimals: 0, locale: locale),
          Self.formatNumber(shift.calc.total, decimals: 0, locale: locale),
        ]
        for (offset, value) in values.enumerated() {
          let column = offset + 1
          Self.drawPDFText(
            value,
            in: cellRect(column, height: rowHeight),
            font: column == totalColumn ? rowStrongFont : rowFont,
            color: column == totalColumn || column == 1 ? textColor : secondaryTextColor,
            alignment: columns[column].alignment
          )
        }

        yPosition += rowHeight
        rowInMonth += 1
      }

      if yPosition + totalsHeight > bottomLimit {
        beginPage()
      }

      yPosition += 6
      Self.drawLine(
        from: CGPoint(x: margin, y: yPosition),
        to: CGPoint(x: pageWidth - margin, y: yPosition),
        color: textColor,
        width: 1
      )
      yPosition += 4

      let totalRowHeight = totalsHeight - 10
      Self.drawPDFText(
        sumLabel,
        in: CGRect(x: margin + cellPadding, y: yPosition, width: 200, height: totalRowHeight),
        font: totalFont,
        color: textColor
      )
      let totals = [
        Self.formatNumber(totalHours, decimals: 2, locale: locale),
        Self.formatNumber(totalBaseWage, decimals: 0, locale: locale),
        Self.formatNumber(totalSupplement, decimals: 0, locale: locale),
        Self.formatNumber(totalWage, decimals: 0, locale: locale),
      ]
      for (offset, value) in totals.enumerated() {
        Self.drawPDFText(
          value,
          in: cellRect(hoursColumn + offset, height: totalRowHeight),
          font: totalFont,
          color: textColor,
          alignment: .right
        )
      }
    }

    // Save to temp file
    let filename = Self.buildFilename(range: range, format: .pdf, locale: locale, userName: userName)
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    try pdfData.write(to: tempURL)

    return tempURL
  }

  /// Period shown in the PDF header. A whole calendar month reads as "September 2026".
  private nonisolated static func pdfPeriodText(range: (from: String, to: String), locale: Locale)
    -> String
  {
    guard let fromDate = Date.fromISODateString(range.from),
      let toDate = Date.fromISODateString(range.to),
      fromDate <= toDate
    else {
      return "\(range.from) – \(range.to)"
    }

    let calendar = Calendar.gregorianCurrent
    let startsOnFirst = calendar.component(.day, from: fromDate) == 1
    let endsOnLast = calendar.date(byAdding: .day, value: 1, to: toDate)
      .map { calendar.component(.day, from: $0) == 1 } ?? false
    if startsOnFirst, endsOnLast, calendar.isDate(fromDate, equalTo: toDate, toGranularity: .month) {
      return fromDate.formatted(
        Date.FormatStyle.dateTime.year().month(.wide).locale(locale).calendar(.gregorian)
      )
    }

    let dateFormat = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)
      .calendar(.gregorian)
    return "\(fromDate.formatted(dateFormat)) – \(toDate.formatted(dateFormat))"
  }

  /// Existing summary labels end with a colon. Headings and card labels read better without it.
  private nonisolated static func pdfLabel(_ resource: LocalizedStringResource) -> String {
    String(localized: resource).trimmingCharacters(in: CharacterSet(charactersIn: ": \u{00A0}"))
  }

  /// Generate CSV from export data in a detached task.
  private static func generateCSVOffMain(
    from data: ExportResponse,
    range: (from: String, to: String),
    localeIdentifier: String,
    userName: String
  ) async throws -> URL {
    try await Task.detached(priority: .utility) {
      try generateCSV(from: data, range: range, localeIdentifier: localeIdentifier, userName: userName)
    }.value
  }

  /// Generate CSV from export data
  nonisolated static func generateCSV(
    from data: ExportResponse,
    range: (from: String, to: String),
    localeIdentifier: String,
    userName: String = ""
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
    let filename = Self.buildFilename(range: range, format: .csv, locale: locale, userName: userName)
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)

    return tempURL
  }

  /// Build filename for export
  private nonisolated static func buildFilename(
    range: (from: String, to: String),
    format: ExportFormat,
    locale: Locale,
    userName: String
  ) -> String {
    let ext = format == .pdf ? "pdf" : "csv"
    let prefix = fileNamePrefix(userName: userName)

    // Parse dates
    guard let fromDate = Date.fromISODateString(range.from),
      let toDate = Date.fromISODateString(range.to)
    else {
      return "\(prefix)_export.\(ext)"
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
      // Full month: ola-nordmann_jan-2026.pdf
      return "\(prefix)_\(fromMonth)-\(fromYear).\(ext)"
    }
    if isSameMonth {
      // Same month range: ola-nordmann_01-15jan-2026.pdf
      let fromDay = String(format: "%02d", calendar.component(.day, from: fromDate))
      let toDay = String(format: "%02d", calendar.component(.day, from: toDate))
      return "\(prefix)_\(fromDay)-\(toDay)\(fromMonth)-\(fromYear).\(ext)"
    }
    if fromYear == toYear {
      // Cross-month same year: ola-nordmann_01jan-15feb-2026.pdf
      let fromDay = String(format: "%02d", calendar.component(.day, from: fromDate))
      let toDay = String(format: "%02d", calendar.component(.day, from: toDate))
      return "\(prefix)_\(fromDay)\(fromMonth)-\(toDay)\(toMonth)-\(fromYear).\(ext)"
    }
    // Cross-year: ola-nordmann_dec2025-jan2026.pdf
    return "\(prefix)_\(fromMonth)\(fromYear)-\(toMonth)\(toYear).\(ext)"
  }

  /// Export file names start with the user's name, such as "ola-nordmann". Only letters and
  /// digits are kept, so a name can't add path separators. Without a name this is "tidex".
  nonisolated static func fileNamePrefix(userName: String) -> String {
    let words = userName.lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
    return words.isEmpty ? "tidex" : words.joined(separator: "-")
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

  private nonisolated static func fillPDFRect(_ rect: CGRect, color: UIColor, cornerRadius: CGFloat = 0) {
    color.setFill()
    UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).fill()
  }
}

private struct PDFColumn {
  let title: String
  let width: CGFloat
  let alignment: NSTextAlignment
}

/// A labelled value in the PDF header, such as the period or total pay.
private struct PDFField {
  let label: String
  let value: String
  var detail: String?
  let width: CGFloat
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
