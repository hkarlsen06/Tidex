import Foundation
import Supabase

/// Service for fetching user settings from Supabase
@MainActor
final class SettingsService: ObservableObject {
    static let shared = SettingsService()

    @Published private(set) var settings: UserSettings?
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    private init() {}

    /// Fetch settings for the current authenticated user
    /// - Returns: User settings or nil if not found
    func fetchSettings() async throws -> UserSettings? {
        guard let userId = try await getCurrentUserId() else {
            return nil
        }
        return try await fetchSettings(for: userId)
    }

    /// Fetch settings for a specific user ID
    /// - Parameter userId: User ID to fetch settings for
    /// - Returns: User settings or nil if not found
    func fetchSettings(for userId: String) async throws -> UserSettings? {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Use single() and catch error if no rows exist
            // Swift SDK doesn't have maybeSingle(), so we handle the error case
            let response: UserSettings = try await supabase
                .from("user_settings")
                .select()
                .eq("user_id", value: userId)
                .single()
                .execute()
                .value

            settings = response
            return response
        } catch {
            // Check if error is "no rows returned" - return nil instead of throwing
            if let postgrestError = error as? PostgrestError,
               postgrestError.code == "PGRST116" {
                // PGRST116 = "The result contains 0 rows"
                settings = nil
                return nil
            }
            self.error = error
            throw error
        }
    }

    /// Get current authenticated user ID
    private func getCurrentUserId() async throws -> String? {
        let session = try await supabase.auth.session
        return session.user.id.uuidString.lowercased()
    }
}
