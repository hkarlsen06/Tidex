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

  // MARK: - Published State

  @Published private(set) var status: SaveStatus = .idle
  @Published private(set) var errorMessage: String?

  // MARK: - Save Status

  enum SaveStatus: Equatable {
    case idle
    case saving
    case success
    case error
  }

  // MARK: - Dependencies

  private let snapshotsRepository: SnapshotsRepository
  private let settingsRepository: SettingsRepository
  private let syncCoordinator: SyncCoordinator
  private var lastCompletionMode: OnboardingCompletionMode = .fullSetup

  // MARK: - Init

  init() {
    self.snapshotsRepository = SnapshotsRepository.shared
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
    status = .saving
    errorMessage = nil
    lastCompletionMode = completionMode

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

  /// Retry saving after an error
  func retry(userId: String, data: OnboardingData) async {
    await saveOnboardingData(userId: userId, data: data, completionMode: lastCompletionMode)
  }

  // MARK: - Private Helpers

  private func createBaselineSnapshot(userId: String, data: OnboardingData) async throws
    -> WageSnapshot
  {
    let snapshot = try await snapshotsRepository.createSnapshot(
      userId: userId,
      fromDate: nil,  // nil = baseline snapshot
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

    return snapshot
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
