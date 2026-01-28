import SwiftUI
import UIKit

// MARK: - Wage Snapshot Editor Sheet

/// Sheet for creating or editing a wage snapshot
struct WageSnapshotEditorSheet: View {
    let mode: PaySettingsViewModel.EditorMode
    let snapshot: WageSnapshot?
    let mostRecentSnapshot: WageSnapshot?
    /// User's currency from settings
    let userCurrency: String
    let onSave: (WageSnapshotEditorInput) async -> Bool
    let onDelete: (WageSnapshot) -> Void
    let onCancel: () -> Void

    @Environment(\.localization) private var localization

    // Form state
    @State private var fromDate: Date = Date()
    @State private var usePreset: Bool = true
    @State private var wageLevel: Int = 1
    @State private var customWage: Double = 200
    @State private var supplements: [OnboardingSupplementRule] = []
    @State private var breakEnabled: Bool = true
    @State private var breakMethod: BreakMethod = .proportional
    @State private var breakThresholdHours: Double = 5.5
    @State private var breakDeductionMinutes: Int = 30
    @State private var taxEnabled: Bool = false
    @State private var taxPercentage: Double = 0

    @State private var isSaving = false
    @State private var errorMessage: String?

    // Supplements editor
    @State private var showingSupplementEditor = false
    @State private var editingSupplementRule: OnboardingSupplementRule?

    private var isBaseline: Bool {
        snapshot?.isBaseline ?? false
    }

    /// Whether tariff option is available (only for Norwegian krone)
    private var showTariffOption: Bool {
        userCurrency == "kr"
    }

    private var currency: String {
        userCurrency
    }

    init(
        mode: PaySettingsViewModel.EditorMode,
        snapshot: WageSnapshot?,
        mostRecentSnapshot: WageSnapshot?,
        userCurrency: String = "kr",
        onSave: @escaping (WageSnapshotEditorInput) async -> Bool,
        onDelete: @escaping (WageSnapshot) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.snapshot = snapshot
        self.mostRecentSnapshot = mostRecentSnapshot
        self.userCurrency = userCurrency
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel

        // Tariff is only available for Norwegian krone
        let canUseTariff = userCurrency == "kr"

        // Initialize form state
        if mode == .edit, let snapshot = snapshot {
            // Editing existing snapshot
            if let fromDateString = snapshot.from_date,
               let date = ISO8601DateFormatter.dateFromDateOnlyString(fromDateString) {
                _fromDate = State(initialValue: date)
            }
            // Only use preset if tariff is available AND snapshot uses tariff
            _usePreset = State(initialValue: canUseTariff && snapshot.wage_level != nil)
            _wageLevel = State(initialValue: snapshot.wage_level ?? 1)
            _customWage = State(initialValue: snapshot.hourly_wage)
            _supplements = State(initialValue: snapshot.supplements.rules.map { OnboardingSupplementRule(from: $0) })
            _breakEnabled = State(initialValue: snapshot.effectiveBreakEnabled)
            _breakMethod = State(initialValue: snapshot.breakMethod)
            _breakThresholdHours = State(initialValue: snapshot.effectiveBreakThresholdHours)
            _breakDeductionMinutes = State(initialValue: snapshot.effectiveBreakDeductionMinutes)
            _taxEnabled = State(initialValue: snapshot.effectiveTaxEnabled)
            _taxPercentage = State(initialValue: snapshot.effectiveTaxPercentage)
        } else if let mostRecent = mostRecentSnapshot {
            // Creating new snapshot - prefill from most recent
            _fromDate = State(initialValue: Date())
            // Only use preset if tariff is available AND most recent uses tariff
            _usePreset = State(initialValue: canUseTariff && mostRecent.wage_level != nil)
            _wageLevel = State(initialValue: mostRecent.wage_level ?? 1)
            _customWage = State(initialValue: mostRecent.hourly_wage)
            _supplements = State(initialValue: mostRecent.supplements.rules.map { OnboardingSupplementRule(from: $0) })
            _breakEnabled = State(initialValue: mostRecent.effectiveBreakEnabled)
            _breakMethod = State(initialValue: mostRecent.breakMethod)
            _breakThresholdHours = State(initialValue: mostRecent.effectiveBreakThresholdHours)
            _breakDeductionMinutes = State(initialValue: mostRecent.effectiveBreakDeductionMinutes)
            _taxEnabled = State(initialValue: mostRecent.effectiveTaxEnabled)
            _taxPercentage = State(initialValue: mostRecent.effectiveTaxPercentage)
        } else {
            // No existing snapshot - default to custom wage if tariff not available
            _usePreset = State(initialValue: canUseTariff)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tidexBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Date section (or baseline indicator)
                        dateSection

                        Divider()
                            .padding(.horizontal)

                        // Wage source selector
                        WageSourceSelector(
                            usePreset: $usePreset,
                            wageLevel: $wageLevel,
                            customWage: $customWage,
                            currency: currency,
                            showTariffOption: showTariffOption
                        )
                        .padding(.horizontal)

                        Divider()
                            .padding(.horizontal)

                        // Supplements section
                        supplementsSection

                        Divider()
                            .padding(.horizontal)

                        // Break deduction section
                        BreakDeductionSection(
                            enabled: $breakEnabled,
                            method: $breakMethod,
                            thresholdHours: $breakThresholdHours,
                            deductionMinutes: $breakDeductionMinutes
                        )
                        .padding(.horizontal)

                        Divider()
                            .padding(.horizontal)

                        // Tax deduction section
                        TaxDeductionSection(
                            enabled: $taxEnabled,
                            percentage: $taxPercentage
                        )
                        .padding(.horizontal)

                        // Error message
                        if let error = errorMessage {
                            errorBanner(error)
                                .padding(.horizontal)
                        }

                        // Bottom spacing for delete button
                        if mode == .edit && !isBaseline {
                            Spacer()
                                .frame(height: 80)
                        } else {
                            Spacer()
                                .frame(height: 24)
                        }
                    }
                    .padding(.vertical, 24)
                }
                .scrollDismissesKeyboard(.interactively)

