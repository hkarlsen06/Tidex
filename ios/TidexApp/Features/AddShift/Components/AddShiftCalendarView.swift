import SwiftUI

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
/// Supports tap to toggle date selection with existing shift and conflict indicators
struct AddShiftCalendarView<ViewModel: AddShiftCalendarViewModeling & ObservableObject>: View {
  @ObservedObject var viewModel: ViewModel
  // swiftlint:disable:next discouraged_optional_collection explicit_acl
  var selectedDatesOverride: Set<String>?
  // swiftlint:disable:next discouraged_optional_collection explicit_acl
  var previewEarningsOverride: [String: CalendarEarningsData]?
  // swiftlint:disable:next explicit_acl
  var onToggleDateOverride: ((String) -> Void)?
  var showSelectionCheckmark: Bool = true
  var selectionEmphasis: AddShiftCalendarSelectionEmphasis = .standard

  private let calendar = Calendar.current

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
      AddShiftCalendarDayCell(
        dayInfo: dayInfo,
        isToday: dayInfo.dateISO == todayISO(),
        isSelected: dayInfo.dateISO.map { resolvedSelectedDates.contains($0) } ?? false,
        hasConflict: dayInfo.dateISO.map { viewModel.conflictDates.contains($0) } ?? false,
        existingHours: dayInfo.dateISO.flatMap { viewModel.existingShiftHours[$0] },
        previewEarnings: dayInfo.dateISO.flatMap { resolvedPreviewEarnings[$0] },
        showSelectionCheckmark: showSelectionCheckmark,
        selectionEmphasis: selectionEmphasis
      )
      .onTapGesture {
        if let dateISO = dayInfo.dateISO, !dayInfo.isOutsideMonth {
          if let onToggleDateOverride {
            onToggleDateOverride(dateISO)
          } else {
            viewModel.toggleDate(dateISO)
          }
        }
      }
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
      showsTodayBadge: isToday && !dayInfo.isOutsideMonth
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
        color: hasConflict ? .tidexWarning : .tidexBlue,
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
          .foregroundColor(hasConflict ? .tidexWarning : .tidexBlue)
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
