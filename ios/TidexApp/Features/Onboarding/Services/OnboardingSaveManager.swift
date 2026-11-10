import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "OnboardingSaveManager")

enum OnboardingCompletionMode: Equatable {
  case fullSetup
  case friendOnlySkip
}

/// Saves the setup collected after sign-up, and the demo shift carried over from before it.
@MainActor
@Observable
final class OnboardingSaveManager {
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

  private(set) var status: SaveStatus = .idle
  /// Saving the carried demo shift after setup succeeded.
  private(set) var carriedShiftStatus: SaveStatus = .idle
  /// The job setup saved the wage to. Set when the setup save succeeds.
  private(set) var setupJob: Job?

  // MARK: - Save Status

  enum SaveStatus: Equatable {
    case idle
    case saving
    case success
    case error(message: String)
  }

  typealias ShiftCreator =
    @MainActor (_ userId: String, _ jobId: String, _ date: Date, _ startTime: String, _ endTime: String)
    async throws -> Void

  // MARK: - Dependencies

  private let snapshotsRepository: SnapshotsRepository
  private let jobsRepository: JobsRepository
  private let settingsRepository: SettingsRepository
  private let syncCoordinator: SyncCoordinator
  private let defaults: UserDefaults
  private let createShift: ShiftCreator
  private var savedCarriedDates: Set<String> = []

  // MARK: - Init

  init(defaults: UserDefaults = .standard, createShift: ShiftCreator? = nil) {
    self.snapshotsRepository = SnapshotsRepository.shared
    self.jobsRepository = JobsRepository.shared
    self.settingsRepository = SettingsRepository.shared
    self.syncCoordinator = SyncCoordinator.shared
    self.defaults = defaults
    self.createShift =
      createShift ?? { userId, jobId, date, startTime, endTime in
        _ = try await ShiftsRepository.shared.createShift(
          userId: userId, jobId: jobId, shiftDate: date, startTime: startTime, endTime: endTime)
      }
  }

  // MARK: - Public API

  func startSave(userId: String, data: OnboardingData, completionMode: OnboardingCompletionMode) {
    guard status != .saving else { return }
    status = .saving
    Task {
      await save(userId: userId, data: data, completionMode: completionMode)
    }
  }

  /// Saves the carried demo shift as one shift per date on the setup job, through the same
  /// repository call as the Add screen. A retry after a partial failure skips the dates
  /// already saved, so no date is saved twice.
  func keepCarriedShift(_ shift: CarriedDemoShift, userId: String, jobId: String) async -> Bool {
    guard carriedShiftStatus != .saving else { return false }
    carriedShiftStatus = .saving

    do {
      for isoDate in shift.dates where !savedCarriedDates.contains(isoDate) {
        guard let date = Date.fromISODateString(isoDate) else {
          throw ShiftSaveError.invalidDate
        }
        try await createShift(userId, jobId, date, shift.startTime, shift.endTime)
        savedCarriedDates.insert(isoDate)
      }
    } catch {
      logger.error("Failed to save the carried demo shift: \(error.localizedDescription)")
      carriedShiftStatus = .error(
        message: Self.message(for: error, fallback: .onboardingSuccessShiftSaveFailed))
      return false
    }

    OnboardingFirstShiftCarryoverStore.clear(defaults: defaults)
    carriedShiftStatus = .success
    return true
  }

