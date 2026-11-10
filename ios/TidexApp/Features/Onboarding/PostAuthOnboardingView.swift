import SwiftUI

/// Setup after sign-up: purpose, job, wage, then the result of the save.
/// The friends-only choice saves from the purpose screen and goes straight to Friends.
struct PostAuthOnboardingView: View {
  let onComplete: () -> Void
  let userId: String

  @State private var currentScreen: PostAuthScreen = .loading
  @State private var onboardingData = OnboardingData()
  @State private var saveManager = OnboardingSaveManager()
  @State private var completionMode: OnboardingCompletionMode = .fullSetup
  @State private var carriedShift = OnboardingFirstShiftCarryoverStore.read()
  @State private var carriedShiftPay: CarriedShiftPay?
  @State private var isNavigatingBack = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase

  enum PostAuthScreen: String {
    case loading
    case purpose
    case jobBasics
    case wage
    /// Keeps the raw value of the success screen it replaced, so its funnel step keeps its name.
    case result = "success"
  }

  var body: some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      currentScreenContent
    }
    .motionAnimation(.navigationPush, value: currentScreen, reduceMotion: reduceMotion)
    .onAppear {
      initializeOnboarding()
    }
    .onChange(of: saveManager.status) { oldStatus, newStatus in
      if oldStatus != .success, newStatus == .success {
        handleSetupSaved()
      }
    }
    .onChange(of: currentScreen) { _, newScreen in
      if newScreen != .loading {
        OnboardingFunnelRecorder.shared.record(
          OnboardingFunnelRecorder.postAuthPrefix + newScreen.rawValue)
      }
      saveProgressIfEditing()
    }
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase == .inactive || newPhase == .background {
        saveProgressIfEditing()
      }
    }
    .onChange(of: onboardingData.jobName) { _, _ in saveProgressIfEditing() }
    .onChange(of: onboardingData.jobColor) { _, _ in saveProgressIfEditing() }
    .onChange(of: onboardingData.wageType) { _, _ in saveProgressIfEditing() }
    .onChange(of: onboardingData.customHourlyWage) { _, _ in saveProgressIfEditing() }
    .onChange(of: onboardingData.selectedTariffLevel) { _, _ in saveProgressIfEditing() }
    .onChange(of: onboardingData.currency) { _, _ in saveProgressIfEditing() }
  }

  // MARK: - Initialization

  private func initializeOnboarding() {
    if let savedScreenName = onboardingData.restore() {
      // Drafts saved on removed steps (supplements, settings, multiple jobs, 2FA) resume at
      // the wage step, the last one before the result.
      let savedScreen = PostAuthScreen(rawValue: savedScreenName) ?? .wage
      if savedScreen != .result, savedScreen != .loading {
        currentScreen = savedScreen
        return
      }
    }

    onboardingData.currency =
      OnboardingCurrencyCarryoverStore.readValidPreferredCurrency()
      ?? OnboardingCurrencyResolver.detectDefaultCurrency()
    onboardingData.hasInitializedWageForLocale = false
    currentScreen = .purpose
  }

  // MARK: - Persistence

  private func saveProgressIfEditing() {
    if currentScreen != .result, currentScreen != .loading {
      onboardingData.save(currentScreen: currentScreen.rawValue)
    }
  }

  // MARK: - Navigation

  private var screenTransition: AnyTransition {
    MotionTokens.navigationTransition(
      direction: isNavigatingBack ? .pop : .push,
      reduceMotion: reduceMotion
    )
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

  // MARK: - Actions

  private func selectFriendsOnly() {
    OnboardingFunnelRecorder.shared.record("purpose_friends")
    completionMode = .friendOnlySkip
    saveManager.startSave(userId: userId, data: onboardingData, completionMode: .friendOnlySkip)
  }

  private func saveSetup() {
    // Break, tax and payday keep their defaults. Outside krone, pay is hours times the wage.
    if onboardingData.usesSimpleSetup {
      onboardingData.applySimpleSetupDefaults()
    }
    completionMode = .fullSetup
    saveManager.startSave(userId: userId, data: onboardingData, completionMode: .fullSetup)
    navigateTo(.result)
  }

  private func handleSetupSaved() {
    OnboardingCurrencyCarryoverStore.clearPreferredCurrency()
    OnboardingFunnelRecorder.shared.record(OnboardingFunnelRecorder.onboardingCompletedStep)

    switch completionMode {
    case .friendOnlySkip:
      finishOnboarding()

    case .fullSetup:
      OnboardingFunnelRecorder.shared.record(
        onboardingData.wageType == .tariff ? "wage_tariff" : "wage_hourly")
      if let carriedShift, let job = saveManager.setupJob {
        carriedShiftPay = CarriedShiftPay(
          shift: carriedShift,
          snapshots: SnapshotsRepository.shared.getSnapshots(for: userId, jobId: job.id),
          currency: job.currency
        )
      }
    }
  }

  private func saveCarriedShift() {
    guard let carriedShift, let jobId = saveManager.setupJob?.id else { return }
    let isFirstShift = CelebrationManager.shared.isFirstShiftSave(for: userId)

    Task {
      guard await saveManager.keepCarriedShift(carriedShift, userId: userId, jobId: jobId) else {
        return
      }
      OnboardingFunnelRecorder.shared.record("demo_shift_saved")
      NotificationCenter.default.postShiftsDidChange(
        context: .affecting(isoDates: carriedShift.dates))
      CelebrationManager.shared.celebrate(dates: Set(carriedShift.dates))
      if isFirstShift {
        CelebrationManager.shared.celebrateFirstShift()
      }
      let landsOnHome = carriedShift.dates.contains { date in
        DashboardFeaturedItemSelector.canFeature(
          shiftDate: date, startTime: carriedShift.startTime, endTime: carriedShift.endTime)
      }
      if !landsOnHome {
        // Home only features a shift that hasn't ended this month, so show it on Schedule.
        AppCoordinator.shared.pendingDeepLink = .shifts(
          dates: carriedShift.dates, shiftIds: nil, action: .highlight)
      }
      requestShiftReminderPermission(afterFirstShift: isFirstShift)
      finishOnboarding()
    }
  }

  /// Same prompt the Add screen shows after a save, after the first-shift confetti has fallen.
  private func requestShiftReminderPermission(afterFirstShift isFirstShift: Bool) {
    let preferences = NotificationPreferencesRepository.shared.getOrCreatePreferences(for: userId)
    guard preferences.shiftRemindersEnabled, !preferences.shiftReminderMinutesArray.isEmpty else {
      return
    }
    Task { [userId] in
      if isFirstShift {
        await FirstShiftConfetti.waitUntilFinished()
      }
      await NotificationService.shared.requestPermissionAndRegister(for: userId)
    }
  }

  private func declineCarriedShift() {
    OnboardingFunnelRecorder.shared.record("demo_shift_dismissed")
    finishOnboarding()
  }

  private func addFirstShift() {
    // MainTabView opens the Add screen when it appears.
    AppCoordinator.shared.pendingDeepLink = .addShift(mode: nil, date: nil)
    finishOnboarding()
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
        Color.tidexBackground
          .ignoresSafeArea()

      case .purpose:
        purposeScreen

      case .jobBasics:
        jobBasicsScreen

      case .wage:
        wageScreen

      case .result:
        resultScreen
      }
    }
  }

  private var purposeScreen: some View {
    PurposeScreen(
      currency: onboardingData.currency,
      friendsSaveStatus: completionMode == .friendOnlySkip ? saveManager.status : .idle,
      onSelectPaySetup: {
        OnboardingFunnelRecorder.shared.record("purpose_pay")
        navigateTo(.jobBasics)
      },
      onSelectFriendsOnly: selectFriendsOnly
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
        navigateBack(to: .purpose)
      }
    )
    .transition(screenTransition)
  }

  private var wageScreen: some View {
    WageScreen(
      data: onboardingData,
      onContinue: saveSetup,
      onBack: {
        navigateBack(to: .jobBasics)
      },
      stepLabel: .onboardingPostAuthStep(2, 2)
    )
    .transition(screenTransition)
  }

  private var resultScreen: some View {
    SetupResultScreen(
      status: saveManager.status,
      carriedShiftPay: carriedShiftPay,
      carriedShiftStatus: saveManager.carriedShiftStatus,
      onRetry: {
        saveManager.startSave(userId: userId, data: onboardingData, completionMode: .fullSetup)
      },
      onBack: {
        navigateBack(to: .wage)
      },
      onSaveCarriedShift: saveCarriedShift,
      onDeclineCarriedShift: declineCarriedShift,
      onAddFirstShift: addFirstShift,
      onFinish: finishOnboarding
    )
    // A soft exit keeps the destination screen from sliding out with it.
    .transition(
      .asymmetric(
        insertion: reduceMotion
          ? .opacity
          : .move(edge: .trailing).combined(with: .opacity),
        removal: .opacity
      ))
  }
}

#Preview {
  PostAuthOnboardingView(
    onComplete: {},
    userId: "test-user-id"
  )
}
