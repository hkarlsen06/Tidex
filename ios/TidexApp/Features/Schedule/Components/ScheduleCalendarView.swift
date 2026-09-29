import SwiftUI
import UIKit

// MARK: - Shifts Calendar View

/// Full-featured calendar for the Shifts tab
/// Shows shift times or earnings per day, ISO week numbers, and monthly totals
/// Tap opens a day. Long press then drag selects every day with shifts it passes.
/// While any day is selected, taps toggle days instead of opening them.
struct ShiftsCalendarView: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl type_body_length
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let appearanceManager = AppearanceManager.shared

  let shifts: [ShiftWithComputations]
  let eventCoverageByDate: [String: [EventPresentation]]
  let presentation: ShiftsCalendarPresentation
  let month: Date
  let year: Int
  let monthNumber: Int  // 1-12
  let currency: String
  let showEarnings: Bool
  let jobs: [Job]
  let showsActionBar: Bool

  /// Transition phase for header text animations
  var phase: MonthTransitionPhase?

  // Day tap callback: opens the day, or toggles it in selection mode
  var onDayTapped: ((String, [ShiftWithComputations]) -> Void)?
  var onSwipeLeft: (() -> Void)?
  var onSwipeRight: (() -> Void)?

  // Selection state bindings from ViewModel
  @Binding var selectedDates: Set<String>

  /// Whether delete confirmation is active
  let confirmingDelete: Bool

  /// Whether deletion is in progress
  let isDeleting: Bool

  /// Selected earnings from ViewModel (computed across all months)
  let selectedEarnings: (net: Double, gross: Double)?
  let selectedCurrencyAggregate: JobCurrencyAggregateResolution?

  /// Whether any selected shift has tax enabled
  let selectedHasTaxEnabled: Bool

  // Action callbacks
  var onDelete: (() -> Void)?
  var onConfirmDelete: (() -> Void)?
  var onCancelDelete: (() -> Void)?
  var onCopy: (() -> Void)?
  var onDetails: (() -> Void)?
  var onEdit: (() -> Void)?
  var onMove: (() -> Void)?
  var onClearSelection: (() -> Void)?

  // Long press + drag callback with the full new selection. Nil disables drag selection.
  var onDragSelect: ((Set<String>) -> Void)?

  // Empty day tap callback (for navigating to add shift with date)
  var onEmptyDayTapped: ((_ dateISO: String?) -> Void)?

  // Copy/Move mode state
  let isCopyMode: Bool
  let isMoveMode: Bool
  let isCopying: Bool
  let isMoving: Bool
  let copyTargetDates: Set<String>
  let copyPreviewEarnings: [String: CalendarEarningsData]
  let copyPreviewConflictDates: Set<String>

  // Copy/Move callbacks
  var onCopyToDate: ((String) -> Void)?
  var onFinishCopy: (() -> Void)?
  var onMoveToDate: ((String) -> Void)?
  var onCancelCopyMove: (() -> Void)?

  // Selection mode is on while any day is selected. Taps then toggle days instead of opening them.
  private var isSelectionModeEnabled: Bool {
    !selectedDates.isEmpty
  }

  // Newly added dates for celebration highlighting
  var newlyAddedDates: Set<String> = []

  // Dates to highlight from widget deeplinks or post-add navigation.
  var deepLinkHighlightDates: Set<String>

  // Dates that have shift conflicts (overlapping shifts)
  var conflictDates: Set<String> = []

  // Shift IDs that should be excluded from totals (conflicting shifts)
  var excludedFromTotalIds: Set<String> = []

  @State private var viewMode = CalendarViewMode.load()  // swiftlint:disable:this explicit_type_interface line_length type_contents_order
  @State private var showSingleSelectionDeleteConfirm = false
  @State private var showMultiSelectionDeleteConfirm = false
  @State private var showMixedCurrencyBreakdownPopover = false

  private struct DayJobTimeColors {
    let topColor: Color
    let bottomColor: Color
  }

  // MARK: - Gesture State

  /// Active long press + drag selection
  @State private var dragSelection: CalendarDragSelection?

  // Haptic feedback for UI interactions (non-gesture haptics)
  private let toggleHaptic = UIImpactFeedbackGenerator(style: .light)
  private let warningHaptic = UINotificationFeedbackGenerator()

  private let calendar = Calendar.gregorianCurrent

  init(
    shifts: [ShiftWithComputations],
    eventCoverageByDate: [String: [EventPresentation]] = [:],
    presentation: ShiftsCalendarPresentation = .empty(),
    month: Date,
    year: Int,
    monthNumber: Int,
    currency: String,
    showEarnings: Bool,
    jobs: [Job],
    showsActionBar: Bool = true,
    phase: MonthTransitionPhase? = nil,
    onDayTapped: ((String, [ShiftWithComputations]) -> Void)? = nil,
    onSwipeLeft: (() -> Void)? = nil,
    onSwipeRight: (() -> Void)? = nil,
    selectedDates: Binding<Set<String>>,
    confirmingDelete: Bool,
    isDeleting: Bool,
    selectedEarnings: (net: Double, gross: Double)?,
    selectedCurrencyAggregate: JobCurrencyAggregateResolution?,
    selectedHasTaxEnabled: Bool,
    onDelete: (() -> Void)? = nil,
    onConfirmDelete: (() -> Void)? = nil,
    onCancelDelete: (() -> Void)? = nil,
    onCopy: (() -> Void)? = nil,
    onDetails: (() -> Void)? = nil,
    onEdit: (() -> Void)? = nil,
    onMove: (() -> Void)? = nil,
    onClearSelection: (() -> Void)? = nil,
    onDragSelect: ((Set<String>) -> Void)? = nil,
    onEmptyDayTapped: ((_ dateISO: String?) -> Void)? = nil,
    isCopyMode: Bool,
    isMoveMode: Bool,
    isCopying: Bool,
    isMoving: Bool,
    copyTargetDates: Set<String> = [],
    copyPreviewEarnings: [String: CalendarEarningsData] = [:],
    copyPreviewConflictDates: Set<String> = [],
    onCopyToDate: ((String) -> Void)? = nil,
    onFinishCopy: (() -> Void)? = nil,
    onMoveToDate: ((String) -> Void)? = nil,
    onCancelCopyMove: (() -> Void)? = nil,
    newlyAddedDates: Set<String> = [],
    deepLinkHighlightDates: Set<String> = [],
    conflictDates: Set<String> = [],
    excludedFromTotalIds: Set<String> = []
  ) {
    self.shifts = shifts
    self.eventCoverageByDate = eventCoverageByDate
    self.presentation = presentation
    self.month = month
    self.year = year
    self.monthNumber = monthNumber
    self.currency = currency
    self.showEarnings = showEarnings
    self.jobs = jobs
    self.showsActionBar = showsActionBar
    self.phase = phase
    self.onDayTapped = onDayTapped
    self.onSwipeLeft = onSwipeLeft
    self.onSwipeRight = onSwipeRight
    _selectedDates = selectedDates
    self.confirmingDelete = confirmingDelete
    self.isDeleting = isDeleting
    self.selectedEarnings = selectedEarnings
    self.selectedCurrencyAggregate = selectedCurrencyAggregate
    self.selectedHasTaxEnabled = selectedHasTaxEnabled
    self.onDelete = onDelete
    self.onConfirmDelete = onConfirmDelete
    self.onCancelDelete = onCancelDelete
    self.onCopy = onCopy
    self.onDetails = onDetails
    self.onEdit = onEdit
    self.onMove = onMove
    self.onClearSelection = onClearSelection
    self.onDragSelect = onDragSelect
    self.onEmptyDayTapped = onEmptyDayTapped
    self.isCopyMode = isCopyMode
    self.isMoveMode = isMoveMode
    self.isCopying = isCopying
    self.isMoving = isMoving
    self.copyTargetDates = copyTargetDates
    self.copyPreviewEarnings = copyPreviewEarnings
    self.copyPreviewConflictDates = copyPreviewConflictDates
    self.onCopyToDate = onCopyToDate
    self.onFinishCopy = onFinishCopy
    self.onMoveToDate = onMoveToDate
    self.onCancelCopyMove = onCancelCopyMove
    self.newlyAddedDates = newlyAddedDates
    self.deepLinkHighlightDates = deepLinkHighlightDates
    self.conflictDates = conflictDates
    self.excludedFromTotalIds = excludedFromTotalIds
  }

  // MARK: - Computed Data

  /// Earnings by ISO date string (excludes conflicting shifts)
  private var earningsByDate: [String: CalendarEarningsData] {
    presentation.earningsByDate
  }

  /// Hours by ISO date string
  private var hoursByDate: [String: HoursData] {
    presentation.hoursByDate
  }

  /// Shifts grouped by ISO date string
  private var shiftsByDate: [String: [ShiftWithComputations]] {
    presentation.shiftsByDate
  }

  private var jobsById: [String: Job] {
    presentation.jobsById
  }

  private var defaultJobId: String? {
    presentation.defaultJobId
  }

  private var hasMultipleActiveJobs: Bool {
    presentation.hasMultipleActiveJobs
  }

  private var shouldUseWorkplaceCalendarColors: Bool {
    appearanceManager.calendarContentColorStyle.usesWorkplaceColors
  }

  private var dayJobTimeColorsByDate: [String: DayJobTimeColors] {
    guard shouldUseWorkplaceCalendarColors, hasMultipleActiveJobs else {
      return [:]
    }

    var result: [String: DayJobTimeColors] = [:]

    for (dateISO, shiftsOnDay) in shiftsByDate where !shiftsOnDay.isEmpty {
      let sortedShifts = shiftsOnDay.sorted { lhs, rhs in
        CalendarGridHelper.timeToMinutes(lhs.startTime)
          < CalendarGridHelper.timeToMinutes(rhs.startTime)
      }

      guard let earliestShift = sortedShifts.first else {
        continue
      }
      guard let topColor = resolvedJobColor(for: earliestShift) else {
        continue
      }

      // For days with multiple shifts, always use the earliest shift's workplace color.
      result[dateISO] = DayJobTimeColors(topColor: topColor, bottomColor: topColor)
    }

    return result
  }

  private var multiDeleteConfirmTitle: String {
    String(localized: .shiftsMultiDeleteConfirmTitle(deleteTargetCount))
  }

  private var multiDeleteConfirmMessage: String {
    deleteConfirmMessage
  }

  private var singleDeleteConfirmTitle: String {
    deleteTargetCount == 1
      ? String(localized: .shiftsDeleteConfirmTitle)
      : String(localized: .shiftsMultiDeleteConfirmTitle(deleteTargetCount))
  }

  private var singleDeleteConfirmMessage: String {
    deleteConfirmMessage
  }

  private var deleteConfirmMessage: String {
    let count = deleteTargetCount
    let message =
      count == 1
      ? String(localized: .shiftsDeleteConfirmMessage)
      : String(localized: .shiftsDeleteConfirmPluralMessage(count))
    guard selectionIncludesRecurringShift else { return message }
    return message + " " + String(localized: .shiftsDeleteConfirmRecurringNote)
  }

  /// Recurring shifts in a selection are only removed on the selected dates.
  private var selectionIncludesRecurringShift: Bool {
    shifts.contains { selectedDates.contains($0.shiftDate) && $0.shift.recurring_id != nil }
  }

  private var deleteTargetCount: Int {
    let selectedShiftCount = shifts.filter { selectedDates.contains($0.shiftDate) }.count
    return max(selectedShiftCount, selectedDates.count)
  }

  // MARK: - Body

  var body: some View {
    VStack(spacing: 0) {
      CalendarHeaderRow(
        totals: headerTotals,
        selectionCount: selectedDates.count >= 2 ? selectedDates.count : nil,
        secondaryStyle: headerSecondaryStyle,
        secondaryCurrency: selectedDates.isEmpty ? nil : selectedCurrencyAggregate?.primary.currency
      )
      .userCurrency(headerDisplayCurrency)
      .contentShape(Rectangle())
      .onTapGesture {
        guard canShowMixedCurrencyBreakdown else {
          return
        }
        toggleHaptic.impactOccurred()
        showMixedCurrencyBreakdownPopover.toggle()
      }
      .popover(isPresented: $showMixedCurrencyBreakdownPopover) {
        MixedCurrencyBreakdownPopover(entries: activeCurrencyAggregate?.secondary ?? [])
          .presentationCompactAdaptation(.popover)
      }

      CalendarWeekdayHeader()
        .padding(.bottom, Spacing.xs)

      calendarGrid

      if showsActionBar {
        actionBar
          .padding(.top, Spacing.sm)
      }
    }
    .onChange(of: selectedDates) { _, _ in
      showMixedCurrencyBreakdownPopover = false
    }
  }

  // MARK: - Header Data

  private var headerTotals: CalendarHeaderTotals? {
    guard showEarnings else {
      return nil
    }

    if isCopyMode, !copyPreviewEarnings.isEmpty {
      return copyPreviewHeaderTotals
    }

    // The month total stays on the leading side. While dates are selected, the trailing side
    // shows the selection total instead of the month's before-tax amount.
    let aggregate = monthlyCurrencyAggregate
    let primaryAmount = aggregate.primary.displayAmount > 0 ? aggregate.primary.displayAmount : nil
    let secondaryAmount: Double?

    if selectedDates.isEmpty {
      secondaryAmount =
        (!aggregate.hasMixedCurrency && aggregate.primary.hasTaxEnabled
          && aggregate.primary.grossAmount > 0
          && aggregate.primary.grossAmount != aggregate.primary.displayAmount)
        ? aggregate.primary.grossAmount : nil
    } else {
      secondaryAmount = selectionTotal
    }

    return CalendarHeaderTotals(
      primary: primaryAmount,
      secondary: secondaryAmount
    )
  }

  /// Selection total after tax when tax is on, otherwise before tax.
  private var selectionTotal: Double? {
    let amount: Double
    if let aggregate = selectedCurrencyAggregate {
      amount = aggregate.primary.displayAmount
    } else if let earnings = selectedEarnings {
      amount = selectedHasTaxEnabled ? earnings.net : earnings.gross
    } else {
      return nil
    }
    return amount > 0 ? amount : nil
  }

  private var copyPreviewHeaderTotals: CalendarHeaderTotals? {
    let existingByDate = earningsByDate.filter { dateISO, _ in
      isDateInDisplayedMonth(dateISO)
    }
    let previewByDate = copyPreviewEarnings.filter { dateISO, _ in
      isDateInDisplayedMonth(dateISO)
    }
    guard !previewByDate.isEmpty else {
      return nil
    }

    let totals = ConflictExclusion.combinedEarnings(
      existingByDate: existingByDate,
      previewByDate: previewByDate,
      conflictDates: copyPreviewConflictDates
    )
    guard totals.gross > 0 else {
      return nil
    }

    let baselineTotals = ConflictExclusion.combinedEarnings(
      existingByDate: existingByDate,
      previewByDate: [:],
      conflictDates: []
    )

    let primaryAmount = totals.hasTaxEnabled ? totals.net : totals.gross
    let baselinePrimary =
      baselineTotals.hasTaxEnabled ? baselineTotals.net : baselineTotals.gross
    let delta = max(primaryAmount - baselinePrimary, 0)

    return CalendarHeaderTotals(
      primary: primaryAmount,
      secondary: delta > 0 ? delta : nil,
      primaryIsAfterTax: totals.hasTaxEnabled
    )
  }

  private var headerSecondaryStyle: CalendarHeaderSecondaryStyle {
    if isCopyMode && !copyPreviewEarnings.isEmpty {
      return .delta
    }
    return selectedDates.isEmpty ? .detail : .selection
  }

  private func isDateInDisplayedMonth(_ dateISO: String) -> Bool {
    guard let date = Date.fromISODateString(dateISO) else {
      return false
    }
    let components = calendar.dateComponents([.year, .month], from: date)
    return components.year == year && components.month == monthNumber
  }

  private var monthlyCurrencyAggregate: JobCurrencyAggregateResolution {
    presentation.monthlyCurrencyAggregate
  }

  private var canShowMixedCurrencyBreakdown: Bool {
    showEarnings
      && activeCurrencyAggregate?.hasMixedCurrency == true
      && !(activeCurrencyAggregate?.secondary.isEmpty ?? true)
  }

  private var headerDisplayCurrency: String {
    monthlyCurrencyAggregate.primary.currency
  }

  private var activeCurrencyAggregate: JobCurrencyAggregateResolution? {
    if selectedDates.isEmpty {
      return monthlyCurrencyAggregate
    }
    return selectedCurrencyAggregate
  }

  // MARK: - Calendar Grid

  @ViewBuilder
  private var calendarGrid: some View {
    let days = CalendarGridHelper.daysInMonth(year: year, month: monthNumber)
    let shiftsByDate = self.shiftsByDate
    let earningsByDate = self.earningsByDate
    let hoursByDate = self.hoursByDate
    let dayJobTimeColorsByDate = self.dayJobTimeColorsByDate
    let currentTodayISO = todayISO()

    CalendarMonthGrid(days: days, monthTransitionPhase: phase) { dayInfo in
      calendarDayCell(
        dayInfo,
        lookups: CalendarDayLookups(
          shiftsByDate: shiftsByDate,
          earningsByDate: earningsByDate,
          hoursByDate: hoursByDate,
          dayJobTimeColorsByDate: dayJobTimeColorsByDate,
          todayISO: currentTodayISO
        )
      )
    }
    .coordinateSpace(name: "calendar")
    .overlay {
      GeometryReader { geometry in
        CalendarDragSelectOverlay(
          onTap: { location in
            Haptics.play(.selection)
            handleTap(at: location, geometry: geometry, days: days)
          },
          onDragSelect: onDragSelect == nil
            ? nil
            : { state, location in
              handleDragSelect(state, at: location, geometry: geometry, days: days)
            },
          onSwipeLeft: onSwipeLeft,
          onSwipeRight: onSwipeRight
        )
      }
    }
  }

  private struct CalendarDayLookups {
    let shiftsByDate: [String: [ShiftWithComputations]]
    let earningsByDate: [String: CalendarEarningsData]
    let hoursByDate: [String: HoursData]
    let dayJobTimeColorsByDate: [String: DayJobTimeColors]
    let todayISO: String
  }

  private struct CalendarDayState {
    let isToday: Bool
    let isSelected: Bool
    let isNewlyAdded: Bool
    let isDeepLinkHighlighted: Bool
    let hasConflict: Bool
  }

  private func dayState(for dateISO: String?, todayISO: String) -> CalendarDayState {
    CalendarDayState(
      isToday: dateISO == todayISO,
      isSelected: dateISO.map { selectedDates.contains($0) || copyTargetDates.contains($0) }
        ?? false,
      isNewlyAdded: dateISO.map { newlyAddedDates.contains($0) } ?? false,
      isDeepLinkHighlighted: dateISO.map { deepLinkHighlightDates.contains($0) } ?? false,
      hasConflict: dateISO.map {
        conflictDates.contains($0) || copyPreviewConflictDates.contains($0)
      } ?? false
    )
  }

  private func usesJobMetricColors(
    for dayInfo: CalendarDayInfo,
    state: CalendarDayState,
    hasShifts: Bool,
    hasJobColors: Bool
  ) -> Bool {
    shouldUseWorkplaceCalendarColors
      && hasMultipleActiveJobs
      && !dayInfo.isOutsideMonth
      && !state.isSelected
      && !state.isNewlyAdded
      && !state.isDeepLinkHighlighted
      && hasShifts
      && hasJobColors
  }

  @ViewBuilder
  private func calendarDayCell(_ dayInfo: CalendarDayInfo, lookups: CalendarDayLookups) -> some View
  {
    let shiftsOnDay = dayInfo.dateISO.flatMap { lookups.shiftsByDate[$0] } ?? []
    let eventsOnDay = dayInfo.dateISO.flatMap { eventCoverageByDate[$0] } ?? []
    let state = dayState(for: dayInfo.dateISO, todayISO: lookups.todayISO)
    let dayJobTimeColors = dayInfo.dateISO.flatMap { lookups.dayJobTimeColorsByDate[$0] }
    let shouldColorJobMetrics = usesJobMetricColors(
      for: dayInfo, state: state, hasShifts: !shiftsOnDay.isEmpty,
      hasJobColors: dayJobTimeColors != nil)

    CalendarDayCell(
      dayInfo: dayInfo,
      style: cellStyle(
        isToday: state.isToday,
        isSelected: state.isSelected,
        isNewlyAdded: state.isNewlyAdded,
        isDeepLinkHighlighted: state.isDeepLinkHighlighted,
        hasConflict: state.hasConflict
      ),
      content: cellContent(
        for: dayInfo,
        dayJobTimeColors: dayJobTimeColors,
        shouldColorJobMetrics: shouldColorJobMetrics,
        earningsByDate: lookups.earningsByDate,
        hoursByDate: lookups.hoursByDate
      ),
      eventIndicatorCount: eventsOnDay.count
    )
    // VoiceOver activation taps the cell center, which the coordinate tap overlay handles
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      dayAccessibilityLabel(
        dateISO: dayInfo.dateISO,
        isToday: state.isToday,
        shiftsOnDay: shiftsOnDay,
        earnings: dayInfo.dateISO.flatMap { lookups.earningsByDate[$0] },
        eventCount: eventsOnDay.count
      )
    )
    .accessibilityAddTraits(state.isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityHidden(dayInfo.dateISO == nil)
  }

  private func dayAccessibilityLabel(
    dateISO: String?,
    isToday: Bool,
    shiftsOnDay: [ShiftWithComputations],
    earnings: CalendarEarningsData?,
    eventCount: Int
  ) -> Text {
    guard let date = dateISO.flatMap({ Date.fromISODateString($0) }) else {
      return Text(verbatim: "")
    }
    var parts: [String] = [
      date.formatted(
        .dateTime.weekday(.wide).day().month(.wide).locale(.appLocale).calendar(.gregorian))
    ]
    if isToday {
      parts.append(String(localized: .commonToday))
    }
    if !shiftsOnDay.isEmpty {
      parts.append(String(localized: .commonShiftCount(shiftsOnDay.count)))
      let sortedShifts = shiftsOnDay.sorted {
        CalendarGridHelper.timeToMinutes($0.startTime)
          < CalendarGridHelper.timeToMinutes($1.startTime)
      }
      parts += sortedShifts.map {
        CalendarGridHelper.shiftTimesAccessibilityText(startTime: $0.startTime, endTime: $0.endTime)
      }
      if let earnings {
        parts.append(CalendarGridHelper.earningsAccessibilityText(earnings))
      }
    }
    if eventCount > 0 {
      parts.append(String(localized: .calendarAccessibilityEventCount(eventCount)))
    }
    return Text(verbatim: parts.joined(separator: ", "))
  }

  // MARK: - Cell Styling

  /// Celebration green color for newly added shifts
  private static let celebrationColor = Color.tidexSuccess

  /// Purple/violet color for deep link highlight from widgets
  private static let deepLinkHighlightColor = Color.tidexPurple

  private static func highlightStyle(color: Color) -> CalendarCellStyle {
    CalendarCellStyle(
      backgroundColor: color.opacity(0.2),
      borderColor: color,
      borderWidth: 2.5,
      dayNumberColor: .tidexTextPrimary,
      showsTodayBadge: false
    )
  }

  private func cellStyle(
    isToday: Bool,
    isSelected: Bool,
    isNewlyAdded: Bool,
    isDeepLinkHighlighted: Bool,
    hasConflict: Bool
  ) -> CalendarCellStyle {
    // Priority order: deep link > newly added > selected/drag > conflict > today > default
    if isDeepLinkHighlighted {
      return Self.highlightStyle(color: Self.deepLinkHighlightColor)
    }
    if isNewlyAdded {
      return Self.highlightStyle(color: Self.celebrationColor)
    }
    if isSelected {
      let color: Color = hasConflict ? .tidexWarning : .tidexBlue
      return CalendarCellStyle(
        backgroundColor: isToday ? color.opacity(0.2) : .tidexSurfacePrimary,
        borderColor: color,
        borderWidth: 2,
        dayNumberColor: hasConflict ? .tidexWarning : .tidexTextPrimary,
        showsTodayBadge: isToday
      )
    }
    if hasConflict {
      return CalendarCellStyle(
        backgroundColor: Color.tidexWarning.opacity(0.15),
        borderColor: .clear,
        borderWidth: 0,
        dayNumberColor: .tidexTextPrimary,
        showsTodayBadge: false
      )
    }
    if isToday {
      return .today()
    }
    return .default
  }

  private func cellContent(
    for dayInfo: CalendarDayInfo,
    dayJobTimeColors: DayJobTimeColors?,
    shouldColorJobMetrics: Bool,
    earningsByDate: [String: CalendarEarningsData],
    hoursByDate: [String: HoursData]
  ) -> CalendarCellContent {
    guard let dateISO = dayInfo.dateISO else {
      return .empty
    }

    if isCopyMode, copyTargetDates.contains(dateISO) {
      if let earnings = copyPreviewEarnings[dateISO] {
        return .earningsBreakdown(
          earnings,
          color: copyPreviewConflictDates.contains(dateISO) ? .tidexWarning : .tidexBlue,
          beforeTaxColor: .tidexTextMuted
        )
      }
      return .custom
    }

    let effectiveViewMode = showEarnings ? viewMode : .hours

    if effectiveViewMode == .money, let earnings = earningsByDate[dateISO] {
      if shouldColorJobMetrics, let dayJobTimeColors {
        return .earningsBreakdown(
          earnings,
          color: dayJobTimeColors.topColor,
          beforeTaxColor: dayJobTimeColors.bottomColor.opacity(0.75)
        )
      }
      return .earningsBreakdown(earnings)
    }
    if effectiveViewMode == .hours, let hoursData = hoursByDate[dateISO] {
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

  // MARK: - Gesture Handling

  private func handleTap(at location: CGPoint, geometry: GeometryProxy, days: [CalendarDayInfo]) {
    guard
      let dayISO = CalendarDragSelection.dateISO(
        at: location, gridSize: geometry.size, days: days)
    else {
      if isCopyMode || isMoveMode {
        onCancelCopyMove?()
      } else {
        onEmptyDayTapped?(nil)
      }
      return
    }

    if isCopyMode {
      onCopyToDate?(dayISO)
      return
    }

    if isMoveMode {
      onMoveToDate?(dayISO)
      return
    }

    let shiftsOnDay = shiftsByDate[dayISO] ?? []
    let eventsOnDay = eventCoverageByDate[dayISO] ?? []

    if isSelectionModeEnabled {
      guard !shiftsOnDay.isEmpty else {
        return
      }
      onDayTapped?(dayISO, shiftsOnDay)
      return
    }

    if shiftsOnDay.isEmpty, eventsOnDay.isEmpty {
      onEmptyDayTapped?(dayISO)
    } else {
      onDayTapped?(dayISO, shiftsOnDay)
    }
  }

  private func handleDragSelect(
    _ state: UIGestureRecognizer.State, at location: CGPoint, geometry: GeometryProxy,
    days: [CalendarDayInfo]
  ) {
    guard !isCopyMode, !isMoveMode,
      let selection = CalendarDragSelection.update(
        &dragSelection, state: state,
        dateISO: CalendarDragSelection.dateISO(at: location, gridSize: geometry.size, days: days),
        days: days, current: selectedDates, isEligible: { shiftsByDate[$0]?.isEmpty == false })
    else { return }
    Haptics.play(.selection)
    onDragSelect?(selection)
  }

  // MARK: - Action Bar

  @ViewBuilder
  private var actionBar: some View {
    HStack(spacing: 0) {
      if isCopyMode || isMoveMode {
        copyMoveBar
      } else if selectedDates.isEmpty {
        CalendarViewModeToggle(
          viewMode: $viewMode,
          currency: currency,
          showMoneyOption: showEarnings
        )
      } else if selectedDates.count == 1 {
        singleSelectionBar
      } else {
        multiSelectionBar
      }
    }
    .animation(
      reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: selectedDates.count
    )
    .animation(
      reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: confirmingDelete
    )
    .animation(
      reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: isCopyMode
    )
    .animation(
      reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: isMoveMode
    )
    .onAppear {
      toggleHaptic.prepare()
      warningHaptic.prepare()
    }
    .alert(
      singleDeleteConfirmTitle,
      isPresented: $showSingleSelectionDeleteConfirm
    ) {
      Button(String(localized: .commonCancel), role: .cancel) {
        // The cancel role dismisses the alert automatically.
      }
      Button(String(localized: .shiftsDeleteButton), role: .destructive) {
        warningHaptic.notificationOccurred(.warning)
        onConfirmDelete?()
      }
    } message: {
      Text(singleDeleteConfirmMessage)
    }
    .alert(multiDeleteConfirmTitle, isPresented: $showMultiSelectionDeleteConfirm) {
      Button(String(localized: .commonCancel), role: .cancel) {
        // The cancel role dismisses the alert automatically.
      }
      Button(String(localized: .shiftsDeleteButton), role: .destructive) {
        warningHaptic.notificationOccurred(.warning)
        onConfirmDelete?()
      }
    } message: {
      Text(multiDeleteConfirmMessage)
    }
  }

  @ViewBuilder
  private var copyMoveBar: some View {
    HStack(spacing: Spacing.xxs) {
      copyMoveStatus

      Button {
        toggleHaptic.impactOccurred()
        onCancelCopyMove?()
      } label: {
        Text(.commonCancel)
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextPrimary)
          .padding(.horizontal, Spacing.md)
          .frame(height: 44)
          .background(
            Capsule().fill(.clear)
              .tidexGlass(shape: .capsule, interactive: true)
          )
      }
      .buttonStyle(.plain)
      .disabled(isCopying || isMoving)

      if isCopyMode {
        finishCopyButton
      }
    }
    .padding(Spacing.xxs)
    .background(Capsule().fill(Color.tidexSurfaceSecondary))
  }

  @ViewBuilder
  private var copyMoveStatus: some View {
    if isCopying || isMoving {
      ProgressView()
        .progressViewStyle(
          CircularProgressViewStyle(tint: isCopyMode ? .tidexBlue : .tidexWarning)
        )
        .scaleEffect(0.8)
        .frame(width: 36)

      Text(
        isCopyMode
          ? String(localized: .shiftsCopying)
          : String(localized: .shiftsMoving)
      )
      .font(.tidexLabel)
      .foregroundColor(.tidexTextSecondary)
      .frame(maxWidth: .infinity)
    } else {
      Image(systemName: isCopyMode ? "doc.on.doc" : "arrow.left.arrow.right")
        .font(.tidexLabel)
        .foregroundColor(isCopyMode ? .tidexTextSecondary : .tidexWarning)
        .frame(width: 36)

      Text(
        isCopyMode
          ? String(localized: .shiftsChooseDates)
          : String(localized: .shiftsSelectMoveTarget)
      )
      .font(.tidexLabel)
      .foregroundColor(.tidexTextSecondary)
      .frame(maxWidth: .infinity)
    }
  }

  private var finishCopyButton: some View {
    Button {
      toggleHaptic.impactOccurred()
      onFinishCopy?()
    } label: {
      Text(.commonCopy)
        .font(.tidexLabelStrong)
        .foregroundColor(copyTargetDates.isEmpty ? .tidexTextMuted : .tidexTextOnBrand)
        .padding(.horizontal, Spacing.md)
        .frame(height: 44)
        .background(
          Capsule()
            .fill(copyTargetDates.isEmpty ? Color.clear : Color.tidexBrandPrimary)
            .tidexGlass(shape: .capsule, interactive: !copyTargetDates.isEmpty)
        )
    }
    .buttonStyle(.plain)
    .disabled(isCopying || copyTargetDates.isEmpty)
  }

  @ViewBuilder
  private var singleSelectionBar: some View {
    HStack(spacing: Spacing.xxs) {
      singleSelectionButton(
        systemImage: "pencil",
        label: .shiftsActionsEdit,
        tint: .tidexTextPrimary
      ) {
        onEdit?()
      }

      singleSelectionButton(
        systemImage: "doc.on.doc",
        label: .commonCopy,
        tint: .tidexBlue
      ) {
        onCopy?()
      }

      singleSelectionButton(
        systemImage: "arrow.left.arrow.right",
        label: .shiftsMove,
        tint: .tidexWarning
      ) {
        onMove?()
      }

      singleSelectionButton(
        systemImage: "info.circle",
        label: .shiftsDetails,
        tint: .tidexTextMuted
      ) {
        onDetails?()
      }

      singleSelectionDeleteButton
    }
    .padding(Spacing.xxs)
    .background(Capsule().fill(Color.tidexSurfaceSecondary))
  }

  private var singleSelectionDeleteButton: some View {
    Button {
      toggleHaptic.impactOccurred()
      showSingleSelectionDeleteConfirm = true
    } label: {
      Group {
        if isDeleting {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .tidexError))
            .scaleEffect(0.7)
        } else {
          Image(systemName: "trash")
            .font(.tidexLabel)
        }
      }
      .foregroundColor(.tidexError)
      .frame(maxWidth: .infinity)
      .frame(height: 44)
      .background(
        Capsule().fill(.clear)
          .tidexGlass(shape: .capsule, tint: .tidexError.opacity(0.15), interactive: true)
      )
    }
    .buttonStyle(.plain)
    .disabled(isDeleting)
    .accessibilityLabel(Text(.shiftsActionsDelete))
  }

  private func singleSelectionButton(
    systemImage: String,
    label: LocalizedStringResource,
    tint: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button {
      toggleHaptic.impactOccurred()
      action()
    } label: {
      Image(systemName: systemImage)
        .font(.tidexLabel)
        .foregroundColor(tint)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
          Capsule().fill(.clear)
            .tidexGlass(shape: .capsule, interactive: true)
        )
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(label))
  }

  @ViewBuilder
  private var multiSelectionBar: some View {
    HStack(spacing: Spacing.xxs) {
      Button {
        toggleHaptic.impactOccurred()
        showMultiSelectionDeleteConfirm = true
      } label: {
        HStack(spacing: Spacing.xxxs) {
          if isDeleting {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .tidexError))
              .scaleEffect(0.7)
          } else {
            Image(systemName: "trash")
              .font(.tidexLabel)
          }
          Text(.shiftsActionsDelete)
            .font(.tidexLabelStrong)
        }
        .foregroundColor(.tidexError)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
          Capsule().fill(.clear)
            .tidexGlass(shape: .capsule, tint: .tidexError.opacity(0.15), interactive: true)
        )
      }
      .buttonStyle(.plain)
      .disabled(isDeleting)

      Button {
        toggleHaptic.impactOccurred()
        onClearSelection?()
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
      .disabled(isDeleting)
    }
    .padding(Spacing.xxs)
    .background(Capsule().fill(Color.tidexSurfaceSecondary))
  }

  @ViewBuilder
  private var deleteButton: some View {
    Button {
      if confirmingDelete {
        warningHaptic.notificationOccurred(.warning)
        onConfirmDelete?()
      } else {
        toggleHaptic.impactOccurred()
        onDelete?()
      }
    } label: {
      HStack(spacing: Spacing.xxxs) {
        if isDeleting {
          ProgressView()
            .progressViewStyle(
              CircularProgressViewStyle(tint: confirmingDelete ? .white : .tidexError)
            )
            .scaleEffect(0.7)
        } else {
          Image(systemName: "trash")
            .font(.tidexLabel)
        }

        if confirmingDelete {
          Text(.shiftsConfirm)
            .font(.tidexLabelStrong)
        }
      }
      .foregroundColor(confirmingDelete ? .white : .tidexError)
      .frame(width: confirmingDelete ? nil : 44, height: 44)
      .frame(maxWidth: confirmingDelete ? .infinity : nil)
      .padding(.horizontal, confirmingDelete ? 16 : 0)
      .background(
        Capsule().fill(confirmingDelete ? Color.tidexError : Color.tidexError.opacity(0.1))
      )
    }
    .buttonStyle(.plain)
    .disabled(isDeleting)
    .accessibilityLabel(Text(.commonDelete))
  }

  @ViewBuilder
  private var cancelButton: some View {
    Button {
      toggleHaptic.impactOccurred()
      onCancelDelete?()
    } label: {
      HStack(spacing: Spacing.xxxs) {
        Image(systemName: "xmark")
          .font(.tidexLabel)
        Text(.commonCancel)
          .font(.tidexLabelStrong)
      }
      .foregroundColor(.tidexTextOnBrand)
      .frame(maxWidth: .infinity)
      .frame(height: 44)
      .background(Capsule().fill(Color.tidexBrandPrimary))
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Preview

#Preview {
  struct PreviewWrapper: View {
    @State private var selectedDates: Set<String> = []

    var body: some View {
      ScrollView {
        ShiftsCalendarView(
          shifts: [],
          month: Date(),
          year: 2_025,
          monthNumber: 1,
          currency: "kr",
          showEarnings: true,
          jobs: [],
          selectedDates: $selectedDates,
          confirmingDelete: false,
          isDeleting: false,
          selectedEarnings: nil,
          selectedCurrencyAggregate: nil,
          selectedHasTaxEnabled: false,
          isCopyMode: false,
          isMoveMode: false,
          isCopying: false,
          isMoving: false,
          newlyAddedDates: []
        )
        .padding()
      }
      .background(Color.tidexBackground)
    }
  }

  return PreviewWrapper()
}  // swiftlint:disable:this file_length
