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

  // MARK: - Computed Data

  /// Earnings by ISO date string
  private var earningsByDate: [String: Double] {
    var result: [String: Double] = [:]
    for shift in shifts {
      let net = shift.taxEnabled ? shift.netPay : shift.grossPay
      result[shift.shiftDate, default: 0] += net
    }
    return result
  }

  /// Hours by ISO date string
  private var hoursByDate: [String: HoursData] {
    var shiftsByDateDict: [String: [ShiftWithComputations]] = [:]
    for shift in shifts {
      shiftsByDateDict[shift.shiftDate, default: []].append(shift)
    }

    var result: [String: HoursData] = [:]
    for (date, shiftsOnDate) in shiftsByDateDict {
      let sorted = shiftsOnDate.sorted { $0.startTime < $1.startTime }
      let earliestStart = sorted.first?.startTime ?? ""
      let latestEnd = sorted.map(\.endTime).max() ?? ""

      let crossesMidnight = shiftsOnDate.contains { shift in
        let startMinutes = CalendarGridHelper.timeToMinutes(shift.startTime)
        let endMinutes = CalendarGridHelper.timeToMinutes(shift.endTime)
        return endMinutes <= startMinutes
      }

      result[date] = HoursData(
        start: CalendarGridHelper.formatTime(earliestStart),
        end: CalendarGridHelper.formatTime(latestEnd),
        crossesMidnight: crossesMidnight
      )
    }
    return result
  }

  /// Shifts grouped by ISO date string
  private var shiftsByDate: [String: [ShiftWithComputations]] {
    var result: [String: [ShiftWithComputations]] = [:]
    for shift in shifts {
      result[shift.shiftDate, default: []].append(shift)
    }
    return result
  }

  private var jobsById: [String: SharedJob] {
    Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) })
  }

  private var defaultJobId: String? {
    jobs.first(where: { $0.is_default == true })?.id
  }

  private var hasMultipleActiveJobs: Bool {
    jobs.count > 1
  }

  private var dayJobTimeColorsByDate: [String: DayJobTimeColors] {
    guard hasMultipleActiveJobs else { return [:] }

    var result: [String: DayJobTimeColors] = [:]

    for (dateISO, shiftsOnDay) in shiftsByDate where !shiftsOnDay.isEmpty {
      let sortedShifts = shiftsOnDay.sorted { lhs, rhs in
        CalendarGridHelper.timeToMinutes(lhs.startTime)
          < CalendarGridHelper.timeToMinutes(rhs.startTime)
      }

      guard let earliestShift = sortedShifts.first else { continue }
      guard let topColor = resolvedJobColor(for: earliestShift) else { continue }

      result[dateISO] = DayJobTimeColors(topColor: topColor, bottomColor: topColor)
    }

    return result
  }

  /// Shifts that belong to the committed month (excludes out-of-month padding days)
  private var shiftsInDisplayedMonth: [ShiftWithComputations] {
    shifts.filter { shift in
      guard let date = Date.fromISODateString(shift.shiftDate) else { return false }
      let components = calendar.dateComponents([.year, .month], from: date)
      return components.year == year && components.month == month
    }
  }

  /// Monthly totals (net and gross)
  private var monthlyTotals: (net: Double, gross: Double) {
    let gross = shiftsInDisplayedMonth.reduce(0) { $0 + $1.grossPay }
    let net = shiftsInDisplayedMonth.reduce(0) {
      $0 + ($1.taxEnabled ? $1.netPay : $1.grossPay)
    }
    return (net: net, gross: gross)
  }

  /// Whether tax is enabled for any shift
  private var hasTaxEnabled: Bool {
    shiftsInDisplayedMonth.contains { $0.taxEnabled }
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
    VStack(spacing: 0) {
      if isSuperimposing {
        superimposeLegend
          .padding(.bottom, Spacing.sm)
          .transition(.move(edge: .top).combined(with: .opacity))
      }

      // Header: Month name + Year and Total
      headerRow

      // Weekday headers
      CalendarWeekdayHeader()
        .padding(.bottom, Spacing.xs)

      // Calendar grid
      calendarGrid
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

  private var headerRow: some View {
    HStack {
      monthYearLabel

      Spacer()

      // Monthly total (if showing earnings)
      if showEarnings {
        earningsDisplay
      }
    }
    .padding(.horizontal, Spacing.xxs)
    .padding(.bottom, Spacing.sm)
  }

  @ViewBuilder
  private var monthYearLabel: some View {
    if let phase {
      HStack(spacing: Spacing.xxxs) {
        Text(monthName)
          .font(.tidexTitle2)
          .foregroundColor(.tidexTextPrimary)

        Text(String(year))
          .font(.tidexBodyLarge)
          .foregroundColor(.tidexTextMuted)
      }
      .textTransition(phase: phase, config: .default)
    } else {
      HStack(spacing: Spacing.xxxs) {
        Text(monthName)
          .font(.tidexTitle2)
          .foregroundColor(.tidexTextPrimary)

        Text(String(year))
          .font(.tidexBodyLarge)
          .foregroundColor(.tidexTextMuted)
      }
    }
  }

  /// Earnings display - shows monthly totals
  @ViewBuilder
  private var earningsDisplay: some View {
    let displayTotals = monthlyTotals
    let showTax = hasTaxEnabled
    let displayAmount = showTax ? displayTotals.net : displayTotals.gross

    VStack(alignment: .trailing, spacing: Spacing.micro) {
      Text(
        displayTotals.gross == 0 ? "—" : CurrencyConfig.format(displayAmount, currency: currency)
      )
      .font(.tidexHeadline)
      .foregroundColor(.tidexTextPrimary)

      if showTax && displayTotals.gross > 0 {
        Text(CurrencyConfig.format(displayTotals.gross, currency: currency))
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextMuted)
      }
    }
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
  private var calendarGrid: some View {
    let days = CalendarGridHelper.daysInMonth(year: year, month: month)

    let grid = CalendarMonthGrid(days: days) { dayInfo in
      calendarDayView(for: dayInfo)
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
  private func calendarDayView(for dayInfo: CalendarDayInfo) -> some View {
    let shiftsOnDay = dayInfo.dateISO.flatMap { shiftsByDate[$0] } ?? []
    let dayJobTimeColors = dayInfo.dateISO.flatMap { dayJobTimeColorsByDate[$0] }
    let shouldColorJobMetrics =
      hasMultipleActiveJobs
      && !dayInfo.isOutsideMonth
      && !shiftsOnDay.isEmpty
      && dayJobTimeColors != nil
    let isToday = dayInfo.dateISO == todayISO()
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
            shouldColorJobMetrics: shouldColorJobMetrics
          ),
          showOverlapIndicator: showOverlap,
          showSingleUserIndicator: showSingleUserIndicator,
          singleUserIndicatorColor: singleUserIndicatorColor
        )
      }
    }
    .onTapGesture {
      handleDayTap(dayInfo: dayInfo)
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
  private func handleDayTap(dayInfo: CalendarDayInfo) {
    guard !dayInfo.isOutsideMonth, let dateISO = dayInfo.dateISO else { return }
    let shiftsForDay = shiftsByDate[dateISO] ?? []
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
    shouldColorJobMetrics: Bool
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
    if effectiveViewMode == .money, let amount = earningsByDate[dateISO] {
      if shouldColorJobMetrics, let dayJobTimeColors {
        return .earnings(amount, color: dayJobTimeColors.topColor)
      }
      return .earnings(amount)
    } else if effectiveViewMode == .hours, let hoursData = hoursByDate[dateISO] {
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

  private func resolvedJobColor(for shift: ShiftWithComputations) -> Color? {
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
