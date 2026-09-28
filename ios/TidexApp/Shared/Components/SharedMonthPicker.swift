import SwiftUI

/// Month picker bound to `SharedMonthContext`, so every screen that shows it stays on the same month.
internal struct SharedMonthPicker: View {
  private let monthContext: SharedMonthContext = .shared

  internal var body: some View {
    AnimatedMonthHeader(
      monthName: monthContext.displayMonthName,
      year: monthContext.displayYear,
      phase: MonthTransitionPhase(
        year: monthContext.displayYear,
        month: monthContext.displayMonth,
        direction: monthContext.navigationDirection
      ),
      config: .default,
      onPrevious: {
        AppearanceTracker.shared.reset()
        monthContext.goToPreviousMonth()
      },
      onNext: {
        AppearanceTracker.shared.reset()
        monthContext.goToNextMonth()
      },
      onNavigateToMonth: { year, month in
        AppearanceTracker.shared.reset()
        monthContext.navigateTo(year: year, month: month)
      },
      isLoading: false
    )
  }
}
