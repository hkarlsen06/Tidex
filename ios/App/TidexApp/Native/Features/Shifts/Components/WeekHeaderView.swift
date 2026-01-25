import SwiftUI

/// Header view for a week group in the shifts list
/// Shows week number and total earnings for the week
struct WeekHeaderView: View {
    let weekNumber: Int
    let totalGross: Double

    @Environment(\.localization) private var localization
    @Environment(\.userCurrency) private var currency

    // MARK: - Computed Properties

    private var weekLabel: String {
        localization.string("shifts.weekLabel")
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Week label with number
            HStack(spacing: 4) {
                Text(weekLabel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)

                Text("\(weekNumber)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)
            }

            Spacer()

            // Total earnings for the week
            Text(formatCurrency(totalGross))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    // MARK: - Formatting

    private func formatCurrency(_ amount: Double) -> String {
        CurrencyConfig.format(amount, currency: currency)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        WeekHeaderView(weekNumber: 3, totalGross: 12500)
        WeekHeaderView(weekNumber: 4, totalGross: 8750.50)
    }
    .padding()
    .background(Color.tidexBackground)
}
