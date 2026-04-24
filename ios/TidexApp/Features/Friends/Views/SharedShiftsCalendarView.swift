import SwiftUI

/// Read-only calendar view for shared shifts
/// Matches the visual style of ShiftsCalendarView but without selection/editing features
struct SharedShiftsCalendarView: View {
  let shifts: [ShiftWithComputations]
  let jobs: [SharedJob]
  let year: Int
  let month: Int  // 1-12
  var phase: MonthTransitionPhase? = nil
  let currency: String
  let showEarnings: Bool
  let friendFirstName: String

  /// Dates to highlight from notification deeplink (e.g., friend's updated shifts)
  var highlightDates: Set<String> = []

  /// Shift IDs to highlight from notification deeplink (more precise than dates)
  var highlightShiftIds: Set<String> = []

  /// Whether superimpose mode is active (shows user's shifts and censors friend's metrics)
  var isSuperimposing: Bool = false

  /// User's own shift hours by date (for superimpose feature)
  var userHoursByDate: [String: HoursData]?

  /// User's own earnings by date (for superimpose feature in earnings mode)
  var userEarningsByDate: [String: CalendarEarningsData]?

  /// Callback when a shift is tapped (for showing details)
  var onShiftTapped: ((ShiftWithComputations) -> Void)?

  @State private var viewMode: CalendarViewMode = CalendarViewMode.load()
  private let calendar = Calendar.current

  /// Purple/violet color for deep link highlight (matches ShiftsCalendarView)
  private static let deepLinkHighlightColor = Color(red: 0.545, green: 0.361, blue: 0.965)

  private struct DayJobTimeColors {
    let topColor: Color
    let bottomColor: Color
  }

  private struct CalendarMetrics {
    let earningsByDate: [String: Double]
    let hoursByDate: [String: HoursData]
    let shiftsByDate: [String: [ShiftWithComputations]]
    let dayJobTimeColorsByDate: [String: DayJobTimeColors]
    let hasMultipleActiveJobs: Bool
    let monthlyTotals: (net: Double, gross: Double)
    let hasTaxEnabled: Bool
    let todayISO: String
  }

