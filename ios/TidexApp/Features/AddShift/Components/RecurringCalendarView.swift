import SwiftUI

/// Calendar for selecting anchor dates in recurring shift mode
/// Uses the same visual style as ShiftsCalendarView with rectangular cells and week numbers
/// Allows one anchor per weekday (max 7 anchors)
/// Note: Month navigation is handled by AnimatedMonthHeader in AddShiftView
struct RecurringCalendarView: View {
  @ObservedObject var viewModel: AddShiftViewModel

  var body: some View {
    RecurringAnchorCalendar(
      displayMonth: viewModel.displayMonth,
      selectedDays: viewModel.selectedDays,
      projectedDates: viewModel.projectedRecurringDates,
      existingShiftDates: viewModel.existingShiftDates,
      conflictDates: viewModel.conflictDates,
      existingShiftHours: viewModel.existingShiftHours,
      anchorEarnings: { viewModel.earningsForRecurringDate($0) },
      onToggleAnchorDate: viewModel.toggleAnchorDate
    )
  }
}

// MARK: - Preview

#Preview {
  ScrollView {
    RecurringCalendarView(viewModel: AddShiftViewModel())
      .padding()
  }
  .background(Color.tidexBackground)
}
