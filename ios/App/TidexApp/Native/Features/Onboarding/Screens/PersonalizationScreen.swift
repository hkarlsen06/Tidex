import SwiftUI
import UIKit

/// Screen 5: Personalization (Post-Auth)
/// Collect essential data: hourly wage and payroll day
struct PersonalizationScreen: View {
    let onComplete: (Double, Int) -> Void

        @State private var hourlyWage: Double = 0  // Set on appear based on locale
    @State private var hasInitializedWage = false
    @State private var payrollDay: Int = 15

    private let payrollDayOptions = [1, 10, 15, 20, 25, 28]

    /// Default hourly wage based on locale
    /// Norwegian: 200 kr/hour, English: $25/hour
    private var defaultHourlyWage: Double {
        Locale.current.tidexIsNorwegian ? 200 : 25
    }

    var body: some View {
        ZStack {
            // Background
            Color.tidexBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 60)

                    // Header - constrained for iPad
                    VStack(spacing: 12) {
                        Text(.onboardingPersonalizeTitle)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.tidexTextPrimary)
                            .multilineTextAlignment(.center)

                        Text(.onboardingPersonalizeSubtitle)
                            .font(.system(size: 17))
                            .foregroundColor(.tidexTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .adaptiveContentWidth()

                    Spacer()
                        .frame(height: 48)

                    // Form - constrained for iPad
                    VStack(spacing: 24) {
                        // Hourly wage slider
                        OnboardingRateSlider(value: $hourlyWage, style: .full)

                        // Payroll day picker
                        payrollDayPicker
                    }
                    .padding(.horizontal, 24)
                    .adaptiveContentWidth()

                    Spacer()
                        .frame(height: 48)

                    // Continue button - constrained for iPad
                    OnboardingButton(
                        title: String(localized: .commonContinue),
                        action: validateAndContinue
                    )
                    .padding(.horizontal, 24)
                    .adaptiveContentWidth()

                    Spacer()
                        .frame(height: 32)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            // Initialize hourly wage based on locale (only once)
            if !hasInitializedWage {
                hourlyWage = defaultHourlyWage
                hasInitializedWage = true
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var payrollDayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(.onboardingPersonalizePaydayLabel)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            // Horizontal scroll with day options
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(payrollDayOptions, id: \.self) { day in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                payrollDay = day
                            }
                        } label: {
                            Text(day == 28 ? String(localized: .onboardingPersonalizePaydayLastDay) : "\(day)")
                                .font(.system(size: 16, weight: payrollDay == day ? .semibold : .medium))
                                .foregroundColor(payrollDay == day ? .white : .tidexTextSecondary)
                                .frame(minWidth: 56, minHeight: 44)
                                .background(payrollDay == day ? Color.tidexBrandPrimary : Color.tidexSurfaceSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(payrollDay == day ? Color.clear : Color.tidexBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Text(.onboardingPersonalizePaydayHelper)
                .font(.system(size: 13))
                .foregroundColor(.tidexTextMuted)
        }
    }

    // MARK: - Validation

    private func validateAndContinue() {
        // Slider always provides valid value, so just proceed
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onComplete(hourlyWage, payrollDay)
    }
}

#Preview {
    PersonalizationScreen { wage, payrollDay in
        print("Wage: \(wage), Payroll day: \(payrollDay)")
    }
}
