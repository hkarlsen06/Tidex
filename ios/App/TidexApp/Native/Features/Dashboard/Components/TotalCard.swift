import SwiftUI

/// Card displaying current month's total earnings
/// Design matches OfflineTotalCard from the Capacitor app
struct TotalCard: View {
    let gross: Double
    let net: Double?
    let shiftCount: Int
    let plannedCount: Int
    let percentageChange: Double?
    let taxEnabled: Bool

    @Environment(\.localization) private var localization

    // MARK: - Computed Properties

    private var mainDisplayValue: Double {
        taxEnabled ? (net ?? gross) : gross
    }

    private var showDashes: Bool {
        mainDisplayValue == 0
    }

    private var hasChange: Bool {
        percentageChange != nil && percentageChange != 0
    }

    private var isPositive: Bool {
        (percentageChange ?? 0) >= 0
    }

    private var displayPercentage: Double {
        abs(percentageChange ?? 0)
    }

    // MARK: - Subtitle Text

    private var subtitleText: String? {
        if showDashes { return "— — —" }

        let hasGross = taxEnabled && gross > 0 && gross != mainDisplayValue

        if hasGross {
            return "\(formatCurrency(gross)) \(localization.string("dashboard.beforeTax"))"
        }

        if shiftCount > 0 {
            let shiftsLabel = shiftCount == 1
                ? localization.string("dashboard.shift")
                : localization.string("dashboard.shifts")
            return "\(shiftCount) \(shiftsLabel)"
        }

        if plannedCount > 0 {
            let plannedLabel = plannedCount == 1
                ? localization.string("dashboard.shiftPlanned")
                : localization.string("dashboard.shiftsPlanned")
            return "\(plannedCount) \(plannedLabel)"
        }

        return nil
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 4) {
            // Percentage change indicator (top)
            percentageIndicator

            // Main total display (large centered)
            mainAmountDisplay

            // Subtitle row
            if let subtitle = subtitleText {
                Text(subtitle)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(.tidexTextSecondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.tidexSurfacePrimary)
        )
    }

    // MARK: - Subviews

    @ViewBuilder
    private var percentageIndicator: some View {
        HStack(spacing: 4) {
            if hasChange {
                Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                    .font(.system(size: 14, weight: .semibold))
            }
            Text(String(format: "%.0f%%", displayPercentage))
                .font(.system(size: 17, weight: .semibold))
        }
        .foregroundColor(hasChange ? (isPositive ? .tidexBlue : .tidexTextSecondary) : .tidexTextMuted)
    }

    @ViewBuilder
    private var mainAmountDisplay: some View {
        if showDashes {
            Text("— — —")
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.tidexBlue)
        } else {
            Text(formatCurrency(mainDisplayValue))
                .font(.system(size: 48, weight: .bold))
                .foregroundColor(.tidexBlue)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
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
    VStack(spacing: 12) {
        // With tax and positive change
        TotalCard(
            gross: 15000,
            net: 12500,
            shiftCount: 8,
            plannedCount: 3,
            percentageChange: 15,
            taxEnabled: true
        )

        // Without tax and negative change
        TotalCard(
            gross: 12000,
            net: nil,
            shiftCount: 5,
            plannedCount: 0,
            percentageChange: -8,
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
    .padding(.horizontal, 24)
    .background(Color.tidexDarkBackground)
    .environment(\.localization, LocalizationManager.shared)
}
