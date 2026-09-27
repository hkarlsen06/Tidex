import SwiftUI
import UIKit

/// Read-only calendar view for shared shifts
/// Matches the visual style of ShiftsCalendarView but without selection/editing features
internal struct SharedShiftsCalendarView: View {  // swiftlint:disable:this type_body_length
  @ObservedObject private var appearanceManager = AppearanceManager.shared

  let shifts: [ShiftWithComputations]
  let jobs: [SharedJob]
  let year: Int
  let month: Int  // 1-12
  // swiftlint:disable:next explicit_acl type_contents_order
  var phase: MonthTransitionPhase?
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

  /// User's own raw shifts by date (for precise overlap indicators)
  var userShiftsByDate: [String: [ShiftRow]]?

  /// User's own earnings by date (for superimpose feature in earnings mode)
  var userEarningsByDate: [String: CalendarEarningsData]?

  /// Callback when a shift is tapped (for showing details)
  var onShiftTapped: ((ShiftWithComputations) -> Void)?

  // swiftlint:disable:next explicit_type_interface type_contents_order
  @State private var viewMode = CalendarViewMode.load()
  @State private var selectedDates: Set<String> = []
  @State private var selectedEarningsByDate: [String: CalendarEarningsData] = [:]
  private let toggleHaptic = UIImpactFeedbackGenerator(style: .light)
  private let calendar = Calendar.current

  /// Purple/violet color for deep link highlight (matches ShiftsCalendarView)
  private static let deepLinkHighlightColor = Color.tidexPurple

  /// Superimpose indicator colors mark whose shift it is. They avoid the error and success
  /// colors so neither person's shift reads as a problem or a confirmation.
  private static let yourIndicatorColor = Color.tidexTextPrimary
  private static let friendIndicatorColor = Color.tidexPurple

  private struct DayJobTimeColors {
    let topColor: Color
    let bottomColor: Color
  }

  private struct CalendarMetrics {
    let earningsByDate: [String: CalendarEarningsData]
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
    let hasMultipleActiveJobs =
      appearanceManager.calendarContentColorStyle.usesWorkplaceColors && jobs.count > 1
    var netByDate: [String: Double] = [:]
    var grossByDate: [String: Double] = [:]
    var hasTaxByDate: [String: Bool] = [:]
    var shiftsByDate: [String: [ShiftWithComputations]] = [:]
    var monthlyGross = 0.0
    var monthlyNet = 0.0
    var hasTaxEnabled = false

    for shift in shifts {
      let net = shift.taxEnabled ? shift.netPay : shift.grossPay
      netByDate[shift.shiftDate, default: 0] += net
      grossByDate[shift.shiftDate, default: 0] += shift.grossPay
      hasTaxByDate[shift.shiftDate, default: false] =
        hasTaxByDate[shift.shiftDate, default: false] || shift.taxEnabled
      shiftsByDate[shift.shiftDate, default: []].append(shift)

      guard let date = Date.fromISODateString(shift.shiftDate) else { continue }
      let components = calendar.dateComponents([.year, .month], from: date)
      guard components.year == year, components.month == month else { continue }

      monthlyGross += shift.grossPay
      monthlyNet += net
      hasTaxEnabled = hasTaxEnabled || shift.taxEnabled
    }

    var hoursByDate: [String: HoursData] = [:]
    var dayJobTimeColorsByDate: [String: DayJobTimeColors] = [:]
    var earningsByDate: [String: CalendarEarningsData] = [:]

    for (date, net) in netByDate {
      let gross = grossByDate[date] ?? net
      earningsByDate[date] = CalendarEarningsData(
        net: net,
        gross: gross,
        hasTaxEnabled: hasTaxByDate[date] ?? false
      )
    }

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

