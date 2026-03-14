import SwiftUI

/// Large card showing monthly earnings with tax breakdown and percentage change
/// Matches the design from the Next.js stats page
struct MonthlyEarningsCard: View {
  let grossEarnings: Double
  let netEarnings: Double
  let taxEnabled: Bool
  let percentageChange: Double?
  var onTap: (() -> Void)?

  @Environment(\.userCurrency) private var currency

  // MARK: - Computed Properties

  /// Main display value (net if tax enabled, gross otherwise)
  private var mainDisplayValue: Double {
    taxEnabled ? netEarnings : grossEarnings
  }

  private var showTaxSubtitle: Bool {
    taxEnabled && grossEarnings != netEarnings
  }

  private var hasChange: Bool {
    percentageChange != nil && percentageChange != 0
  }

  private var changeText: String {
    let change = percentageChange ?? 0
    let prefix: String

    if change > 0 {
      prefix = "+"
    } else if change < 0 {
      prefix = "-"
    } else {
      prefix = ""
    }

    return
      "\(prefix)\(Int(abs(change)))% \(String(localized: .statsFromPreviousMonth))"
  }

  private var isPositive: Bool {
    (percentageChange ?? 0) >= 0
  }

  // MARK: - Body

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      // Title, amount, and after tax label grouped tightly
      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text(.statsMonthlyEarnings)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)

        CurrencyCountUpText(
          amount: mainDisplayValue,
          animateOnAppear: false,
          animateChanges: false
        )
        .font(.tidexStat)
        .foregroundColor(.tidexTextPrimary)
        .minimumScaleFactor(0.5)
        .lineLimit(1)

        if taxEnabled {
          Text(String(localized: .statsAfterTax).lowercased())
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextSecondary)
        }
      }

      // Before tax subtitle
      if taxEnabled && showTaxSubtitle {
        Text("\(String(localized: .statsBeforeTax)): \(formatCurrency(grossEarnings))")
          .font(.tidexSubheadline)
          .foregroundColor(.tidexTextMuted)
      }

      // Always reserve space for the month-over-month footer to avoid card height jumps.
      HStack(spacing: Spacing.xxs) {
        if hasChange {
          Image(
            systemName: isPositive ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis"
          )
          .font(.tidexCaptionStrong)
        }

        Text(changeText)
          .font(.tidexSubheadline)
          .opacity(percentageChange == nil ? 0 : 1)
      }
      .foregroundColor(hasChange ? (isPositive ? .tidexSuccess : .tidexError) : .tidexTextMuted)
      .padding(.top, Spacing.xxs)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Spacing.lg)
    .background(Color.tidexSurfacePrimary)
    .cornerRadius(CornerRadius.card)
    .tidexCardShadow()
    .contentShape(Rectangle())
    .onTapGesture {
      onTap?()
    }
  }

  // MARK: - Formatting

  private func formatCurrency(_ amount: Double) -> String {
    CurrencyConfig.format(amount, currency: currency)
  }
}

#Preview {
  VStack(spacing: Spacing.md) {
    // With tax and negative change
    MonthlyEarningsCard(
      grossEarnings: 13772,
      netEarnings: 12808,
      taxEnabled: true,
      percentageChange: -32,
      onTap: nil
    )

    // With positive change
    MonthlyEarningsCard(
      grossEarnings: 20000,
      netEarnings: 18500,
      taxEnabled: true,
      percentageChange: 15,
      onTap: nil
    )

    // No tax
    MonthlyEarningsCard(
      grossEarnings: 15000,
      netEarnings: 15000,
      taxEnabled: false,
      percentageChange: 5,
      onTap: nil
    )
  }
  .padding()
  .background(Color.tidexBackground)
}
