import SwiftUI

/// Card displaying previous month's earnings and payroll information
/// Design matches OfflinePayrollCard from the Capacitor app
struct PayrollCard: View {
    let payrollDate: Date
    let label: String
    let gross: Double
    let net: Double?
    let tax: Double?
    let taxEnabled: Bool

    @Environment(\.localization) private var localization

    // MARK: - Computed Properties

    private var isPayrollToday: Bool {
        Calendar.current.isDateInToday(payrollDate)
    }

    private var showBreakdown: Bool {
        taxEnabled && (tax ?? 0) > 0
    }

    private var hasPayout: Bool {
        gross > 0
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: showBreakdown ? .top : .center, spacing: 16) {
            // Left side: date and label
            VStack(alignment: .leading, spacing: 4) {
                // Date display
                if isPayrollToday {
                    HStack(spacing: 8) {
                        Text(localization.string("dashboard.today"))
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.tidexTextPrimary)
                        Image(systemName: "party.popper.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.tidexBlue)
                    }
                } else {
                    Text(formattedPayrollDate)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.tidexTextPrimary)
                }

                // Label with calendar icon
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.tidexTextMuted)
                    Text(label)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.tidexTextPrimary)
                }
            }

            Spacer()

            // Right side: amount and breakdown
            if hasPayout {
                VStack(alignment: .trailing, spacing: 2) {
                    // Net/gross amount (primary display)
                    let primaryAmount = taxEnabled ? (net ?? gross) : gross
                    Text(formatCurrency(primaryAmount))
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundColor(.tidexTextPrimary)

                    // Breakdown (gross - tax) when tax enabled
                    if showBreakdown {
                        HStack(spacing: 4) {
                            Text(formatCurrency(gross))
                            Text("−")
                            Text(formatCurrency(tax ?? 0))
                        }
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.tidexTextMuted)
                    }
                }
            } else {
                // No payout placeholder
                VStack(alignment: .trailing, spacing: 2) {
                    Text("—— kr")
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundColor(.tidexTextMuted)
                    Text("——")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.tidexTextMuted)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color.tidexSurfacePrimary)
        )
    }

    // MARK: - Formatting

    private var formattedPayrollDate: String {
        let formatter = DateFormatter()
        let isNorwegian = localization.currentLocale == .norwegian
        formatter.locale = Locale(identifier: isNorwegian ? "nb_NO" : "en_US")

        // Get day number and month name
        let dayFormatter = DateFormatter()
        dayFormatter.locale = formatter.locale
        dayFormatter.dateFormat = "d"
        let day = dayFormatter.string(from: payrollDate)

        let monthFormatter = DateFormatter()
        monthFormatter.locale = formatter.locale
        monthFormatter.dateFormat = "MMMM"
        let month = monthFormatter.string(from: payrollDate).lowercased()

        if isNorwegian {
            return "\(day). \(month)"
        } else {
            return "\(month.capitalized) \(day)"
        }
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
    VStack(spacing: 12) {
        // With tax
        PayrollCard(
            payrollDate: Date(),
            label: "Neste utbetaling",
            gross: 15800,
            net: 12500,
            tax: 3300,
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
    .padding(.horizontal, 24)
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
