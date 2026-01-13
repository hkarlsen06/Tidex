import SwiftUI

/// Card displaying previous month's earnings and payroll information
struct PayrollCard: View {
    let payrollDate: Date
    let label: String
    let gross: Double
    let net: Double?
    let tax: Double?
    let taxEnabled: Bool

    @Environment(\.localization) private var localization

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextSecondary)

                    Text(formattedPayrollDate)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.tidexTextPrimary)
                }

                Spacer()

                Image(systemName: "banknote")
                    .font(.system(size: 24))
                    .foregroundColor(.tidexBlue)
            }

            Divider()
                .background(Color.tidexBorderSubtle)

            // Amount display
            if taxEnabled, let netAmount = net {
                // Show net as primary, gross as secondary
                VStack(alignment: .leading, spacing: 4) {
                    Text(formatCurrency(netAmount))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.tidexTextPrimary)

                    HStack(spacing: 8) {
                        Text("\(localization.string("dashboard.gross")): \(formatCurrency(gross))")
                            .font(.system(size: 12))
                            .foregroundColor(.tidexTextMuted)

                        if let taxAmount = tax {
                            Text("\(localization.string("dashboard.tax")): \(formatCurrency(taxAmount))")
                                .font(.system(size: 12))
                                .foregroundColor(.tidexTextMuted)
                        }
                    }
                }
            } else {
                // Show gross only
                if gross > 0 {
                    Text(formatCurrency(gross))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.tidexTextPrimary)
                } else {
                    Text("—— kr")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.tidexTextMuted)
                }
            }
        }
        .padding(20)
        .background(Color.tidexSurfacePrimary)
        .cornerRadius(16)
    }

    // MARK: - Formatting

    private var formattedPayrollDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localization.currentLocale == .norwegian ? "nb_NO" : "en_US")
        formatter.dateFormat = "d. MMMM"
        return formatter.string(from: payrollDate)
    }

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
        // With tax
        PayrollCard(
            payrollDate: Date(),
            label: "Neste utbetaling",
            gross: 25000,
            net: 18500,
            tax: 6500,
            taxEnabled: true
        )

        // Without tax
        PayrollCard(
            payrollDate: Date(),
            label: "Forrige utbetaling",
            gross: 22000,
            net: nil,
            tax: nil,
            taxEnabled: false
        )

        // No earnings
        PayrollCard(
            payrollDate: Date(),
            label: "Neste utbetaling",
            gross: 0,
            net: nil,
            tax: nil,
            taxEnabled: false
        )
    }
    .padding()
    .background(Color.tidexDarkBackground)
    .environment(\.localization, LocalizationManager.shared)
}
