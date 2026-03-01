import SwiftUI

/// Pre-auth onboarding flow container (Screens 1-4)
/// Shows value proposition before requiring authentication
struct OnboardingView: View {
  let onComplete: () -> Void
  let onNavigateToSignup: () -> Void
  let onNavigateToLogin: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var currentPage = 0
  @State private var isSkipButtonVisible = false
  @State private var simulatorBaselineTotals: CalendarHeaderTotals?
  @State private var preAuthCurrency: String = {
    OnboardingCurrencyCarryoverStore.readValidPreferredCurrency()
      ?? OnboardingCurrencyResolver.detectDefaultCurrency()
  }()
  @State private var howItWorksFromTotals: CalendarHeaderTotals?
  @State private var howItWorksToTotals: CalendarHeaderTotals?
  @State private var howItWorksShouldShowConfetti = false
  @State private var howItWorksShouldAnimateFromPrevious = false
  @State private var howItWorksTotalCardSeed = 0
  @State private var isAdvancingFromSimulatorAdd = false
  @State private var shouldPreloadSimulatorScreen = false
  @State private var shouldPreloadHowItWorksScreen = false

  private let totalPages = 4
  private let simulatorPage = 1
  private let howItWorksPage = 2
  private let skipButtonRevealDelayNanoseconds: UInt64 = 1_500_000_000

  private var isSimulatorPage: Bool {
    currentPage == simulatorPage
  }

  private var isWelcomePage: Bool {
    currentPage == 0
  }

  private var canShowWelcomeHeaderControls: Bool {
    isWelcomePage
  }

  private var fallbackHowItWorksTotals: CalendarHeaderTotals {
    // Match simulator baseline defaults: 5 shifts * 7.5 paid hours at currency-tier default wage.
    let hourlyRate = OnboardingCurrencyResolver.defaultHourlyWage(for: preAuthCurrency)
    let gross = hourlyRate * 37.5
    let net = gross * 0.8
    return CalendarHeaderTotals(primary: net, secondary: gross)
  }

