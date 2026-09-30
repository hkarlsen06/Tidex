import SwiftUI

/// Pre-auth onboarding flow container: the welcome screen, then the add-shift simulator.
/// Shows value proposition before requiring authentication
struct OnboardingView: View {
  let onNavigateToSignup: () -> Void
  var onNavigateToLogin: () -> Void = {}

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var currentPage = 0
  @State private var preAuthCurrency: String = {
    OnboardingCurrencyCarryoverStore.readValidPreferredCurrency()
      ?? OnboardingCurrencyResolver.detectDefaultCurrency()
  }()
  @State private var shouldPreloadSimulatorScreen = false
  @State private var isCompletingPreAuth = false

  private let totalPages = 2
  private let simulatorPage = 1
  private let completionHandoffDelay: TimeInterval = 0.32

  private var isSimulatorPage: Bool {
    currentPage == simulatorPage
  }

  var body: some View {
    ZStack {
      // Background
      Color.tidexBackground
        .ignoresSafeArea()

      if shouldPreloadSimulatorScreen {
        preloadedSimulatorScreen
      }

      VStack(spacing: 0) {
        // Page content - takes full height, skip button overlaid
        pageTabs

        // Bottom controls area - constrained for iPad
        if !isSimulatorPage {
          bottomControls
        }
      }
      .opacity(isCompletingPreAuth ? 0 : 1)
      .scaleEffect(isCompletingPreAuth ? 0.985 : 1)
      .offset(y: isCompletingPreAuth ? -18 : 0)
      .motionAnimation(.emphasis, value: isCompletingPreAuth, reduceMotion: reduceMotion)
      .allowsHitTesting(!isCompletingPreAuth)
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      if !isSimulatorPage {
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
      shouldPreloadSimulatorScreen = currentPage < simulatorPage
      recordFunnelStep(for: currentPage)
    }
  }

  private func recordFunnelStep(for page: Int) {
    OnboardingFunnelRecorder.shared.recordPreAuth(
      page == simulatorPage ? "add_shift_simulator" : "welcome")
  }

  private func advanceToNextPage() {
    MotionTokens.animate(.pageTransition, reduceMotion: reduceMotion) {
      currentPage += 1
    }
  }

  private func goBackToPreviousPage() {
    MotionTokens.animate(.pageTransition, reduceMotion: reduceMotion) {
      currentPage = max(currentPage - 1, 0)
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
}

extension OnboardingView {
  /// Page content - takes full height, skip button overlaid
  private var pageTabs: some View {
    TabView(selection: $currentPage) {
      WelcomeScreen(currency: preAuthCurrency)
        .tag(0)

      simulatorScreen
        .tag(simulatorPage)
    }
    .tabViewStyle(.page(indexDisplayMode: .never))
    .motionAnimation(.pageTransition, value: currentPage, reduceMotion: reduceMotion)
    .onChange(of: currentPage) { _, newPage in
      shouldPreloadSimulatorScreen = newPage < simulatorPage
      recordFunnelStep(for: newPage)
    }
  }

  private var simulatorScreen: some View {
    PreAuthAddShiftSimulatorScreen(
      initialCurrency: preAuthCurrency,
      onCurrencyChanged: { currency in
        preAuthCurrency = currency
      },
      onContinue: {
        OnboardingFunnelRecorder.shared.recordPreAuth("demo_shift_added")
        completeAndNavigateToSignup()
      },
      onSkip: {
        completeAndNavigateToSignup()
      },
      isPreloaded: false,
      onBack: {
        goBackToPreviousPage()
      }
    )
  }

  private var preloadedSimulatorScreen: some View {
    PreAuthAddShiftSimulatorScreen(
      initialCurrency: preAuthCurrency,
      onCurrencyChanged: { _ in },
      onContinue: {},
      onSkip: {},
      isPreloaded: true
    )
    .frame(width: 1, height: 1)
    .clipped()
    .opacity(0.001)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private var topHeader: some View {
    HStack(alignment: .center, spacing: Spacing.sm) {
      Image("MarketingAppIcon")
        .resizable()
        .scaledToFit()
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(Text("Tidex"))

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
    .frame(maxWidth: AdaptiveMaxWidth.tabContent)
    .frame(maxWidth: .infinity)
    .padding(.horizontal, Spacing.lg)
    .padding(.top, Spacing.lg)
    .padding(.bottom, Spacing.xl)
    .background(Color.tidexBackground)
  }

  private var bottomControls: some View {
    VStack(spacing: Spacing.sm) {
      firstPageActionRow

      PageIndicator(totalPages: totalPages, currentPage: currentPage)
        .padding(.top, Spacing.xxs)

      loginButton
    }
    .padding(.horizontal, Spacing.lg)
    .adaptiveContentWidth()
    .padding(.bottom, Spacing.xs)
    .motionAnimation(.emphasis, value: currentPage, reduceMotion: reduceMotion)
  }

  @ViewBuilder
  private var firstPageActionRow: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(spacing: Spacing.sm) {
        OnboardingButton(
          title: String(localized: .commonContinue),
          action: advanceToNextPage
        )
        skipButton(showsTitle: true)
      }
    } else {
      GeometryReader { geometry in
        let availableWidth = max(0, geometry.size.width - Spacing.sm)
        let skipWidth = availableWidth / 5
        let continueWidth = availableWidth - skipWidth

        HStack(spacing: Spacing.sm) {
          skipButton(showsTitle: false)
            .frame(width: skipWidth)

          OnboardingButton(
            title: String(localized: .commonContinue),
            action: advanceToNextPage
          )
          .frame(width: continueWidth)
        }
      }
      .frame(height: 54)
    }
  }

  private func skipButton(showsTitle: Bool) -> some View {
    Button {
      Haptics.play(.light)
      completeAndNavigateToSignup()
    } label: {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "forward.end.fill")
          .font(.body.weight(.semibold))
          .accessibilityHidden(true)
        if showsTitle {
          Text(.onboardingSkip)
            .font(.tidexHeadline)
            .multilineTextAlignment(.center)
        }
      }
      .foregroundColor(.tidexTextSecondary)
      .frame(maxWidth: .infinity)
      .padding(.vertical, showsTitle ? Spacing.xs : 0)
      .frame(minHeight: 54)
      .background(Color.tidexSurfaceSecondary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
    }
    .buttonStyle(SnappyButtonStyle())
    .accessibilityLabel(Text(.onboardingSkip))
  }

  /// Lets returning users go straight to login instead of through the intro.
  private var loginButton: some View {
    Button {
      Haptics.play(.light)
      onNavigateToLogin()
    } label: {
      Text(.onboardingGetstartedLogin)
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexBlueText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxs)
        .frame(minHeight: 44)
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
