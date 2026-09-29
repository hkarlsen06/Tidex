import SwiftUI

/// Header view for a week group in the shifts list
/// Shows week number and total earnings for the week
internal struct WeekHeaderView: View {
  internal let weekNumber: Int
  internal let totalGross: Double
  internal let totalGrossTextOverride: String?

  @Environment(\.userCurrency) private var currency: String
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize: DynamicTypeSize

  // MARK: - Computed Properties

  private var weekLabel: String {
    String(localized: .shiftsWeekLabel)
  }

  // MARK: - Body

  internal var body: some View {
    layout {
      // Week label with number
      HStack(spacing: Spacing.xxs) {
        Text(weekLabel)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)

        Text("\(weekNumber)")
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextPrimary)
      }

      if !dynamicTypeSize.isAccessibilitySize {
        Spacer()
      }

      // Total earnings for the week
      Text(totalText)
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexTextPrimary)
    }
    .padding(.horizontal, Spacing.xxs)
    .padding(.vertical, Spacing.xs)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      Text(.shiftsAccessibilityWeekTotal("\(weekLabel) \(weekNumber)", totalText))
    )
    .accessibilityAddTraits(.isHeader)
  }

  private var totalText: String {
    totalGrossTextOverride ?? formatCurrency(totalGross)
  }

  /// Stacks the week and its total at accessibility text sizes so neither is squeezed.
  private var layout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xxs))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 0))
  }

  internal init(weekNumber: Int, totalGross: Double, totalGrossTextOverride: String? = nil) {
    self.weekNumber = weekNumber
    self.totalGross = totalGross
    self.totalGrossTextOverride = totalGrossTextOverride
  }

  // MARK: - Formatting

  private func formatCurrency(_ amount: Double) -> String {
    CurrencyConfig.format(amount, currency: currency)
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: Spacing.md) {
    WeekHeaderView(weekNumber: 3, totalGross: 12_500)
    WeekHeaderView(weekNumber: 4, totalGross: 8_750.50)
  }
  .padding()
  .background(Color.tidexBackground)
}