  var body: some View {
    ZStack {
      // Background
      Color.tidexBackground
        .ignoresSafeArea()

      if shouldPreloadSimulatorScreen {
        preloadedSimulatorScreen
      }

      if shouldPreloadHowItWorksScreen {
        preloadedHowItWorksScreen
      }

      VStack(spacing: 0) {
        // Page content - takes full height, skip button overlaid
        TabView(selection: $currentPage) {
          WelcomeScreen(currency: preAuthCurrency)
            .tag(0)

          PreAuthAddShiftSimulatorScreen(
            initialCurrency: preAuthCurrency,
            onCurrencyChanged: { currency in
              preAuthCurrency = currency
            },
            onContinue: { fromTotals, toTotals, currency in
              completeSimulatorAndAdvance(
                fromTotals: fromTotals,
                toTotals: toTotals,
                currency: currency
              )
            },
            onSkip: {
              skipFromSimulator()
            },
            onBaselineReady: { baselineTotals, currency in
              simulatorBaselineTotals = baselineTotals
              preAuthCurrency = currency
            },
            isPreloaded: false
          )
          .tag(1)

          HowItWorksScreen(
            totalFrom: howItWorksFromTotals,
            totalTo: howItWorksToTotals,
            currency: preAuthCurrency,
            isActive: currentPage == 2,
            shouldShowConfetti: howItWorksShouldShowConfetti,
            shouldAnimateTotalFromPrevious: howItWorksShouldAnimateFromPrevious,
            totalCardSeed: howItWorksTotalCardSeed
          )
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
        .motionAnimation(.pageTransition, value: currentPage, reduceMotion: reduceMotion)
        .onChange(of: currentPage) { oldPage, newPage in
          handlePageTransition(from: oldPage, to: newPage)
          preloadUpcomingScreen(after: newPage)
        }

        // Bottom controls area - constrained for iPad
        if !isSimulatorPage {
          VStack(spacing: Spacing.md) {
            PageIndicator(totalPages: totalPages, currentPage: currentPage)

            if currentPage < totalPages - 1 {
              OnboardingButton(
                title: String(localized: .commonContinue),
                action: {
                  MotionTokens.animate(.pageTransition, reduceMotion: reduceMotion) {
                    currentPage += 1
                  }
                }
              )
            }
          }
          .padding(.horizontal, Spacing.lg)
          .adaptiveContentWidth()
          .padding(.bottom, Spacing.xl)
          .motionAnimation(.emphasis, value: currentPage, reduceMotion: reduceMotion)
        }
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      if canShowWelcomeHeaderControls {
        welcomeTopHeader
      }
    }
    .onAppear {
      OnboardingCurrencyCarryoverStore.writePreferredCurrency(preAuthCurrency)
      preloadUpcomingScreen(after: currentPage)
    }
    .task(id: currentPage) {
      if isSkipButtonVisible {
        if reduceMotion {
          isSkipButtonVisible = false
        } else {
          MotionTokens.animate(.emphasis, reduceMotion: reduceMotion) {
            isSkipButtonVisible = false
          }
        }
      }

      guard canShowWelcomeHeaderControls else { return }

      try? await Task.sleep(nanoseconds: skipButtonRevealDelayNanoseconds)
      guard canShowWelcomeHeaderControls else { return }

      if reduceMotion {
        isSkipButtonVisible = true
      } else {
        MotionTokens.animate(.pageTransition, reduceMotion: reduceMotion) {
          isSkipButtonVisible = true
        }
      }
    }
  }

  private var preloadedSimulatorScreen: some View {
    PreAuthAddShiftSimulatorScreen(
      initialCurrency: preAuthCurrency,
      onCurrencyChanged: { _ in },
      onContinue: { _, _, _ in },
      onSkip: {},
      onBaselineReady: { _, _ in },
      isPreloaded: true
    )
    .frame(width: 1, height: 1)
    .clipped()
    .opacity(0.001)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private var preloadedHowItWorksScreen: some View {
    HowItWorksScreen(
      totalFrom: howItWorksFromTotals ?? simulatorBaselineTotals ?? fallbackHowItWorksTotals,
      totalTo: howItWorksToTotals ?? howItWorksFromTotals ?? simulatorBaselineTotals
        ?? fallbackHowItWorksTotals,
      currency: preAuthCurrency,
      isActive: false,
      shouldShowConfetti: false,
      shouldAnimateTotalFromPrevious: false,
      totalCardSeed: howItWorksTotalCardSeed
    )
    .frame(width: 1, height: 1)
    .clipped()
    .opacity(0.001)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private var welcomeTopHeader: some View {
    ZStack(alignment: .center) {
      HStack(spacing: Spacing.sm) {
        if isSkipButtonVisible {
          Button {
            MotionTokens.animate(.pageTransition, reduceMotion: reduceMotion) {
              currentPage = totalPages - 1
            }
          } label: {
            Text(.onboardingSkip)
              .font(.tidexBodyMedium)
              .foregroundColor(.tidexTextSecondary)
              .lineLimit(1)
              .minimumScaleFactor(0.9)
              .allowsTightening(true)
              .padding(.horizontal, Spacing.sm)
              .padding(.vertical, Spacing.xxxs)
          }
          .fixedSize(horizontal: true, vertical: false)
          .buttonStyle(.plain)
          .tidexGlass(shape: .capsule, interactive: true)
          .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }

        Spacer(minLength: 0)
      }

      OnboardingCurrencyCapsuleSelector(
        selectedCurrency: Binding(
          get: { preAuthCurrency },
          set: { selectedCurrency in
            guard selectedCurrency != preAuthCurrency else { return }
            preAuthCurrency = selectedCurrency
            OnboardingCurrencyCarryoverStore.writePreferredCurrency(selectedCurrency)
          }
        )
      )
      .fixedSize(horizontal: true, vertical: false)
    }
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, Spacing.lg)
    .padding(.top, Spacing.xxxs)
    .padding(.bottom, Spacing.sm)
    .background(Color.tidexBackground)
    .motionAnimation(.emphasis, value: isSkipButtonVisible, reduceMotion: reduceMotion)
  }

  private func completeSimulatorAndAdvance(
    fromTotals: CalendarHeaderTotals?,
    toTotals: CalendarHeaderTotals?,
    currency: String
  ) {
    isAdvancingFromSimulatorAdd = true
    preAuthCurrency = currency
    howItWorksFromTotals = fromTotals ?? simulatorBaselineTotals
    howItWorksToTotals = toTotals ?? fromTotals ?? simulatorBaselineTotals
    howItWorksShouldShowConfetti = true
    howItWorksShouldAnimateFromPrevious = true
    howItWorksTotalCardSeed += 1

    MotionTokens.animate(.pageTransition, reduceMotion: reduceMotion) {
      currentPage = min(currentPage + 1, totalPages - 1)
    }
  }

  private func skipFromSimulator() {
    MotionTokens.animate(.pageTransition, reduceMotion: reduceMotion) {
      currentPage = totalPages - 1
    }
  }

  private func handlePageTransition(from oldPage: Int, to newPage: Int) {
    if newPage == howItWorksPage {
      let baseline = simulatorBaselineTotals ?? fallbackHowItWorksTotals
      howItWorksFromTotals = howItWorksFromTotals ?? baseline
      howItWorksToTotals = howItWorksToTotals ?? howItWorksFromTotals ?? baseline
    }

    if oldPage == simulatorPage, newPage == simulatorPage + 1 {
      if isAdvancingFromSimulatorAdd {
        isAdvancingFromSimulatorAdd = false
      } else {
        let baseline = simulatorBaselineTotals
        howItWorksFromTotals = baseline
        howItWorksToTotals = baseline
        howItWorksShouldShowConfetti = false
        howItWorksShouldAnimateFromPrevious = false
        howItWorksTotalCardSeed += 1
      }
    }

    if oldPage == simulatorPage, newPage != simulatorPage + 1 {
      isAdvancingFromSimulatorAdd = false
    }

    if oldPage == simulatorPage + 1, newPage != simulatorPage + 1 {
      howItWorksShouldShowConfetti = false
      howItWorksShouldAnimateFromPrevious = false
    }
  }

  private func preloadUpcomingScreen(after page: Int) {
    if page < simulatorPage {
      shouldPreloadSimulatorScreen = true
    } else {
      shouldPreloadSimulatorScreen = false
    }

    if page == simulatorPage {
      shouldPreloadHowItWorksScreen = true
    } else if page >= howItWorksPage {
      shouldPreloadHowItWorksScreen = false
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
