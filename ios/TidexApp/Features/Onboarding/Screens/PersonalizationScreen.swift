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
  /// Norwegian: 200 kr/hour, English/German: $25/hour
  private var defaultHourlyWage: Double {
    Locale.current.isNorwegian ? 200 : 25
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
          VStack(spacing: Spacing.sm) {
            Text(.onboardingPersonalizeTitle)
              .font(.tidexScreenTitle)
              .foregroundColor(.tidexTextPrimary)
              .multilineTextAlignment(.center)

            Text(.onboardingPersonalizeSubtitle)
              .font(.tidexBody)
              .foregroundColor(.tidexTextSecondary)
              .multilineTextAlignment(.center)
          }
          .padding(.horizontal, Spacing.xl)
          .adaptiveContentWidth()

          Spacer()
            .frame(height: 48)

          // Form - constrained for iPad
          VStack(spacing: Spacing.lg) {
            // Hourly wage slider
            OnboardingRateSlider(value: $hourlyWage, style: .full)

            // Payroll day picker
            payrollDayPicker
          }
          .padding(.horizontal, Spacing.lg)
          .adaptiveContentWidth()

          Spacer()
            .frame(height: 48)

          // Continue button - constrained for iPad
          OnboardingButton(
            title: String(localized: .commonContinue),
            action: validateAndContinue
          )
          .padding(.horizontal, Spacing.lg)
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
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.onboardingPersonalizePaydayLabel)
        .font(.tidexLabel)
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
                .font(payrollDay == day ? .tidexButton : .tidexBodyMedium)
                .foregroundColor(payrollDay == day ? .white : .tidexTextSecondary)
                .frame(minWidth: 56, minHeight: 44)
                .background(
                  payrollDay == day ? Color.tidexBrandPrimary : Color.tidexSurfaceSecondary
                )
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
                .overlay(
                  RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .stroke(payrollDay == day ? Color.clear : Color.tidexBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
          }
        }
      }

      Text(.onboardingPersonalizePaydayHelper)
        .font(.tidexFootnote)
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
