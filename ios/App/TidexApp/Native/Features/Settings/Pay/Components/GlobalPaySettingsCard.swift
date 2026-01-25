import SwiftUI
import UIKit

// MARK: - Global Pay Settings Card

/// Card for editing global pay settings: monthly goal, payroll day, half-tax month
struct GlobalPaySettingsCard: View {
    let settings: UserSettings?
    let onUpdateMonthlyGoal: (Int?) -> Void
    let onUpdatePayrollDay: (Int) -> Void
    let onUpdateHalfTaxMonth: (Int?) async -> Void

    @Environment(\.localization) private var localization

    @State private var monthlyGoalText: String = ""
    @State private var payrollDay: Int = 1
    @State private var halfTaxMonth: Int? = nil
    @State private var isInitialized = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section header
            Text(localization.string("settings.pay.global.title"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)

            // Monthly goal
            monthlyGoalInput

            // Payroll day
            payrollDayInput

            // Half-tax month
            halfTaxMonthPicker
        }
        .padding(16)
        .background(Color.tidexSurfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            initializeFromSettings()
        }
        .onChange(of: settings) { _, _ in
            // Only re-initialize if settings changed externally (not from our edits)
            if !isInitialized {
                initializeFromSettings()
            }
        }
    }

    private func initializeFromSettings() {
        guard !isInitialized else { return }

        if let goal = settings?.monthly_goal {
            monthlyGoalText = "\(goal)"
        } else {
            monthlyGoalText = ""
        }

        payrollDay = settings?.effectivePayrollDay ?? 1
        halfTaxMonth = settings?.half_tax_month

        isInitialized = true
    }

    // MARK: - Monthly Goal Input

    @ViewBuilder
    private var monthlyGoalInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localization.string("settings.pay.global.monthlyGoal"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            HStack {
                TextField(
                    localization.string("settings.pay.global.monthlyGoalPlaceholder"),
                    text: $monthlyGoalText
                )
                .keyboardType(.numberPad)
                .font(.system(size: 16))
                .foregroundColor(.tidexTextPrimary)
                .onChange(of: monthlyGoalText) { _, newValue in
                    // Filter to digits only
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered != newValue {
                        monthlyGoalText = filtered
                    }

                    // Debounced save
                    if let value = Int(filtered), value > 0 {
                        onUpdateMonthlyGoal(value)
                    } else if filtered.isEmpty {
                        onUpdateMonthlyGoal(nil)
                    }
                }

                Text("kr")
                    .font(.system(size: 14))
                    .foregroundColor(.tidexTextMuted)
            }
            .padding(12)
            .background(Color.tidexSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(localization.string("settings.pay.global.monthlyGoalHelper"))
                .font(.system(size: 12))
                .foregroundColor(.tidexTextMuted)
        }
    }

    // MARK: - Payroll Day Input

    @ViewBuilder
    private var payrollDayInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localization.string("settings.pay.global.payrollDay"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            HStack {
                Text(formatPayrollDay(payrollDay))
                    .font(.system(size: 16))
                    .foregroundColor(.tidexTextPrimary)

                Spacer()

                Picker("", selection: $payrollDay) {
                    ForEach(1...31, id: \.self) { day in
                        Text("\(day)").tag(day)
                    }
                }
                .pickerStyle(.menu)
                .tint(.tidexBlue)
                .onChange(of: payrollDay) { _, newValue in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onUpdatePayrollDay(newValue)
                }
            }
            .padding(12)
            .background(Color.tidexSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(localization.string("settings.pay.global.payrollDayHelper"))
                .font(.system(size: 12))
                .foregroundColor(.tidexTextMuted)
        }
    }

    private func formatPayrollDay(_ day: Int) -> String {
        let isNorwegian = localization.currentLocale == .norwegian
        if isNorwegian {
            return "\(day). hver måned"
        } else {
            let suffix: String
            switch day {
            case 1, 21, 31: suffix = "st"
            case 2, 22: suffix = "nd"
            case 3, 23: suffix = "rd"
            default: suffix = "th"
            }
            return "\(day)\(suffix) of each month"
        }
    }

    // MARK: - Half-Tax Month Picker

    @ViewBuilder
    private var halfTaxMonthPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localization.string("settings.pay.global.halfTaxMonth"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            Picker("", selection: $halfTaxMonth) {
                Text(localization.string("settings.pay.global.halfTaxMonthOff"))
                    .tag(nil as Int?)
                Text(localization.string("settings.pay.global.halfTaxMonthNovember"))
                    .tag(11 as Int?)
                Text(localization.string("settings.pay.global.halfTaxMonthDecember"))
                    .tag(12 as Int?)
            }
            .pickerStyle(.menu)
            .tint(.tidexBlue)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.tidexSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onChange(of: halfTaxMonth) { _, newValue in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task {
                    await onUpdateHalfTaxMonth(newValue)
                }
            }

            Text(localization.string("settings.pay.global.halfTaxMonthHelper"))
                .font(.system(size: 12))
                .foregroundColor(.tidexTextMuted)
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        GlobalPaySettingsCard(
            settings: UserSettings.defaults(for: "test"),
            onUpdateMonthlyGoal: { _ in },
            onUpdatePayrollDay: { _ in },
            onUpdateHalfTaxMonth: { _ in }
        )
        .padding()
    }
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
