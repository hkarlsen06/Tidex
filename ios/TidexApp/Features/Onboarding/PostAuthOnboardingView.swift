import SwiftUI

enum PostAuthOnboardingEntryMode: Equatable {
  case initial
  case reentry
}

/// Post-auth onboarding flow container
/// Collects job, wage, supplements and settings
/// Creates a baseline wage snapshot before transitioning to the app
struct PostAuthOnboardingView: View {
  let entryMode: PostAuthOnboardingEntryMode
  let onComplete: () -> Void
  let onClose: (() -> Void)?
  let userId: String

  @State private var currentScreen: PostAuthScreen = .loading
  @State private var onboardingData = OnboardingData()
  @State private var saveManager = OnboardingSaveManager()
  @State private var isNavigatingBack = false
  @State private var successCompletionMode: OnboardingCompletionMode = .fullSetup
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  enum PostAuthScreen: String {
    case loading
    case purpose
    case wage
    case supplements
    case jobBasics
    case settingsAccordion
    case success
  }

  var body: some View {
    ZStack {
      // Background
      Color.tidexBackground
        .ignoresSafeArea()

      // Current screen with transition
      currentScreenContent
    }
    .overlay(alignment: .topTrailing) {
      if shouldShowCloseButton {
        closeButton
      }
    }
    .motionAnimation(.navigationPush, value: currentScreen, reduceMotion: reduceMotion)
    .onAppear {
      initializeOnboarding()
    }
    .onChange(of: saveManager.status) { oldStatus, newStatus in
      if oldStatus != .success, newStatus == .success {
        OnboardingCurrencyCarryoverStore.clearPreferredCurrency()
        if entryMode == .initial {
          OnboardingFunnelRecorder.shared.record(OnboardingFunnelRecorder.onboardingCompletedStep)
        }
      }
    }
    .onChange(of: currentScreen) { _, newScreen in
      if entryMode == .initial, newScreen != .loading {
        OnboardingFunnelRecorder.shared.record(
          OnboardingFunnelRecorder.postAuthPrefix + newScreen.rawValue)
      }
      // Save progress when screen changes (except success and loading screens)
      if newScreen != .success, newScreen != .loading {
        saveProgress()
      }
    }
    .onChange(of: scenePhase) { _, newPhase in
      // Save when app goes to background
      if newPhase == .inactive || newPhase == .background {
        saveProgressIfEditing()
      }
    }
    // Save when key data changes within screens
    .onChange(of: onboardingData.supplementRules.count) { _, _ in saveProgressIfEditing() }
    .onChange(of: onboardingData.jobName) { _, _ in saveProgressIfEditing() }
    .onChange(of: onboardingData.jobColor) { _, _ in saveProgressIfEditing() }
    .onChange(of: onboardingData.wageType) { _, _ in saveProgressIfEditing() }
    .onChange(of: onboardingData.customHourlyWage) { _, _ in saveProgressIfEditing() }
    .onChange(of: onboardingData.selectedTariffLevel) { _, _ in saveProgressIfEditing() }
    .onChange(of: onboardingData.breakEnabled) { _, _ in saveProgressIfEditing() }
    .onChange(of: onboardingData.taxEnabled) { _, _ in saveProgressIfEditing() }
    .onChange(of: onboardingData.taxPercentage) { _, _ in saveProgressIfEditing() }
    .onChange(of: onboardingData.payrollDay) { _, _ in saveProgressIfEditing() }
    .onChange(of: onboardingData.currency) { _, _ in saveProgressIfEditing() }
  }

  // MARK: - Initialization

  /// Initialize onboarding by restoring progress
  private func initializeOnboarding() {
    if entryMode == .initial {
      if let savedScreenName = onboardingData.restore() {
        // Drafts saved on the removed multi-job and 2FA steps resume at settings, the step before.
        let savedScreen = PostAuthScreen(rawValue: savedScreenName) ?? .settingsAccordion
        if savedScreen != .success, savedScreen != .loading {
          currentScreen = savedScreen
          return
        }
      }
    } else {
      onboardingData = OnboardingData()
    }

    onboardingData.currency =
      OnboardingCurrencyCarryoverStore.readValidPreferredCurrency()
      ?? OnboardingCurrencyResolver.detectDefaultCurrency()
    onboardingData.hasInitializedWageForLocale = false

    // Default start
    currentScreen = entryMode == .initial ? .purpose : .wage
  }

  // MARK: - Persistence

  private func saveProgress() {
    onboardingData.save(currentScreen: currentScreen.rawValue)
  }

  /// Saves progress unless the loading or success screen is showing.
  private func saveProgressIfEditing() {
    if currentScreen != .success, currentScreen != .loading {
      saveProgress()
    }
  }

  // MARK: - Navigation

  private var screenTransition: AnyTransition {
    MotionTokens.navigationTransition(
      direction: isNavigatingBack ? .pop : .push,
      reduceMotion: reduceMotion
    )
  }

  private func navigateFromWage() {
    // Only show supplements screen for custom wage users
    switch onboardingData.wageType {
    case .tariff:
      navigateTo(.settingsAccordion)

    case .custom:
      if onboardingData.usesSimpleSetup {
        onboardingData.applySimpleSetupDefaults()
        navigateAfterSettings()
      } else {
        navigateTo(.supplements)
      }
    }
  }

  /// Continues to the step after settings. The simple setup for non-krone users jumps here
  /// straight from the wage step.
  private func navigateAfterSettings() {
    startSaveAndNavigateToSuccess()
  }

