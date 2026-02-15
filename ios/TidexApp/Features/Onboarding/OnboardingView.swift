import SwiftUI

/// Pre-auth onboarding flow container (Screens 1-4)
/// Shows value proposition before requiring authentication
struct OnboardingView: View {
  let onComplete: () -> Void
  let onNavigateToSignup: () -> Void
  let onNavigateToLogin: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var currentPage = 0
  @State private var hourlyRate: Double = 0  // Set on appear based on locale
  @State private var hasInitializedRate = false
  @State private var isSkipButtonVisible = false

  private let totalPages = 4
  private let skipButtonRevealDelayNanoseconds: UInt64 = 1_500_000_000

  /// Default hourly rate based on locale
  /// Norwegian: 200 kr/hour, Others: $25/hour
  private var defaultHourlyRate: Double {
    Locale.current.isNorwegian ? 200 : 25
  }

  var body: some View {
    ZStack {
      // Background
      Color.tidexBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        // Page content - takes full height, skip button overlaid
        TabView(selection: $currentPage) {
          WelcomeScreen()
            .tag(0)

          SamplePaycheckScreen(hourlyRate: $hourlyRate)
            .tag(1)

          HowItWorksScreen()
            .tag(2)

          GetStartedScreen(
            onCreateAccount: {
              onComplete()
              onNavigateToSignup()
            },
            onLogin: {
              onComplete()
              onNavigateToLogin()
            }
          )
          .tag(3)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(
          reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: currentPage)

        // Bottom controls area - constrained for iPad
        VStack(spacing: Spacing.md) {
          // Hourly rate slider (only on page 2)
          if currentPage == 1 {
            OnboardingRateSlider(value: $hourlyRate)
              .transition(
                .asymmetric(
                  insertion: .move(edge: .bottom).combined(with: .opacity),
                  removal: .opacity
                ))
          }

          PageIndicator(totalPages: totalPages, currentPage: currentPage)

          if currentPage < totalPages - 1 {
            OnboardingButton(
              title: String(localized: .commonContinue),
              action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                  currentPage += 1
                }
              }
            )
          }
        }
        .padding(.horizontal, Spacing.lg)
        .adaptiveContentWidth()
        .padding(.bottom, Spacing.xl)
        .animation(
          reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.8), value: currentPage)
      }

      // Skip button overlaid at top-right (only on first page)
      VStack {
        HStack {
          Spacer()
          if currentPage == 0 && isSkipButtonVisible {
            Button {
              withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                currentPage = totalPages - 1
              }
            } label: {
              Text(.onboardingSkip)
                .font(.tidexBodyMedium)
                .foregroundColor(.tidexTextSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
            }
            .tidexGlass(shape: .capsule, interactive: true)
            .padding(.trailing, Spacing.lg)
            .padding(.top, Spacing.md)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
          }
        }
        Spacer()
      }
      .animation(
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: currentPage)
    }
    .onAppear {
      // Initialize hourly rate based on locale (only once)
      if !hasInitializedRate {
        hourlyRate = defaultHourlyRate
        hasInitializedRate = true
      }
    }
    .task(id: currentPage) {
      guard currentPage == 0, !isSkipButtonVisible else { return }

      try? await Task.sleep(nanoseconds: skipButtonRevealDelayNanoseconds)
      guard currentPage == 0 else { return }

      if reduceMotion {
        isSkipButtonVisible = true
      } else {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
          isSkipButtonVisible = true
        }
      }
    }
  }
}

#Preview {
  OnboardingView(
    onComplete: {},
    onNavigateToSignup: {},
    onNavigateToLogin: {}
  )
}
