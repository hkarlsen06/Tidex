import SwiftUI
import UIKit

/// Screen for choosing wage type and selecting tariff level or custom rate
/// First screen in the post-auth onboarding flow
struct WageScreen: View {
    @Bindable var data: OnboardingData
    let onContinue: () -> Void
    var onBack: (() -> Void)? = nil

    @Environment(\.localization) private var localization

    var body: some View {
        ZStack {
            // Background
            Color.tidexBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        // Back button (if not first screen)
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
                            Text(localization.string("onboarding.wage.title"))
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(.tidexTextPrimary)
                                .multilineTextAlignment(.center)

                            Text(localization.string("onboarding.wage.subtitle"))
                                .font(.system(size: 17))
                                .foregroundColor(.tidexTextSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 32)
                        .adaptiveContentWidth()

                        Spacer()
                            .frame(height: 32)

                        // Wage type toggle
                        wageTypeToggle
                            .padding(.horizontal, 24)
                            .adaptiveContentWidth()

                        Spacer()
                            .frame(height: 24)

                        // Content based on wage type
                        Group {
                            switch data.wageType {
                            case .tariff:
                                tariffSelector
                            case .custom:
                                customWageSlider
                            }
                        }
                        .padding(.horizontal, 24)
                        .adaptiveContentWidth()

                        // Bottom padding to account for fixed button
                        Spacer()
                            .frame(height: 120)
                    }
                }
                .scrollDismissesKeyboard(.interactively)

                // Fixed continue button at bottom
                VStack(spacing: 0) {
                    // Gradient fade
                    LinearGradient(
                        colors: [Color.tidexBackground.opacity(0), Color.tidexBackground],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 24)

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
                    .background(Color.tidexBackground)
                }
            }
        }
        .onAppear {
            if !data.hasInitializedWageForLocale {
                // Initialize custom wage based on locale (only once)
                let isNorwegian = localization.currentLocale == .norwegian
                data.customHourlyWage = isNorwegian ? 200 : 25
                data.hasInitializedWageForLocale = true
            }
        }
    }

    // MARK: - Wage Type Toggle

    @ViewBuilder
    private var wageTypeToggle: some View {
        HStack(spacing: 12) {
            WageTypeButton(
                title: localization.string("onboarding.wage.custom"),
                isSelected: data.wageType == .custom,
                action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        data.wageType = .custom
                    }
                }
            )

            WageTypeButton(
                title: localization.string("onboarding.wage.tariff"),
                isSelected: data.wageType == .tariff,
                action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        data.wageType = .tariff
                    }
                }
            )
        }
    }

    // MARK: - Tariff Selector

    @ViewBuilder
    private var tariffSelector: some View {
        VStack(spacing: 12) {
            ForEach(TariffLevel.all) { level in
                TariffLevelRow(
                    level: level,
                    isSelected: data.selectedTariffLevel == level.level,
                    action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            data.selectedTariffLevel = level.level
                        }
                    }
                )
            }
        }
    }

    // MARK: - Custom Wage Slider

    @ViewBuilder
    private var customWageSlider: some View {
        OnboardingRateSlider(value: $data.customHourlyWage, style: .full)
    }
}

// MARK: - Wage Type Button

private struct WageTypeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Text(title)
                .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : .tidexTextSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(isSelected ? Color.tidexBrandPrimary : Color.tidexSurfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Color.clear : Color.tidexBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tariff Level Row

private struct TariffLevelRow: View {
    let level: TariffLevel
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(level.displayName)
                        .font(.system(size: 16, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(.tidexTextPrimary)

                    Text(level.formattedRate)
                        .font(.system(size: 14))
                        .foregroundColor(.tidexTextSecondary)
                }

                Spacer()

                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.tidexBrandPrimary : Color.tidexBorder, lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(Color.tidexBrandPrimary)
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .padding(16)
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

#Preview {
    WageScreen(data: OnboardingData(), onContinue: {})
        .environment(\.localization, LocalizationManager.shared)
}
