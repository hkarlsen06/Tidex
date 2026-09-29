import Observation
import SwiftUI
import UIKit

/// Minimal contract needed by AddShiftCalendarView.
/// Lets us reuse the exact calendar UI in onboarding without coupling to AddShiftViewModel.
@MainActor
protocol AddShiftCalendarViewModeling: AnyObject {
  var selectedDates: Set<String> { get }
  var conflictDates: Set<String> { get }
  var existingShiftHours: [String: HoursData] { get }
  var previewEarnings: [String: CalendarEarningsData] { get }
  var displayMonth: Date { get }
  var navigationDirection: MonthNavigationDirection? { get }

  func toggleDate(_ dateISO: String)
}

enum AddShiftCalendarSelectionEmphasis {
  case standard
  case subtle
}

/// Multi-select calendar for choosing shift dates in AddShift
/// Uses the same visual style as ShiftsCalendarView but adapted for date selection
/// Supports tap to toggle date selection with existing shift and conflict indicators,
/// and long press then drag to select a run of dates
struct AddShiftCalendarView<ViewModel: AddShiftCalendarViewModeling & Observable>: View {
  var viewModel: ViewModel
  // swiftlint:disable:next discouraged_optional_collection explicit_acl
  var selectedDatesOverride: Set<String>?
  // swiftlint:disable:next discouraged_optional_collection explicit_acl
  var previewEarningsOverride: [String: CalendarEarningsData]?
  // swiftlint:disable:next explicit_acl
  var onToggleDateOverride: ((String) -> Void)?
  var showSelectionCheckmark: Bool = true
  var selectionEmphasis: AddShiftCalendarSelectionEmphasis = .standard

  @State private var dragSelection: CalendarDragSelection?

  private let calendar = Calendar.gregorianCurrent

  var body: some View {
    VStack(spacing: 0) {
      // Weekday headers
      CalendarWeekdayHeader()
        .padding(.bottom, Spacing.xs)

      // Calendar grid
      calendarGrid
    }
  }

  // MARK: - Calendar Grid

  @ViewBuilder
  private var calendarGrid: some View {
    let days = daysInMonth()

    CalendarMonthGrid(days: days, monthTransitionPhase: monthTransitionPhase) { dayInfo in
      dayCell(dayInfo)
    }
    .overlay {
      GeometryReader { geometry in
        CalendarDragSelectOverlay(
          onTap: { location in
            guard
              let dateISO = CalendarDragSelection.dateISO(
                at: location, gridSize: geometry.size, days: days)
            else { return }
            toggleDate(dateISO)
          },
          // Event ranges use their own tap semantics, so only shift dates support drag selection.
          onDragSelect: onToggleDateOverride != nil
            ? nil
            : { state, location in
              handleDragSelect(state, at: location, size: geometry.size, days: days)
            }
        )
      }
    }
  }

  private func toggleDate(_ dateISO: String) {
    if let onToggleDateOverride {
      onToggleDateOverride(dateISO)
    } else {
      viewModel.toggleDate(dateISO)
    }
  }

  // MARK: - Day Cell