  private func save(
    userId: String,
    data: OnboardingData,
    completionMode: OnboardingCompletionMode
  ) async {
    logger.info(
      "Starting onboarding save for user: \(userId), mode: \(String(describing: completionMode))")

    do {
      switch completionMode {
      case .fullSetup:
        let job = try await prepareSetupJob(userId: userId, data: data)
        try await updateSettings(
          userId: userId,
          payrollDay: data.payrollDay,
          currency: data.currency
        )
        setupJob = job
        OnboardingCompletionStore.setPayAssumptionsReviewPending(
          true, userId: userId, defaults: defaults)
        logger.info("Saved setup for job \(job.id) with payroll day \(data.payrollDay)")

      case .friendOnlySkip:
        try await prepareFriendOnlySkip(userId: userId, data: data)
        logger.info("Prepared friend-only skip state")
      }

      // The local flag finishes onboarding. The metadata update runs in the background and
      // stays queued if it fails, so a slow or missing network never blocks the next screen.
      OnboardingCompletionStore.markCompleted(userId: userId, defaults: defaults)
      Task { await OnboardingCompletionStore.retryPendingMetadataIfNeeded(userId: userId) }

      if completionMode == .friendOnlySkip {
        clearOnboardingDraftState()
      }

      let syncResult = await syncCoordinator.sync(reason: .localChange, userId: userId)
      if syncResult.outcome != .completed {
        logger.warning("Sync had issues but continuing: \(String(describing: syncResult.outcome))")
      }

      status = .success
    } catch {
      logger.error("Failed to save onboarding data: \(error.localizedDescription)")
      status = .error(message: Self.message(for: error, fallback: .onboardingSuccessErrorMessage))
    }
  }

  /// A cancelled save still has to leave the saving state, so it gets the fallback message too.
  private static func message(for error: Error, fallback: LocalizedStringResource) -> String {
    ErrorTranslations.translate(error, fallback: fallback) ?? String(localized: fallback)
  }

  // MARK: - Private Helpers

  /// Creates or updates the first job and its baseline wage, and returns the job.
  private func prepareSetupJob(userId: String, data: OnboardingData) async throws -> Job {
    guard data.hasValidWageSelection else {
      throw NSError(
        domain: "TariffSelection", code: 1,
        userInfo: [NSLocalizedDescriptionKey: String(localized: .tariffUnavailable)])
    }
    if jobsRepository.getActiveJobs(for: userId).isEmpty {
      // Pull first so a job that already exists on the server is reused instead of duplicated.
      _ = await syncCoordinator.sync(reason: .manualRefresh, userId: userId)
    }

    let activeSetupJob =
      jobsRepository.getDefaultJob(for: userId)
      ?? jobsRepository.getActiveJobs(for: userId).first

    if let activeSetupJob {
      let preparedJob = try await ensureJobMetadata(
        userId: userId,
        job: activeSetupJob,
        data: data
      )
      _ = try await ensureBaselineSnapshot(userId: userId, job: preparedJob, data: data)
      return preparedJob
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

    _ = try await ensureBaselineSnapshot(userId: userId, job: createdJob, data: data)
    return createdJob
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
      return try await updateBaselineSnapshot(existingSnapshot, data: data) ?? existingSnapshot
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
      return try await updateBaselineSnapshot(updatedLegacySnapshot, data: data)
        ?? updatedLegacySnapshot
    }

    return try await snapshotsRepository.createSnapshot(
      userId: userId,
      jobId: job.id,
      fromDate: nil,
      hourlyWage: data.resolvedHourlyWage,
      wageLevel: data.resolvedWageLevel,
      tariffTypeId: data.resolvedTariffTypeId,
      supplements: data.resolvedSupplements,
      overtime: data.resolvedOvertime,
      taxEnabled: data.taxEnabled,
      taxPercentage: data.taxEnabled ? data.taxPercentage : nil,
      breakEnabled: data.breakEnabled,
      breakMethod: "proportional",
      breakThresholdHours: 5.5,
      breakDeductionMinutes: 30
    )
  }

  private func updateBaselineSnapshot(_ snapshot: WageSnapshot, data: OnboardingData) async throws
    -> WageSnapshot?
  {
    try await snapshotsRepository.updateSnapshot(
      id: snapshot.id,
      hourlyWage: data.resolvedHourlyWage,
      wageLevel: data.resolvedWageLevel,
      updateWageLevel: true,
      tariffTypeId: data.resolvedTariffTypeId,
      updateTariffTypeId: true,
      supplements: data.resolvedSupplements,
      overtime: data.resolvedOvertime,
      taxEnabled: data.taxEnabled,
      taxPercentage: data.taxEnabled ? data.taxPercentage : nil,
      updateTaxPercentage: true,
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

    defaults.set("sharing", forKey: Self.startupTabCacheKey)
  }

  private func clearOnboardingDraftState() {
    OnboardingData.clearSavedData()
    OnboardingCurrencyCarryoverStore.clearPreferredCurrency()
  }
}
