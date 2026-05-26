import CoreImage.CIFilterBuiltins
import Supabase
import SwiftUI

enum PostAuthOnboardingEntryMode: Equatable {
  case initial
  case reentry
}

/// Post-auth onboarding flow container
/// Collects wage, supplements, settings, and optionally MFA setup
/// Creates a baseline wage snapshot before transitioning to the app
struct PostAuthOnboardingView: View {
  let entryMode: PostAuthOnboardingEntryMode
  let onComplete: () -> Void
  let onClose: (() -> Void)?
  let userId: String

  @State private var currentScreen: PostAuthScreen = .loading
  @State private var onboardingData = OnboardingData()
  @StateObject private var saveManager = OnboardingSaveManager()
  @State private var showingMFAEnrollment = false
  @State private var showAddJobSheet = false
  @State private var addJobSheetPresentationID = UUID()
  @State private var isPreparingJobSheet = false
  @State private var navigateToMFAAfterJobSheet = false
  @State private var onboardingActiveJobs: [Job] = []
  @State private var onboardingJobNeedingSetup: Job?
  @State private var temporaryPlaceholderJobId: String?
  @State private var multiJobErrorMessage: String?
  @State private var isNavigatingBack = false
  @State private var successCompletionMode: OnboardingCompletionMode = .fullSetup
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  private let jobsRepository = JobsRepository.shared
  private let snapshotsRepository = SnapshotsRepository.shared
  private let syncCoordinator = SyncCoordinator.shared

  enum PostAuthScreen: String {
    case loading
    case purpose
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

        case .purpose:
          PurposeScreen(
            onSelectPaySetup: {
              navigateTo(.wage)
            },
            onSelectFriendsOnly: {
              startSaveAndNavigateToSuccess(completionMode: .friendOnlySkip)
            }
          )
          .transition(screenTransition)

