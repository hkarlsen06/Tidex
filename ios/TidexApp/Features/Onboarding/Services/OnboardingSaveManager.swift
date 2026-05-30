import Combine
import Foundation
import Supabase
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "OnboardingSaveManager")

enum OnboardingCompletionMode: Equatable {
  case fullSetup
  case friendOnlySkip
}

/// Handles async save with status tracking for onboarding data
/// Creates baseline wage snapshot and updates settings
@MainActor
final class OnboardingSaveManager: ObservableObject {
  private static let startupTabCacheKey = "defaultStartupTab"

  nonisolated static func defaultJobName(locale: Locale? = nil) -> String {
    guard let locale else {
      return String(
        localized: String.LocalizationValue("jobs.defaultPlaceholderName"),
        table: "Localizable"
      )
    }

    if locale.isNorwegian {
      return "Jobb"
    }

    return "Job"
  }

  // MARK: - Published State

  @Published private(set) var status: SaveStatus = .idle
  @Published private(set) var errorMessage: String?

  // MARK: - Save Status

  enum SaveStatus: Equatable {
    case idle
    case saving
    case success
    case error

    var allowsCompletion: Bool {
      self == .success
    }
  }

  // MARK: - Dependencies

  private let snapshotsRepository: SnapshotsRepository
  private let jobsRepository: JobsRepository
  private let settingsRepository: SettingsRepository
  private let syncCoordinator: SyncCoordinator
  private var lastCompletionMode: OnboardingCompletionMode = .fullSetup

  // MARK: - Init

  init() {
    self.snapshotsRepository = SnapshotsRepository.shared
    self.jobsRepository = JobsRepository.shared
    self.settingsRepository = SettingsRepository.shared
    self.syncCoordinator = SyncCoordinator.shared
  }

  // MARK: - Public API

  /// Save all onboarding data to create baseline snapshot and update settings
  /// - Parameters:
  ///   - userId: The user's ID
  ///   - data: The collected onboarding data
  ///   - completionMode: Whether onboarding should finish with full setup or friend-only skip
  func saveOnboardingData(
    userId: String,
    data: OnboardingData,
    completionMode: OnboardingCompletionMode = .fullSetup
  ) async {
    prepareForSave(completionMode: completionMode)

    logger.info(
      "Starting onboarding save for user: \(userId), mode: \(String(describing: completionMode))")

    do {
      switch completionMode {
      case .fullSetup:
        let snapshot = try await createBaselineSnapshot(userId: userId, data: data)
        logger.info("Created baseline snapshot: \(snapshot.id)")

        try await updateSettings(
          userId: userId,
          payrollDay: data.payrollDay,
          currency: data.currency
        )
        logger.info(
          "Updated settings with payroll day: \(data.payrollDay), currency: \(data.currency)")
      case .friendOnlySkip:
        try await prepareFriendOnlySkip(userId: userId, data: data)
        logger.info("Prepared friend-only skip state")
      }

      try await markOnboardingFinished()
      logger.info("Marked onboarding as finished in user metadata")

      if completionMode == .friendOnlySkip {
        clearOnboardingDraftState()
      }

      let syncResult = await syncCoordinator.sync(reason: .localChange, userId: userId)
      if syncResult.success {
        logger.info("Sync completed successfully")
      } else {
        // Non-blocking - sync will retry later
        logger.warning("Sync had issues but continuing: \(syncResult.error ?? "unknown")")
      }

      status = .success
      logger.info("Onboarding save completed successfully")

    } catch {
      status = .error
      errorMessage = error.localizedDescription
      logger.error("Failed to save onboarding data: \(error.localizedDescription)")
    }
  }

  /// Move the state machine into the pending save state before the success screen is shown.
  func prepareForSave(completionMode: OnboardingCompletionMode = .fullSetup) {
    status = .saving
    errorMessage = nil
    lastCompletionMode = completionMode
  }

  /// Retry saving after an error
  func retry(userId: String, data: OnboardingData) async {
    await saveOnboardingData(userId: userId, data: data, completionMode: lastCompletionMode)
  }

  // MARK: - Private Helpers

