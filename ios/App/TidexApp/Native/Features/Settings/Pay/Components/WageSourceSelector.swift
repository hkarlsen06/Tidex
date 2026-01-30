import SwiftUI
import UIKit

// MARK: - Wage Source Selector

/// Toggle between tariff (preset rates) and custom wage
/// Shows appropriate input for each mode
struct WageSourceSelector: View {
    @Binding var usePreset: Bool
    @Binding var wageLevel: Int
    @Binding var customWage: Double
    let currency: String
    /// When false, only shows custom wage input (hides tariff toggle)
    /// Used when user's currency is not "kr" (Norwegian krone)
    var showTariffOption: Bool = true
    /// Optional tariff version to use for rates (when nil, uses static fallback)
    var tariffVersion: TariffVersion? = nil

    @Environment(\.localization) private var localization

    /// Tariff levels to display - from version if available, otherwise static fallback
    private var tariffLevels: [TariffLevel] {
        if let version = tariffVersion {
            return TariffLevel.from(tariffVersion: version)
        }
        return TariffLevel.all
    }

    /// Get wage rate for a specific level
    private func wageRate(for level: Int) -> Double {
        if let version = tariffVersion {
            return version.rate(forLevel: level) ?? PayrollCalculator.presetWageRates[String(level)] ?? 184.54
        }
        return PayrollCalculator.presetWageRates[String(level)] ?? 184.54
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            Text(localization.string("settings.pay.editor.wageSource"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            // Toggle buttons: Tariff vs Custom (only show if tariff is available)
            if showTariffOption {
                HStack(spacing: 12) {
                    WageTypeToggleButton(
                        title: localization.string("onboarding.wage.tariff"),
                        icon: "building.2",
                        isSelected: usePreset,
                        action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                usePreset = true
                            }
                        }
                    )

                    WageTypeToggleButton(
                        title: localization.string("onboarding.wage.custom"),
                        icon: "slider.horizontal.3",
                        isSelected: !usePreset,
                        action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                usePreset = false
                            }
                        }
                    )
                }
            }

            // Content based on selection
            if usePreset && showTariffOption {
                tariffLevelPicker
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                customWageSlider
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Current wage display
            currentWageDisplay
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: usePreset)
    }

    // MARK: - Tariff Level Picker

    @ViewBuilder
    private var tariffLevelPicker: some View {
        VStack(spacing: 8) {
            ForEach(tariffLevels) { level in
                TariffLevelSelectionRow(
                    level: level,
                    isSelected: wageLevel == level.level,
                    action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            wageLevel = level.level
                        }
                    }
                )
            }
        }
    }

    // MARK: - Custom Wage Slider

    @ViewBuilder
    private var customWageSlider: some View {
        OnboardingRateSlider(
            value: $customWage,
            currency: currency,
            style: .full
        )
    }

    // MARK: - Current Wage Display

    @ViewBuilder
    private var currentWageDisplay: some View {
        let currentWage = (usePreset && showTariffOption)
            ? wageRate(for: wageLevel)
            : customWage

        HStack {
            Text(localization.string("settings.pay.editor.currentWage"))
                .font(.system(size: 14))
                .foregroundColor(.tidexTextSecondary)

            Spacer()

            Text(formatWage(currentWage))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.tidexTextPrimary)
        }
        .padding(12)
        .background(Color.tidexBrandPrimary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func formatWage(_ wage: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "nb_NO")
        let formatted = formatter.string(from: NSNumber(value: wage)) ?? "\(wage)"

        let currencyConfig = CurrencyConfig.get(currency)
        let isNorwegian = localization.currentLocale == .norwegian
        let perHour = isNorwegian ? "/t" : "/hr"

        switch currencyConfig.display {
        case .prefix:
            return "\(currency)\(formatted)\(perHour)"
        case .suffix:
            return "\(formatted) \(currency)\(perHour)"
        }
    }
}

// MARK: - Wage Type Toggle Button

private struct WageTypeToggleButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? .tidexBrandPrimary : .tidexTextMuted)

                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .tidexTextPrimary : .tidexTextSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .background(isSelected ? Color.tidexBrandPrimary.opacity(0.08) : Color.tidexSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.tidexBrandPrimary : Color.tidexBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tariff Level Selection Row

private struct TariffLevelSelectionRow: View {
    let level: TariffLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(.tidexTextPrimary)

                    Text(level.formattedRate)
                        .font(.system(size: 13))
                        .foregroundColor(.tidexTextSecondary)
                }

                Spacer()

                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.tidexBrandPrimary : Color.tidexBorder, lineWidth: 2)
                        .frame(width: Spacing.iconSize, height: Spacing.iconSize)

                    if isSelected {
                        Circle()
                            .fill(Color.tidexBrandPrimary)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(12)
            .background(isSelected ? Color.tidexBrandPrimary.opacity(0.08) : Color.tidexSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.tidexBrandPrimary : Color.tidexBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        WageSourceSelector(
            usePreset: .constant(true),
            wageLevel: .constant(1),
            customWage: .constant(200),
            currency: "kr"
        )
    }
    .padding()
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