  private func dayCell(_ dayInfo: CalendarDayInfo) -> some View {
    let dateISO = dayInfo.dateISO
    let isToday = dateISO == todayISO()
    let isSelected = dateISO.map { resolvedSelectedDates.contains($0) } ?? false
    let hasConflict = dateISO.map { viewModel.conflictDates.contains($0) } ?? false
    let existingHours = dateISO.flatMap { viewModel.existingShiftHours[$0] }
    let previewEarnings = dateISO.flatMap { resolvedPreviewEarnings[$0] }

    return AddShiftCalendarDayCell(
      dayInfo: dayInfo,
      isToday: isToday,
      isSelected: isSelected,
      hasConflict: hasConflict,
      existingHours: existingHours,
      previewEarnings: previewEarnings,
      showSelectionCheckmark: showSelectionCheckmark,
      selectionEmphasis: selectionEmphasis
    )
    // The tap overlay handles pointer taps. VoiceOver and Voice Control use this action instead.
    .calendarDayAccessibility(isHidden: dateISO == nil || dayInfo.isOutsideMonth) { cell in
      cell
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          Text(
            verbatim: AddShiftCalendarAccessibility.label(
              dateText: dateISO.flatMap(Self.spokenDate) ?? "",
              todayText: isToday ? String(localized: .commonToday) : nil,
              existingShiftText: existingHours.map {
                "\(String(localized: .shiftsAccessibilityExistingShift)), "
                  + CalendarGridHelper.timeRangeAccessibilityText(
                    start: $0.start, end: $0.end, crossesMidnight: $0.crossesMidnight)
              },
              earningsText: previewEarnings.map(CalendarGridHelper.earningsAccessibilityText),
              conflictText: hasConflict ? String(localized: .shiftsAccessibilityConflict) : nil
            )
          )
        )
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default) {
          guard let dateISO, !dayInfo.isOutsideMonth else { return }
          toggleDate(dateISO)
        }
    }
  }

  private static func spokenDate(_ dateISO: String) -> String? {
    Date.fromISODateString(dateISO)?.formatted(
      .dateTime.weekday(.wide).day().month(.wide).locale(.appLocale).calendar(.gregorian))
  }

  // MARK: - Drag Selection

  private func handleDragSelect(
    _ state: UIGestureRecognizer.State, at location: CGPoint, size: CGSize, days: [CalendarDayInfo]
  ) {
    guard
      let selection = CalendarDragSelection.update(
        &dragSelection, state: state,
        dateISO: CalendarDragSelection.dateISO(at: location, gridSize: size, days: days),
        days: days, current: resolvedSelectedDates)
    else { return }
    for dateISO in resolvedSelectedDates.symmetricDifference(selection).sorted() {
      viewModel.toggleDate(dateISO)
    }
  }

  private var resolvedSelectedDates: Set<String> {
    selectedDatesOverride ?? viewModel.selectedDates
  }

  private var resolvedPreviewEarnings: [String: CalendarEarningsData] {
    previewEarningsOverride ?? viewModel.previewEarnings
  }

  private var monthTransitionPhase: MonthTransitionPhase? {
    let components = calendar.dateComponents([.year, .month], from: viewModel.displayMonth)
    guard let year = components.year, let month = components.month else { return nil }

    return MonthTransitionPhase(
      year: year,
      month: month,
      direction: viewModel.navigationDirection
    )
  }

  // MARK: - Calendar Helpers

  private func daysInMonth() -> [CalendarDayInfo] {
    var days: [CalendarDayInfo] = []

    // Get first day of month from viewModel's displayMonth
    let components = calendar.dateComponents([.year, .month], from: viewModel.displayMonth)
    guard let firstOfMonth = calendar.date(from: components) else { return days }

    // Get weekday of first day (1 = Sunday, 7 = Saturday)
    let firstWeekday = calendar.component(.weekday, from: firstOfMonth)

    // Convert to Monday-start (0 = Monday, 6 = Sunday)
    let startOffset = (firstWeekday + 5) % 7

    // Get number of days in month
    guard let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return days }

    // Get last day of previous month for "outside days"
    guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: firstOfMonth),
      let previousMonthRange = calendar.range(of: .day, in: .month, for: previousMonth)
    else { return days }
    let daysInPreviousMonth = previousMonthRange.count

    // Add days from previous month (outside days)
    for i in 0..<startOffset {
      let day = daysInPreviousMonth - startOffset + i + 1
      guard let date = calendar.date(byAdding: .day, value: i - startOffset, to: firstOfMonth)
      else { continue }
      let dateISO = date.toISODateString()
      let weekNum = calendar.component(.weekday, from: date) == 2 ? getIsoWeek(from: date) : nil

      days.append(
        .outsideMonth(
          // swiftlint:disable:next no_magic_numbers
          id: -1_000 + i,
          dayNumber: day,
          dateISO: dateISO,
          weekNumber: weekNum
        ))
    }

    // Add cells for each day in current month
    for day in range {
      guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth) else {
        continue
      }
      let dateISO = date.toISODateString()
      let isMonday = calendar.component(.weekday, from: date) == 2
      let weekNum = isMonday ? getIsoWeek(from: date) : nil

      days.append(
        .inMonth(
          id: day,
          dayNumber: day,
          dateISO: dateISO,
          weekNumber: weekNum
        ))
    }

    // Add days from next month to fill the last row
    let totalDays = days.count
    let remainder = totalDays % 7
    if remainder > 0 {
      let daysToAdd = 7 - remainder
      for i in 0..<daysToAdd {
        guard let date = calendar.date(byAdding: .day, value: range.count + i, to: firstOfMonth)
        else { continue }
        let dateISO = date.toISODateString()
        let weekNum = calendar.component(.weekday, from: date) == 2 ? getIsoWeek(from: date) : nil

        days.append(
          .outsideMonth(
            // swiftlint:disable:next no_magic_numbers
            id: 1_000 + i,
            dayNumber: i + 1,
            dateISO: dateISO,
            weekNumber: weekNum
          ))
      }
    }

    return days
  }

  private func getIsoWeek(from date: Date) -> Int {
    var isoCalendar = Calendar(identifier: .iso8601)
    isoCalendar.firstWeekday = 2  // Monday
    isoCalendar.minimumDaysInFirstWeek = 4
    return isoCalendar.component(.weekOfYear, from: date)
  }
}

