import SwiftUI
import UIKit

// MARK: - Global Pay Settings Card

/// Card for editing global pay settings: currency, monthly goal, payroll day, half-tax month
struct GlobalPaySettingsCard: View {
    let settings: UserSettings?
    /// Whether currency can be changed (false if tariff snapshots exist)
    let canChangeCurrency: Bool
    let onUpdateMonthlyGoal: (Int?) -> Void
    let onUpdatePayrollDay: (Int) -> Void
    let onUpdateHalfTaxMonth: (Int?) async -> Void
    let onUpdateCurrency: (String) async -> Void

    @Environment(\.localization) private var localization

    @State private var currency: String = "kr"
    @State private var monthlyGoalText: String = ""
    @State private var payrollDay: Int = 1
    @State private var halfTaxMonth: Int? = nil
    @State private var isInitialized = false
    @State private var showingCurrencyPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section header
            Text(localization.string("settings.pay.global.title"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)

            // Currency selector
            currencyInput

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
        .sheet(isPresented: $showingCurrencyPicker) {
            CurrencyPickerSheet(
                selectedCurrency: $currency,
                isPresented: $showingCurrencyPicker,
                onSelect: { newCurrency in
                    Task {
                        await onUpdateCurrency(newCurrency)
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func initializeFromSettings() {
        guard !isInitialized else { return }

        currency = settings?.currency ?? "kr"

        if let goal = settings?.monthly_goal {
            monthlyGoalText = "\(goal)"
        } else {
            monthlyGoalText = ""
        }

        payrollDay = settings?.effectivePayrollDay ?? 1
        halfTaxMonth = settings?.half_tax_month

        isInitialized = true
    }

    // MARK: - Currency Input

    @ViewBuilder
    private var currencyInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localization.string("settings.pay.global.currency"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            Button(action: {
                if canChangeCurrency {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingCurrencyPicker = true
                }
            }) {
                HStack {
                    Text(CurrencyConfig.get(currency).label)
                        .font(.system(size: 16))
                        .foregroundColor(canChangeCurrency ? .tidexTextPrimary : .tidexTextMuted)

                    Spacer()

                    if canChangeCurrency {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.tidexTextMuted)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.tidexTextMuted)
                    }
                }
                .padding(12)
                .background(Color.tidexSurfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canChangeCurrency)

            if !canChangeCurrency {
                Text(localization.currentLocale == .norwegian
                     ? "Valuta kan ikke endres når du har lønnstrinn-innstillinger"
                     : "Currency cannot be changed when using tariff wage settings")
                    .font(.system(size: 12))
                    .foregroundColor(.tidexTextMuted)
            }
        }
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

                Text(currency)
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

// MARK: - Currency Picker Sheet

/// Sheet for selecting a currency
private struct CurrencyPickerSheet: View {
    @Binding var selectedCurrency: String
    @Binding var isPresented: Bool
    let onSelect: (String) -> Void

    @Environment(\.localization) private var localization

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tidexBackground
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(CurrencyConfig.groups) { group in
                            Section {
                                ForEach(group.options) { option in
                                    CurrencyRow(
                                        option: option,
                                        isSelected: selectedCurrency == option.value,
                                        action: {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            selectedCurrency = option.value
                                            onSelect(option.value)
                                            isPresented = false
                                        }
                                    )
                                }
                            } header: {
                                HStack {
                                    Text(group.label)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.tidexTextMuted)
                                        .textCase(.uppercase)
                                    Spacer()
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Color.tidexBackground)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .navigationTitle(localization.string("settings.pay.global.currencyTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.string("common.cancel")) {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Currency Row

private struct CurrencyRow: View {
    let option: CurrencyOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(option.label)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.tidexTextPrimary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.tidexBrandPrimary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(isSelected ? Color.tidexBrandPrimary.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        GlobalPaySettingsCard(
            settings: UserSettings.defaults(for: "test"),
            canChangeCurrency: true,
            onUpdateMonthlyGoal: { _ in },
            onUpdatePayrollDay: { _ in },
            onUpdateHalfTaxMonth: { _ in },
            onUpdateCurrency: { _ in }
        )
        .padding()
    }
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