  private func createBaselineSnapshot(userId: String, data: OnboardingData) async throws
    -> WageSnapshot
  {
    let activeSetupJob =
      jobsRepository.getDefaultJob(for: userId)
      ?? jobsRepository.getActiveJobs(for: userId).first

    if let activeSetupJob {
      let preparedJob = try await ensureJobMetadata(
        userId: userId,
        job: activeSetupJob,
        data: data
      )
      return try await ensureBaselineSnapshot(
        userId: userId,
        job: preparedJob,
        data: data
      )
    }

    // Avoid relying on the server-side lazy default-job trigger here.
    // Onboarding waits for a single sync cycle, and sync runs pull -> push,
    // so a job created remotely during snapshot push is not visible locally
    // until a second sync/pull. Creating the job locally keeps work setup
    // complete on the first post-onboarding render.
    let createdJob = try await jobsRepository.createJob(
      userId: userId,
      name: data.resolvedJobName(),
      color: data.jobColor,
      currency: resolvedJobCurrency(for: data),
      payrollDay: data.payrollDay,
      halfTaxMonth: nil,
      monthlyGoal: nil
    )

    logger.info("Created onboarding default job: \(createdJob.id)")

    return try await ensureBaselineSnapshot(
      userId: userId,
      job: createdJob,
      data: data
    )
  }

  private func ensureJobMetadata(
    userId: String,
    job: Job,
    data: OnboardingData
  ) async throws -> Job {
    let resolvedName = data.resolvedJobName()
    let resolvedColor = data.jobColor

    guard job.name != resolvedName || job.color != resolvedColor else {
      return job
    }

    return try await jobsRepository.updateJob(
      userId: userId,
      jobId: job.id,
      name: resolvedName,
      color: resolvedColor
    ) ?? job
  }

  private func ensureBaselineSnapshot(
    userId: String,
    job: Job,
    data: OnboardingData
  ) async throws -> WageSnapshot {
    if let existingSnapshot = snapshotsRepository.getBaselineSnapshot(for: userId, jobId: job.id) {
      return existingSnapshot
    }

    if let legacyBaselineSnapshot = snapshotsRepository.getBaselineSnapshot(for: userId),
      legacyBaselineSnapshot.job_id == nil,
      let updatedLegacySnapshot = try await snapshotsRepository.updateSnapshot(
        id: legacyBaselineSnapshot.id,
        jobId: job.id
      )
    {
      logger.info(
        "Attached legacy onboarding baseline snapshot \(legacyBaselineSnapshot.id) to job \(job.id)"
      )
      return updatedLegacySnapshot
    }

    return try await snapshotsRepository.createSnapshot(
      userId: userId,
      jobId: job.id,
      fromDate: nil,
      hourlyWage: data.resolvedHourlyWage,
      wageLevel: data.resolvedWageLevel,
      tariffTypeId: data.resolvedTariffTypeId,
      supplements: data.resolvedSupplements,
      taxEnabled: data.taxEnabled,
      taxPercentage: data.taxEnabled ? data.taxPercentage : nil,
      breakEnabled: data.breakEnabled,
      breakMethod: "proportional",
      breakThresholdHours: 5.5,
      breakDeductionMinutes: 30
    )
  }

  private func resolvedJobCurrency(for data: OnboardingData) -> String {
    if data.resolvedWageLevel != nil || data.resolvedTariffTypeId != nil {
      return "kr"
    }

    return data.currency
  }

  private func updateSettings(userId: String, payrollDay: Int, currency: String) async throws {
    // Use getOrCreateSettings to handle the case where no settings exist yet (new user)
    _ = try await settingsRepository.getOrCreateSettings(
      for: userId,
      payrollDay: payrollDay,
      currency: currency
    )
  }

  private func prepareFriendOnlySkip(userId: String, data: OnboardingData) async throws {
    _ = try await settingsRepository.getOrCreateSettings(for: userId, currency: data.currency)

    _ = try await settingsRepository.updateSettings(
      for: userId,
      defaultStartupTab: "sharing",
      triggerSync: false
    )

    UserDefaults.standard.set("sharing", forKey: Self.startupTabCacheKey)
  }

  private func markOnboardingFinished() async throws {
    _ = try await supabase.auth.update(
      user: UserAttributes(
        data: ["finishedOnboarding": .bool(true)]
      )
    )
  }

  private func clearOnboardingDraftState() {
    OnboardingData.clearSavedData()
    OnboardingCurrencyCarryoverStore.clearPreferredCurrency()
  }
}
