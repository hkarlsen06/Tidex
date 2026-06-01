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
      monthTransitionPhase: monthTransitionPhase,
      anchorEarnings: { viewModel.earningsForRecurringDate($0) },
      onToggleAnchorDate: viewModel.toggleAnchorDate
    )
  }

  private var monthTransitionPhase: MonthTransitionPhase {
    MonthTransitionPhase(
      year: viewModel.displayYear,
      month: viewModel.displayMonthNumber,
      direction: viewModel.navigationDirection
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
