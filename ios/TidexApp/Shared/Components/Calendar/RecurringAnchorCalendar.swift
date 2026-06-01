import SwiftUI

enum RecurringAnchorSelection {
  static func weekdayKey(for dateISO: String) -> String {
    guard let date = Date.fromISODateString(dateISO) else { return "0" }
    let weekday = Calendar.current.component(.weekday, from: date)
    return String((weekday - 1) % 7)
  }

  static func toggledSelectedDays(
    _ selectedDays: SelectedDays,
    dateISO: String,
    requiresAtLeastOneAnchor: Bool
  ) -> SelectedDays {
    let weekday = weekdayKey(for: dateISO)
    var updatedSelectedDays = selectedDays

    if updatedSelectedDays[weekday] == dateISO {
      if !requiresAtLeastOneAnchor || updatedSelectedDays.count > 1 {
        updatedSelectedDays.removeValue(forKey: weekday)
      }
    } else {
      updatedSelectedDays[weekday] = dateISO
    }

    return updatedSelectedDays
  }
}

struct RecurringAnchorCalendar: View {
  let displayMonth: Date
  let selectedDays: SelectedDays
  let projectedDates: [String]
  let existingShiftDates: Set<String>
  let conflictDates: Set<String>
  let existingShiftHours: [String: HoursData]
  let monthTransitionPhase: MonthTransitionPhase?
  let showsInstructionsWhenEmpty: Bool
  let anchorEarnings: (String) -> CalendarEarningsData?
  let onToggleAnchorDate: (String) -> Void

  init(
    displayMonth: Date,
    selectedDays: SelectedDays,
    projectedDates: [String],
    existingShiftDates: Set<String>,
    conflictDates: Set<String> = [],
    existingShiftHours: [String: HoursData] = [:],
    monthTransitionPhase: MonthTransitionPhase? = nil,
    showsInstructionsWhenEmpty: Bool = false,
    anchorEarnings: @escaping (String) -> CalendarEarningsData? = { _ in nil },
    onToggleAnchorDate: @escaping (String) -> Void
  ) {
    self.displayMonth = displayMonth
    self.selectedDays = selectedDays
    self.projectedDates = projectedDates
    self.existingShiftDates = existingShiftDates
    self.conflictDates = conflictDates
    self.existingShiftHours = existingShiftHours
    self.monthTransitionPhase = monthTransitionPhase
    self.showsInstructionsWhenEmpty = showsInstructionsWhenEmpty
    self.anchorEarnings = anchorEarnings
    self.onToggleAnchorDate = onToggleAnchorDate
  }

  var body: some View {
    VStack(spacing: 0) {
      CalendarWeekdayHeader()
        .padding(.bottom, Spacing.xs)

      calendarGrid

      if showsInstructionsWhenEmpty && selectedDays.isEmpty {
        RecurringAnchorCalendarInstructions()
          .padding(.top, Spacing.md)
      }
    }
  }

  @ViewBuilder
  private var calendarGrid: some View {
    let days = CalendarGridHelper.daysInMonth(for: displayMonth)
    let projectedDatesSet = Set(projectedDates)

    CalendarMonthGrid(days: days, monthTransitionPhase: monthTransitionPhase) { dayInfo in
      let dateISO = dayInfo.dateISO
      let isAnchor = dateISO.map { selectedDays.values.contains($0) } ?? false
      let isProjected = dateISO.map { projectedDatesSet.contains($0) } ?? false
      let hasConflict = dateISO.map { conflictDates.contains($0) } ?? false
      let hasExistingShift = dateISO.map { existingShiftDates.contains($0) } ?? false
      let isToday = dateISO == todayISO()
      let hours = dateISO.flatMap { existingShiftHours[$0] }
      let earnings = isAnchor ? dateISO.flatMap(anchorEarnings) : nil

      CalendarDayCell(
        dayInfo: dayInfo,
        style: cellStyle(
          isAnchor: isAnchor,
          isProjected: isProjected,
          hasConflict: hasConflict,
          hasExistingShift: hasExistingShift,
          isToday: isToday,
          isOutsideMonth: dayInfo.isOutsideMonth
        ),
        content: cellContent(
          isAnchor: isAnchor,
          isProjected: isProjected,
          hasConflict: hasConflict,
          anchorEarnings: earnings,
          existingHours: hours,
          isOutsideMonth: dayInfo.isOutsideMonth
        )
      )
      .contentShape(Rectangle())
      .onTapGesture {
        if let dateISO, !dayInfo.isOutsideMonth {
          onToggleAnchorDate(dateISO)
        }
      }
    }
  }

  private func cellStyle(
    isAnchor: Bool,
    isProjected: Bool,
    hasConflict: Bool,
    hasExistingShift: Bool,
    isToday: Bool,
    isOutsideMonth: Bool
  ) -> CalendarCellStyle {
    if isAnchor {
      return CalendarCellStyle(
        backgroundColor: .tidexBlue,
        borderColor: .tidexBlue,
        borderWidth: 2,
        dayNumberColor: .white,
        showsTodayBadge: false
      )
    }
    if isProjected {
      return CalendarCellStyle(
        backgroundColor: hasConflict
          ? Color.tidexWarning.opacity(0.15) : Color.tidexBlue.opacity(0.15),
        borderColor: hasConflict ? .tidexWarning : .tidexBlue,
        borderWidth: 2,
        dayNumberColor: hasConflict ? .tidexWarning : .tidexBlue,
        showsTodayBadge: false
      )
    }
    if isToday && !isOutsideMonth {
      return CalendarCellStyle(
        backgroundColor: .tidexSurfacePrimary,
        borderColor: .tidexBlue,
        borderWidth: 2,
        dayNumberColor: .tidexTextPrimary,
        showsTodayBadge: true
      )
    }
    if hasExistingShift && !isOutsideMonth {
      return CalendarCellStyle(
        backgroundColor: .tidexSurfacePrimary,
        borderColor: .clear,
        borderWidth: 0,
        dayNumberColor: .tidexTextPrimary,
        showsTodayBadge: false
      )
    }
    return .default
  }

  private func cellContent(
    isAnchor: Bool,
    isProjected: Bool,
    hasConflict: Bool,
    anchorEarnings: CalendarEarningsData?,
    existingHours: HoursData?,
    isOutsideMonth: Bool
  ) -> CalendarCellContent {
    if isAnchor {
      if let anchorEarnings {
        return .earningsBreakdown(
          anchorEarnings,
          color: .white,
          beforeTaxColor: .white.opacity(0.75)
        )
      }
      return .starIcon(color: .white)
    }

    if isProjected {
      return .dot(color: hasConflict ? .tidexWarning : .tidexBlue)
    }

    if let existingHours, !isOutsideMonth {
      return .hours(existingHours, color: .tidexTextMuted)
    }

    return .empty
  }
}

private struct RecurringAnchorCalendarInstructions: View {
  var body: some View {
    VStack(spacing: Spacing.xs) {
      Image(systemName: "calendar.badge.plus")
        .font(.system(size: 24))
        .foregroundColor(.tidexTextMuted)

      Text(.addShiftTapToSetAnchors)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.center)

      Text(.addShiftOneAnchorPerWeekday)
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextMuted)
    }
    .padding(Spacing.mlg)
    .frame(maxWidth: .infinity)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }
}
