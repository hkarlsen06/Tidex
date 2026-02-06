import SwiftUI
import UIKit

/// Multi-select calendar for choosing shift dates in AddShift
/// Uses the same visual style as ShiftsCalendarView but adapted for date selection
/// Supports tap to toggle date selection with existing shift and conflict indicators
struct AddShiftCalendarView: View {
  @ObservedObject var viewModel: AddShiftViewModel
  let onReset: (() -> Void)?

  init(viewModel: AddShiftViewModel, onReset: (() -> Void)? = nil) {
    self.viewModel = viewModel
    self.onReset = onReset
  }

  private let calendar = Calendar.current
  private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

  var body: some View {
    VStack(spacing: 0) {
      CalendarHeaderRow(
        monthName: monthName,
        year: viewModel.displayYear,
        selectionCount: viewModel.selectedDates.count >= 2 ? viewModel.selectedDates.count : nil,
        phase: transitionPhase,
        totals: headerTotals,
        trailingAccessory: resetButton
      )

      // Weekday headers
      weekdayHeaderRow
        .padding(.bottom, 8)

      // Calendar grid
      calendarGrid
    }
  }

  private var monthName: String {
    CalendarGridHelper.monthName(
      from: viewModel.displayMonth,
      locale: Locale.appLocale
    )
  }

  private var transitionPhase: MonthTransitionPhase {
    MonthTransitionPhase(
      year: viewModel.displayYear,
      month: viewModel.displayMonthNumber,
      direction: viewModel.navigationDirection
    )
  }

  private var headerTotals: CalendarHeaderTotals {
    let monthTotals = monthlyTotals
    let selectedTotals = selectedPreviewTotals
    let displayTotals = selectedTotals ?? monthTotals

    let primaryAmount =
      displayTotals.gross > 0
      ? (displayTotals.hasTaxEnabled ? displayTotals.net : displayTotals.gross)
      : nil

    return CalendarHeaderTotals(
      primary: primaryAmount,
      secondary: nil
    )
  }

  private var resetButton: AnyView? {
    guard viewModel.hasContent, let onReset else { return nil }
    return AnyView(
      Button(action: onReset) {
        Image(systemName: "arrow.counterclockwise.circle.fill")
          .font(.system(size: 24))
          .foregroundColor(.tidexBlue)
      }
      .buttonStyle(.plain)
    )
  }

  private var monthlyTotals: (net: Double, gross: Double, hasTaxEnabled: Bool) {
    viewModel.existingShiftEarnings.values.reduce(
      into: (net: 0.0, gross: 0.0, hasTaxEnabled: false)
    ) { partial, earnings in
      partial.net += earnings.net
      partial.gross += earnings.gross
      partial.hasTaxEnabled = partial.hasTaxEnabled || earnings.hasTaxEnabled
    }
  }

  private var selectedPreviewTotals: (net: Double, gross: Double, hasTaxEnabled: Bool)? {
    guard !viewModel.selectedDates.isEmpty else { return nil }

    let selectedEarnings = viewModel.selectedDates.compactMap { dateISO in
      viewModel.previewEarnings[dateISO]
    }
    guard !selectedEarnings.isEmpty else { return nil }

    return selectedEarnings.reduce(
      into: (net: 0.0, gross: 0.0, hasTaxEnabled: false)
    ) { partial, earnings in
      partial.net += earnings.net
      partial.gross += earnings.gross
      partial.hasTaxEnabled = partial.hasTaxEnabled || earnings.hasTaxEnabled
    }
  }

  // MARK: - Weekday Header Row

  private var weekdayHeaderRow: some View {
    HStack(spacing: 0) {
      ForEach(weekdaySymbols.indices, id: \.self) { index in
        Text(weekdaySymbols[index])
          .font(.system(size: 12, weight: .medium))
          .foregroundColor(.tidexTextMuted)
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var weekdaySymbols: [String] {
    [
      String(localized: .calendarWeekdayMonday),
      String(localized: .calendarWeekdayTuesday),
      String(localized: .calendarWeekdayWednesday),
      String(localized: .calendarWeekdayThursday),
      String(localized: .calendarWeekdayFriday),
      String(localized: .calendarWeekdaySaturday),
      String(localized: .calendarWeekdaySunday),
    ]
  }

  // MARK: - Calendar Grid

  @ViewBuilder
  private var calendarGrid: some View {
    let days = daysInMonth()

    LazyVGrid(columns: columns, spacing: 4) {
      ForEach(days, id: \.id) { dayInfo in
        AddShiftCalendarDayCell(
          dayInfo: dayInfo,
          isToday: dayInfo.dateISO == todayISO(),
          isSelected: dayInfo.dateISO.map { viewModel.selectedDates.contains($0) } ?? false,
          hasConflict: dayInfo.dateISO.map { viewModel.conflictDates.contains($0) } ?? false,
          existingHours: dayInfo.dateISO.flatMap { viewModel.existingShiftHours[$0] },
          previewEarnings: dayInfo.dateISO.flatMap { viewModel.previewEarnings[$0] }
        )
        .onTapGesture {
          if let dateISO = dayInfo.dateISO, !dayInfo.isOutsideMonth {
            viewModel.toggleDate(dateISO)
          }
        }
      }
    }
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
          id: -1000 + i,
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
            id: 1000 + i,
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
      borderWidth: isSelected ? 2 : 0,
      dayNumberColor: dayNumberColor
    )
  }

  private var backgroundColor: Color {
    if isSelected {
      return hasConflict ? Color.tidexWarning.opacity(0.15) : Color.tidexBlue.opacity(0.15)
    }
    if isToday && !dayInfo.isOutsideMonth {
      return Color.tidexBlue.opacity(0.2)
    }
    return Color.tidexSurfacePrimary
  }

  private var borderColor: Color {
    if isSelected {
      return hasConflict ? Color.tidexWarning : Color.tidexBlue
    }
    return Color.clear
  }

  private var dayNumberColor: Color {
    if hasConflict && isSelected {
      return .tidexWarning
    }
    if isToday && !dayInfo.isOutsideMonth {
      return .tidexBlue
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
    } else if isSelected {
      return .custom
    } else if let existingHours, !dayInfo.isOutsideMonth {
      return .hours(existingHours, color: .tidexTextMuted)
    }
    return .empty
  }

  @ViewBuilder
  private var addShiftContent: some View {
    if isSelected && previewEarnings == nil {
      // Selected but no preview earnings yet (need times)
      Image(systemName: "checkmark")
        .font(.system(size: 16, weight: .bold))
        .foregroundColor(hasConflict ? .tidexWarning : .tidexBlue)
        .padding(.top, 8)
    }
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
