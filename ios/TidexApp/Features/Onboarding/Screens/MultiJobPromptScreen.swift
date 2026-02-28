import SwiftUI
import UIKit

/// Optional post-auth onboarding step for setting up an additional workplace/job.
struct MultiJobPromptScreen: View {
  var isLoading: Bool = false
  let onAddNow: () -> Void
  let onContinueLater: () -> Void
  let onBack: () -> Void
  var errorMessage: String?

  var body: some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        HStack {
          Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onBack()
          }) {
            HStack(spacing: Spacing.xxs) {
              Image(systemName: "chevron.left")
                .font(.tidexButton)
              Text(.commonBack)
                .font(.tidexBody)
            }
            .foregroundColor(.tidexBlue)
          }
          .buttonStyle(.plain)

          Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, Spacing.md)
        .adaptiveContentWidth()

        Spacer()

        ZStack {
          Circle()
            .fill(Color.tidexBlue.opacity(0.1))
            .frame(width: 120, height: 120)

          Image(systemName: "building.2")
            .font(.system(size: 52))
            .foregroundColor(.tidexBlue)
        }
        .padding(.bottom, Spacing.xl)

        VStack(spacing: Spacing.sm) {
          Text(String(localized: "onboarding.multi_job.title", table: "Localizable"))
            .font(.tidexScreenTitle)
            .foregroundColor(.tidexTextPrimary)
            .multilineTextAlignment(.center)

          Text(String(localized: "settings.pay.add_job.setup_subtitle", table: "Localizable"))
            .font(.tidexBody)
            .foregroundColor(.tidexTextSecondary)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)

          Text(String(localized: "onboarding.multi_job.later_hint", table: "Localizable"))
            .font(.tidexSubheadline)
            .foregroundColor(.tidexTextSecondary)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Spacing.xs)
        }
        .padding(.horizontal, Spacing.xl)
        .adaptiveContentWidth()

        if let errorMessage, !errorMessage.isEmpty {
          Text(errorMessage)
            .font(.tidexFootnote)
            .foregroundColor(.tidexError)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.md)
            .adaptiveContentWidth()
        }

        Spacer()

        VStack(spacing: Spacing.sm) {
          OnboardingButton(
            title: String(localized: "settings.pay.add_job.cta", table: "Localizable"),
            action: {
              UINotificationFeedbackGenerator().notificationOccurred(.success)
              onAddNow()
            }
          )
          .disabled(isLoading)

          Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onContinueLater()
          }) {
            Text(.onboardingMfaSkip)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextSecondary)
          }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.xl)
        .adaptiveContentWidth()
      }
    }
  }
}

#Preview {
  MultiJobPromptScreen(
    onAddNow: {},
    onContinueLater: {},
    onBack: {},
    errorMessage: nil
  )
}
