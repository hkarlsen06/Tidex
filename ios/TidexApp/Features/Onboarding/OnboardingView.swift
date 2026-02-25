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
            }
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
        .animation(
          reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: currentPage
        )
        .onChange(of: currentPage) { oldPage, newPage in
          handlePageTransition(from: oldPage, to: newPage)
        }

        // Bottom controls area - constrained for iPad
        if !isSimulatorPage {
          VStack(spacing: Spacing.md) {
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
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      if canShowWelcomeHeaderControls {
        welcomeTopHeader
      }
    }
    .onAppear {
      OnboardingCurrencyCarryoverStore.writePreferredCurrency(preAuthCurrency)
    }
    .task(id: currentPage) {
      if isSkipButtonVisible {
        if reduceMotion {
          isSkipButtonVisible = false
        } else {
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
          isSkipButtonVisible = true
        }
      }
    }
  }

  @ViewBuilder
  private var welcomeTopHeader: some View {
    ZStack(alignment: .center) {
      HStack(spacing: Spacing.sm) {
        if isSkipButtonVisible {
          Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
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
    .animation(
      reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8),
      value: isSkipButtonVisible
    )
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

    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
      currentPage = min(currentPage + 1, totalPages - 1)
    }
  }

  private func skipFromSimulator() {
    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
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
}

#Preview {
  OnboardingView(
    onComplete: {},
    onNavigateToSignup: {},
    onNavigateToLogin: {}
  )
}
