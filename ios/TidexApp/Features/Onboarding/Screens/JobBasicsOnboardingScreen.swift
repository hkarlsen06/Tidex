import SwiftUI
import UIKit

/// Screen for naming and coloring the first job created during onboarding.
struct JobBasicsOnboardingScreen: View {
  @Bindable var data: OnboardingData
  let onContinue: () -> Void
  var onBack: (() -> Void)? = nil

  private var trimmedJobName: String {
    data.jobName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var canContinue: Bool {
    !trimmedJobName.isEmpty
  }

  var body: some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        ScrollView {
          VStack(spacing: 0) {
            if let onBack {
              backButton(onBack)
            }

            Spacer()
              .frame(height: onBack != nil ? 24 : 60)

            VStack(spacing: Spacing.sm) {
              Text(String(localized: "onboarding.jobBasics.title", table: "Localizable"))
                .font(.tidexScreenTitle)
                .foregroundColor(.tidexTextPrimary)
                .multilineTextAlignment(.center)

              Text(String(localized: "onboarding.jobBasics.subtitle", table: "Localizable"))
                .font(.tidexBody)
                .foregroundColor(.tidexTextSecondary)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Spacing.xl)
            .adaptiveContentWidth()

            Spacer()
              .frame(height: 32)

            VStack(alignment: .leading, spacing: Spacing.lg) {
              TidexTextField(
                label: String(localized: "settings.pay.add_job.name", table: "Localizable"),
                placeholder: String(
                  localized: "onboarding.jobBasics.namePlaceholder",
                  table: "Localizable"
                ),
                text: $data.jobName,
                autocapitalization: .words,
                onSubmit: {
                  continueIfReady()
                }
              )

              VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(String(localized: "settings.pay.add_job.color_label", table: "Localizable"))
                  .font(.tidexLabel)
                  .foregroundColor(.tidexTextSecondary)

                WorkplaceColorCarousel(
                  selectedHex: data.jobColor ?? OnboardingData.defaultJobColor
                ) { hex in
                  data.jobColor = hex
                }
              }
            }
            .padding(.horizontal, Spacing.lg)
            .adaptiveContentWidth()

            Spacer()
              .frame(height: 120)
          }
        }
        .scrollDismissesKeyboard(.interactively)

        VStack(spacing: 0) {
          LinearGradient(
            colors: [Color.tidexBackground.opacity(0), Color.tidexBackground],
            startPoint: .top,
            endPoint: .bottom
          )
          .frame(height: 24)

          OnboardingButton(
            title: String(localized: .commonContinue),
            isEnabled: canContinue,
            action: {
              continueIfReady()
            }
          )
          .padding(.horizontal, Spacing.lg)
          .adaptiveContentWidth()

          Spacer()
            .frame(height: Spacing.xl)
        }
        .background(Color.tidexBackground)
      }
    }
    .onAppear {
      if data.jobColor == nil {
        data.jobColor = OnboardingData.defaultJobColor
      }
    }
  }

  private func backButton(_ onBack: @escaping () -> Void) -> some View {
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
  }

  private func continueIfReady() {
    guard canContinue else { return }
    data.jobName = trimmedJobName
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    onContinue()
  }
}

#Preview {
  JobBasicsOnboardingScreen(
    data: OnboardingData(),
    onContinue: {}
  )
}
