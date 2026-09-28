// swiftlint:disable conditional_returns_on_newline no_magic_numbers
// swiftlint:disable:previous blanket_disable_command
import Foundation
import SwiftData
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "SettingsRepository")

// MARK: - Settings Repository

/// Local-first repository for user settings
/// All reads come from SwiftData; network calls are handled by SyncCoordinator
/// Automatically triggers sync after mutations for immediate upload
@MainActor
final class SettingsRepository {
  static let shared = SettingsRepository()

  private let localStore: LocalStore
  private let syncCoordinator: SyncCoordinator

  private init(localStore: LocalStore? = nil, syncCoordinator: SyncCoordinator? = nil) {
    self.localStore = localStore ?? LocalStore.shared
    self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
  }

  // MARK: - Sync Helper

  /// Trigger sync after a mutation (fire-and-forget)
  private func triggerSync(userId: String) {
    Task {
      _ = await syncCoordinator.sync(reason: .localChange, userId: userId)
    }
  }

  // MARK: - Read Operations (Local Only)

  /// Get user settings for a user
  /// - Parameter userId: User ID
  /// - Returns: UserSettings if found, nil otherwise
  func getSettings(for userId: String) -> UserSettings? {
    let context = localStore.mainContext

    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    do {
      guard let localSettings = try context.fetch(descriptor).first else {
        return nil
      }
      return localSettings.toUserSettings()
    } catch {
      logger.error("Failed to fetch settings: \(error.localizedDescription)")
      return nil
    }
  }

  /// Get the raw LocalUserSettings object
  /// - Parameter userId: User ID
  /// - Returns: LocalUserSettings if found
  func getLocalSettings(for userId: String) -> LocalUserSettings? {
    let context = localStore.mainContext

    let descriptor = FetchDescriptor<LocalUserSettings>(
      predicate: #Predicate { $0.userId == userId }
    )

    do {
      return try context.fetch(descriptor).first
    } catch {
      logger.error("Failed to fetch local settings: \(error.localizedDescription)")
      return nil
    }
  }

  /// Check if settings have a sync conflict
  /// - Parameter userId: User ID
  /// - Returns: True if settings are in conflict state
  func hasConflict(for userId: String) -> Bool {
    guard let localSettings = getLocalSettings(for: userId) else {
      return false
    }
    return localSettings.syncStatus == .conflict
  }

  /// Check if settings have pending changes
  /// - Parameter userId: User ID
  /// - Returns: True if settings are dirty
  func hasPendingChanges(for userId: String) -> Bool {
    guard let localSettings = getLocalSettings(for: userId) else {
      return false
    }
    return localSettings.syncStatus == .dirty
  }

  // MARK: - Write Operations (Local with Dirty Tracking)

  /// Get or create user settings
  /// Returns existing settings if found, otherwise creates new settings with provided defaults
  /// - Parameters:
  ///   - userId: User ID
  ///   - payrollDay: Payroll day (used if creating new settings)
  ///   - currency: Currency code (used if creating new settings)
  /// - Returns: UserSettings (existing or newly created)
  func getOrCreateSettings(
    for userId: String,
    payrollDay: Int? = nil,
    currency: String? = nil
  ) async throws -> UserSettings {
    let settings = try await localStore.storeActor.getOrCreateUserSettings(
      userId: userId,
      payrollDay: payrollDay,
      currency: currency
    )
    logger.info("Got or created settings for user: \(userId)")
    return settings
  }

