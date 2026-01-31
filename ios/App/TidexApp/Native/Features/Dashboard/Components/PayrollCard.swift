import SwiftUI

/// Card displaying previous month's earnings and payroll information
/// Design matches NextPayrollCard from the Next.js app
struct PayrollCard: View {
    let payrollDate: Date
    let label: String
    let gross: Double
    let net: Double?
    let tax: Double?
    let taxEnabled: Bool
    /// Progress through the month until payroll (0-100), shows a subtle progress bar when provided
    var progress: Double?
    /// When true, shows skeleton state with shimmer animation (for loading)
    var isLoading: Bool = false

    @Environment(\.localization) private var localization
    @Environment(\.userCurrency) private var currency

    /// Animated progress value for smooth entrance animation
    @State private var animatedProgress: Double = 0

    // MARK: - Computed Properties

    private var isPayrollToday: Bool {
        Calendar.current.isDateInToday(payrollDate)
    }

    private var showBreakdown: Bool {
        taxEnabled && (tax ?? 0) > 0
    }

    private var hasPayout: Bool {
        !isLoading && gross > 0
    }

    // MARK: - Body

    /// Whether to show the progress bar (valid progress between 1-100)
    private var hasProgress: Bool {
        guard let progress = progress else { return false }
        return progress >= 1 && progress <= 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Row 1: Date (left) and amount (right) - center aligned
            HStack(alignment: .center) {
                // Date display
                if isPayrollToday {
                    HStack(spacing: 8) {
                        Text(localization.string("dashboard.today"))
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.tidexTextPrimary)
                        Image(systemName: "party.popper.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.tidexBlue)
                    }
                } else {
                    Text(formattedPayrollDate)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.tidexTextPrimary)
                }

                Spacer()

                // Right side: amount
                if hasPayout {
                    let primaryAmount = taxEnabled ? (net ?? gross) : gross
                    Text(formatCurrency(primaryAmount))
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundColor(.tidexTextPrimary)
                } else {
                    // Skeleton for amount
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.tidexTextMuted.opacity(0.3))
                        .frame(width: 100, height: 20)
                }
            }

            // Row 2: Label (left) and breakdown (right) - center aligned
            HStack(alignment: .center) {
                // Label with calendar icon
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.tidexTextMuted)
                    Text(label)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.tidexTextPrimary)
                }

                Spacer()

                // Breakdown (gross - tax) when tax enabled
                if hasPayout && showBreakdown {
                    HStack(spacing: 4) {
                        Text(formatPlainAmount(gross))
                        Text("−")
                        Text(formatPlainAmount(tax ?? 0))
                    }
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.tidexTextMuted)
                } else if !hasPayout {
                    // Skeleton for breakdown
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.tidexTextMuted.opacity(0.2))
                        .frame(width: 70, height: 12)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .background(Color.tidexSurfacePrimary)
        .overlay(alignment: .leading) {
            // Progress bar overlay - fills from left based on progress
            // Uses Rectangle instead of RoundedRectangle so small widths don't overflow
            // The clipShape on the parent handles the rounded corners
            if hasProgress {
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.tidexBlue.opacity(0.1))
                        .frame(width: geometry.size.width * (animatedProgress / 100))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .tidexCardShadow()
        .shimmer(isActive: isLoading)
        .onChange(of: progress) { _, newValue in
            // Animate to new progress value
            withAnimation(.linear(duration: 1.0)) {
                animatedProgress = newValue ?? 0
            }
        }
        .onAppear {
            // Animate from 0 to current progress on appear (matches CSS animation)
            if let progress = progress, progress >= 1, progress <= 100 {
                withAnimation(.linear(duration: 1.0)) {
                    animatedProgress = progress
                }
            }
        }
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
        CurrencyConfig.format(amount, currency: currency)
    }

    /// Format amount without currency symbol (for breakdown display)
    private func formatPlainAmount(_ amount: Double) -> String {
        CurrencyConfig.formatPlain(amount)
    }
}

#Preview {
    VStack(spacing: 12) {
        // With tax and progress bar
        PayrollCard(
            payrollDate: Date(),
            label: "Neste utbetaling",
            gross: 15800,
            net: 12500,
            tax: 3300,
            taxEnabled: true,
            progress: 65
        )

        // Without tax, no progress
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
