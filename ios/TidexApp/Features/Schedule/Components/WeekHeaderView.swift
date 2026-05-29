import SwiftUI

/// Header view for a week group in the shifts list
/// Shows week number and total earnings for the week
struct WeekHeaderView: View {
  let weekNumber: Int
  let totalGross: Double
  let totalGrossTextOverride: String?

  @Environment(\.userCurrency) private var currency

  init(weekNumber: Int, totalGross: Double, totalGrossTextOverride: String? = nil) {
    self.weekNumber = weekNumber
    self.totalGross = totalGross
    self.totalGrossTextOverride = totalGrossTextOverride
  }

  // MARK: - Computed Properties

  private var weekLabel: String {
    String(localized: .shiftsWeekLabel)
  }

  // MARK: - Body

  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      // Week label with number
      HStack(spacing: Spacing.xxs) {
        Text(weekLabel)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)

        Text("\(weekNumber)")
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextPrimary)
      }

      Spacer()

      // Total earnings for the week
      Text(totalGrossTextOverride ?? formatCurrency(totalGross))
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexTextPrimary)
    }
    .padding(.horizontal, Spacing.xxs)
    .padding(.vertical, Spacing.xs)
  }

  // MARK: - Formatting

  private func formatCurrency(_ amount: Double) -> String {
    CurrencyConfig.format(amount, currency: currency)
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: Spacing.md) {
    WeekHeaderView(weekNumber: 3, totalGross: 12500)
    WeekHeaderView(weekNumber: 4, totalGross: 8750.50)
  }
  .padding()
  .background(Color.tidexBackground)
}
