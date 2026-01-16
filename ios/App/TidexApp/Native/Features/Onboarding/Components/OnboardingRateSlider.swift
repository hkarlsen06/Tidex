import SwiftUI
import UIKit

/// Unified hourly rate slider for onboarding flows
/// Supports compact (inline) and full (with label/helper) styles
struct OnboardingRateSlider: View {
    @Binding var value: Double
    var style: Style = .compact

    @Environment(\.localization) private var localization
    @State private var showingCustomInput = false
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    enum Style {
        case compact  // Used inline in onboarding page 2
        case full     // Used in personalization screen with label/helper
    }

    var body: some View {
        switch style {
        case .compact:
            compactLayout
        case .full:
            fullLayout
        }
    }

    // MARK: - Locale-Aware Configuration

    private var isNorwegian: Bool {
        localization.currentLocale == .norwegian
    }

    /// Wage ranges differ significantly by locale
    /// Norwegian: 150-550 kr/hour (typical hourly wages)
    /// English: $15-$75/hour (typical US hourly wages)
    private var minValue: Double {
        isNorwegian ? 150 : 15
    }

    private var maxValue: Double {
        isNorwegian ? 550 : 75
    }

    private var defaultValue: Double {
        isNorwegian ? 200 : 25
    }

    private var currencySymbol: String {
        isNorwegian ? "kr" : "$"
    }

    private var hourSuffix: String {
        isNorwegian ? "/t" : "/hr"
    }

    // MARK: - Compact Layout (inline)

    @ViewBuilder
    private var compactLayout: some View {
        VStack(spacing: 12) {
            // Current value display: "Your hourly rate" on left, "200 kr/t" on right
            HStack(spacing: 4) {
                Text(localization.string("onboarding.slider.label"))
                    .font(.system(size: 13))
                    .foregroundColor(.tidexTextSecondary)

                Spacer()

                // Tappable currency display (locale-aware)
                if showingCustomInput {
                    customInputField
                } else if isNorwegian {
                    // Norwegian: "200 kr/t"
                    tappableValue(formatValueWithDecimals(value))
                    Text("\(currencySymbol)\(hourSuffix)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.tidexTextMuted)
                } else {
                    // English: "$200/hr"
                    Text(currencySymbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.tidexTextMuted)
                    tappableValue(formatValueWithDecimals(value))
                    Text(hourSuffix)
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextMuted)
                }
            }

            sliderControl

            minMaxLabels(fontSize: 11)
        }
        .padding(16)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Full Layout (with label and helper)

    @ViewBuilder
    private var fullLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Label
            Text(localization.string("onboarding.personalize.wage.label"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            // Slider card
            VStack(spacing: 16) {
                // Current value display (locale-aware)
                HStack {
                    if showingCustomInput {
                        customInputFieldFull
                    } else if isNorwegian {
                        // Norwegian: "200 kr per time"
                        tappableValueFull(formatValueWithDecimals(value))

                        Text("kr")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.tidexTextSecondary)

                        Text("per time")
                            .font(.system(size: 14))
                            .foregroundColor(.tidexTextMuted)
                    } else {
                        // English: "$200 per hour"
                        Text("$")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.tidexTextSecondary)

                        tappableValueFull(formatValueWithDecimals(value))

                        Text("per hour")
                            .font(.system(size: 14))
                            .foregroundColor(.tidexTextMuted)
                    }

                    Spacer()
                }

                sliderControl

                minMaxLabels(fontSize: 12)
            }
            .padding(16)
            .background(Color.tidexSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Helper text
            Text(localization.string("onboarding.personalize.wage.helper"))
                .font(.system(size: 13))
                .foregroundColor(.tidexTextMuted)
        }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private var sliderControl: some View {
        Slider(
            value: $value,
            in: minValue...maxValue,
            onEditingChanged: { isEditing in
                if isEditing {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            }
        )
        .tint(.tidexBlue)
    }

    @ViewBuilder
    private func minMaxLabels(fontSize: CGFloat) -> some View {
        HStack {
            Text(formatCurrencyLabel(minValue))
                .font(.system(size: fontSize))
                .foregroundColor(.tidexTextMuted)

            Spacer()

            Text(formatCurrencyLabel(maxValue))
                .font(.system(size: fontSize))
                .foregroundColor(.tidexTextMuted)
        }
    }

    /// Format just the number (for inline display where currency symbol is separate)
    private func formatValue(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale(identifier: isNorwegian ? "nb_NO" : "en_US")
        return formatter.string(from: NSNumber(value: amount)) ?? "0"
    }

    /// Format with currency for min/max labels
    /// Norwegian: "120 kr" / English: "$120"
    private func formatCurrencyLabel(_ amount: Double) -> String {
        let number = formatValue(amount)
        if isNorwegian {
            return "\(number) kr"
        } else {
            return "$\(number)"
        }
    }

    /// Format value with up to 2 decimal places (shows decimals only if needed)
    private func formatValueWithDecimals(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: isNorwegian ? "nb_NO" : "en_US")
        return formatter.string(from: NSNumber(value: amount)) ?? "0"
    }

    // MARK: - Tappable Value Views

    @ViewBuilder
    private func tappableValue(_ text: String) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            inputText = formatValueWithDecimals(value)
            showingCustomInput = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }) {
            Text(text)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.tidexBlue)
                .contentTransition(.numericText())
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.tidexBlue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func tappableValueFull(_ text: String) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            inputText = formatValueWithDecimals(value)
            showingCustomInput = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isInputFocused = true
            }
        }) {
            Text(text)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.tidexBlue)
                .contentTransition(.numericText())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.tidexBlue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Custom Input Fields

    @ViewBuilder
    private var customInputField: some View {
        HStack(spacing: 4) {
            TextField("", text: $inputText)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.tidexBlue)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($isInputFocused)
                .frame(width: 80)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.tidexBlue.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.tidexBlue, lineWidth: 2)
                )
                .onSubmit {
                    applyCustomValue()
                }
                .onChange(of: isInputFocused) { _, focused in
                    if !focused {
                        applyCustomValue()
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(localization.string("common.done")) {
                            applyCustomValue()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
    }

    @ViewBuilder
    private var customInputFieldFull: some View {
        HStack(spacing: 4) {
            TextField("", text: $inputText)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.tidexBlue)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.leading)
                .focused($isInputFocused)
                .frame(width: 100)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.tidexBlue.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.tidexBlue, lineWidth: 2)
                )
                .onSubmit {
                    applyCustomValue()
                }
                .onChange(of: isInputFocused) { _, focused in
                    if !focused {
                        applyCustomValue()
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(localization.string("common.done")) {
                            applyCustomValue()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
    }

    private func applyCustomValue() {
        // Parse the input, handling both comma and period as decimal separator
        let normalized = inputText.replacingOccurrences(of: ",", with: ".")
        if let parsed = Double(normalized) {
            // Clamp to valid range and round to 2 decimal places
            let clamped = min(max(parsed, minValue), maxValue)
            let rounded = (clamped * 100).rounded() / 100
            value = rounded
        }
        showingCustomInput = false
        isInputFocused = false
    }
}

#Preview("Compact") {
    OnboardingRateSlider(value: .constant(200), style: .compact)
        .padding()
        .background(Color.tidexBackground)
        .environment(\.localization, LocalizationManager.shared)
}

#Preview("Full") {
    OnboardingRateSlider(value: .constant(280), style: .full)
        .padding()
        .background(Color.tidexBackground)
        .environment(\.localization, LocalizationManager.shared)
}