// MARK: - Accessibility

/// Builds the spoken label for a day in the add-shift calendar.
enum AddShiftCalendarAccessibility {
  /// Joins the date with whichever details apply, in the order they are read.
  static func label(
    dateText: String,
    todayText: String?,
    existingShiftText: String?,
    earningsText: String?,
    conflictText: String?
  ) -> String {
    [dateText, todayText, existingShiftText, earningsText, conflictText]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: ", ")
  }
}

// MARK: - Day Cell

/// Add-shift specific calendar day cell that wraps CalendarDayCell
/// Handles multi-select, conflict detection, selected earnings, and existing-shift hours display
private struct AddShiftCalendarDayCell: View {
  let dayInfo: CalendarDayInfo
  let isToday: Bool
  let isSelected: Bool
  let hasConflict: Bool
  let existingHours: HoursData?
  let previewEarnings: CalendarEarningsData?
  let showSelectionCheckmark: Bool
  let selectionEmphasis: AddShiftCalendarSelectionEmphasis

  var body: some View {
    CalendarDayCell(
      dayInfo: dayInfo,
      style: cellStyle,
      content: cellContent
    ) {
      addShiftContent
    }
    .contentShape(Rectangle())
  }

  // MARK: - Cell Style

  private var cellStyle: CalendarCellStyle {
    CalendarCellStyle(
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      borderWidth: isSelected ? selectionBorderWidth : 0,
      dayNumberColor: dayNumberColor,
      showsTodayBadge: isToday && !dayInfo.isOutsideMonth,
      marker: hasConflict && !dayInfo.isOutsideMonth ? .conflict : nil
    )
  }

  private var backgroundColor: Color {
    if isSelected {
      let opacity = selectionEmphasis == .subtle ? 0.08 : 0.15
      return hasConflict ? Color.tidexWarning.opacity(opacity) : Color.tidexBlue.opacity(opacity)
    }
    if isToday, !dayInfo.isOutsideMonth {
      return CalendarCellStyle.today().backgroundColor
    }
    return Color.tidexSurfacePrimary
  }

  private var borderColor: Color {
    if isSelected {
      return hasConflict ? Color.tidexWarning : Color.tidexBlue
    }
    return Color.clear
  }

  private var selectionBorderWidth: CGFloat {
    selectionEmphasis == .subtle ? 1 : 2
  }

  private var dayNumberColor: Color {
    if hasConflict, isSelected {
      return .tidexWarning
    }
    if isToday, !dayInfo.isOutsideMonth {
      return .tidexTextPrimary
    }
    return .tidexTextPrimary
  }

  // MARK: - Content

  private var cellContent: CalendarCellContent {
    if isSelected, let earnings = previewEarnings {
      return .earningsBreakdown(
        earnings,
        color: hasConflict ? .tidexWarning : .tidexBlueText,
        beforeTaxColor: .tidexTextMuted
      )
    }
    if isSelected {
      return .custom
    }
    if let existingHours, !dayInfo.isOutsideMonth {
      return .hours(existingHours, color: .tidexTextMuted)
    }
    return .empty
  }

  @ViewBuilder
  private var addShiftContent: some View {
    VStack(spacing: 0) {
      if showSelectionCheckmark, isSelected, previewEarnings == nil {
        // Selected but no preview earnings yet (need times)
        Image(systemName: "checkmark")
          .font(.tidexButton)
          .foregroundColor(hasConflict ? .tidexWarning : .tidexBlueText)
          .padding(.top, Spacing.xs)
      }

      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

// MARK: - Preview

#Preview {
  ScrollView {
    AddShiftCalendarView(viewModel: AddShiftViewModel())
      .padding()
  }
  .background(Color.tidexBackground)
}
