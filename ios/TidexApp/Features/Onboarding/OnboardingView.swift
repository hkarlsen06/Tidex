import SwiftUI

/// Pre-auth onboarding flow container (Screens 1-3)
/// Shows value proposition before requiring authentication
struct OnboardingView: View {
  let onNavigateToSignup: () -> Void
  var onNavigateToLogin: () -> Void = {}

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var currentPage = 0
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
  @State private var isCompletingPreAuth = false

  private let totalPages = 3
  private let simulatorPage = 1
  private let howItWorksPage = 2
  private let completionHandoffDelay: TimeInterval = 0.32

  private var isSimulatorPage: Bool {
    currentPage == simulatorPage
  }

  private var shouldShowTopHeader: Bool {
    currentPage != simulatorPage
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
        pageTabs

        // Bottom controls area - constrained for iPad
        if !isSimulatorPage {
          bottomControls
        }
      }
      .opacity(isCompletingPreAuth && currentPage != howItWorksPage ? 0 : 1)
      .scaleEffect(isCompletingPreAuth && currentPage != howItWorksPage ? 0.985 : 1)
      .offset(y: isCompletingPreAuth && currentPage != howItWorksPage ? -18 : 0)
      .motionAnimation(.emphasis, value: isCompletingPreAuth, reduceMotion: reduceMotion)
      .allowsHitTesting(!isCompletingPreAuth)
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      if shouldShowTopHeader {
        topHeader
          .opacity(isCompletingPreAuth ? 0 : 1)
          .offset(
            y: isCompletingPreAuth ? -10 : 0
          )
          .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.16),
            value: isCompletingPreAuth
          )
      }
    }
    .onAppear {
      OnboardingCurrencyCarryoverStore.writePreferredCurrency(preAuthCurrency)
      preloadUpcomingScreen(after: currentPage)
      recordFunnelStep(for: currentPage)
    }
  }

  private func recordFunnelStep(for page: Int) {
    let name: String
    switch page {
    case simulatorPage: name = "add_shift_simulator"
    case howItWorksPage: name = "how_it_works"
    default: name = "welcome"
    }
    OnboardingFunnelRecorder.shared.recordPreAuth(name)
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
      currentPage = min(currentPage + 1, howItWorksPage)
    }
  }

  private func skipFromSimulator() {
    let baseline = simulatorBaselineTotals ?? fallbackHowItWorksTotals
    isAdvancingFromSimulatorAdd = true
    howItWorksFromTotals = baseline
    howItWorksToTotals = baseline
    howItWorksShouldShowConfetti = false
    howItWorksShouldAnimateFromPrevious = false
    howItWorksTotalCardSeed += 1

    MotionTokens.animate(.pageTransition, reduceMotion: reduceMotion) {
      currentPage = howItWorksPage
    }
  }

  private func advanceToNextPage() {
    MotionTokens.animate(.pageTransition, reduceMotion: reduceMotion) {
      currentPage += 1
    }
  }

  private func completeAndNavigateToSignup() {
    guard !isCompletingPreAuth else { return }

    guard !reduceMotion else {
      onNavigateToSignup()
      return
    }

    isCompletingPreAuth = true

    DispatchQueue.main.asyncAfter(deadline: .now() + completionHandoffDelay) {
      onNavigateToSignup()
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

extension OnboardingView {
  /// Page content - takes full height, skip button overlaid
  private var pageTabs: some View {
    TabView(selection: $currentPage) {
      WelcomeScreen(currency: preAuthCurrency)
        .tag(0)

      simulatorScreen
        .tag(1)

      HowItWorksScreen(
        totalFrom: howItWorksFromTotals,
        totalTo: howItWorksToTotals,
        currency: preAuthCurrency,
        isActive: currentPage == 2,
        shouldShowConfetti: howItWorksShouldShowConfetti,
        shouldAnimateTotalFromPrevious: howItWorksShouldAnimateFromPrevious,
        totalCardSeed: howItWorksTotalCardSeed,
        isExiting: isCompletingPreAuth,
        showsTitle: false
      )
      .tag(2)

    }
    .tabViewStyle(.page(indexDisplayMode: .never))
    .motionAnimation(.pageTransition, value: currentPage, reduceMotion: reduceMotion)
    .onChange(of: currentPage) { oldPage, newPage in
      handlePageTransition(from: oldPage, to: newPage)
      preloadUpcomingScreen(after: newPage)
      recordFunnelStep(for: newPage)
    }
  }

  private var simulatorScreen: some View {
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
      totalCardSeed: howItWorksTotalCardSeed,
      showsTitle: false
    )
    .frame(width: 1, height: 1)
    .clipped()
    .opacity(0.001)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private var topHeader: some View {
    ZStack(alignment: .center) {
      HStack(alignment: .center, spacing: Spacing.sm) {
        if currentPage == 0 {
          Image("MarketingAppIcon")
            .resizable()
            .scaledToFit()
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityLabel(Text("Tidex"))
        } else if currentPage == howItWorksPage {
          Text(.onboardingHowTitle)
            .font(.tidexScreenTitle)
            .foregroundColor(.tidexTextPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        Spacer(minLength: 0)

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
    }
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, Spacing.lg)
    .padding(.top, Spacing.lg)
    .padding(.bottom, currentPage == howItWorksPage ? Spacing.sm : Spacing.xl)
    .background(Color.tidexBackground)
  }

  private var bottomControls: some View {
    VStack(spacing: Spacing.sm) {
      primaryBottomAction

      PageIndicator(totalPages: totalPages, currentPage: currentPage)
        .onboardingHowExitStep(
          isExiting: isCompletingPreAuth && currentPage == howItWorksPage,
          delay: 0.205
        )
        .padding(.top, Spacing.xxs)

      if currentPage == 0 {
        loginButton
      }
    }
    .padding(.horizontal, Spacing.lg)
    .adaptiveContentWidth()
    .padding(.bottom, Spacing.xs)
    .motionAnimation(.emphasis, value: currentPage, reduceMotion: reduceMotion)
  }

  @ViewBuilder
  private var primaryBottomAction: some View {
    if currentPage < totalPages - 1 {
      if currentPage == 0 {
        firstPageActionRow
      } else {
        OnboardingButton(
          title: String(localized: .commonContinue),
          action: advanceToNextPage
        )
      }
    } else {
      OnboardingButton(
        title: String(localized: .onboardingHowTakeControl),
        action: completeAndNavigateToSignup
      )
      .onboardingHowExitStep(
        isExiting: isCompletingPreAuth && currentPage == howItWorksPage,
        delay: 0.165
      )
    }
  }

  private var firstPageActionRow: some View {
    GeometryReader { geometry in
      let availableWidth = max(0, geometry.size.width - Spacing.sm)
      let skipWidth = availableWidth / 5
      let continueWidth = availableWidth - skipWidth

      HStack(spacing: Spacing.sm) {
        Button {
          Haptics.play(.light)
          completeAndNavigateToSignup()
        } label: {
          Image(systemName: "forward.end.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.tidexTextSecondary)
            .frame(width: skipWidth)
            .frame(height: 54)
            .background(Color.tidexSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
        }
        .buttonStyle(SnappyButtonStyle())
        .accessibilityLabel(Text(.onboardingSkip))

        OnboardingButton(
          title: String(localized: .commonContinue),
          action: advanceToNextPage
        )
        .frame(width: continueWidth)
      }
    }
    .frame(height: 54)
  }

  /// Lets returning users go straight to login instead of through the intro.
  private var loginButton: some View {
    Button {
      Haptics.play(.light)
      onNavigateToLogin()
    } label: {
      Text(.onboardingGetstartedLogin)
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexBlue)
        .lineLimit(1)
        .minimumScaleFactor(0.86)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  OnboardingView(
    onNavigateToSignup: {}
  )
}