        case .wage:
          WageScreen(
            data: onboardingData,
            onContinue: {
              navigateFromWage()
            },
            onBack: entryMode == .initial
              ? {
                navigateBack(to: .purpose)
              } : nil
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
            completionMode: successCompletionMode,
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
    .overlay(alignment: .topTrailing) {
      if shouldShowCloseButton {
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
        } else {
          Task {
            await discardTemporaryPlaceholderIfNeeded()
          }
        }
      }
    ) {
      AddJobSheet(
        initialCurrency: onboardingData.currency,
        existingJobNeedingSetup: nil
      ) { input in
        await createOnboardingJob(input: input)
      }
      .id(addJobSheetPresentationID)
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
    if entryMode == .initial {
      if let savedScreenName = onboardingData.restore(),
        let savedScreen = PostAuthScreen(rawValue: savedScreenName),
        savedScreen != .success && savedScreen != .loading
      {
        currentScreen = savedScreen
        return
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

  private func prepareJobsForOnboardingAdd() async {
    defer { isPreparingJobSheet = false }

    guard !userId.isEmpty else {
      multiJobErrorMessage = String(localized: "settings.pay.choose_job.error_not_authenticated")
      return
    }

    multiJobErrorMessage = nil
    var activeJobs = jobsRepository.getActiveJobs(for: userId)

    if activeJobs.isEmpty {
      _ = await syncCoordinator.sync(reason: .manualRefresh, userId: userId)
      guard currentScreen == .multiJobPrompt else { return }
      activeJobs = jobsRepository.getActiveJobs(for: userId)
    }

    if activeJobs.isEmpty && entryMode == .reentry {
      do {
        let placeholderJob = try await jobsRepository.createJob(
          userId: userId,
          name: OnboardingSaveManager.defaultJobName(),
          color: nil,
          currency: onboardingData.currency.isEmpty ? "kr" : onboardingData.currency,
          payrollDay: onboardingData.payrollDay,
          halfTaxMonth: nil,
          monthlyGoal: nil
        )
        activeJobs = [placeholderJob]
        temporaryPlaceholderJobId = placeholderJob.id
      } catch {
        multiJobErrorMessage = error.localizedDescription
        return
      }
    }

    onboardingActiveJobs = activeJobs
    onboardingJobNeedingSetup = incompleteSetupJob(from: activeJobs)
    addJobSheetPresentationID = UUID()
    showAddJobSheet = true
  }

  private func createOnboardingJob(input: AddJobSetupInput) async -> Bool {
    guard !userId.isEmpty else {
      multiJobErrorMessage = String(localized: "settings.pay.choose_job.error_not_authenticated")
      return false
    }

    do {
      if let jobNeedingSetup = onboardingJobNeedingSetup {
        try await completeOnboardingSetup(for: jobNeedingSetup, input: input)

        if jobNeedingSetup.id == temporaryPlaceholderJobId {
          temporaryPlaceholderJobId = nil
        }
      } else {
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
      }

      onboardingActiveJobs = jobsRepository.getActiveJobs(for: userId)
      onboardingJobNeedingSetup = incompleteSetupJob(from: onboardingActiveJobs)
      multiJobErrorMessage = nil
      navigateToMFAAfterJobSheet = true
      return true
    } catch {
      multiJobErrorMessage = error.localizedDescription
      return false
    }
  }

  private func completeOnboardingSetup(for job: Job, input: AddJobSetupInput) async throws {
    guard
      try await jobsRepository.updateJob(
        userId: userId,
        jobId: job.id,
        name: input.name,
        color: input.color
      ) != nil
    else {
      throw JobsRepositoryError.jobNotFound
    }

    if job.currency != input.currency {
      guard
        try await jobsRepository.updateJobCurrency(
          userId: userId,
          jobId: job.id,
          currency: input.currency
        ) != nil
      else {
        throw JobsRepositoryError.jobNotFound
      }
    }

    guard
      try await jobsRepository.updateJobPaySettings(
        userId: userId,
        jobId: job.id,
        payrollDay: input.payrollDay,
        halfTaxMonth: input.halfTaxMonth,
        monthlyGoal: input.monthlyGoal
      ) != nil
    else {
      throw JobsRepositoryError.jobNotFound
    }

    _ = try await snapshotsRepository.createSnapshot(
      userId: userId,
      jobId: job.id,
      fromDate: nil,
      hourlyWage: input.baselineSnapshot.hourlyWage,
      wageLevel: input.baselineSnapshot.wageLevel,
      tariffTypeId: input.baselineSnapshot.tariffTypeId,
      supplements: input.baselineSnapshot.supplements,
      taxEnabled: input.baselineSnapshot.taxEnabled,
      taxPercentage: input.baselineSnapshot.taxPercentage,
      breakEnabled: input.baselineSnapshot.breakEnabled,
      breakMethod: input.baselineSnapshot.breakMethod,
      breakThresholdHours: input.baselineSnapshot.breakThresholdHours,
      breakDeductionMinutes: input.baselineSnapshot.breakDeductionMinutes
    )
  }

  private func incompleteSetupJob(from activeJobs: [Job]) -> Job? {
    let status = WorkSetupStatusResolver.resolve(activeJobs: activeJobs) { jobId in
      snapshotsRepository.getBaselineSnapshot(for: userId, jobId: jobId) != nil
    }

    guard !status.hasBaselineSnapshotForActiveSetupJob,
      let activeSetupJobId = status.activeSetupJobId
    else {
      return nil
    }

    return activeJobs.first(where: { $0.id == activeSetupJobId })
  }

  private var shouldShowCloseButton: Bool {
    entryMode == .reentry && currentScreen != .loading && currentScreen != .success
  }

  private func closeOnboarding() {
    OnboardingData.clearSavedData()
    OnboardingCurrencyCarryoverStore.clearPreferredCurrency()
    Task {
      await discardTemporaryPlaceholderIfNeeded()
      onClose?()
    }
  }

  private func discardTemporaryPlaceholderIfNeeded() async {
    guard let temporaryPlaceholderJobId else { return }

    let otherActiveJobs = jobsRepository.getActiveJobs(for: userId).filter {
      $0.id != temporaryPlaceholderJobId
    }

    do {
      if let replacementJob = otherActiveJobs.first {
        try await jobsRepository.setDefaultJob(userId: userId, jobId: replacementJob.id)
      }

      try await jobsRepository.discardIncompleteJob(
        userId: userId,
        jobId: temporaryPlaceholderJobId
      )
    } catch {
      multiJobErrorMessage = error.localizedDescription
    }

    self.temporaryPlaceholderJobId = nil
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
            .textContentType(.oneTimeCode)
            .multilineTextAlignment(.center)
            .font(.tidexMonoTitle)
            .frame(width: 160)
            .padding(Spacing.sm)
            .background(Color.tidexSurfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
            .onChange(of: verificationCode) { _, newValue in
              let filtered = newValue.filter { $0.isNumber }
              if filtered.count > 6 {
                verificationCode = String(filtered.prefix(6))
              } else if filtered != newValue {
                verificationCode = filtered
              }
            }
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
    entryMode: .initial,
    onComplete: {},
    onClose: nil,
    userId: "test-user-id"
  )
}
