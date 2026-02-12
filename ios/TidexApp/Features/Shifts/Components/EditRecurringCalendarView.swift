import SwiftUI

/// Calendar view for editing recurring shift anchor dates
/// Similar to RecurringCalendarView but designed for use in RecurringShiftEditorSheet
/// Works with bindings instead of requiring AddShiftViewModel
struct EditRecurringCalendarView: View {
  /// The month currently being displayed
  let displayMonth: Date

  /// Selected anchor days: weekday "0"-"6" -> anchor ISO date
  @Binding var selectedDays: SelectedDays

  /// Repeat interval (0 = weekly, 1 = biweekly, etc.)
  let repeatInterval: Int

  /// End condition for the recurring pattern
  let endCondition: EndCondition?

  /// Existing shift dates to show as occupied
  let existingShiftDates: Set<String>

  /// Projected dates based on current settings
  private var projectedDates: [String] {
    RecurringShiftProjector.generateDatesForCalendarDisplay(
      selectedDays: selectedDays,
      repeatInterval: repeatInterval,
      displayMonth: displayMonth,
      endCondition: endCondition
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      // Weekday headers
      CalendarWeekdayHeader()
        .padding(.bottom, Spacing.xs)

      // Calendar grid
      calendarGrid

      // Instructions
      if selectedDays.isEmpty {
        CalendarInstructions()
          .padding(.top, Spacing.md)
      }
    }
  }

  // MARK: - Calendar Grid

  @ViewBuilder
  private var calendarGrid: some View {
    let days = CalendarGridHelper.daysInMonth(for: displayMonth)
    let projectedDatesSet = Set(projectedDates)

    CalendarMonthGrid(days: days) { dayInfo in
      let isAnchor = dayInfo.dateISO.map { isAnchorDate($0) } ?? false
      let isProjected = dayInfo.dateISO.map { projectedDatesSet.contains($0) } ?? false
      let hasExistingShift = dayInfo.dateISO.map { existingShiftDates.contains($0) } ?? false
      let isToday = dayInfo.dateISO == todayISO()

      CalendarDayCell(
        dayInfo: dayInfo,
        style: cellStyle(
          isAnchor: isAnchor,
          isProjected: isProjected,
          hasExistingShift: hasExistingShift,
          isToday: isToday,
          isOutsideMonth: dayInfo.isOutsideMonth
        ),
        content: cellContent(
          isAnchor: isAnchor,
          isProjected: isProjected,
          isOutsideMonth: dayInfo.isOutsideMonth
        )
      )
      .contentShape(Rectangle())
      .onTapGesture {
        if let dateISO = dayInfo.dateISO, !dayInfo.isOutsideMonth {
          toggleAnchorDate(dateISO)
        }
      }
    }
  }

  // MARK: - Helpers

  private func isAnchorDate(_ dateISO: String) -> Bool {
    selectedDays.values.contains(dateISO)
  }

  /// Toggle anchor date for a weekday
  private func toggleAnchorDate(_ dateISO: String) {
    let weekday = weekdayFromDate(dateISO)

    if selectedDays[weekday] == dateISO {
      // Remove this anchor (but keep at least one)
      if selectedDays.count > 1 {
        selectedDays.removeValue(forKey: weekday)
      }
    } else {
      // Set or replace anchor for this weekday
      selectedDays[weekday] = dateISO
    }

    // Haptic feedback
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()
  }

  /// Get weekday string ("0"-"6") from ISO date
  private func weekdayFromDate(_ dateISO: String) -> String {
    guard let date = Date.fromISODateString(dateISO) else { return "0" }
    let calendar = Calendar.current
    let weekday = calendar.component(.weekday, from: date)
    // Calendar weekday is 1=Sun, 2=Mon, ..., 7=Sat
    // JavaScript weekday is 0=Sun, 1=Mon, ..., 6=Sat
    return String((weekday - 1) % 7)
  }

  // MARK: - Cell Styling

  private func cellStyle(
    isAnchor: Bool,
    isProjected: Bool,
    hasExistingShift: Bool,
    isToday: Bool,
    isOutsideMonth: Bool
  ) -> CalendarCellStyle {
    if isAnchor {
      return CalendarCellStyle(
        backgroundColor: .tidexBlue,
        borderColor: .tidexBlue,
        borderWidth: 2,
        dayNumberColor: .white
      )
    }
    if isProjected {
      return CalendarCellStyle(
        backgroundColor: Color.tidexBlue.opacity(0.15),
        borderColor: .tidexBlue,
        borderWidth: 2,
        dayNumberColor: .tidexBlue
      )
    }
    if isToday && !isOutsideMonth {
      return CalendarCellStyle(
        backgroundColor: .tidexSurfacePrimary,
        borderColor: .tidexBlue,
        borderWidth: 2,
        dayNumberColor: .tidexBlue
      )
    }
    if hasExistingShift && !isOutsideMonth {
      return CalendarCellStyle(
        backgroundColor: .tidexSurfacePrimary,
        borderColor: .clear,
        borderWidth: 0,
        dayNumberColor: .tidexBlue
      )
    }
    return .default
  }

  private func cellContent(
    isAnchor: Bool,
    isProjected: Bool,
    isOutsideMonth: Bool
  ) -> CalendarCellContent {
    if isAnchor {
      // Anchor date: show star icon
      return .starIcon(color: .white)
    }

    if isProjected {
      // Projected dates: simple dot indicator
      return .dot(color: .tidexBlue)
    }

    return .empty
  }
}

// MARK: - Calendar Instructions

private struct CalendarInstructions: View {

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

// MARK: - Preview

#Preview {
  ScrollView {
    EditRecurringCalendarView(
      displayMonth: Date(),
      selectedDays: .constant([
        "1": "2025-01-27",
        "3": "2025-01-29",
      ]),
      repeatInterval: 0,
      endCondition: .months(value: 6),
      existingShiftDates: []
    )
    .padding()
  }
  .background(Color.tidexBackground)
}
