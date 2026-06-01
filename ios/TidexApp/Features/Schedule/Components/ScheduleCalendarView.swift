import SwiftUI
import UIKit

// MARK: - Gesture State Machine

/// The current mode of the gesture state machine
private enum GestureMode: Equatable {
  /// No touch active
  case idle
  /// Long-press activated, actively selecting date range
  case selecting
}

private enum SingleSelectionActionMode: Equatable {
  case primary
  case copyMoveChoices
}

// MARK: - Shifts Calendar View

/// Full-featured calendar for the Shifts tab
/// Shows shift times or earnings per day, ISO week numbers, and monthly totals
/// Supports multi-date selection via long-press + drag
struct ShiftsCalendarView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ObservedObject private var appearanceManager = AppearanceManager.shared

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

  // Day tap callback (single tap for selection toggle)
  var onDayTapped: ((String, [ShiftWithComputations]) -> Void)?
  // Day long-press callback (normal mode details/picker presentation)
  var onDayLongPressed: ((String, [ShiftWithComputations]) -> Void)?
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

  // Range selection callback (for long-press + drag)
  var onSelectDateRange: (([String]) -> Void)?

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

  // Selection mode toggle - when enabled, taps/long-press work; when disabled, swipes work
  @Binding var isSelectionModeEnabled: Bool

  // Newly added dates for celebration highlighting
  var newlyAddedDates: Set<String> = []

  // Dates to highlight from widget deeplinks or post-add navigation.
  var deepLinkHighlightDates: Set<String>

  // Dates that have shift conflicts (overlapping shifts)
  var conflictDates: Set<String> = []

  // Shift IDs that should be excluded from totals (conflicting shifts)
  var excludedFromTotalIds: Set<String> = []

  @State private var viewMode: CalendarViewMode = CalendarViewMode.load()
  @State private var singleSelectionActionMode: SingleSelectionActionMode = .primary
  @State private var showSingleSelectionDeleteConfirm = false
  @State private var showMultiSelectionDeleteConfirm = false
  @State private var showMixedCurrencyBreakdownPopover = false

  private struct DayJobTimeColors {
    let topColor: Color
    let bottomColor: Color
  }

  // MARK: - Gesture State

  /// Current gesture state
  @State private var gestureMode: GestureMode = .idle

  /// ISO date where long-press started (anchor for range)
  @State private var anchorDateISO: String?

  /// Current hover date during drag
  @State private var hoverDateISO: String?

  /// Preview dates during drag (before committing)
  @State private var dragPreviewDates: Set<String> = []

  // Haptic feedback for UI interactions (non-gesture haptics)
  private let toggleHaptic = UIImpactFeedbackGenerator(style: .light)
  private let warningHaptic = UINotificationFeedbackGenerator()

  private let calendar = Calendar.current

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
    onDayLongPressed: ((String, [ShiftWithComputations]) -> Void)? = nil,
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
    onSelectDateRange: (([String]) -> Void)? = nil,
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
    isSelectionModeEnabled: Binding<Bool>,
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
    self.onDayLongPressed = onDayLongPressed
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
    self.onSelectDateRange = onSelectDateRange
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
    _isSelectionModeEnabled = isSelectionModeEnabled
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

  /// Monthly totals (net and gross, excludes conflicting shifts)
  private var monthlyTotals: (net: Double, gross: Double) {
    (net: presentation.monthlyTotals.net, gross: presentation.monthlyTotals.gross)
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
    guard shouldUseWorkplaceCalendarColors, hasMultipleActiveJobs else { return [:] }

    var result: [String: DayJobTimeColors] = [:]

    for (dateISO, shiftsOnDay) in shiftsByDate where !shiftsOnDay.isEmpty {
      let sortedShifts = shiftsOnDay.sorted { lhs, rhs in
        CalendarGridHelper.timeToMinutes(lhs.startTime)
          < CalendarGridHelper.timeToMinutes(rhs.startTime)
      }

      guard let earliestShift = sortedShifts.first else { continue }
      guard let topColor = resolvedJobColor(for: earliestShift) else { continue }

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
    if count == 1 {
      return String(localized: .shiftsDeleteConfirmMessage)
    }
    return String(localized: .shiftsDeleteConfirmPluralMessage(count))
  }

  private var deleteTargetCount: Int {
    let selectedShiftCount = shifts.filter { selectedDates.contains($0.shiftDate) }.count
    return max(selectedShiftCount, selectedDates.count)
  }

  // MARK: - Body

  var body: some View {
    VStack(spacing: 0) {
      CalendarHeaderRow(
        monthName: monthName,
        year: year,
        selectionCount: selectedDates.count >= 2 ? selectedDates.count : nil,
        phase: phase,
        totals: headerTotals,
        trailingAccessory: nil,
        secondaryStyle: headerSecondaryStyle
      )
      .userCurrency(headerDisplayCurrency)
      .contentShape(Rectangle())
      .onTapGesture {
        guard canShowMixedCurrencyBreakdown else { return }
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
    guard showEarnings else { return nil }

    if isCopyMode, !copyPreviewEarnings.isEmpty {
      return copyPreviewHeaderTotals
    }

    let primaryAmount: Double?
    let secondaryAmount: Double?

    if selectedDates.isEmpty {
      let aggregate = monthlyCurrencyAggregate
      primaryAmount = aggregate.primary.displayAmount > 0 ? aggregate.primary.displayAmount : nil
      secondaryAmount =
        (!aggregate.hasMixedCurrency && aggregate.primary.hasTaxEnabled
          && aggregate.primary.grossAmount > 0
          && aggregate.primary.grossAmount != aggregate.primary.displayAmount)
        ? aggregate.primary.grossAmount : nil
    } else if let aggregate = selectedCurrencyAggregate {
      primaryAmount = aggregate.primary.displayAmount > 0 ? aggregate.primary.displayAmount : nil
      secondaryAmount =
        (!aggregate.hasMixedCurrency && aggregate.primary.hasTaxEnabled
          && aggregate.primary.grossAmount > 0
          && aggregate.primary.grossAmount != aggregate.primary.displayAmount)
        ? aggregate.primary.grossAmount : nil
    } else {
      let displayTotals = selectedEarnings ?? monthlyTotals
      let showTax = selectedHasTaxEnabled
      primaryAmount =
        displayTotals.gross > 0 ? (showTax ? displayTotals.net : displayTotals.gross) : nil
      secondaryAmount = (showTax && displayTotals.gross > 0) ? displayTotals.gross : nil
    }

    return CalendarHeaderTotals(
      primary: primaryAmount,
      secondary: secondaryAmount
    )
  }

  private var copyPreviewHeaderTotals: CalendarHeaderTotals? {
    let existingByDate = earningsByDate.filter { dateISO, _ in
      isDateInDisplayedMonth(dateISO)
    }
    let previewByDate = copyPreviewEarnings.filter { dateISO, _ in
      isDateInDisplayedMonth(dateISO)
    }
    guard !previewByDate.isEmpty else { return nil }

    let totals = ConflictExclusion.combinedEarnings(
      existingByDate: existingByDate,
      previewByDate: previewByDate,
      conflictDates: copyPreviewConflictDates
    )
    guard totals.gross > 0 else { return nil }

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
      secondary: delta > 0 ? delta : nil
    )
  }

  private var headerSecondaryStyle: CalendarHeaderSecondaryStyle {
    isCopyMode && !copyPreviewEarnings.isEmpty ? .delta : .detail
  }

  private func isDateInDisplayedMonth(_ dateISO: String) -> Bool {
    guard let date = Date.fromISODateString(dateISO) else { return false }
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
    activeCurrencyAggregate?.primary.currency ?? currency
  }

  private var activeCurrencyAggregate: JobCurrencyAggregateResolution? {
    if selectedDates.isEmpty {
      return monthlyCurrencyAggregate
    }
    return selectedCurrencyAggregate
  }

  // MARK: - Month Name

  private var monthName: String {
    CalendarGridHelper.monthName(
      from: month,
      locale: Locale.appLocale
    )
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
      let shiftsOnDay = dayInfo.dateISO.flatMap { shiftsByDate[$0] } ?? []
      let eventsOnDay = dayInfo.dateISO.flatMap { eventCoverageByDate[$0] } ?? []
      let isSelected =
        dayInfo.dateISO.map { selectedDates.contains($0) || copyTargetDates.contains($0) } ?? false
      let isInDragPreview = dayInfo.dateISO.map { dragPreviewDates.contains($0) } ?? false
      let isNewlyAdded = dayInfo.dateISO.map { newlyAddedDates.contains($0) } ?? false
      let isDeepLinkHighlighted =
        dayInfo.dateISO.map { deepLinkHighlightDates.contains($0) } ?? false
      let isToday = dayInfo.dateISO == currentTodayISO
      let hasConflict =
        dayInfo.dateISO.map { conflictDates.contains($0) || copyPreviewConflictDates.contains($0) }
        ?? false
      let dayJobTimeColors = dayInfo.dateISO.flatMap { dayJobTimeColorsByDate[$0] }
      let shouldColorJobMetrics =
        shouldUseWorkplaceCalendarColors
        && hasMultipleActiveJobs
        && !dayInfo.isOutsideMonth
        && !isSelected
        && !isInDragPreview
        && !isNewlyAdded
        && !isDeepLinkHighlighted
        && !shiftsOnDay.isEmpty
        && dayJobTimeColors != nil
      let eventIndicatorCount = eventsOnDay.count

      CalendarDayCell(
        dayInfo: dayInfo,
        style: cellStyle(
          isToday: isToday,
          isSelected: isSelected,
          isInDragPreview: isInDragPreview,
          isNewlyAdded: isNewlyAdded,
          isDeepLinkHighlighted: isDeepLinkHighlighted,
          hasConflict: hasConflict
        ),
        content: cellContent(
          for: dayInfo,
          dayJobTimeColors: dayJobTimeColors,
          shouldColorJobMetrics: shouldColorJobMetrics,
          earningsByDate: earningsByDate,
          hoursByDate: hoursByDate
        ),
        eventIndicatorCount: eventIndicatorCount
      )
    }
    .coordinateSpace(name: "calendar")
    .overlay(
      GeometryReader { geometry in
        Color.clear
          .contentShape(Rectangle())
          .calendarPressGestures(
            onTap: { location in
              handleTap(at: location, geometry: geometry, days: days)
            },
            onLongPress: { location in
              handleLongPress(at: location, geometry: geometry, days: days)
            },
            onSwipeLeft: onSwipeLeft,
            onSwipeRight: onSwipeRight,
            isEnabled: !isSelectionModeEnabled
          )
          .calendarSelectionGestures(
            actions: CalendarGestureActions(
              onTap: { location in
                handleTap(at: location, geometry: geometry, days: days)
              },
              onDragStart: { location in
                handleDragStart(at: location, geometry: geometry, days: days)
              },
              onDragChanged: { location in
                handleDragChanged(at: location, geometry: geometry, days: days)
              },
              onDragEnded: {
                handleDragEnded()
              }
            ),
            config: .default,
            isEnabled: isSelectionModeEnabled
          )
      }
    )
  }

  // MARK: - Cell Styling

  /// Celebration green color for newly added shifts
  private static let celebrationColor = Color(red: 0.298, green: 0.686, blue: 0.314)

  /// Purple/violet color for deep link highlight from widgets
  private static let deepLinkHighlightColor = Color(red: 0.545, green: 0.361, blue: 0.965)

  private func cellStyle(
    isToday: Bool,
    isSelected: Bool,
    isInDragPreview: Bool,
    isNewlyAdded: Bool,
    isDeepLinkHighlighted: Bool,
    hasConflict: Bool
  ) -> CalendarCellStyle {
    // Priority order: deep link > newly added > selected/drag > conflict > today > default
    if isDeepLinkHighlighted {
      return CalendarCellStyle(
        backgroundColor: Self.deepLinkHighlightColor.opacity(0.2),
        borderColor: Self.deepLinkHighlightColor,
        borderWidth: 2.5,
        dayNumberColor: .tidexTextPrimary,
        showsTodayBadge: false
      )
    }
    if isNewlyAdded {
      return CalendarCellStyle(
        backgroundColor: Self.celebrationColor.opacity(0.2),
        borderColor: Self.celebrationColor,
        borderWidth: 2.5,
        dayNumberColor: .tidexTextPrimary,
        showsTodayBadge: false
      )
    }
    if isSelected || isInDragPreview {
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
      return CalendarCellStyle(
        backgroundColor: Color.tidexBlue.opacity(0.2),
        borderColor: .clear,
        borderWidth: 0,
        dayNumberColor: .tidexTextPrimary,
        showsTodayBadge: true
      )
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
    guard let dateISO = dayInfo.dateISO else { return .empty }

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

  // MARK: - Gesture Handling

  private func handleTap(at location: CGPoint, geometry: GeometryProxy, days: [CalendarDayInfo]) {
    guard let dayISO = findDayAt(location: location, geometry: geometry, days: days) else {
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
      guard !shiftsOnDay.isEmpty else { return }
      onDayTapped?(dayISO, shiftsOnDay)
      return
    }

    if shiftsOnDay.isEmpty && eventsOnDay.isEmpty {
      onEmptyDayTapped?(dayISO)
    } else {
      onDayTapped?(dayISO, shiftsOnDay)
    }
  }

  private func handleLongPress(
    at location: CGPoint, geometry: GeometryProxy, days: [CalendarDayInfo]
  ) {
    guard !isCopyMode, !isMoveMode else { return }
    guard let dayISO = findDayAt(location: location, geometry: geometry, days: days) else {
      return
    }

    let shiftsOnDay = shiftsByDate[dayISO] ?? []
    guard !shiftsOnDay.isEmpty else { return }

    onDayLongPressed?(dayISO, shiftsOnDay)
  }

  private func handleDragStart(
    at location: CGPoint, geometry: GeometryProxy, days: [CalendarDayInfo]
  ) {
    guard let dayISO = findDayAt(location: location, geometry: geometry, days: days) else {
      return
    }

    gestureMode = .selecting
    anchorDateISO = dayISO
    hoverDateISO = dayISO
    dragPreviewDates = [dayISO]
  }

  private func handleDragChanged(
    at location: CGPoint, geometry: GeometryProxy, days: [CalendarDayInfo]
  ) {
    guard gestureMode == .selecting else { return }

    if let dayISO = findDayAt(location: location, geometry: geometry, days: days) {
      if dayISO != hoverDateISO {
        hoverDateISO = dayISO
        updateDragPreview()
      }
    }
  }

  private func handleDragEnded() {
    guard gestureMode == .selecting else {
      resetGestureState()
      return
    }

    if !dragPreviewDates.isEmpty {
      let datesToSelect = Array(dragPreviewDates)
      onSelectDateRange?(datesToSelect)
    }

    resetGestureState()
  }

  private func resetGestureState() {
    gestureMode = .idle
    anchorDateISO = nil
    hoverDateISO = nil
    dragPreviewDates.removeAll()
  }

  private func updateDragPreview() {
    guard let anchorISO = anchorDateISO, let hoverISO = hoverDateISO else {
      dragPreviewDates.removeAll()
      return
    }

    let range = buildDateRange(from: anchorISO, to: hoverISO)
    let datesWithShifts = range.filter { dateISO in
      if let shiftsOnDay = shiftsByDate[dateISO] {
        return !shiftsOnDay.isEmpty
      }
      return false
    }

    dragPreviewDates = Set(datesWithShifts)
  }

  private func buildDateRange(from startISO: String, to endISO: String) -> [String] {
    guard let startDate = Date.fromISODateString(startISO),
      let endDate = Date.fromISODateString(endISO)
    else {
      return [startISO]
    }

    let (earlierDate, laterDate) =
      startDate <= endDate ? (startDate, endDate) : (endDate, startDate)

    var result: [String] = []
    var current = earlierDate

    while current <= laterDate {
      result.append(current.toISODateString())
      guard let nextDay = calendar.date(byAdding: .day, value: 1, to: current) else { break }
      current = nextDay
    }

    return result
  }

  private func findDayAt(location: CGPoint, geometry: GeometryProxy, days: [CalendarDayInfo])
    -> String?
  {
    let gridWidth = geometry.size.width
    let numRows = (days.count + 6) / 7
    let spacing = CalendarGridHelper.cellSpacing
    let totalHorizontalSpacing = spacing * CGFloat(CalendarGridHelper.columnCount - 1)
    let cellWidth = (gridWidth - totalHorizontalSpacing) / CGFloat(CalendarGridHelper.columnCount)
    let cellHeight = cellWidth / CalendarGridHelper.cellAspectRatio
    let colStep = cellWidth + spacing
    let rowStep = cellHeight + spacing

    guard colStep > 0, rowStep > 0 else { return nil }

    let col = Int(location.x / colStep)
    let row = Int(location.y / rowStep)

    guard col >= 0, col < CalendarGridHelper.columnCount, row >= 0, row < numRows else {
      return nil
    }

    // Ignore hits in the inter-cell spacing gutters.
    let xInCell = location.x - CGFloat(col) * colStep
    let yInCell = location.y - CGFloat(row) * rowStep
    guard xInCell <= cellWidth, yInCell <= cellHeight else { return nil }

    let index = row * CalendarGridHelper.columnCount + col
    guard index >= 0, index < days.count else { return nil }

    let dayInfo = days[index]
    guard !dayInfo.isOutsideMonth else { return nil }

    return dayInfo.dateISO
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
    .animation(
      reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8),
      value: singleSelectionActionMode
    )
    .onAppear {
      toggleHaptic.prepare()
      warningHaptic.prepare()
    }
    .onChange(of: selectedDates) { _, _ in
      singleSelectionActionMode = .primary
    }
    .onChange(of: confirmingDelete) { _, _ in
      singleSelectionActionMode = .primary
    }
    .onChange(of: isCopyMode) { _, _ in
      singleSelectionActionMode = .primary
    }
    .onChange(of: isMoveMode) { _, _ in
      singleSelectionActionMode = .primary
    }
    .alert(
      singleDeleteConfirmTitle,
      isPresented: $showSingleSelectionDeleteConfirm
    ) {
      Button(String(localized: .commonCancel), role: .cancel) {}
      Button(String(localized: .shiftsDeleteButton), role: .destructive) {
        warningHaptic.notificationOccurred(.warning)
        onConfirmDelete?()
      }
    } message: {
      Text(singleDeleteConfirmMessage)
    }
    .alert(multiDeleteConfirmTitle, isPresented: $showMultiSelectionDeleteConfirm) {
      Button(String(localized: .commonCancel), role: .cancel) {}
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
          .foregroundColor(isCopyMode ? .tidexBlue : .tidexWarning)
          .frame(width: 36)

        Text(
          isCopyMode
            ? String(localized: "shifts.chooseDates")
            : String(localized: .shiftsSelectMoveTarget)
        )
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)
        .frame(maxWidth: .infinity)
      }

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
        Button {
          toggleHaptic.impactOccurred()
          onFinishCopy?()
        } label: {
          Text("common.copy")
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
    }
    .padding(Spacing.xxs)
    .background(Capsule().fill(Color.tidexSurfaceSecondary))
  }

  @ViewBuilder
  private var singleSelectionBar: some View {
    if singleSelectionActionMode == .copyMoveChoices {
      copyMoveChoicesBar
    } else {
      primarySingleSelectionBar
    }
  }

  @ViewBuilder
  private var primarySingleSelectionBar: some View {
    HStack(spacing: Spacing.xxs) {
      Button {
        toggleHaptic.impactOccurred()
        onDetails?()
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
            .tidexGlass(shape: .capsule, interactive: true)
        )
      }
      .buttonStyle(.plain)

      Button {
        toggleHaptic.impactOccurred()
        onEdit?()
      } label: {
        Image(systemName: "pencil")
          .font(.tidexLabel)
          .foregroundColor(.tidexTextMuted)
          .frame(width: 44, height: 44)
          .background(
            Capsule().fill(.clear)
              .tidexGlass(shape: .capsule, interactive: true)
          )
      }
      .buttonStyle(.plain)

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
        .frame(width: 44, height: 44)
        .background(
          Capsule().fill(.clear)
            .tidexGlass(shape: .capsule, tint: .tidexError.opacity(0.15), interactive: true)
        )
      }
      .buttonStyle(.plain)
      .disabled(isDeleting)
      .accessibilityLabel(Text(.shiftsActionsDelete))

      Button {
        toggleHaptic.impactOccurred()
        singleSelectionActionMode = .copyMoveChoices
      } label: {
        Image(systemName: "line.3.horizontal")
          .font(.tidexLabel)
          .foregroundColor(.tidexTextMuted)
          .frame(width: 44, height: 44)
          .background(
            Capsule().fill(.clear)
              .tidexGlass(shape: .capsule, interactive: true)
          )
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(.shiftsMoreActionsLabel))
    }
    .padding(Spacing.xxs)
    .background(Capsule().fill(Color.tidexSurfaceSecondary))
  }

  @ViewBuilder
  private var copyMoveChoicesBar: some View {
    HStack(spacing: Spacing.xxs) {
      Button {
        toggleHaptic.impactOccurred()
        onCopy?()
      } label: {
        HStack(spacing: Spacing.xxxs) {
          Image(systemName: "doc.on.doc")
            .font(.tidexLabel)
          Text("common.copy")
            .font(.tidexLabelStrong)
        }
        .foregroundColor(.tidexBlue)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
          Capsule().fill(.clear)
            .tidexGlass(shape: .capsule, tint: .tidexBlue.opacity(0.15), interactive: true)
        )
      }
      .buttonStyle(.plain)

      Button {
        toggleHaptic.impactOccurred()
        onMove?()
      } label: {
        HStack(spacing: Spacing.xxxs) {
          Image(systemName: "arrow.left.arrow.right")
            .font(.tidexLabel)
          Text(.shiftsMove)
            .font(.tidexLabelStrong)
        }
        .foregroundColor(.tidexWarning)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
          Capsule().fill(.clear)
            .tidexGlass(shape: .capsule, tint: .tidexWarning.opacity(0.15), interactive: true)
        )
      }
      .buttonStyle(.plain)

      Button {
        toggleHaptic.impactOccurred()
        singleSelectionActionMode = .primary
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
    .accessibilityLabel(Text(String(localized: "common.delete")))
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
    @State private var isSelectionModeEnabled: Bool = false

    var body: some View {
      ScrollView {
        ShiftsCalendarView(
          shifts: [],
          month: Date(),
          year: 2025,
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
          isSelectionModeEnabled: $isSelectionModeEnabled,
          newlyAddedDates: []
        )
        .padding()
      }
      .background(Color.tidexBackground)
    }
  }

  return PreviewWrapper()
}
