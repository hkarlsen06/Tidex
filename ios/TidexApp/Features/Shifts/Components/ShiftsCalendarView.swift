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

// MARK: - Shifts Calendar View

/// Full-featured calendar for the Shifts tab
/// Shows shift times or earnings per day, ISO week numbers, and monthly totals
/// Supports multi-date selection via long-press + drag
struct ShiftsCalendarView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let shifts: [ShiftWithComputations]
  let month: Date
  let year: Int
  let monthNumber: Int  // 1-12
  let currency: String
  let showEarnings: Bool

  /// Transition phase for header text animations
  var phase: MonthTransitionPhase?

  // Day tap callback (single tap for selection toggle)
  var onDayTapped: ((String, [ShiftWithComputations]) -> Void)?

  // Selection state bindings from ViewModel
  @Binding var selectedDates: Set<String>

  /// Whether delete confirmation is active
  let confirmingDelete: Bool

  /// Whether deletion is in progress
  let isDeleting: Bool

  /// Selected earnings from ViewModel (computed across all months)
  let selectedEarnings: (net: Double, gross: Double)?

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

  // Copy/Move callbacks
  var onCopyToDate: ((String) -> Void)?
  var onMoveToDate: ((String) -> Void)?
  var onCancelCopyMove: (() -> Void)?

  // Selection mode toggle - when enabled, taps/long-press work; when disabled, swipes work
  @Binding var isSelectionModeEnabled: Bool

  // Newly added dates for celebration highlighting
  var newlyAddedDates: Set<String> = []

  // Date to highlight from widget deeplink (temporary visual highlight)
  var deepLinkHighlightDate: String?

  // Dates that have shift conflicts (overlapping shifts)
  var conflictDates: Set<String> = []

  // Shift IDs that should be excluded from totals (conflicting shifts)
  var excludedFromTotalIds: Set<String> = []

  @State private var viewMode: CalendarViewMode = CalendarViewMode.load()
  @State private var showSingleSelectionOverflowMenu = false
  @State private var showSingleSelectionDeleteConfirm = false
  @State private var showMultiSelectionDeleteConfirm = false

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

  // MARK: - Computed Data

  /// Earnings by ISO date string (excludes conflicting shifts)
  private var earningsByDate: [String: CalendarEarningsData] {
    var netByDate: [String: Double] = [:]
    var grossByDate: [String: Double] = [:]
    var hasTaxByDate: [String: Bool] = [:]

    for shift in shifts {
      // Skip shifts excluded from totals
      guard !excludedFromTotalIds.contains(shift.id) else { continue }
      let net = shift.taxEnabled ? shift.netPay : shift.grossPay
      netByDate[shift.shiftDate, default: 0] += net
      grossByDate[shift.shiftDate, default: 0] += shift.grossPay
      hasTaxByDate[shift.shiftDate, default: false] =
        hasTaxByDate[shift.shiftDate, default: false] || shift.taxEnabled
    }

    var result: [String: CalendarEarningsData] = [:]
    for (date, net) in netByDate {
      let gross = grossByDate[date] ?? net
      result[date] = CalendarEarningsData(
        net: net,
        gross: gross,
        hasTaxEnabled: hasTaxByDate[date] ?? false
      )
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

  /// Monthly totals (net and gross, excludes conflicting shifts)
  private var monthlyTotals: (net: Double, gross: Double) {
    let filteredShifts = shifts.filter { shift in
      // Skip shifts excluded from totals
      guard !excludedFromTotalIds.contains(shift.id) else { return false }
      guard let date = Date.fromISODateString(shift.shiftDate) else { return false }
      let components = calendar.dateComponents([.year, .month], from: date)
      return components.year == year && components.month == monthNumber
    }

    let gross = filteredShifts.reduce(0) { $0 + $1.grossPay }
    let net = filteredShifts.reduce(0) {
      $0 + ($1.taxEnabled ? $1.netPay : $1.grossPay)
    }
    return (net: net, gross: gross)
  }

  /// Whether tax is enabled for any shift
  private var hasTaxEnabled: Bool {
    shifts.contains { $0.taxEnabled }
  }

  /// Shifts grouped by ISO date string
  private var shiftsByDate: [String: [ShiftWithComputations]] {
    var result: [String: [ShiftWithComputations]] = [:]
    for shift in shifts {
      result[shift.shiftDate, default: []].append(shift)
    }
    return result
  }

  private var multiDeleteConfirmTitle: String {
    let count = selectedDates.count
    if Locale.appLocale.isNorwegian {
      return "Slette \(count) vakter?"
    } else {
      return "Delete \(count) shifts?"
    }
  }

  private var multiDeleteConfirmMessage: String {
    let count = selectedDates.count
    if Locale.appLocale.isNorwegian {
      return "Er du sikker på at du vil slette \(count) vakter? Dette kan ikke angres."
    } else {
      return "Are you sure you want to delete \(count) shifts? This cannot be undone."
    }
  }

  // MARK: - Body

  var body: some View {
    VStack(spacing: 0) {
      CalendarHeaderRow(
        monthName: monthName,
        year: year,
        selectionCount: selectedDates.count >= 2 ? selectedDates.count : nil,
        phase: nil,
        totals: headerTotals,
        trailingAccessory: nil
      )

      CalendarWeekdayHeader()
        .padding(.bottom, Spacing.xs)

      if let phase {
        StaggeredCardsContainer(phase: phase, config: .default) {
          calendarGrid
        }
      } else {
        calendarGrid
      }

      actionBar
        .padding(.top, Spacing.sm)
    }
  }

  // MARK: - Header Data

  private var headerTotals: CalendarHeaderTotals? {
    guard showEarnings else { return nil }

    // Use selection earnings if dates are selected, otherwise monthly
    let displayTotals: (net: Double, gross: Double) = {
      if selectedDates.isEmpty {
        return monthlyTotals
      } else if let selected = selectedEarnings {
        return selected
      } else {
        return monthlyTotals
      }
    }()

    // Use selectedHasTaxEnabled when dates are selected
    let showTax = selectedDates.isEmpty ? hasTaxEnabled : selectedHasTaxEnabled
    let primaryAmount =
      displayTotals.gross > 0 ? (showTax ? displayTotals.net : displayTotals.gross) : nil
    let secondaryAmount = (showTax && displayTotals.gross > 0) ? displayTotals.gross : nil

    return CalendarHeaderTotals(
      primary: primaryAmount,
      secondary: secondaryAmount
    )
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

    LazyVGrid(columns: CalendarGridHelper.columns, spacing: Spacing.xxs) {
      ForEach(days, id: \.id) { dayInfo in
        let shiftsOnDay = dayInfo.dateISO.flatMap { shiftsByDate[$0] } ?? []
        let isSelected = dayInfo.dateISO.map { selectedDates.contains($0) } ?? false
        let isInDragPreview = dayInfo.dateISO.map { dragPreviewDates.contains($0) } ?? false
        let isNewlyAdded = dayInfo.dateISO.map { newlyAddedDates.contains($0) } ?? false
        let isDeepLinkHighlighted = dayInfo.dateISO == deepLinkHighlightDate
        let isToday = dayInfo.dateISO == todayISO()
        let hasConflict = dayInfo.dateISO.map { conflictDates.contains($0) } ?? false

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
            hasShifts: !shiftsOnDay.isEmpty
          )
        )
      }
    }
    .coordinateSpace(name: "calendar")
    .overlay(
      GeometryReader { geometry in
        Color.clear
          .contentShape(Rectangle())
          .calendarTapGesture(
            onTap: { location in
              handleTap(at: location, geometry: geometry, days: days)
            },
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
        dayNumberColor: .tidexTextPrimary
      )
    }
    if isNewlyAdded {
      return CalendarCellStyle(
        backgroundColor: Self.celebrationColor.opacity(0.2),
        borderColor: Self.celebrationColor,
        borderWidth: 2.5,
        dayNumberColor: .tidexTextPrimary
      )
    }
    if isSelected || isInDragPreview {
      return CalendarCellStyle(
        backgroundColor: Color.tidexBlue.opacity(0.15),
        borderColor: .tidexBlue,
        borderWidth: 2,
        dayNumberColor: .tidexTextPrimary
      )
    }
    if hasConflict {
      return CalendarCellStyle(
        backgroundColor: Color.tidexWarning.opacity(0.15),
        borderColor: .clear,
        borderWidth: 0,
        dayNumberColor: .tidexTextPrimary
      )
    }
    if isToday {
      return CalendarCellStyle(
        backgroundColor: Color.tidexBlue.opacity(0.2),
        borderColor: .clear,
        borderWidth: 0,
        dayNumberColor: .tidexBlue
      )
    }
    return .default
  }

  private func cellContent(for dayInfo: CalendarDayInfo, hasShifts: Bool) -> CalendarCellContent {
    guard let dateISO = dayInfo.dateISO else { return .empty }

    let effectiveViewMode = showEarnings ? viewMode : .hours

    if effectiveViewMode == .money, let earnings = earningsByDate[dateISO] {
      return .earningsBreakdown(earnings)
    } else if effectiveViewMode == .hours, let hoursData = hoursByDate[dateISO] {
      return .hours(hoursData)
    }

    return .empty
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

    if shiftsOnDay.isEmpty {
      onEmptyDayTapped?(dayISO)
    } else {
      onDayTapped?(dayISO, shiftsOnDay)
    }
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
    let gridHeight = geometry.size.height

    let numRows = (days.count + 6) / 7
    let cellWidth = gridWidth / 7
    let cellHeight = gridHeight / CGFloat(numRows)

    let col = Int(location.x / cellWidth)
    let row = Int(location.y / cellHeight)

    guard col >= 0, col < 7, row >= 0, row < numRows else { return nil }

    let index = row * 7 + col
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
    .onAppear {
      toggleHaptic.prepare()
      warningHaptic.prepare()
    }
    .confirmationDialog(
      "Handlinger",
      isPresented: $showSingleSelectionOverflowMenu,
      titleVisibility: .visible
    ) {
      Button(role: .destructive) {
        showSingleSelectionDeleteConfirm = true
      } label: {
        Label(String(localized: .shiftsActionsDelete), systemImage: "trash")
      }

      Button {
        toggleHaptic.impactOccurred()
        onCopy?()
      } label: {
        Label(String(localized: "common.copy"), systemImage: "doc.on.doc")
      }

      Button {
        toggleHaptic.impactOccurred()
        onMove?()
      } label: {
        Label(String(localized: .shiftsMove), systemImage: "arrow.left.arrow.right")
      }

      Button(String(localized: .commonCancel), role: .cancel) {}
    }
    .alert(
      String(localized: .shiftsDeleteConfirmTitle),
      isPresented: $showSingleSelectionDeleteConfirm
    ) {
      Button(String(localized: .commonCancel), role: .cancel) {}
      Button(String(localized: .shiftsDeleteButton), role: .destructive) {
        warningHaptic.notificationOccurred(.warning)
        onConfirmDelete?()
      }
    } message: {
      Text(.shiftsDeleteConfirmMessage)
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
            ? String(localized: .shiftsSelectCopyTarget)
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
          .foregroundColor(.tidexTextOnBrand)
          .padding(.horizontal, Spacing.md)
          .frame(height: 44)
          .background(Capsule().fill(Color.tidexBrandPrimary))
      }
      .buttonStyle(.plain)
      .disabled(isCopying || isMoving)
    }
    .padding(Spacing.xxs)
    .background(Capsule().fill(Color.tidexSurfaceSecondary))
  }

  @ViewBuilder
  private var singleSelectionBar: some View {
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
        .foregroundColor(.tidexTextOnBrand)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(Capsule().fill(Color.tidexBrandPrimary))
      }
      .buttonStyle(.plain)

      Button {
        toggleHaptic.impactOccurred()
        onEdit?()
      } label: {
        Image(systemName: "pencil")
          .font(.tidexLabel)
          .foregroundColor(.tidexBlue)
          .frame(width: 44, height: 44)
          .background(Capsule().fill(Color.tidexBlue.opacity(0.1)))
      }
      .buttonStyle(.plain)

      Button {
        toggleHaptic.impactOccurred()
        showSingleSelectionOverflowMenu = true
      } label: {
        Image(systemName: "line.3.horizontal")
          .font(.tidexLabel)
          .foregroundColor(.tidexBlue)
          .frame(width: 44, height: 44)
          .background(Capsule().fill(Color.tidexBlue.opacity(0.1)))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(String(localized: "Flere handlinger")))
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
              .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnDanger))
              .scaleEffect(0.7)
          } else {
            Image(systemName: "trash")
              .font(.tidexLabel)
          }
          Text(.shiftsActionsDelete)
            .font(.tidexLabelStrong)
        }
        .foregroundColor(.tidexTextOnDanger)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(Capsule().fill(Color.tidexError))
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
        .foregroundColor(.tidexTextOnBrand)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(Capsule().fill(Color.tidexBrandPrimary))
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
          selectedDates: $selectedDates,
          confirmingDelete: false,
          isDeleting: false,
          selectedEarnings: nil,
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
