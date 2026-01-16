import SwiftUI
import UIKit

/// Screen 2: Sample Paycheck (THE AHA MOMENT)
/// Demonstrates core value with dynamic data based on hourly rate
struct SamplePaycheckScreen: View {
    @Binding var hourlyRate: Double

    @Environment(\.localization) private var localization
    @State private var showHeader = false
    @State private var showAmount = false
    @State private var showBreakdown = false
    @State private var showSampleLabel = false

    /// Compute sample paycheck data based on hourly rate
    /// Assumes ~120 hours/month with evening/weekend supplements
    private var sampleData: SamplePaycheckData {
        let hoursWorked: Double = 120
        let basePay = hourlyRate * hoursWorked
        let eveningSupplements = hourlyRate * 0.15 * 40  // ~40 evening hours
        let weekendBonus = hourlyRate * 0.20 * 16        // ~16 weekend hours
        let gross = basePay + eveningSupplements + weekendBonus
        let taxDeducted = gross * 0.20                   // ~20% tax
        let netPay = gross - taxDeducted

        return SamplePaycheckData(
            gross: gross,
            basePay: basePay,
            eveningSupplements: eveningSupplements,
            weekendBonus: weekendBonus,
            taxDeducted: taxDeducted,
            netPay: netPay
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 40)

            // Header with entrance animation
            Text(localization.string("onboarding.paycheck.title"))
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)
                .offset(y: showHeader ? 0 : 20)
                .opacity(showHeader ? 1 : 0)

            Spacer()
                .frame(height: 16)

            // Large animated total with entrance animation
            CurrencyCountUpText(amount: sampleData.gross, duration: 0.8)
                .font(.system(size: 52, weight: .bold))
                .foregroundColor(.tidexBlue)
                .scaleEffect(showAmount ? 1 : 0.8)
                .opacity(showAmount ? 1 : 0)

            Spacer()
                .frame(height: 32)

            // Breakdown card with entrance animation
            breakdownCard
                .padding(.horizontal, 24)
                .offset(y: showBreakdown ? 0 : 40)
                .opacity(showBreakdown ? 1 : 0)

            Spacer()
                .frame(height: 16)

            // Sample label with entrance animation
            Text(localization.string("onboarding.paycheck.sample_label"))
                .font(.system(size: 13))
                .foregroundColor(.tidexTextMuted)
                .multilineTextAlignment(.center)
                .offset(y: showSampleLabel ? 0 : 20)
                .opacity(showSampleLabel ? 1 : 0)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Staggered entrance animations for visual flow
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                showHeader = true
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.2)) {
                showAmount = true
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.4)) {
                showBreakdown = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
                showSampleLabel = true
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

    private var isNorwegian: Bool {
        localization.currentLocale == .norwegian
    }

    /// Format currency based on locale
    /// Norwegian: "24 380 kr" (number + kr)
    /// English: "$24,380" ($ + number)
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 0

        if isNorwegian {
            formatter.numberStyle = .decimal
            formatter.locale = Locale(identifier: "nb_NO")
            let number = formatter.string(from: NSNumber(value: amount)) ?? "0"
            return "\(number) kr"
        } else {
            formatter.numberStyle = .currency
            formatter.currencyCode = "USD"
            formatter.currencySymbol = "$"
            formatter.locale = Locale(identifier: "en_US")
            return formatter.string(from: NSNumber(value: amount)) ?? "$0"
        }
    }
}

#Preview {
    SamplePaycheckScreen(hourlyRate: .constant(200))
        .background(Color.tidexBackground)
        .environment(\.localization, LocalizationManager.shared)
}