  private func navigateTo(_ screen: PostAuthScreen) {
    isNavigatingBack = false
    MotionTokens.animate(.navigationPush, reduceMotion: reduceMotion) {
      currentScreen = screen
    }
  }

  private func navigateBack(to screen: PostAuthScreen) {
    isNavigatingBack = true
    MotionTokens.animate(.navigationPop, reduceMotion: reduceMotion) {
      currentScreen = screen
    }
  }

  private func navigateBackFromJobBasics() {
    if entryMode == .initial {
      navigateBack(to: .purpose)
      return
    }

    navigateBack(to: .wage)
  }

  private func navigateBackFromSettings() {
    switch onboardingData.wageType {
    case .custom:
      navigateBack(to: .supplements)

    case .tariff:
      navigateBack(to: .wage)
    }
  }

  private func startSaveAndNavigateToSuccess(
    completionMode: OnboardingCompletionMode = .fullSetup
  ) {
    successCompletionMode = completionMode
    saveManager.prepareForSave(completionMode: completionMode)

    // Navigate to success screen first
    navigateTo(.success)

    // Start saving in the background
    Task {
      await saveManager.saveOnboardingData(
        userId: userId,
        data: onboardingData,
        completionMode: completionMode
      )
    }
  }

  private var shouldShowCloseButton: Bool {
    entryMode == .reentry && currentScreen != .loading && currentScreen != .success
  }

  private func closeOnboarding() {
    OnboardingData.clearSavedData()
    OnboardingCurrencyCarryoverStore.clearPreferredCurrency()
    onClose?()
  }

  private func finishOnboarding() {
    OnboardingData.clearSavedData()
    OnboardingCurrencyCarryoverStore.clearPreferredCurrency()
    OnboardingFirstShiftCarryoverStore.clear()
    onComplete()
  }
}

extension PostAuthOnboardingView {
  private var currentScreenContent: some View {
    Group {
      switch currentScreen {
      case .loading:
        // Brief loading state while restoring progress
        Color.tidexBackground
          .ignoresSafeArea()

      case .purpose:
        purposeScreen

      case .wage:
        wageScreen

      case .supplements:
        supplementsScreen

      case .jobBasics:
        jobBasicsScreen

      case .settingsAccordion:
        settingsScreen

      case .success:
        successScreen
      }
    }
  }

  private var purposeScreen: some View {
    PurposeScreen(
      onSelectPaySetup: {
        navigateTo(.jobBasics)
      },
      onSelectFriendsOnly: {
        startSaveAndNavigateToSuccess(completionMode: .friendOnlySkip)
      }
    )
    .transition(screenTransition)
  }

  private var wageScreen: some View {
    WageScreen(
      data: onboardingData,
      onContinue: {
        navigateFromWage()
      },
      onBack: entryMode == .initial
        ? {
          navigateBack(to: .jobBasics)
        } : nil
    )
    .transition(screenTransition)
  }

  private var supplementsScreen: some View {
    SupplementsScreen(
      data: onboardingData,
      onContinue: {
        navigateTo(.settingsAccordion)
      },
      onBack: {
        navigateBack(to: .wage)
      }
    )
    .transition(screenTransition)
  }

  private var jobBasicsScreen: some View {
    JobBasicsOnboardingScreen(
      data: onboardingData,
      onContinue: {
        navigateTo(.wage)
      },
      onBack: {
        navigateBackFromJobBasics()
      }
    )
    .transition(screenTransition)
  }

  private var settingsScreen: some View {
    SettingsAccordionScreen(
      data: onboardingData,
      onContinue: {
        navigateAfterSettings()
      },
      onBack: {
        navigateBackFromSettings()
      }
    )
    .transition(screenTransition)
  }

  private var successScreen: some View {
    SuccessScreen(
      completionMode: successCompletionMode,
      saveStatus: saveManager.status,
      errorMessage: saveManager.errorMessage,
      onComplete: {
        finishOnboarding()
      },
      onAddFirstShift: {
        if OnboardingFirstShiftCarryoverStore.moveToAddShiftDraft() {
          OnboardingFunnelRecorder.shared.record("demo_shift_prefilled")
        }
        // MainTabView opens the Add screen when it appears, and the Add screen loads the draft.
        AppCoordinator.shared.pendingDeepLink = .addShift(mode: nil, date: nil)
        finishOnboarding()
      },
      onRetry: {
        Task {
          await saveManager.retry(userId: userId, data: onboardingData)
        }
      }
    )
    // Success keeps a softer exit to avoid the destination screen sliding out with it.
    .transition(
      .asymmetric(
        insertion: reduceMotion
          ? .opacity
          : .move(edge: .trailing).combined(with: .opacity),
        removal: .opacity
      ))
  }

  private var closeButton: some View {
    Button {
      closeOnboarding()
    } label: {
      Image(systemName: "xmark")
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextPrimary)
        .frame(width: 36, height: 36)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(Circle())
        .overlay(
          Circle()
            .stroke(Color.tidexBorder, lineWidth: 1)
        )
    }
    .padding(.top, 12)
    .padding(.trailing, Spacing.lg)
    .accessibilityLabel(String(localized: .commonCancel))
  }
}

#Preview {
  PostAuthOnboardingView(
    entryMode: .initial,
    onComplete: {},
    onClose: nil,
    userId: "test-user-id"
  )
}
