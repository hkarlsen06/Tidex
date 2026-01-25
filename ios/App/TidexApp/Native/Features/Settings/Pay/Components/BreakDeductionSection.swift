import SwiftUI
import UIKit

// MARK: - Break Deduction Section

/// Section for configuring break deduction settings
struct BreakDeductionSection: View {
    @Binding var enabled: Bool
    @Binding var method: BreakMethod
    @Binding var thresholdHours: Double
    @Binding var deductionMinutes: Int

    @Environment(\.localization) private var localization

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header with toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localization.string("settings.pay.editor.breakTitle"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.tidexTextPrimary)

                    Text(localization.string("settings.pay.editor.breakDescription"))
                        .font(.system(size: 13))
                        .foregroundColor(.tidexTextSecondary)
                }

                Spacer()

                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .tint(.tidexBrandPrimary)
                    .onChange(of: enabled) { _, _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            }

            // Settings (only shown when enabled)
            if enabled {
                VStack(spacing: 16) {
                    // Break method picker
                    breakMethodPicker

                    // Threshold hours
                    thresholdInput

                    // Deduction minutes
                    deductionInput
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: enabled)
    }

    // MARK: - Break Method Picker

    @ViewBuilder
    private var breakMethodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localization.string("settings.pay.editor.breakMethod"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            VStack(spacing: 6) {
                ForEach(BreakMethod.allCases, id: \.self) { breakMethod in
                    BreakMethodRow(
                        method: breakMethod,
                        isSelected: method == breakMethod,
                        localization: localization,
                        action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                method = breakMethod
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Threshold Input

    @ViewBuilder
    private var thresholdInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localization.string("settings.pay.editor.breakThreshold"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            HStack {
                Text(formatThreshold(thresholdHours))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.tidexTextPrimary)

                Spacer()

                Stepper("", value: $thresholdHours, in: 1...12, step: 0.5)
                    .labelsHidden()
            }
            .padding(12)
            .background(Color.tidexSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func formatThreshold(_ hours: Double) -> String {
        let isNorwegian = localization.currentLocale == .norwegian
        if hours == floor(hours) {
            return isNorwegian ? "\(Int(hours)) timer" : "\(Int(hours)) hours"
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
            formatter.locale = Locale(identifier: isNorwegian ? "nb_NO" : "en_US")
            let formatted = formatter.string(from: NSNumber(value: hours)) ?? "\(hours)"
            return isNorwegian ? "\(formatted) timer" : "\(formatted) hours"
        }
    }

    // MARK: - Deduction Input

    @ViewBuilder
    private var deductionInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localization.string("settings.pay.editor.breakDeduction"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            HStack {
                Text(formatDeduction(deductionMinutes))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.tidexTextPrimary)

                Spacer()

                Stepper("", value: $deductionMinutes, in: 5...120, step: 5)
                    .labelsHidden()
            }
            .padding(12)
            .background(Color.tidexSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func formatDeduction(_ minutes: Int) -> String {
        let isNorwegian = localization.currentLocale == .norwegian
        return isNorwegian ? "\(minutes) minutter" : "\(minutes) minutes"
    }
}

// MARK: - Break Method Row

private struct BreakMethodRow: View {
    let method: BreakMethod
    let isSelected: Bool
    let localization: LocalizationManager
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(methodTitle)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(.tidexTextPrimary)

                    Text(methodDescription)
                        .font(.system(size: 12))
                        .foregroundColor(.tidexTextSecondary)
                        .lineLimit(2)
                }

                Spacer()

                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.tidexBrandPrimary : Color.tidexBorder, lineWidth: 2)
                        .frame(width: 20, height: 20)

                    if isSelected {
                        Circle()
                            .fill(Color.tidexBrandPrimary)
                            .frame(width: 10, height: 10)
                    }
                }
            }
            .padding(Spacing.xs)
            .background(isSelected ? Color.tidexBrandPrimary.opacity(0.08) : Color.tidexSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var methodTitle: String {
        let isNorwegian = localization.currentLocale == .norwegian
        switch method {
        case .proportional:
            return isNorwegian ? "Proporsjonalt" : "Proportional"
        case .baseOnly:
            return isNorwegian ? "Kun grunnlønn" : "Base Only"
        case .endOfShift:
            return isNorwegian ? "Slutten av vakten" : "End of Shift"
        case .none:
            return isNorwegian ? "Ingen" : "None"
        }
    }

    private var methodDescription: String {
        let isNorwegian = localization.currentLocale == .norwegian
        switch method {
        case .proportional:
            return isNorwegian
                ? "Trekker pause proporsjonalt fra alle tillegg"
                : "Deducts break proportionally from all supplements"
        case .baseOnly:
            return isNorwegian
                ? "Trekker pause kun fra grunnlønn"
                : "Deducts break only from base wage"
        case .endOfShift:
            return isNorwegian
                ? "Trekker pause fra slutten av vakten"
                : "Deducts break from end of shift"
        case .none:
            return isNorwegian
                ? "Ingen automatisk pausetrekk"
                : "No automatic break deduction"
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        BreakDeductionSection(
            enabled: .constant(true),
            method: .constant(.proportional),
            thresholdHours: .constant(5.5),
            deductionMinutes: .constant(30)
        )
        .padding()
    }
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