  private var calendarMetrics: CalendarMetrics {
    let jobsById = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) })
    let defaultJobId = jobs.first(where: { $0.is_default == true })?.id
    let hasMultipleActiveJobs = jobs.count > 1
    var earningsByDate: [String: Double] = [:]
    var shiftsByDate: [String: [ShiftWithComputations]] = [:]
    var monthlyGross = 0.0
    var monthlyNet = 0.0
    var hasTaxEnabled = false

    for shift in shifts {
      let net = shift.taxEnabled ? shift.netPay : shift.grossPay
      earningsByDate[shift.shiftDate, default: 0] += net
      shiftsByDate[shift.shiftDate, default: []].append(shift)

      guard let date = Date.fromISODateString(shift.shiftDate) else { continue }
      let components = calendar.dateComponents([.year, .month], from: date)
      guard components.year == year && components.month == month else { continue }

      monthlyGross += shift.grossPay
      monthlyNet += net
      hasTaxEnabled = hasTaxEnabled || shift.taxEnabled
    }

    var hoursByDate: [String: HoursData] = [:]
    var dayJobTimeColorsByDate: [String: DayJobTimeColors] = [:]

    for (date, shiftsOnDate) in shiftsByDate {
      var earliestStart: String?
      var latestEnd: String?
      var earliestShift: ShiftWithComputations?
      var earliestStartMinutes = Int.max
      var crossesMidnight = false

      for shift in shiftsOnDate {
        if earliestStart == nil || shift.startTime < (earliestStart ?? "") {
          earliestStart = shift.startTime
        }
        if latestEnd == nil || shift.endTime > (latestEnd ?? "") {
          latestEnd = shift.endTime
        }

        let startMinutes = CalendarGridHelper.timeToMinutes(shift.startTime)
        let endMinutes = CalendarGridHelper.timeToMinutes(shift.endTime)
        crossesMidnight = crossesMidnight || endMinutes <= startMinutes

        if startMinutes < earliestStartMinutes {
          earliestStartMinutes = startMinutes
          earliestShift = shift
        }
      }

      hoursByDate[date] = HoursData(
        start: CalendarGridHelper.formatTime(earliestStart ?? ""),
        end: CalendarGridHelper.formatTime(latestEnd ?? ""),
        crossesMidnight: crossesMidnight
      )

      if hasMultipleActiveJobs,
        let earliestShift,
        let topColor = resolvedJobColor(
          for: earliestShift,
          jobsById: jobsById,
          defaultJobId: defaultJobId
        )
      {
        dayJobTimeColorsByDate[date] = DayJobTimeColors(topColor: topColor, bottomColor: topColor)
      }
    }

    return CalendarMetrics(
      earningsByDate: earningsByDate,
      hoursByDate: hoursByDate,
      shiftsByDate: shiftsByDate,
      dayJobTimeColorsByDate: dayJobTimeColorsByDate,
      hasMultipleActiveJobs: hasMultipleActiveJobs,
      monthlyTotals: (net: monthlyNet, gross: monthlyGross),
      hasTaxEnabled: hasTaxEnabled,
      todayISO: todayISO()
    )
  }

  /// Month name
  private var monthName: String {
    CalendarGridHelper.monthName(
      year: year,
      month: month,
      locale: Locale.appLocale
    )
  }

  // MARK: - Body

  var body: some View {
    let metrics = calendarMetrics

    VStack(spacing: 0) {
      if isSuperimposing {
        superimposeLegend
          .padding(.bottom, Spacing.sm)
          .transition(.move(edge: .top).combined(with: .opacity))
      }

      // Header: Month name + Year and Total
      headerRow(metrics: metrics)

      // Weekday headers
      CalendarWeekdayHeader()
        .padding(.bottom, Spacing.xs)

      // Calendar grid
      calendarGrid(metrics: metrics)
        .padding(.bottom, Spacing.sm)

      // View mode toggle (hours/money)
      if showEarnings {
        CalendarViewModeToggle(
          viewMode: $viewMode,
          currency: currency
        )
      }
    }
    .animation(.spring(duration: 0.4, bounce: 0.15), value: isSuperimposing)
  }

  // MARK: - Header Row

  private func headerRow(metrics: CalendarMetrics) -> some View {
    CalendarHeaderRow(
      monthName: monthName,
      year: year,
      selectionCount: nil,
      phase: phase,
      totals: headerTotals(metrics: metrics),
      trailingAccessory: nil
    )
    .userCurrency(currency)
  }

  private func headerTotals(metrics: CalendarMetrics) -> CalendarHeaderTotals? {
    guard showEarnings else { return nil }

    let displayTotals = metrics.monthlyTotals
    let showTax = metrics.hasTaxEnabled
    let displayAmount = showTax ? displayTotals.net : displayTotals.gross
    let primaryAmount = displayTotals.gross > 0 ? displayAmount : nil
    let secondaryAmount = (showTax && displayTotals.gross > 0) ? displayTotals.gross : nil

    return CalendarHeaderTotals(primary: primaryAmount, secondary: secondaryAmount)
  }

  // MARK: - Superimpose Legend

  /// Legend explaining the calendar indicators when superimpose is active
  private var superimposeLegend: some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      superimposeLegendRow(
        icon: "person.2.fill",
        iconColor: .tidexBlue,
        description: Text(.sharingSuperimposeLegendBoth)
      )
      superimposeLegendRow(
        icon: "person.fill",
        iconColor: .tidexSuccess,
        description: Text(.sharingSuperimposeLegendOnlyYou)
      )
      superimposeLegendRow(
        icon: "person.fill",
        iconColor: .tidexError,
        description: Text(.sharingSuperimposeLegendOnlyFriend(friendFirstName))
      )
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.horizontal, Spacing.xxs)
  }

  private func superimposeLegendRow(
    icon: String,
    iconColor: Color,
    description: Text
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
      Image(systemName: icon)
        .font(.tidexFootnote.weight(.semibold))
        .foregroundColor(iconColor)
        .frame(width: Spacing.iconSize, alignment: .leading)

      description
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)
    }
  }

  // MARK: - Calendar Grid

  @ViewBuilder
  private func calendarGrid(metrics: CalendarMetrics) -> some View {
    let days = CalendarGridHelper.daysInMonth(year: year, month: month)

    let grid = CalendarMonthGrid(days: days) { dayInfo in
      calendarDayView(for: dayInfo, metrics: metrics)
    }

    if let phase {
      grid
        .cardTransition(phase: phase, config: .default)
    } else {
      grid
    }
  }

  /// Build the view for a single calendar day
  /// Extracted to help Swift's type inference
  @ViewBuilder
  private func calendarDayView(
    for dayInfo: CalendarDayInfo,
    metrics: CalendarMetrics
  ) -> some View {
    let shiftsOnDay = dayInfo.dateISO.flatMap { metrics.shiftsByDate[$0] } ?? []
    let dayJobTimeColors = dayInfo.dateISO.flatMap { metrics.dayJobTimeColorsByDate[$0] }
    let shouldColorJobMetrics =
      metrics.hasMultipleActiveJobs
      && !dayInfo.isOutsideMonth
      && !shiftsOnDay.isEmpty
      && dayJobTimeColors != nil
    let isToday = dayInfo.dateISO == metrics.todayISO
    let isHighlighted = isDateHighlighted(dayInfo: dayInfo, shiftsOnDay: shiftsOnDay)

    // Show overlap indicator whenever both user and friend have shifts.
    let friendHasShift = !shiftsOnDay.isEmpty
    let userHasShift = dayInfo.dateISO.flatMap { userHoursByDate?[$0] } != nil
    let showOverlap = friendHasShift && userHasShift
    let showOnlyUserIndicator = isSuperimposing && userHasShift && !friendHasShift
    let showOnlyFriendIndicator = isSuperimposing && friendHasShift && !userHasShift
    let showSingleUserIndicator = showOnlyUserIndicator || showOnlyFriendIndicator
    let singleUserIndicatorColor: Color = showOnlyFriendIndicator ? .tidexError : .tidexSuccess
    let showHiddenFriendMetrics = showOnlyFriendIndicator

    Group {
      if showHiddenFriendMetrics {
        CalendarDayCell(
          dayInfo: dayInfo,
          style: cellStyle(isToday: isToday, isHighlighted: isHighlighted),
          content: .custom,
          showOverlapIndicator: showOverlap,
          showSingleUserIndicator: showSingleUserIndicator,
          singleUserIndicatorColor: singleUserIndicatorColor
        ) {
          hiddenFriendMetricsPlaceholder
        }
      } else {
        CalendarDayCell(
          dayInfo: dayInfo,
          style: cellStyle(isToday: isToday, isHighlighted: isHighlighted),
          content: cellContent(
            for: dayInfo,
            dayJobTimeColors: dayJobTimeColors,
            shouldColorJobMetrics: shouldColorJobMetrics,
            metrics: metrics
          ),
          showOverlapIndicator: showOverlap,
          showSingleUserIndicator: showSingleUserIndicator,
          singleUserIndicatorColor: singleUserIndicatorColor
        )
      }
    }
    .onTapGesture {
      handleDayTap(dayInfo: dayInfo, metrics: metrics)
    }
  }

  /// Check if a date should be highlighted (from notification deeplink)
  private func isDateHighlighted(dayInfo: CalendarDayInfo, shiftsOnDay: [ShiftWithComputations])
    -> Bool
  {
    // Check if any shift on this day matches a highlight shift ID (for added/updated)
    let matchesShiftId =
      !highlightShiftIds.isEmpty
      && shiftsOnDay.contains(where: { highlightShiftIds.contains($0.id) })

    // Check date-based highlighting (for deleted shifts or legacy payloads)
    let matchesDate = dayInfo.dateISO.map { highlightDates.contains($0) } ?? false

    return matchesShiftId || matchesDate
  }

  /// Handle tap on a calendar day
  private func handleDayTap(dayInfo: CalendarDayInfo, metrics: CalendarMetrics) {
    guard !dayInfo.isOutsideMonth, let dateISO = dayInfo.dateISO else { return }
    let shiftsForDay = metrics.shiftsByDate[dateISO] ?? []
    if let firstShift = shiftsForDay.first {
      onShiftTapped?(firstShift)
    }
  }

  // MARK: - Cell Styling

  private func cellStyle(isToday: Bool, isHighlighted: Bool) -> CalendarCellStyle {
    // Priority: highlighted > today > default
    if isHighlighted {
      return CalendarCellStyle(
        backgroundColor: Self.deepLinkHighlightColor.opacity(0.2),
        borderColor: Self.deepLinkHighlightColor,
        borderWidth: 2.5,
        dayNumberColor: .tidexTextPrimary,
        showsTodayBadge: false
      )
    }
    if isToday {
      return .today()
    }
    return .default
  }

  // MARK: - Cell Content

  private func cellContent(
    for dayInfo: CalendarDayInfo,
    dayJobTimeColors: DayJobTimeColors?,
    shouldColorJobMetrics: Bool,
    metrics: CalendarMetrics
  ) -> CalendarCellContent {
    guard let dateISO = dayInfo.dateISO else { return .empty }
    let effectiveViewMode = showEarnings ? viewMode : .hours

    // When superimposing, only show the current user's data in cells.
    if isSuperimposing {
      if effectiveViewMode == .money, let earnings = userEarningsByDate?[dateISO] {
        return .earningsBreakdown(earnings)
      }
      if let userHours = userHoursByDate?[dateISO] {
        return .hours(userHours, color: .tidexTextPrimary)
      }
      return .empty
    }

    // Otherwise show friend's shifts (normal behavior)
    if effectiveViewMode == .money, let amount = metrics.earningsByDate[dateISO] {
      if shouldColorJobMetrics, let dayJobTimeColors {
        return .earnings(amount, color: dayJobTimeColors.topColor)
      }
      return .earnings(amount)
    } else if effectiveViewMode == .hours, let hoursData = metrics.hoursByDate[dateISO] {
      if shouldColorJobMetrics, let dayJobTimeColors {
        return .hours(
          hoursData,
          color: dayJobTimeColors.topColor,
          secondaryColor: dayJobTimeColors.bottomColor
        )
      }
      return .hours(hoursData)
    }

    return .empty
  }

  private func resolvedJobColor(
    for shift: ShiftWithComputations,
    jobsById: [String: SharedJob],
    defaultJobId: String?
  ) -> Color? {
    let effectiveJobId = shift.shift.job_id ?? defaultJobId
    guard
      let effectiveJobId,
      let job = jobsById[effectiveJobId],
      let uiColor = WorkplaceColor.hexToUIColor(job.color)
    else {
      return nil
    }
    return Color(uiColor: uiColor)
  }

  private var hiddenFriendMetricsPlaceholder: some View {
    GeometryReader { geo in
      let lineHeight = max(4, min(7, geo.size.height * 0.14))
      let primaryWidth = max(12, geo.size.width * 0.58)
      let secondaryWidth = max(10, geo.size.width * 0.45)

      VStack(spacing: Spacing.xxxs) {
        RoundedRectangle(cornerRadius: CornerRadius.xxs)
          .fill(Color.tidexTextMuted.opacity(0.35))
          .frame(width: primaryWidth, height: lineHeight)
        RoundedRectangle(cornerRadius: CornerRadius.xxs)
          .fill(Color.tidexTextMuted.opacity(0.24))
          .frame(width: secondaryWidth, height: lineHeight)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .accessibilityHidden(true)
  }
}

// MARK: - Preview

#Preview {
  SharedShiftsCalendarView(
    shifts: [],
    jobs: [],
    year: 2025,
    month: 1,
    currency: "kr",
    showEarnings: true,
    friendFirstName: "Alex"
  )
  .background(Color.tidexBackground)
}
