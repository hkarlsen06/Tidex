import SwiftUI
import UIKit

/// Screen 5: Personalization (Post-Auth)
/// Collect essential data: hourly wage and payroll day
struct PersonalizationScreen: View {
    let onComplete: (Double, Int) -> Void

    @Environment(\.localization) private var localization
    @State private var hourlyWage: String = ""
    @State private var payrollDay: Int = 15
    @State private var wageError: String?
    @FocusState private var isWageFocused: Bool

    private let payrollDayOptions = [1, 10, 15, 20, 25, 28]

    var body: some View {
        ZStack {
            // Background
            Color.tidexBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: 60)

                    // Header
                    VStack(spacing: 12) {
                        Text(localization.string("onboarding.personalize.title"))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.tidexTextPrimary)
                            .multilineTextAlignment(.center)

                        Text(localization.string("onboarding.personalize.subtitle"))
                            .font(.system(size: 17))
                            .foregroundColor(.tidexTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)

                    Spacer()
                        .frame(height: 48)

                    // Form
                    VStack(spacing: 24) {
                        // Hourly wage input
                        wageInput

                        // Payroll day picker
                        payrollDayPicker
                    }
                    .padding(.horizontal, 24)

                    Spacer()
                        .frame(height: 48)

                    // Continue button
                    OnboardingButton(
                        title: localization.string("common.continue"),
                        action: validateAndContinue
                    )
                    .padding(.horizontal, 24)

                    Spacer()
                        .frame(height: 32)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            // Auto-focus wage input
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isWageFocused = true
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var wageInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localization.string("onboarding.personalize.wage.label"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            HStack(spacing: 0) {
                Text("kr")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)
                    .frame(width: 40)

                TextField("200", text: $hourlyWage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.tidexTextPrimary)
                    .keyboardType(.numberPad)
                    .focused($isWageFocused)
                    .onChange(of: hourlyWage) { _, _ in
                        wageError = nil
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.tidexSurfaceSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(wageError != nil ? Color.tidexError : (isWageFocused ? Color.tidexBrandPrimary : Color.tidexBorder), lineWidth: 1)
            )
            .cornerRadius(10)

            Text(localization.string("onboarding.personalize.wage.helper"))
                .font(.system(size: 13))
                .foregroundColor(wageError != nil ? .tidexError : .tidexTextMuted)

            if let error = wageError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.tidexError)
            }
        }
    }

    @ViewBuilder
    private var payrollDayPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localization.string("onboarding.personalize.payday.label"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.tidexTextSecondary)

            // Horizontal scroll with day options
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(payrollDayOptions, id: \.self) { day in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                payrollDay = day
                            }
                        } label: {
                            Text(day == 28 ? localization.string("onboarding.personalize.payday.lastDay") : "\(day)")
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

            Text(localization.string("onboarding.personalize.payday.helper"))
                .font(.system(size: 13))
                .foregroundColor(.tidexTextMuted)
        }
    }

    // MARK: - Validation

    private func validateAndContinue() {
        // Dismiss keyboard
        isWageFocused = false

        guard let wage = Double(hourlyWage), wage > 0 else {
            wageError = localization.string("onboarding.personalize.wage.error")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        // Success haptic
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onComplete(wage, payrollDay)
    }
}

#Preview {
    PersonalizationScreen { wage, payrollDay in
        print("Wage: \(wage), Payroll day: \(payrollDay)")
    }
    .environment(\.localization, LocalizationManager.shared)
}