  /// Update user settings locally
  /// Only the changed fields will be marked dirty
  /// - Parameters:
  ///   - userId: User ID
  ///   - monthlyGoal: New monthly goal (optional)
  ///   - monthlyGoalsByMonth: Sparse month-specific goals keyed by YYYY-MM (optional)
  ///   - defaultShiftsView: New default shifts view (optional)
  ///   - profilePictureUrl: New profile picture URL (optional)
  ///   - payrollDay: New payroll day (optional)
  ///   - theme: New theme (optional)
  ///   - calendarContentColorStyle: New calendar content color style (optional)
  ///   - showDashboardClockButtons: Whether dashboard clock buttons are visible (optional)
  ///   - aiDataSharingEnabled: Whether Wagey AI data sharing is enabled (optional)
  ///   - halfTaxMonth: New half tax month (optional)
  ///   - currency: New currency (optional)
  ///   - defaultStartupTab: New default startup tab (optional)
  ///   - triggerSync: Whether to trigger sync immediately after the local write
  /// - Returns: Updated UserSettings if successful
  func updateSettings(
    for userId: String,
    monthlyGoal: Int? = nil,
    monthlyGoalsByMonth: [String: Int]? = nil,
    defaultShiftsView: String? = nil,
    profilePictureUrl: String? = nil,
    payrollDay: Int? = nil,
    theme: String? = nil,
    calendarContentColorStyle: String? = nil,
    showDashboardClockButtons: Bool? = nil,
    aiDataSharingEnabled: Bool? = nil,
    wageyShowcaseSeen: Bool? = nil,
    halfTaxMonth: Int? = nil,
    currency: String? = nil,
    defaultStartupTab: String? = nil,
    triggerSync: Bool = true
  ) async throws -> UserSettings? {
    do {
      let updatedSettings = try await localStore.storeActor.updateUserSettings(
        userId: userId,
        monthlyGoal: monthlyGoal,
        monthlyGoalsByMonth: monthlyGoalsByMonth,
        defaultShiftsView: defaultShiftsView,
        profilePictureUrl: profilePictureUrl,
        payrollDay: payrollDay,
        theme: theme,
        calendarContentColorStyle: calendarContentColorStyle,
        showDashboardClockButtons: showDashboardClockButtons,
        aiDataSharingEnabled: aiDataSharingEnabled,
        wageyShowcaseSeen: wageyShowcaseSeen,
        halfTaxMonth: halfTaxMonth,
        currency: currency,
        defaultStartupTab: defaultStartupTab
      )

      logger.info("Updated local settings for user: \(userId)")

      if triggerSync {
        self.triggerSync(userId: userId)
      }

      return updatedSettings
    } catch LocalStoreWriteError.notFound {
      logger.warning("Settings not found for update: \(userId)")
      return nil
    } catch {
      throw error
    }
  }

  /// Clear the profile picture URL (set to nil)
  /// - Parameter userId: User ID
  /// - Returns: Updated UserSettings if successful
  func clearProfilePictureUrl(for userId: String) async throws -> UserSettings? {
    do {
      let updatedSettings = try await localStore.storeActor.clearProfilePictureUrl(userId: userId)
      logger.info("Cleared profile picture URL for user: \(userId)")

      // Trigger sync to upload immediately
      triggerSync(userId: userId)

      return updatedSettings
    } catch LocalStoreWriteError.notFound {
      logger.warning("Settings not found for clearing profile picture: \(userId)")
      return nil
    } catch {
      throw error
    }
  }

  // MARK: - Conflict Resolution

  /// Resolve a conflict by keeping the local version
  /// - Parameter userId: User ID
  func resolveConflictKeepLocal(for userId: String) async throws {
    do {
      try await localStore.storeActor.resolveStoredUserSettingsConflictKeepLocal(userId: userId)
      logger.info("Resolved settings conflict (kept local) for user: \(userId)")
    } catch LocalStoreWriteError.notFound {
      logger.warning("Settings not found for conflict resolution: \(userId)")
    } catch LocalStoreWriteError.notInConflict {
      logger.warning("Settings are not in conflict state: \(userId)")
    } catch LocalStoreWriteError.missingConflictSnapshot {
      logger.error("No server snapshot found for settings conflict: \(userId)")
    } catch {
      throw error
    }
  }

  /// Resolve a conflict by accepting the server version
  /// - Parameter userId: User ID
  func resolveConflictKeepServer(for userId: String) async throws {
    do {
      try await localStore.storeActor.resolveStoredUserSettingsConflictKeepServer(userId: userId)
      logger.info("Resolved settings conflict (kept server) for user: \(userId)")
    } catch LocalStoreWriteError.notFound {
      logger.warning("Settings not found for conflict resolution: \(userId)")
    } catch LocalStoreWriteError.notInConflict {
      logger.warning("Settings are not in conflict state: \(userId)")
    } catch LocalStoreWriteError.missingConflictSnapshot {
      logger.error("No server snapshot found for settings conflict: \(userId)")
    } catch {
      throw error
    }
  }
}
