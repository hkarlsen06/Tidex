import SwiftUI

/// Card displaying current month's earnings and statistics
struct TotalCard: View {
    let gross: Double
    let net: Double?
    let shiftCount: Int
    let plannedCount: Int
    let percentageChange: Double?
    let taxEnabled: Bool

    @Environment(\.localization) private var localization

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with percentage badge
            HStack {
                Text(localization.string("dashboard.earnedToDate"))
                    .font(.system(size: 14))
                    .foregroundColor(.tidexTextSecondary)

                Spacer()

                // Percentage change badge
                if let change = percentageChange {
                    HStack(spacing: 4) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 12))
                        Text(String(format: "%.1f%%", abs(change)))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(change >= 0 ? .tidexSuccess : .tidexError)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((change >= 0 ? Color.tidexSuccess : Color.tidexError).opacity(0.15))
                    .cornerRadius(8)
                }
            }

            // Main amount
            let displayAmount = taxEnabled ? (net ?? gross) : gross
            if displayAmount > 0 {
                Text(formatCurrency(displayAmount))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.tidexTextPrimary)
            } else {
                Text("—— kr")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.tidexTextMuted)
            }

            // Gross before tax (if tax enabled)
            if taxEnabled && gross > 0 {
                Text("\(localization.string("dashboard.gross")): \(formatCurrency(gross))")
                    .font(.system(size: 12))
                    .foregroundColor(.tidexTextMuted)
            }

            Divider()
                .background(Color.tidexBorderSubtle)

            // Shift counts
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.tidexSuccess)
                    Text("\(shiftCount) \(shiftCount == 1 ? localization.string("dashboard.shift") : localization.string("dashboard.shifts"))")
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextSecondary)
                }

                if plannedCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 14))
                            .foregroundColor(.tidexBlue)
                        Text("\(plannedCount) \(localization.string("dashboard.planned"))")
                            .font(.system(size: 14))
                            .foregroundColor(.tidexTextSecondary)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(16)
    }

    // MARK: - Formatting

    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "NOK"
        formatter.currencySymbol = "kr "
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale(identifier: "nb_NO")
        return formatter.string(from: NSNumber(value: amount)) ?? "kr 0"
    }
}

#Preview {
    VStack(spacing: 16) {
        // With tax and positive change
        TotalCard(
            gross: 15000,
            net: 11100,
            shiftCount: 8,
            plannedCount: 3,
            percentageChange: 12.5,
            taxEnabled: true
        )

        // Without tax and negative change
        TotalCard(
            gross: 12000,
            net: nil,
            shiftCount: 5,
            plannedCount: 0,
            percentageChange: -8.2,
            taxEnabled: false
        )

        // No earnings yet
        TotalCard(
            gross: 0,
            net: nil,
            shiftCount: 0,
            plannedCount: 5,
            percentageChange: nil,
            taxEnabled: false
        )
    }
    .padding()
    .background(Color.tidexDarkBackground)
    .environment(\.localization, LocalizationManager.shared)
}
