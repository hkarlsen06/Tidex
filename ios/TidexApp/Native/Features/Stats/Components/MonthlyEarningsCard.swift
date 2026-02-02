import SwiftUI

/// Large card showing monthly earnings with tax breakdown and percentage change
/// Matches the design from the Next.js stats page
struct MonthlyEarningsCard: View {
    let grossEarnings: Double
    let netEarnings: Double
    let taxEnabled: Bool
    let percentageChange: Double?

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

    private var isPositive: Bool {
        (percentageChange ?? 0) >= 0
    }

    private var displayPercentage: Int {
        Int(abs(percentageChange ?? 0))
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title, amount, and after tax label grouped tightly
            VStack(alignment: .leading, spacing: 2) {
                Text(.statsMonthlyEarnings)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)

                CurrencyCountUpText(amount: mainDisplayValue)
                    .font(.system(size: 56, weight: .bold))
                    .foregroundColor(.tidexTextPrimary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                if taxEnabled {
                    Text(String(localized: .statsAfterTax).lowercased())
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.tidexTextSecondary)
                }
            }

            // Before tax subtitle
            if taxEnabled && showTaxSubtitle {
                Text("\(String(localized: .statsBeforeTax)): \(formatCurrency(grossEarnings))")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.tidexTextMuted)
            }

            // Percentage change indicator
            if hasChange || percentageChange == nil {
                HStack(spacing: 4) {
                    if hasChange {
                        Image(systemName: isPositive ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
                            .font(.system(size: 14, weight: .semibold))
                    }

                    if hasChange {
                        Text("\(isPositive ? "+" : "-")\(displayPercentage)% \(String(localized: .statsFromPreviousMonth))")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
                .foregroundColor(hasChange ? (isPositive ? .tidexSuccess : .tidexError) : .tidexTextMuted)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(24)
        .tidexCardShadow()
    }

    // MARK: - Formatting

    private func formatCurrency(_ amount: Double) -> String {
        CurrencyConfig.format(amount, currency: currency)
    }
}

#Preview {
    VStack(spacing: 16) {
        // With tax and negative change
        MonthlyEarningsCard(
            grossEarnings: 13772,
            netEarnings: 12808,
            taxEnabled: true,
            percentageChange: -32
        )

        // With positive change
        MonthlyEarningsCard(
            grossEarnings: 20000,
            netEarnings: 18500,
            taxEnabled: true,
            percentageChange: 15
        )

        // No tax
        MonthlyEarningsCard(
            grossEarnings: 15000,
            netEarnings: 15000,
            taxEnabled: false,
            percentageChange: 5
        )
    }
    .padding()
    .background(Color.tidexBackground)
}