                // Delete button at bottom
                if mode == .edit && !isBaseline {
                    VStack {
                        Spacer()

                        deleteButton
                            .padding(.horizontal, 24)
                            .padding(.bottom, 32)
                            .background(
                                LinearGradient(
                                    colors: [Color.tidexBackground.opacity(0), Color.tidexBackground],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 100)
                                .allowsHitTesting(false)
                            )
                    }
                }
            }
            .navigationTitle(
                mode == .create
                    ? localization.string("settings.pay.editor.createTitle")
                    : localization.string("settings.pay.editor.editTitle")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localization.string("common.cancel")) {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localization.string("common.save")) {
                        Task { await save() }
                    }
                    .disabled(!canSave || isSaving)
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingSupplementEditor) {
                SupplementRuleEditor(
                    rule: editingSupplementRule,
                    currency: currency,
                    onSave: { rule in
                        if let editingRule = editingSupplementRule {
                            // Update existing rule
                            if let index = supplements.firstIndex(where: { $0.id == editingRule.id }) {
                                supplements[index] = rule
                            }
                        } else {
                            // Add new rule
                            supplements.append(rule)
                        }
                        showingSupplementEditor = false
                        editingSupplementRule = nil
                    },
                    onCancel: {
                        showingSupplementEditor = false
                        editingSupplementRule = nil
                    }
                )
            }
        }
    }

    // MARK: - Can Save

    private var canSave: Bool {
        if usePreset {
            return true // Tariff always valid
        } else {
            return customWage > 0
        }
    }

    // MARK: - Date Section

    @ViewBuilder
    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localization.string("settings.pay.editor.fromDateLabel"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            if isBaseline {
                // Baseline indicator
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.tidexWarning)

                    Text(localization.string("settings.pay.editor.baselineIndicator"))
                        .font(.system(size: 15))
                        .foregroundColor(.tidexTextPrimary)

                    Spacer()
                }
                .padding(12)
                .background(Color.tidexWarning.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Text(localization.string("settings.pay.editor.baselineHelp"))
                    .font(.system(size: 12))
                    .foregroundColor(.tidexTextMuted)
            } else {
                // Date picker
                DatePicker(
                    "",
                    selection: $fromDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(.tidexBrandPrimary)
                .padding(12)
                .background(Color.tidexSurfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(localization.string("settings.pay.editor.fromDateHelp"))
                    .font(.system(size: 12))
                    .foregroundColor(.tidexTextMuted)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Supplements Section

    @ViewBuilder
    private var supplementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localization.string("settings.pay.editor.supplementsTitle"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)

                Spacer()

                if !usePreset {
                    Button(action: {
                        editingSupplementRule = nil
                        showingSupplementEditor = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.tidexBlue)
                    }
                }
            }

            if usePreset {
                // Read-only preset supplements
                Text(localization.string("settings.pay.editor.supplementsTariff"))
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextSecondary)

                ForEach(PayrollCalculator.presetSupplementRules.indices, id: \.self) { index in
                    presetSupplementRow(PayrollCalculator.presetSupplementRules[index])
                }
            } else {
                // Editable custom supplements
                if supplements.isEmpty {
                    Text(localization.string("settings.pay.editor.supplementsEmpty"))
                        .font(.system(size: 13))
                        .foregroundColor(.tidexTextMuted)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.tidexSurfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    ForEach(supplements) { rule in
                        customSupplementRow(rule)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func presetSupplementRow(_ rule: SupplementRule) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatDays(rule.days))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextPrimary)

                Text("\(rule.from) - \(rule.to)")
                    .font(.system(size: 12))
                    .foregroundColor(.tidexTextSecondary)
            }

            Spacer()

            Text(formatRuleValue(rule))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.tidexBrandPrimary)
        }
        .padding(Spacing.xs)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func customSupplementRow(_ rule: OnboardingSupplementRule) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.daysDescription(locale: localization.currentLocale))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.tidexTextPrimary)

                Text(rule.timeDescription)
                    .font(.system(size: 12))
                    .foregroundColor(.tidexTextSecondary)
            }

            Spacer()

            Text(rule.valueDescription(locale: localization.currentLocale, currency: currency))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.tidexBrandPrimary)

            // Edit button
            Button(action: {
                editingSupplementRule = rule
                showingSupplementEditor = true
            }) {
                Image(systemName: "pencil")
                    .font(.system(size: 14))
                    .foregroundColor(.tidexTextMuted)
            }

            // Delete button
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation {
                    supplements.removeAll { $0.id == rule.id }
                }
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(.tidexError)
            }
        }
        .padding(Spacing.xs)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func formatDays(_ days: [Int]) -> String {
        let isNorwegian = localization.currentLocale == .norwegian
        let sortedDays = days.sorted()

        if sortedDays == [1, 2, 3, 4, 5] {
            return isNorwegian ? "Hverdager" : "Weekdays"
        } else if sortedDays == [6, 7] || sortedDays == [0, 6] {
            return isNorwegian ? "Helg" : "Weekend"
        } else if sortedDays == Array(1...7) || sortedDays == Array(0...6) {
            return isNorwegian ? "Alle dager" : "All days"
        }

        let dayNames = isNorwegian
            ? ["Søn", "Man", "Tir", "Ons", "Tor", "Fre", "Lør"]
            : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

        return sortedDays.map { dayNames[$0 % 7] }.joined(separator: ", ")
    }

    private func formatRuleValue(_ rule: SupplementRule) -> String {
        if let rate = rule.rate {
            return "+\(Int(rate)) kr/t"
        } else if let percent = rule.percent {
            return "+\(Int(percent))%"
        }
        return ""
    }

    // MARK: - Error Banner

    @ViewBuilder
    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.tidexError)

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.tidexError)

            Spacer()
        }
        .padding(12)
        .background(Color.tidexError.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Delete Button

    @ViewBuilder
    private var deleteButton: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if let snapshot = snapshot {
                onDelete(snapshot)
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                    .font(.system(size: 16))

                Text(localization.string("settings.pay.editor.delete"))
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Spacing.buttonHeight)
            .background(Color.tidexError)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Save

    private func save() async {
        isSaving = true
        errorMessage = nil

        // Build input - only use preset if tariff is available and selected
        let effectiveUsePreset = showTariffOption && usePreset

        let resolvedHourlyWage = effectiveUsePreset
            ? (PayrollCalculator.presetWageRates[String(wageLevel)] ?? 184.54)
            : customWage

        let resolvedWageLevel = effectiveUsePreset ? wageLevel : nil

        let resolvedSupplements: SupplementRulesSnapshot
        if effectiveUsePreset {
            resolvedSupplements = SupplementRulesSnapshot(rules: PayrollCalculator.presetSupplementRules)
        } else {
            resolvedSupplements = SupplementRulesSnapshot(rules: supplements.map { $0.toSupplementRule() })
        }

        let input = WageSnapshotEditorInput(
            fromDate: isBaseline ? nil : fromDate,
            hourlyWage: resolvedHourlyWage,
            wageLevel: resolvedWageLevel,
            supplements: resolvedSupplements,
            taxEnabled: taxEnabled,
            taxPercentage: taxPercentage,
            breakEnabled: breakEnabled,
            breakMethod: breakMethod,
            breakThresholdHours: breakThresholdHours,
            breakDeductionMinutes: breakDeductionMinutes
        )

        let success = await onSave(input)

        if !success {
            // Error message should be set by the view model
            isSaving = false
        }
    }
}

