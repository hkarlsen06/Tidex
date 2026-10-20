import Foundation
import os.log

private let kSettingsServiceLogger: Logger = Logger(
  subsystem: "com.tidex.app",
  category: "SettingsService"
)

/// Service for fetching user settings from Convex
@MainActor
internal final class SettingsService {
  internal static let shared: SettingsService = SettingsService()

  internal private(set) var settings: UserSettings?
  internal private(set) var isLoading: Bool = false
  internal private(set) var error: Error?

  private init() {
    // Singleton.
  }

  /// Fetch settings for the current authenticated user
  /// - Returns: User settings or nil if not found
  internal func fetchSettings() async throws -> UserSettings? {
    guard let userId = try await getCurrentUserId() else {
      return nil
    }
    return try await fetchSettings(for: userId)
  }

  /// Fetch settings for a specific user ID
  /// - Parameter userId: User ID to fetch settings for
  /// - Returns: User settings or nil if not found
  internal func fetchSettings(for userId: String) async throws -> UserSettings? {
    isLoading = true
    error = nil
    defer { isLoading = false }

    return try await withTaskCancellationHandler {
      do {
        // Check for cancellation before making network request
        try Task.checkCancellation()

        // The user has one settings row, or none before the first sync.
        let rows: [SyncUserSettingsRow] = try await SyncConvex.pullAll(.userSettings)
        let response = rows.first { $0.user_id.lowercased() == userId.lowercased() }?
          .toUserSettings()

        // Check for cancellation after network request
        try Task.checkCancellation()

        settings = response
        return response
      } catch is CancellationError {
        kSettingsServiceLogger.info("Settings fetch was cancelled")
        throw CancellationError()
      } catch {
        self.error = error
        throw error
      }
    } onCancel: {
      kSettingsServiceLogger.info("Settings fetch cancellation requested")
    }
  }

  /// Get current authenticated user ID
  private func getCurrentUserId() async throws -> String? {
    // Use AuthSessionManager to prevent concurrent refresh race conditions
    let session: AuthSession = try await AuthSessionManager.shared.getSession()
    return session.normalizedUserId
  }

  deinit {
    // Singleton.
  }
}
