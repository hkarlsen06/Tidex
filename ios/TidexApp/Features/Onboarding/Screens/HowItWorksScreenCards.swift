import SwiftUI

struct OnboardingHowItWorksShiftPreviewCard: View {
  let shift: ShiftWithComputations
  let isVisible: Bool
  let isDimmedForFocus: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    FeaturedShiftCard(
      shift: shift,
      isToday: false,
      isBestShift: true,
      countdownText: nil,
      progress: nil,
      showIncreaseHighlight: true,
      showFooter: false
    )
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, Spacing.md)
    .padding(.bottom, Spacing.xxl)
    .frame(maxWidth: .infinity, alignment: .leading)
    .opacity(isVisible ? 1 : 0)
    .saturation(isDimmedForFocus ? HowItWorksScreen.dimmedSaturation : 1)
    .offset(y: isVisible ? 0 : 18)
    .animation(
      reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82).delay(0.24),
      value: isVisible
    )
    .animation(.easeInOut(duration: 0.26), value: isDimmedForFocus)
  }
}

struct OnboardingHowItWorksTotalCard: View {
  let fromTotals: CalendarHeaderTotals?
  let toTotals: CalendarHeaderTotals?

  private let payrollDay = 15

  var body: some View {
    PayrollCard(
      payrollDate: nextMonthPayrollDate,
      label: String(localized: .dashboardNextPayout),
      gross: displayedGross,
      net: displayedNet,
      tax: displayedTax,
      taxEnabled: displayedNet != nil,
      progress: nil
    )
  }

  private var displayedTotals: CalendarHeaderTotals? {
    toTotals ?? fromTotals
  }

  private var displayedNet: Double? {
    guard displayedSecondary != nil else { return nil }
    return displayedPrimary
  }

  private var displayedPrimary: Double {
    displayedTotals?.primary ?? 0
  }

  private var displayedSecondary: Double? {
    displayedTotals?.secondary
  }

  private var displayedGross: Double {
    if let displayedSecondary {
      return displayedSecondary
    }
    return displayedPrimary
  }

  private var displayedTax: Double? {
    guard let net = displayedNet else { return nil }
    return max(displayedGross - net, 0)
  }

  private var nextMonthPayrollDate: Date {
    let calendar = Calendar.gregorianCurrent
    let currentMonth = Date.currentYearMonth()
    let currentMonthDate =
      calendar.date(
        from: DateComponents(year: currentMonth.year, month: currentMonth.month, day: 1))
      ?? Date()
    let nextMonthDate =
      calendar.date(byAdding: .month, value: 1, to: currentMonthDate) ?? currentMonthDate
    let components = calendar.dateComponents([.year, .month], from: nextMonthDate)
    let year = components.year ?? currentMonth.year
    let month = components.month ?? currentMonth.month
    let clampedDay = min(payrollDay, Date.daysInMonth(year: year, month: month))
    return calendar.date(from: DateComponents(year: year, month: month, day: clampedDay))
      ?? nextMonthDate
  }
}
