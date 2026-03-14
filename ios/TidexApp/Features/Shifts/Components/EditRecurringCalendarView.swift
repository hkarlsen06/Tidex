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
    RecurringAnchorCalendar(
      displayMonth: displayMonth,
      selectedDays: selectedDays,
      projectedDates: projectedDates,
      existingShiftDates: existingShiftDates,
      showsInstructionsWhenEmpty: true,
      onToggleAnchorDate: toggleAnchorDate
    )
  }

  // MARK: - Helpers

  /// Toggle anchor date for a weekday
  private func toggleAnchorDate(_ dateISO: String) {
    selectedDays = RecurringAnchorSelection.toggledSelectedDays(
      selectedDays,
      dateISO: dateISO,
      requiresAtLeastOneAnchor: true
    )

    // Haptic feedback
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()
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
