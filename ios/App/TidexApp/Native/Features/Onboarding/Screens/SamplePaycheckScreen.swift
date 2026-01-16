import SwiftUI
import UIKit

/// Screen 2: Sample Paycheck (THE AHA MOMENT)
/// Demonstrates core value with fake/sample data + interactive industry selector
struct SamplePaycheckScreen: View {
    @Environment(\.localization) private var localization
    @State private var selectedIndustry: SampleIndustry = .retail
    @State private var hasAppeared = false

    private var sampleData: SamplePaycheckData {
        selectedIndustry.sampleData
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 40)

            // Header
            Text(localization.string("onboarding.paycheck.title"))
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)

            Spacer()
                .frame(height: 16)

            // Large animated total
            CurrencyCountUpText(amount: sampleData.gross, duration: 0.8)
                .font(.system(size: 52, weight: .bold))
                .foregroundColor(.tidexBlue)
                .id(selectedIndustry) // Force re-render on industry change

            Spacer()
                .frame(height: 24)

            // Industry picker
            IndustryPicker(selection: $selectedIndustry)
                .padding(.horizontal, 32)

            Spacer()
                .frame(height: 32)

            // Breakdown card
            breakdownCard
                .padding(.horizontal, 24)
                .offset(y: hasAppeared ? 0 : 40)
                .opacity(hasAppeared ? 1 : 0)

            Spacer()
                .frame(height: 16)

            // Sample label
            Text(localization.string("onboarding.paycheck.sample_label"))
                .font(.system(size: 13))
                .foregroundColor(.tidexTextMuted)
                .multilineTextAlignment(.center)
                .opacity(hasAppeared ? 1 : 0)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.3)) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Breakdown Card

    @ViewBuilder
    private var breakdownCard: some View {
        VStack(spacing: 0) {
            breakdownRow(
                label: localization.string("onboarding.paycheck.base_pay"),
                amount: sampleData.basePay,
                isPositive: true
            )

            Divider()
                .background(Color.tidexBorderSubtle)

            breakdownRow(
                label: localization.string("onboarding.paycheck.evening"),
                amount: sampleData.eveningSupplements,
                isPositive: true
            )

            Divider()
                .background(Color.tidexBorderSubtle)

            breakdownRow(
                label: localization.string("onboarding.paycheck.weekend"),
                amount: sampleData.weekendBonus,
                isPositive: true
            )

            Divider()
                .background(Color.tidexBorderSubtle)

            breakdownRow(
                label: localization.string("onboarding.paycheck.tax"),
                amount: sampleData.taxDeducted,
                isPositive: false
            )

            Divider()
                .background(Color.tidexBorder)
                .padding(.vertical, 4)

            // Net pay row (highlighted)
            HStack {
                Text(localization.string("onboarding.paycheck.net"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Spacer()

                Text(formatCurrency(sampleData.netPay))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.tidexSuccess)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .background(Color.tidexSurfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.tidexBorderSubtle, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func breakdownRow(label: String, amount: Double, isPositive: Bool) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(.tidexTextSecondary)

            Spacer()

            Text("\(isPositive ? "" : "-")\(formatCurrency(amount))")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(isPositive ? .tidexTextPrimary : .tidexTextSecondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
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
    SamplePaycheckScreen()
        .background(Color.tidexBackground)
        .environment(\.localization, LocalizationManager.shared)
}
