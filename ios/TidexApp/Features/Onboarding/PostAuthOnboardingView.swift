import CoreImage.CIFilterBuiltins
import Supabase
import SwiftUI

/// Post-auth onboarding flow container
/// Collects wage, supplements, settings, and optionally MFA setup
/// Creates a baseline wage snapshot before transitioning to the app
struct PostAuthOnboardingView: View {
  let onComplete: () -> Void
  let userId: String

  @State private var currentScreen: PostAuthScreen = .loading
  @State private var onboardingData = OnboardingData()
  @StateObject private var saveManager = OnboardingSaveManager()
  @State private var showingMFAEnrollment = false
  @State private var showAddJobSheet = false
  @State private var isPreparingJobSheet = false
  @State private var navigateToMFAAfterJobSheet = false
  @State private var onboardingActiveJobs: [Job] = []
  @State private var multiJobErrorMessage: String?
  @State private var isNavigatingBack = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  private let jobsRepository = JobsRepository.shared
  private let syncCoordinator = SyncCoordinator.shared

  enum PostAuthScreen: String {
    case loading
    case wage
    case supplements
    case settingsAccordion
    case multiJobPrompt
    case mfaSetup
    case success
  }

  var body: some View {
    ZStack {
      // Background
      Color.tidexBackground
        .ignoresSafeArea()

      // Current screen with transition
      Group {
        switch currentScreen {
        case .loading:
          // Brief loading state while restoring progress
          Color.tidexBackground
            .ignoresSafeArea()

        case .wage:
          WageScreen(
            data: onboardingData,
            onContinue: {
              navigateFromWage()
            },
            onBack: nil
          )
          .transition(screenTransition)

        case .supplements:
          SupplementsScreen(
            data: onboardingData,
            onContinue: {
              navigateTo(.settingsAccordion)
            },
            onSkip: {
              navigateTo(.settingsAccordion)
            },
            onBack: {
              navigateBack(to: .wage)
            }
          )
          .transition(screenTransition)

        case .settingsAccordion:
          SettingsAccordionScreen(
            data: onboardingData,
            onContinue: {
              navigateTo(.multiJobPrompt)
            },
            onBack: {
              navigateBackFromSettings()
            }
          )
          .transition(screenTransition)

        case .multiJobPrompt:
          MultiJobPromptScreen(
            isLoading: isPreparingJobSheet,
            onAddNow: {
              isPreparingJobSheet = true
              Task {
                await prepareJobsForOnboardingAdd()
              }
            },
            onContinueLater: {
              navigateTo(.mfaSetup)
            },
            onBack: {
              navigateBack(to: .settingsAccordion)
            },
            errorMessage: multiJobErrorMessage
          )
          .transition(screenTransition)

        case .mfaSetup:
          MFASetupScreen(
            onSetupMFA: {
              showingMFAEnrollment = true
            },
            onSkip: {
              startSaveAndNavigateToSuccess()
            },
            onBack: {
              navigateBack(to: .multiJobPrompt)
            }
          )
          .transition(screenTransition)

        case .success:
          SuccessScreen(
            saveStatus: saveManager.status,
            errorMessage: saveManager.errorMessage,
            onComplete: {
              // Clear saved onboarding draft data on successful completion
              OnboardingData.clearSavedData()
              OnboardingCurrencyCarryoverStore.clearPreferredCurrency()
              onComplete()
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
      }
    }
    .motionAnimation(.navigationPush, value: currentScreen, reduceMotion: reduceMotion)
    .sheet(isPresented: $showingMFAEnrollment) {
      MFAEnrollmentSheet(
        onComplete: {
          showingMFAEnrollment = false
          startSaveAndNavigateToSuccess()
        },
        onCancel: {
          showingMFAEnrollment = false
        }
      )
    }
    .sheet(
      isPresented: $showAddJobSheet,
      onDismiss: {
        if navigateToMFAAfterJobSheet {
          navigateToMFAAfterJobSheet = false
          navigateTo(.mfaSetup)
        }
      }
    ) {
      AddJobSheet(
        initialCurrency: onboardingData.currency,
        existingJobNeedingSetup: onboardingActiveJobs.count == 1 ? onboardingActiveJobs.first : nil
      ) { input in
        await createOnboardingJob(input: input)
      }
    }
    .onAppear {
      initializeOnboarding()
    }
    .onChange(of: saveManager.status) { oldStatus, newStatus in
      if oldStatus != .success && newStatus == .success {
        OnboardingCurrencyCarryoverStore.clearPreferredCurrency()
      }
    }
    .onChange(of: currentScreen) { _, newScreen in
      // Save progress when screen changes (except success and loading screens)
      if newScreen != .success && newScreen != .loading {
        saveProgress()
      }
    }
    .onChange(of: scenePhase) { _, newPhase in
      // Save when app goes to background
      if newPhase == .inactive || newPhase == .background {
        if currentScreen != .success && currentScreen != .loading {
          saveProgress()
        }
      }
    }
    // Save when key data changes within screens
    .onChange(of: onboardingData.supplementRules.count) { _, _ in
      if currentScreen != .success && currentScreen != .loading {
        saveProgress()
      }
    }
    .onChange(of: onboardingData.wageType) { _, _ in
      if currentScreen != .success && currentScreen != .loading {
        saveProgress()
      }
    }
    .onChange(of: onboardingData.customHourlyWage) { _, _ in
      if currentScreen != .success && currentScreen != .loading {
        saveProgress()
      }
    }
    .onChange(of: onboardingData.selectedTariffLevel) { _, _ in
      if currentScreen != .success && currentScreen != .loading {
        saveProgress()
      }
    }
    .onChange(of: onboardingData.breakEnabled) { _, _ in
      if currentScreen != .success && currentScreen != .loading {
        saveProgress()
      }
    }
    .onChange(of: onboardingData.taxEnabled) { _, _ in
      if currentScreen != .success && currentScreen != .loading {
        saveProgress()
      }
    }
    .onChange(of: onboardingData.taxPercentage) { _, _ in
      if currentScreen != .success && currentScreen != .loading {
        saveProgress()
      }
    }
    .onChange(of: onboardingData.payrollDay) { _, _ in
      if currentScreen != .success && currentScreen != .loading {
        saveProgress()
      }
    }
    .onChange(of: onboardingData.currency) { _, _ in
      if currentScreen != .success && currentScreen != .loading {
        saveProgress()
      }
    }
  }

  // MARK: - Initialization

  /// Initialize onboarding by restoring progress
  private func initializeOnboarding() {
    // Try to restore saved progress
    if let savedScreenName = onboardingData.restore(),
      let savedScreen = PostAuthScreen(rawValue: savedScreenName),
      savedScreen != .success && savedScreen != .loading
    {
      currentScreen = savedScreen
      return
    }

    onboardingData.currency =
      OnboardingCurrencyCarryoverStore.readValidPreferredCurrency()
      ?? OnboardingCurrencyResolver.detectDefaultCurrency()
    onboardingData.hasInitializedWageForLocale = false

    // Default start
    currentScreen = .wage
  }

  // MARK: - Persistence

  private func saveProgress() {
    onboardingData.save(currentScreen: currentScreen.rawValue)
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
      navigateTo(.supplements)
    }
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

  private func navigateBackFromSettings() {
    // Go back to supplements for custom wage, otherwise to wage
    switch onboardingData.wageType {
    case .custom:
      navigateBack(to: .supplements)
    case .tariff:
      navigateBack(to: .wage)
    }
  }

  private func startSaveAndNavigateToSuccess() {
    // Navigate to success screen first
    navigateTo(.success)

    // Start saving in the background
    Task {
      await saveManager.saveOnboardingData(userId: userId, data: onboardingData)
    }
  }

  private func prepareJobsForOnboardingAdd() async {
    defer { isPreparingJobSheet = false }

    guard !userId.isEmpty else {
      multiJobErrorMessage = String(localized: "settings.pay.choose_job.error_not_authenticated")
      return
    }

    multiJobErrorMessage = nil
    let activeJobs = jobsRepository.getActiveJobs(for: userId)

    if activeJobs.isEmpty {
      _ = await syncCoordinator.sync(reason: .manualRefresh, userId: userId)
      guard currentScreen == .multiJobPrompt else { return }
      let jobsAfterSync = jobsRepository.getActiveJobs(for: userId)
      guard !jobsAfterSync.isEmpty else {
        multiJobErrorMessage = String(localized: .settingsPayErrorLoadFailed)
        return
      }
      onboardingActiveJobs = jobsAfterSync
      showAddJobSheet = true
      return
    }

    onboardingActiveJobs = activeJobs
    showAddJobSheet = true
  }

  private func createOnboardingJob(input: AddJobSetupInput) async -> Bool {
    guard !userId.isEmpty else {
      multiJobErrorMessage = String(localized: "settings.pay.choose_job.error_not_authenticated")
      return false
    }

    do {
      if let existingJobSetup = input.existingJobSetup {
        guard
          try await jobsRepository.updateJob(
            userId: userId,
            jobId: existingJobSetup.id,
            name: existingJobSetup.name,
            color: existingJobSetup.color
          ) != nil
        else {
          multiJobErrorMessage = String(localized: .settingsPayErrorLoadFailed)
          return false
        }
      }

      _ = try await jobsRepository.createJobWithBaselineSnapshot(
        userId: userId,
        name: input.name,
        color: input.color,
        currency: input.currency,
        payrollDay: input.payrollDay,
        halfTaxMonth: input.halfTaxMonth,
        monthlyGoal: input.monthlyGoal,
        baselineSnapshot: input.baselineSnapshot
      )

      onboardingActiveJobs = jobsRepository.getActiveJobs(for: userId)
      multiJobErrorMessage = nil
      navigateToMFAAfterJobSheet = true
      return true
    } catch {
      multiJobErrorMessage = error.localizedDescription
      return false
    }
  }
}

// MARK: - MFA Enrollment Sheet

/// Sheet for MFA enrollment using Supabase MFA APIs
private struct MFAEnrollmentSheet: View {
  let onComplete: () -> Void
  let onCancel: () -> Void

  @State private var isEnrolling = false
  @State private var totpUri: String?
  @State private var secret: String?
  @State private var factorId: String?
  @State private var verificationCode = ""
  @State private var errorMessage: String?
  @State private var showingAddToPasswordsSheet = false

  var body: some View {
    NavigationStack {
      ZStack {
        Color.tidexBackground
          .ignoresSafeArea()

        VStack(spacing: Spacing.lg) {
          if isEnrolling {
            ProgressView()
              .progressViewStyle(.circular)
            Text(.onboardingMfaEnrolling)
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextSecondary)
          } else if totpUri != nil {
            // Show QR code and verification input
            mfaVerificationView()
          } else {
            // Waiting state before auto-start
            ProgressView()
              .progressViewStyle(.circular)
            Text(.onboardingMfaEnrolling)
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextSecondary)
          }

          if let error = errorMessage {
            Text(error)
              .font(.tidexSubheadline)
              .foregroundColor(.tidexError)
              .multilineTextAlignment(.center)
              .padding(.horizontal, Spacing.lg)
          }
        }
      }
      .navigationTitle(String(localized: .onboardingMfaSetupTitle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .commonCancel)) {
            onCancel()
          }
        }
      }
      .onAppear {
        // Auto-start enrollment when sheet opens
        if !isEnrolling && totpUri == nil {
          startEnrollment()
        }
      }
    }
  }

  @ViewBuilder
  private func mfaVerificationView() -> some View {
    ScrollView {
      VStack(spacing: Spacing.mlg) {
        Text(.onboardingMfaScanQR)
          .font(.tidexBody)
          .foregroundColor(.tidexTextPrimary)
          .multilineTextAlignment(.center)

        // QR Code - Generated natively from otpauth:// URI
        if let totpUri = totpUri, let qrImage = generateQRCode(from: totpUri) {
          Image(uiImage: qrImage)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: 200, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
            .background(
              RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color.white)
            )
        } else {
          Rectangle()
            .fill(Color.tidexSurfaceSecondary)
            .frame(width: 200, height: 200)
            .overlay(
              Text(.onboardingMfaQrCodeUnavailable)
                .font(.tidexSubheadline)
                .foregroundColor(.tidexTextMuted)
            )
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
        }

        // Add to Passwords button
        if let totpUri = totpUri, let secret = secret {
          Button(action: {
            addToiCloudKeychain(uri: totpUri, secret: secret)
          }) {
            HStack(spacing: Spacing.xs) {
              Image(systemName: "key.fill")
                .font(.tidexBody)
              Text(.onboardingMfaAddToPasswords)
                .font(.tidexLabel)
            }
            .foregroundColor(.tidexBlue)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color.tidexBlue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous))
          }
        }

        if let secret = secret {
          VStack(spacing: Spacing.xxs) {
            Text(.onboardingMfaManualEntry)
              .font(.tidexFootnote)
              .foregroundColor(.tidexTextMuted)

            HStack(spacing: Spacing.xs) {
              Text(secret)
                .font(.tidexMonoLabel)
                .foregroundColor(.tidexTextSecondary)

              Button(action: {
                UIPasteboard.general.string = secret
                UINotificationFeedbackGenerator().notificationOccurred(.success)
              }) {
                Image(systemName: "doc.on.doc")
                  .font(.tidexSubheadline)
                  .foregroundColor(.tidexBlue)
              }
            }
            .padding(Spacing.xs)
            .background(Color.tidexSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs))
          }
        }

        VStack(spacing: Spacing.xs) {
          Text(.onboardingMfaEnterCode)
            .font(.tidexLabel)
            .foregroundColor(.tidexTextSecondary)

          TextField("000000", text: $verificationCode)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .font(.tidexMonoTitle)
            .frame(width: 160)
            .padding(Spacing.sm)
            .background(Color.tidexSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
        }

        Button(action: verifyCode) {
          Text(.onboardingMfaVerify)
            .font(.tidexHeadline)
            .foregroundColor(.tidexTextOnBrand)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
              verificationCode.count == 6
                ? Color.tidexBrandPrimary : Color.tidexBrandPrimary.opacity(0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
        }
        .disabled(verificationCode.count != 6)
        .padding(.horizontal, Spacing.lg)
      }
      .padding(Spacing.lg)
    }
  }

  /// Generate QR code from a string using CoreImage
  private func generateQRCode(from string: String) -> UIImage? {
    let context = CIContext()
    let filter = CIFilter.qrCodeGenerator()

    guard let data = string.data(using: .utf8) else { return nil }
    filter.setValue(data, forKey: "inputMessage")
    filter.setValue("H", forKey: "inputCorrectionLevel")  // High error correction

    guard let ciImage = filter.outputImage else { return nil }

    // Scale up the QR code for better quality
    let scale = 10.0
    let transform = CGAffineTransform(scaleX: scale, y: scale)
    let scaledImage = ciImage.transformed(by: transform)

    guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
      return nil
    }
    return UIImage(cgImage: cgImage)
  }

  /// Add TOTP to iCloud Keychain / iOS Password Manager
  private func addToiCloudKeychain(uri: String, secret: String) {
    // Open the otpauth:// URI which will trigger iOS to offer adding it to Passwords
    // This works on iOS 15+ and uses the native password manager integration
    if let url = URL(string: uri) {
      UIApplication.shared.open(url, options: [:]) { success in
        if success {
          UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
      }
    }
  }

  private func startEnrollment() {
    isEnrolling = true
    errorMessage = nil

    Task {
      do {
        let response = try await supabase.auth.mfa.enroll(
          params: .totp(issuer: "Tidex", friendlyName: "Tidex 2FA")
        )
        factorId = response.id
        totpUri = response.totp?.uri  // Use URI for native QR generation
        secret = response.totp?.secret
        isEnrolling = false
      } catch {
        errorMessage = error.localizedDescription
        isEnrolling = false
      }
    }
  }

  private func verifyCode() {
    guard let factorId = factorId else { return }

    isEnrolling = true
    errorMessage = nil

    Task {
      do {
        // Challenge and verify in one step
        try await supabase.auth.mfa.challengeAndVerify(
          params: MFAChallengeAndVerifyParams(
            factorId: factorId,
            code: verificationCode
          )
        )

        isEnrolling = false
        onComplete()
      } catch {
        errorMessage = error.localizedDescription
        isEnrolling = false
      }
    }
  }
}

#Preview {
  PostAuthOnboardingView(
    onComplete: {},
    userId: "test-user-id"
  )
}
