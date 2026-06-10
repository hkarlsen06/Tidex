import Foundation
import os.log
import Supabase

private let kSettingsServiceLogger: Logger = Logger(
  subsystem: "com.tidex.app",
  category: "SettingsService"
)

/// Service for fetching user settings from Supabase
@MainActor
internal final class SettingsService: ObservableObject {
  internal static let shared: SettingsService = SettingsService()

  @Published internal private(set) var settings: UserSettings?
  @Published internal private(set) var isLoading: Bool = false
  @Published internal private(set) var error: Error?

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

        // Use single() and catch error if no rows exist
        // Swift SDK doesn't have maybeSingle(), so we handle the error case
        let response: UserSettings =
          try await supabase
          .from("user_settings")
          .select()
          .eq("user_id", value: userId)
          .single()
          .execute()
          .value

        // Check for cancellation after network request
        try Task.checkCancellation()

        settings = response
        return response
      } catch is CancellationError {
        kSettingsServiceLogger.info("Settings fetch was cancelled")
        throw CancellationError()
      } catch {
        // Check if error is "no rows returned" - return nil instead of throwing
        if let postgrestError = error as? PostgrestError,
          postgrestError.code == "PGRST116"
        {
          // PGRST116 = "The result contains 0 rows"
          settings = nil
          return nil
        }
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
    let session: Session = try await AuthSessionManager.shared.getSession()
    return session.normalizedUserId
  }

  deinit {
    // Singleton.
  }
}
