import Foundation
import Supabase
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "OnboardingSaveManager")

/// Handles async save with status tracking for onboarding data
/// Creates baseline wage snapshot and updates settings
@MainActor
final class OnboardingSaveManager: ObservableObject {
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
    func saveOnboardingData(userId: String, data: OnboardingData) async {
        status = .saving
        errorMessage = nil

        logger.info("Starting onboarding save for user: \(userId)")

        do {
            // Step 1: Create baseline wage snapshot
            let snapshot = try await createBaselineSnapshot(userId: userId, data: data)
            logger.info("Created baseline snapshot: \(snapshot.id)")

            // Step 2: Update settings (payroll day and currency)
            try await updateSettings(userId: userId, payrollDay: data.payrollDay, currency: data.currency)
            logger.info("Updated settings with payroll day: \(data.payrollDay), currency: \(data.currency)")

            // Step 3: Mark onboarding as finished in Supabase user metadata
            try await markOnboardingFinished()
            logger.info("Marked onboarding as finished in user metadata")

            // Step 4: Trigger sync to push changes to server
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
        await saveOnboardingData(userId: userId, data: data)
    }

    // MARK: - Private Helpers

    private func createBaselineSnapshot(userId: String, data: OnboardingData) async throws -> WageSnapshot {
        let snapshot = try await snapshotsRepository.createSnapshot(
            userId: userId,
            fromDate: nil, // nil = baseline snapshot
            hourlyWage: data.resolvedHourlyWage,
            wageLevel: data.resolvedWageLevel,
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
        _ = try await settingsRepository.updateSettings(
            for: userId,
            payrollDay: payrollDay,
            currency: currency
        )
    }

    private func markOnboardingFinished() async throws {
        _ = try await supabase.auth.update(
            user: UserAttributes(
                data: ["finishedOnboarding": .bool(true)]
            )
        )
    }
}