// MARK: - OnboardingSupplementRule Extension

extension OnboardingSupplementRule {
    /// Create from a SupplementRule
    init(from rule: SupplementRule) {
        // Convert day format: SupplementRule uses 0-6 (Sunday-Saturday), OnboardingSupplementRule uses 1-7 (Monday-Sunday)
        let convertedDays = Set(rule.days.map { day -> Int in
            // Convert 0-6 (Sun-Sat) to 1-7 (Mon-Sun)
            if day == 0 { return 7 } // Sunday
            else { return day } // Mon-Sat stay as 1-6
        })

        self.id = UUID()
        self.days = convertedDays
        self.fromTime = rule.from
        self.toTime = rule.to
        self.type = rule.rate != nil ? .fixed : .percent
        self.value = rule.rate ?? rule.percent ?? 0
    }
}

// MARK: - WageSnapshotEditorInput Extension

extension WageSnapshotEditorInput {
    /// Create input with explicit values (for editor sheet)
    init(
        fromDate: Date?,
        hourlyWage: Double,
        wageLevel: Int?,
        supplements: SupplementRulesSnapshot,
        taxEnabled: Bool,
        taxPercentage: Double,
        breakEnabled: Bool,
        breakMethod: BreakMethod,
        breakThresholdHours: Double,
        breakDeductionMinutes: Int
    ) {
        self.fromDate = fromDate
        self.hourlyWage = hourlyWage
        self.wageLevel = wageLevel
        self.supplements = supplements
        self.taxEnabled = taxEnabled
        self.taxPercentage = taxPercentage
        self.breakEnabled = breakEnabled
        self.breakMethod = breakMethod
        self.breakThresholdHours = breakThresholdHours
        self.breakDeductionMinutes = breakDeductionMinutes
    }
}

// MARK: - Preview

#Preview("Create Mode") {
    WageSnapshotEditorSheet(
        mode: .create,
        snapshot: nil,
        mostRecentSnapshot: nil,
        onSave: { _ in true },
        onDelete: { _ in },
        onCancel: {}
    )
    .environment(\.localization, LocalizationManager.shared)
}
