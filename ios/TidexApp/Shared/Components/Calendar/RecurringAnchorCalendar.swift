// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_label_for_image accessibility_trait_for_button closure_body_length conditional_returns_on_newline
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface file_types_order
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable function_parameter_count no_magic_numbers prefer_condition_list type_contents_order
import SwiftUI

enum RecurringAnchorSelection {
  static func weekdayKey(for dateISO: String) -> String {
    guard let date = Date.fromISODateString(dateISO) else { return "0" }
    let weekday = Calendar.gregorianCurrent.component(.weekday, from: date)
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

/// Spoken label for a day in the anchor calendar: the date, then what the day is.
enum RecurringAnchorCellAccessibility {
  static func dateText(dateISO: String) -> String {
    guard let date = Date.fromISODateString(dateISO) else { return dateISO }
    return date.formatted(
      .dateTime.weekday(.wide).day().month(.wide).locale(.appLocale).calendar(.gregorian))
  }

  static func label(
    dateISO: String,
    isToday: Bool,
    isAnchor: Bool,
    isProjected: Bool,
    hasConflict: Bool,
    hasExistingShift: Bool,
    hours: HoursData?
  ) -> String {
    var parts = [dateText(dateISO: dateISO)]
    if isToday {
      parts.append(String(localized: .commonToday))
    }
    if isAnchor {
      parts.append(String(localized: .commonAccessibilityAnchorDay))
    } else if isProjected {
      parts.append(String(localized: .commonAccessibilityRepeatDay))
    }
    if let hours {
      parts.append(
        CalendarGridHelper.timeRangeAccessibilityText(
          start: hours.start, end: hours.end, crossesMidnight: hours.crossesMidnight))
    } else if hasExistingShift {
      parts.append(String(localized: .shiftsAccessibilityExistingShift))
    }
    if hasConflict {
      parts.append(String(localized: .shiftsAccessibilityConflict))
    }
    return parts.joined(separator: ", ")
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

      if showsInstructionsWhenEmpty, selectedDays.isEmpty {
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

      Button {
        if let dateISO, !dayInfo.isOutsideMonth {
          onToggleAnchorDate(dateISO)
        }
      } label: {
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
      }
      .buttonStyle(.plain)
      .calendarDayAccessibility(isHidden: dayInfo.isOutsideMonth) { cell in
        cell
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(
            Text(
              verbatim: dateISO.map {
                RecurringAnchorCellAccessibility.label(
                  dateISO: $0, isToday: isToday, isAnchor: isAnchor, isProjected: isProjected,
                  hasConflict: hasConflict, hasExistingShift: hasExistingShift, hours: hours)
              } ?? ""
            )
          )
          .accessibilityInputLabels(
            [Text(verbatim: dateISO.map { RecurringAnchorCellAccessibility.dateText(dateISO: $0) } ?? "")]
          )
          .accessibilityAddTraits(isAnchor ? [.isButton, .isSelected] : .isButton)
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
        dayNumberColor: hasConflict ? .tidexWarning : .tidexBlueText,
        showsTodayBadge: false,
        marker: hasConflict ? .conflict : nil
      )
    }
    if isToday, !isOutsideMonth {
      return CalendarCellStyle(
        backgroundColor: .tidexSurfacePrimary,
        borderColor: .tidexBlue,
        borderWidth: 2,
        dayNumberColor: .tidexTextPrimary,
        showsTodayBadge: true
      )
    }
    if hasExistingShift, !isOutsideMonth {
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
          beforeTaxColor: .white
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
