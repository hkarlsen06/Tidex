import SwiftUI
import UIKit

/// Screen for configuring break, tax, and payday with progressive accordion
/// Each section expands one at a time for focused input
struct SettingsAccordionScreen: View {
    @Bindable var data: OnboardingData
    let onContinue: () -> Void
    var onBack: (() -> Void)? = nil

    @Environment(\.localization) private var localization
    @State private var currentSection: SettingsSection = .breakDeduction
    @State private var completedSections: Set<SettingsSection> = []
    @State private var showingTaxInput = false
    @State private var taxInputText = ""
    @FocusState private var isTaxInputFocused: Bool
    @State private var showingPaydayInput = false
    @State private var paydayInputText = ""
    @FocusState private var isPaydayInputFocused: Bool

    private enum SettingsSection: Int, CaseIterable {
        case breakDeduction = 0
        case tax = 1
        case payday = 2
    }

    private let payrollDayOptions = [1, 10, 15, 20, 25, 28]
    private let taxPresets: [Double] = [22, 25, 30, 40]

    var body: some View {
        ZStack {
            // Background
            Color.tidexBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Back button (if provided)
                        if let onBack = onBack {
                            HStack {
                                Button(action: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    onBack()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.left")
                                            .font(.system(size: 16, weight: .semibold))
                                        Text(localization.string("common.back"))
                                            .font(.system(size: 16))
                                    }
                                    .foregroundColor(.tidexBlue)
                                }
                                .buttonStyle(.plain)
                                Spacer()
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                            .adaptiveContentWidth()
                        }

                        Spacer()
                            .frame(height: onBack != nil ? 24 : 60)

                        // Header
                        VStack(spacing: 12) {
                            Text(localization.string("onboarding.settings.title"))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.tidexTextPrimary)
                                .multilineTextAlignment(.center)

                            Text(localization.string("onboarding.settings.subtitle"))
                                .font(.system(size: 17))
                                .foregroundColor(.tidexTextSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 32)
                        .adaptiveContentWidth()

                        Spacer()
                            .frame(height: 32)

                        // Accordion sections
                        VStack(spacing: 12) {
                            // Break deduction section
                            breakSection

                            // Tax section
                            taxSection

                            // Payday section
                            paydaySection
                        }
                        .padding(.horizontal, 24)
                        .adaptiveContentWidth()

                        Spacer()
                            .frame(height: 48)
                    }
                }