      // View mode toggle or selected-date actions
      if showEarnings {
        actionBar(metrics: metrics)
      }
    }
    .animation(.spring(duration: 0.4, bounce: 0.15), value: isSuperimposing)
    .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selectedDates.count)
    .onAppear {
      toggleHaptic.prepare()
      syncSelectedEarnings(with: metrics)
    }
    .onChange(of: shifts) { _, _ in
      syncSelectedEarnings(with: metrics)
    }
    .onChange(of: showEarnings) { _, canShowEarnings in
      if !canShowEarnings {
        clearSelection()
      }
    }
    .onChange(of: isSuperimposing) { _, isSuperimposing in
      if isSuperimposing {
        clearSelection()
      }
    }
  }

  // MARK: - Header Row

  private func headerRow(metrics: CalendarMetrics) -> some View {
    CalendarHeaderRow(
      monthName: monthName,
      year: year,
      selectionCount: selectedDates.count >= 2 ? selectedDates.count : nil,
      phase: phase,
      totals: headerTotals(metrics: metrics),
      trailingAccessory: nil
    )
    .userCurrency(currency)
  }

  private func headerTotals(metrics: CalendarMetrics) -> CalendarHeaderTotals? {
    guard showEarnings else { return nil }

    let displayTotals = metrics.monthlyTotals
    let showTax: Bool
    let selectedTotals: (net: Double, gross: Double)?

    if let selectedAggregate = selectedEarningsAggregate(metrics: metrics) {
      showTax = selectedAggregate.hasTaxEnabled
      selectedTotals = (net: selectedAggregate.net, gross: selectedAggregate.gross)
    } else {
      showTax = metrics.hasTaxEnabled
      selectedTotals = nil
    }

    let totals = selectedTotals ?? displayTotals
    let displayAmount = showTax ? totals.net : totals.gross
    let primaryAmount = totals.gross > 0 ? displayAmount : nil
    let secondaryAmount = (showTax && totals.gross > 0) ? totals.gross : nil

    return CalendarHeaderTotals(primary: primaryAmount, secondary: secondaryAmount)
  }

  // MARK: - Action Bar

  @ViewBuilder
  private func actionBar(metrics: CalendarMetrics) -> some View {
    if selectedDates.isEmpty {
      CalendarViewModeToggle(
        viewMode: $viewMode,
        currency: currency
      )
    } else if selectedDates.count == 1 {
      singleSelectionBar(metrics: metrics)
    } else {
      multiSelectionBar
    }
  }

  private func singleSelectionBar(metrics: CalendarMetrics) -> some View {
    HStack(spacing: Spacing.xxs) {
      Button {
        toggleHaptic.impactOccurred()
        if let selectedShift = selectedShift(metrics: metrics) {
          onShiftTapped?(selectedShift)
        }
      } label: {
        HStack(spacing: Spacing.xxxs) {
          Image(systemName: "info.circle")
            .font(.tidexLabel)
          Text(.shiftsDetails)
            .font(.tidexLabelStrong)
        }
        .foregroundColor(.tidexTextPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
          Capsule().fill(.clear)
            .tidexGlass(shape: .capsule, interactive: selectedShift(metrics: metrics) != nil)
        )
      }
      .buttonStyle(.plain)
      .disabled(selectedShift(metrics: metrics) == nil)

      Button {
        toggleHaptic.impactOccurred()
        clearSelection()
      } label: {
        HStack(spacing: Spacing.xxxs) {
          Image(systemName: "xmark")
            .font(.tidexLabel)
          Text(.commonCancel)
            .font(.tidexLabelStrong)
        }
        .foregroundColor(.tidexTextPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
          Capsule().fill(.clear)
            .tidexGlass(shape: .capsule, interactive: true)
        )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(.commonCancel))
    }
    .padding(Spacing.xxs)
    .background(Capsule().fill(Color.tidexSurfaceSecondary))
  }

  private var multiSelectionBar: some View {
    HStack(spacing: Spacing.xxs) {
      HStack(spacing: Spacing.xxxs) {
        Image(systemName: "checkmark.circle")
          .font(.tidexLabel)
        Text("\(selectedDates.count)")
          .font(.tidexLabelStrong)
      }
      .foregroundColor(.tidexTextPrimary)
      .frame(maxWidth: .infinity)
      .frame(height: 44)
      .background(
        Capsule().fill(.clear)
          .tidexGlass(shape: .capsule, interactive: false)
      )

      Button {
        toggleHaptic.impactOccurred()
        clearSelection()
      } label: {
        HStack(spacing: Spacing.xxxs) {
          Image(systemName: "xmark")
            .font(.tidexLabel)
          Text(.commonCancel)
            .font(.tidexLabelStrong)
        }
        .foregroundColor(.tidexTextPrimary)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
          Capsule().fill(.clear)
            .tidexGlass(shape: .capsule, interactive: true)
        )
      }
      .buttonStyle(.plain)
    }
    .padding(Spacing.xxs)
    .background(Capsule().fill(Color.tidexSurfaceSecondary))
  }

  private func selectedShift(metrics: CalendarMetrics) -> ShiftWithComputations? {
    guard selectedDates.count == 1, let dateISO = selectedDates.first else { return nil }
    return metrics.shiftsByDate[dateISO]?.first
  }

  private func selectedEarningsAggregate(metrics: CalendarMetrics) -> (
    net: Double, gross: Double, hasTaxEnabled: Bool
  )? {
    guard !selectedDates.isEmpty else { return nil }

    var net = 0.0
    var gross = 0.0
    var hasTaxEnabled = false

    for dateISO in selectedDates {
      guard let earnings = metrics.earningsByDate[dateISO] ?? selectedEarningsByDate[dateISO]
      else {
        continue
      }

      net += earnings.net
      gross += earnings.gross
      hasTaxEnabled = hasTaxEnabled || earnings.hasTaxEnabled
    }

    return (net: net, gross: gross, hasTaxEnabled: hasTaxEnabled)
  }

  private func syncSelectedEarnings(with metrics: CalendarMetrics) {
    guard !selectedDates.isEmpty else {
      selectedEarningsByDate.removeAll()
      return
    }

    selectedEarningsByDate = selectedEarningsByDate.filter { selectedDates.contains($0.key) }

    for dateISO in selectedDates {
      if let earnings = metrics.earningsByDate[dateISO] {
        selectedEarningsByDate[dateISO] = earnings
      }
    }
  }

  private func clearSelection() {
    selectedDates.removeAll()
    selectedEarningsByDate.removeAll()
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
        iconColor: Self.yourIndicatorColor,
        description: Text(.sharingSuperimposeLegendOnlyYou)
      )
      superimposeLegendRow(
        icon: "person.fill",
        iconColor: Self.friendIndicatorColor,
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
    let isSelected = dayInfo.dateISO.map { selectedDates.contains($0) } ?? false
    let shouldColorJobMetrics =
      metrics.hasMultipleActiveJobs
      && !dayInfo.isOutsideMonth
      && !isSelected
      && !shiftsOnDay.isEmpty
      && dayJobTimeColors != nil
    let isToday = dayInfo.dateISO == metrics.todayISO
    let isHighlighted = isDateHighlighted(dayInfo: dayInfo, shiftsOnDay: shiftsOnDay)

    // Show overlap indicator only when at least one shift interval intersects.
    let friendHasShift = !shiftsOnDay.isEmpty
    let userHasShift = dayInfo.dateISO.flatMap { userHoursByDate?[$0] } != nil
    let userShiftsOnDay = dayInfo.dateISO.flatMap { userShiftsByDate?[$0] } ?? []
    let showOverlap = shiftsOverlap(friendShifts: shiftsOnDay, userShifts: userShiftsOnDay)
    let showOnlyUserIndicator = isSuperimposing && userHasShift && !friendHasShift
    let showOnlyFriendIndicator = isSuperimposing && friendHasShift && !userHasShift
    let showSingleUserIndicator = showOnlyUserIndicator || showOnlyFriendIndicator
    let singleUserIndicatorColor: Color =
      showOnlyFriendIndicator ? Self.friendIndicatorColor : Self.yourIndicatorColor
    let showHiddenFriendMetrics = showOnlyFriendIndicator

    Group {
      if showHiddenFriendMetrics {
        CalendarDayCell(
          dayInfo: dayInfo,
          style: cellStyle(isToday: isToday, isHighlighted: isHighlighted, isSelected: isSelected),
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
          style: cellStyle(isToday: isToday, isHighlighted: isHighlighted, isSelected: isSelected),
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
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      dayAccessibilityLabel(
        dayInfo: dayInfo, friendShifts: shiftsOnDay, userShifts: userShiftsOnDay,
        showOverlap: showOverlap, metrics: metrics)
    )
    .accessibilityAddTraits(
      shiftsOnDay.isEmpty ? [] : isSelected ? [.isButton, .isSelected] : .isButton
    )
    .onTapGesture {
      handleDayTap(dayInfo: dayInfo, metrics: metrics)
    }
    .onLongPressGesture {
      handleDayLongPress(dayInfo: dayInfo, metrics: metrics)
    }
  }

  /// Spoken label for a day cell: date, today, whose shifts it has, their times and earnings.
  private func dayAccessibilityLabel(
    dayInfo: CalendarDayInfo,
    friendShifts: [ShiftWithComputations],
    userShifts: [ShiftRow],
    showOverlap: Bool,
    metrics: CalendarMetrics
  ) -> Text {
    guard let dateISO = dayInfo.dateISO, let date = Date.fromISODateString(dateISO) else {
      return Text(verbatim: "")
    }
    let showsMoney = showEarnings && viewMode == .money
    var parts: [String] = [
      date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(.appLocale))
    ]
    if dateISO == metrics.todayISO {
      parts.append(String(localized: .commonToday))
    }
    if isSuperimposing, userHoursByDate?[dateISO] != nil {
      parts.append(String(localized: .calendarAccessibilityYourShift))
      parts += userShifts.map { shift in
        CalendarGridHelper.shiftTimesAccessibilityText(
          startTime: shift.start_time, endTime: shift.end_time)
      }
      if showsMoney, let earnings = userEarningsByDate?[dateISO] {
        parts.append(CalendarGridHelper.earningsAccessibilityText(earnings))
      }
    }
    if !friendShifts.isEmpty {
      parts.append(String(localized: .calendarAccessibilityFriendShift(friendFirstName)))
      // Superimpose mode hides the friend's times and pay in the cell, so VoiceOver does too.
      if !isSuperimposing {
        parts += friendShifts.map { shift in
          CalendarGridHelper.shiftTimesAccessibilityText(
            startTime: shift.startTime, endTime: shift.endTime)
        }
        if showsMoney, let earnings = metrics.earningsByDate[dateISO] {
          parts.append(CalendarGridHelper.earningsAccessibilityText(earnings))
        }
      }
    }
    if showOverlap {
      parts.append(String(localized: .sharingSuperimposeLegendBoth))
    }
    return Text(verbatim: parts.joined(separator: ", "))
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
    guard !shiftsForDay.isEmpty else { return }

    if showEarnings, !isSuperimposing {
      if selectedDates.contains(dateISO) {
        selectedDates.remove(dateISO)
        selectedEarningsByDate.removeValue(forKey: dateISO)
      } else {
        selectedDates.insert(dateISO)
        if let earnings = metrics.earningsByDate[dateISO] {
          selectedEarningsByDate[dateISO] = earnings
        }
      }
    } else if let firstShift = shiftsForDay.first {
      onShiftTapped?(firstShift)
    }
  }

  private func handleDayLongPress(dayInfo: CalendarDayInfo, metrics: CalendarMetrics) {
    guard !dayInfo.isOutsideMonth, let dateISO = dayInfo.dateISO else { return }
    guard let firstShift = metrics.shiftsByDate[dateISO]?.first else { return }
    onShiftTapped?(firstShift)
  }

  // MARK: - Cell Styling

  private func cellStyle(isToday: Bool, isHighlighted: Bool, isSelected: Bool) -> CalendarCellStyle
  {
    // Priority: highlighted > selected > today > default
    if isHighlighted {
      return CalendarCellStyle(
        backgroundColor: Self.deepLinkHighlightColor.opacity(0.2),
        borderColor: Self.deepLinkHighlightColor,
        borderWidth: 2.5,
        dayNumberColor: .tidexTextPrimary,
        showsTodayBadge: false
      )
    }
    if isSelected {
      return CalendarCellStyle(
        backgroundColor: isToday ? Color.tidexBlue.opacity(0.2) : .tidexSurfacePrimary,
        borderColor: .tidexBlue,
        borderWidth: 2,
        dayNumberColor: .tidexTextPrimary,
        showsTodayBadge: isToday
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
    if effectiveViewMode == .money, let earnings = metrics.earningsByDate[dateISO] {
      if shouldColorJobMetrics, let dayJobTimeColors {
        return .earningsBreakdown(
          earnings,
          color: dayJobTimeColors.topColor,
          beforeTaxColor: dayJobTimeColors.bottomColor.opacity(0.75)
        )
      }
      return .earningsBreakdown(earnings)
    }
    if effectiveViewMode == .hours, let hoursData = metrics.hoursByDate[dateISO] {
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

  private func shiftsOverlap(friendShifts: [ShiftWithComputations], userShifts: [ShiftRow]) -> Bool
  {
    guard !friendShifts.isEmpty, !userShifts.isEmpty else { return false }

    return friendShifts.contains { friendShift in
      let friendInterval = shiftInterval(
        startTime: friendShift.startTime, endTime: friendShift.endTime)
      return userShifts.contains { userShift in
        let userInterval = shiftInterval(
          startTime: userShift.start_time, endTime: userShift.end_time)
        return friendInterval.start < userInterval.end && userInterval.start < friendInterval.end
      }
    }
  }

  private func shiftInterval(startTime: String, endTime: String) -> (start: Int, end: Int) {
    let start = CalendarGridHelper.timeToMinutes(startTime)
    var end = CalendarGridHelper.timeToMinutes(endTime)
    if end <= start {
      end += 24 * 60
    }
    return (start, end)
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
    year: 2_025,
    month: 1,
    currency: "kr",
    showEarnings: true,
    friendFirstName: "Alex"
  )
  .background(Color.tidexBackground)
  // swiftlint:disable:next file_length
}