                // Final continue button (visible when all sections complete)
                if allSectionsComplete {
                    OnboardingButton(
                        title: localization.string("common.continue"),
                        action: {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            onContinue()
                        }
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                    .adaptiveContentWidth()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentSection)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: completedSections)
        }
    }

    private var allSectionsComplete: Bool {
        completedSections.count == SettingsSection.allCases.count
    }

    // MARK: - Break Section

    @ViewBuilder
    private var breakSection: some View {
        AccordionSectionView(
            title: localization.string("onboarding.settings.break.title"),
            summary: breakSummary,
            isExpanded: currentSection == .breakDeduction,
            isComplete: completedSections.contains(.breakDeduction),
            onContinue: {
                completeSection(.breakDeduction)
            }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $data.breakEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localization.string("onboarding.settings.break.enable"))
                            .font(.system(size: 15))
                            .foregroundColor(.tidexTextPrimary)

                        Text(localization.string("onboarding.settings.break.hint"))
                            .font(.system(size: 13))
                            .foregroundColor(.tidexTextMuted)
                    }
                }
                .tint(.tidexBrandPrimary)

                if data.breakEnabled {
                    Text(localization.string("onboarding.settings.break.default"))
                        .font(.system(size: 13))
                        .foregroundColor(.tidexTextSecondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.tidexBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .onTapGesture {
            // Allow tapping if not current section (to expand/edit)
            if currentSection != .breakDeduction {
                withAnimation {
                    currentSection = .breakDeduction
                }
            }
        }
    }

    private var breakSummary: String {
        if data.breakEnabled {
            return localization.string("onboarding.settings.break.enabledSummary")
        } else {
            return localization.string("onboarding.settings.break.disabledSummary")
        }
    }

    // MARK: - Tax Section

    @ViewBuilder
    private var taxSection: some View {
        AccordionSectionView(
            title: localization.string("onboarding.settings.tax.title"),
            summary: taxSummary,
            isExpanded: currentSection == .tax,
            isComplete: completedSections.contains(.tax),
            onContinue: {
                completeSection(.tax)
            }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $data.taxEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localization.string("onboarding.settings.tax.enable"))
                            .font(.system(size: 15))
                            .foregroundColor(.tidexTextPrimary)

                        Text(localization.string("onboarding.settings.tax.hint"))
                            .font(.system(size: 13))
                            .foregroundColor(.tidexTextMuted)
                    }
                }
                .tint(.tidexBrandPrimary)

                if data.taxEnabled {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(localization.string("onboarding.settings.tax.percentage"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.tidexTextSecondary)

                        // Tax preset buttons
                        HStack(spacing: 8) {
                            ForEach(taxPresets, id: \.self) { preset in
                                TaxPresetButton(
                                    value: preset,
                                    isSelected: data.taxPercentage == preset,
                                    action: {
                                        withAnimation {
                                            data.taxPercentage = preset
                                        }
                                    }
                                )
                            }
                        }

                        // Current value display - tappable
                        HStack {
                            if showingTaxInput {
                                // Editable input field
                                HStack(spacing: 4) {
                                    TextField("", text: $taxInputText)
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.tidexBlue)
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.leading)
                                        .focused($isTaxInputFocused)
                                        .frame(width: 60)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.tidexBlue.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(Color.tidexBlue, lineWidth: 2)
                                        )
                                        .onChange(of: isTaxInputFocused) { _, focused in
                                            if !focused {
                                                applyTaxInput()
                                            }
                                        }
                                        .toolbar {
                                            ToolbarItemGroup(placement: .keyboard) {
                                                Spacer()
                                                Button(localization.string("common.done")) {
                                                    applyTaxInput()
                                                }
                                                .fontWeight(.semibold)
                                            }
                                        }

                                    Text("%")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.tidexTextMuted)
                                }
                            } else {
                                // Tappable display
                                Button(action: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    taxInputText = formatTaxValue(data.taxPercentage)
                                    showingTaxInput = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        isTaxInputFocused = true
                                    }
                                }) {
                                    HStack(spacing: 2) {
                                        Text(formatTaxValue(data.taxPercentage))
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundColor(.tidexBlue)
                                            .contentTransition(.numericText())
                                        Text("%")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.tidexTextMuted)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.tidexBlue.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer()
                        }

                        Slider(
                            value: $data.taxPercentage,
                            in: 0...50,
                            step: 1,
                            onEditingChanged: { isEditing in
                                if isEditing {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            }
                        )
                        .tint(.tidexBlue)
                    }
                }
            }
        }
        .onTapGesture {
            // Allow tapping if: already completed (to edit) OR unlocked and not yet completed
            if currentSection != .tax && (completedSections.contains(.tax) || completedSections.contains(.breakDeduction)) {
                withAnimation {
                    currentSection = .tax
                }
            }
        }
        .opacity(completedSections.contains(.breakDeduction) || currentSection == .tax ? 1 : 0.5)
    }

    private var taxSummary: String {
        if data.taxEnabled {
            return "\(Int(data.taxPercentage))%"
        } else {
            return localization.string("onboarding.settings.tax.disabledSummary")
        }
    }

    // MARK: - Payday Section

    @ViewBuilder
    private var paydaySection: some View {
        AccordionSectionView(
            title: localization.string("onboarding.settings.payday.title"),
            summary: paydaySummary,
            isExpanded: currentSection == .payday,
            isComplete: completedSections.contains(.payday),
            onContinue: {
                completeSection(.payday)
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(localization.string("onboarding.settings.payday.hint"))
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextMuted)

                // Horizontal scroll with day options + custom input
                // Overlay with fade gradient to hint there's more content
                ZStack(alignment: .trailing) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(payrollDayOptions, id: \.self) { day in
                                PaydayButton(
                                    day: day,
                                    isLast: day == 28,
                                    isSelected: data.payrollDay == day && !showingPaydayInput,
                                    localization: localization,
                                    action: {
                                        showingPaydayInput = false
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            data.payrollDay = day
                                        }
                                    }
                                )
                            }

                            // Custom day input button/field
                            if showingPaydayInput {
                                HStack(spacing: 4) {
                                    TextField("", text: $paydayInputText)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.tidexBlue)
                                        .keyboardType(.numberPad)
                                        .multilineTextAlignment(.center)
                                        .focused($isPaydayInputFocused)
                                        .frame(width: 44)
                                        .frame(minHeight: 44)
                                        .background(Color.tidexBlue.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(Color.tidexBlue, lineWidth: 2)
                                        )
                                        .onChange(of: isPaydayInputFocused) { _, focused in
                                            if !focused {
                                                applyPaydayInput()
                                            }
                                        }
                                        .toolbar {
                                            ToolbarItemGroup(placement: .keyboard) {
                                                Spacer()
                                                Button(localization.string("common.done")) {
                                                    applyPaydayInput()
                                                }
                                                .fontWeight(.semibold)
                                            }
                                        }
                                }
                            } else {
                                // "Other" button to enter custom day
                                Button(action: {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    paydayInputText = !payrollDayOptions.contains(data.payrollDay) ? "\(data.payrollDay)" : ""
                                    showingPaydayInput = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        isPaydayInputFocused = true
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 12))
                                        Text(localization.string("onboarding.settings.payday.other"))
                                    }
                                    .font(.system(size: 14, weight: !payrollDayOptions.contains(data.payrollDay) ? .semibold : .medium))
                                    .foregroundColor(!payrollDayOptions.contains(data.payrollDay) ? .white : .tidexTextSecondary)
                                    .frame(minWidth: 56, minHeight: 44)
                                    .padding(.horizontal, 8)
                                    .background(!payrollDayOptions.contains(data.payrollDay) ? Color.tidexBrandPrimary : Color.tidexBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(!payrollDayOptions.contains(data.payrollDay) ? Color.clear : Color.tidexBorder, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.trailing, 24) // Extra padding for fade area
                    }

                    // Trailing fade gradient to hint more content
                    LinearGradient(
                        colors: [Color.tidexSurfaceSecondary.opacity(0), Color.tidexSurfaceSecondary],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 32)
                    .allowsHitTesting(false)
                }

                // Show current custom value if not a preset
                if !payrollDayOptions.contains(data.payrollDay) && !showingPaydayInput {
                    Text(localization.string("onboarding.settings.payday.customValue")
                        .replacingOccurrences(of: "{day}", with: "\(data.payrollDay)"))
                        .font(.system(size: 13))
                        .foregroundColor(.tidexBlue)
                }
            }
        }
        .onTapGesture {
            // Allow tapping if: already completed (to edit) OR unlocked and not yet completed
            if currentSection != .payday && (completedSections.contains(.payday) || completedSections.contains(.tax)) {
                withAnimation {
                    currentSection = .payday
                }
            }
        }
        .opacity(completedSections.contains(.tax) || currentSection == .payday ? 1 : 0.5)
    }

    private var paydaySummary: String {
        if data.payrollDay == 28 {
            return localization.string("onboarding.personalize.payday.lastDay")
        } else {
            return "\(data.payrollDay)."
        }
    }

    // MARK: - Helpers

    private func completeSection(_ section: SettingsSection) {
        withAnimation {
            completedSections.insert(section)

            // Move to next section
            switch section {
            case .breakDeduction:
                currentSection = .tax
            case .tax:
                currentSection = .payday
            case .payday:
                // All done - button will appear
                break
            }
        }
    }

    private func formatTaxValue(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.locale = Locale(identifier: "nb_NO")
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func applyTaxInput() {
        // Parse the input, handling both comma and period as decimal separator
        let normalized = taxInputText.replacingOccurrences(of: ",", with: ".")
        if let parsed = Double(normalized) {
            // Clamp to valid range (0-50%)
            let clamped = min(max(parsed, 0), 50)
            let rounded = (clamped * 10).rounded() / 10
            data.taxPercentage = rounded
        }
        showingTaxInput = false
        isTaxInputFocused = false
    }

    private func applyPaydayInput() {
        if let parsed = Int(paydayInputText) {
            // Clamp to valid range (1-28)
            let clamped = min(max(parsed, 1), 28)
            data.payrollDay = clamped
        }
        showingPaydayInput = false
        isPaydayInputFocused = false
    }
}

// MARK: - Tax Preset Button

private struct TaxPresetButton: View {
    let value: Double
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Text("\(Int(value))%")
                .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : .tidexTextSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.tidexBrandPrimary : Color.tidexBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color.tidexBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Payday Button

private struct PaydayButton: View {
    let day: Int
    let isLast: Bool
    let isSelected: Bool
    let localization: LocalizationManager
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Text(isLast ? localization.string("onboarding.personalize.payday.lastDay") : "\(day)")
                .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : .tidexTextSecondary)
                .frame(minWidth: 56, minHeight: 44)
                .background(isSelected ? Color.tidexBrandPrimary : Color.tidexBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? Color.clear : Color.tidexBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SettingsAccordionScreen(data: OnboardingData(), onContinue: {})
        .environment(\.localization, LocalizationManager.shared)
}
