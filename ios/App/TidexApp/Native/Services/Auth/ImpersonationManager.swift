import Foundation
import Supabase
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "ImpersonationManager")

/// Manages admin impersonation sessions
///
/// Allows admins to temporarily assume the identity of another user for debugging/support.
/// The admin's original session is stored in Keychain and restored when impersonation ends.
@MainActor
final class ImpersonationManager: ObservableObject {
    static let shared = ImpersonationManager()

    // MARK: - Published State

    /// Whether we are currently impersonating another user
    @Published private(set) var isImpersonating: Bool = false

    /// The target user's display name (when impersonating)
    @Published private(set) var impersonatedUserName: String?

    /// When the impersonation session expires
    @Published private(set) var expiresAt: Date?

    /// The impersonation session ID
    @Published private(set) var sessionId: String?

    // MARK: - Private Constants

    /// Keychain service for impersonation data
    private let keychainService = "no.tidex.impersonation"

    /// Key for storing admin session
    private let adminSessionKey = "admin_session"

    /// Key for storing impersonation session ID
    private let impersonationSessionIdKey = "session_id"

    /// Key for storing target user name
    private let targetUserNameKey = "target_user_name"

    /// Key for storing expiration date
    private let expiresAtKey = "expires_at"

    // MARK: - Initialization

    private init() {
        // Check if we have an active impersonation session on startup
        // Note: Full validation happens asynchronously via validateSessionOnLaunch()
        restoreStateFromKeychain()
    }

    /// Validate the impersonation session on app launch
    /// Call this from AppCoordinator after the app is ready
    /// If session is invalid/expired, automatically stops impersonation
    func validateSessionOnLaunch() async {
        guard isImpersonating else { return }

        // 1. Check local expiration first (fast path)
        if let expiresAt = expiresAt, expiresAt < Date() {
            logger.info("Impersonation session expired locally, stopping")
            await handleInvalidSession()
            return
        }

        // 2. Validate the session is still active server-side
        // Try to get current session - if it fails, the impersonated session is invalid
        do {
            _ = try await AuthSessionManager.shared.getSession()
            logger.info("Impersonation session validated successfully")
        } catch {
            logger.warning("Impersonation session validation failed: \(error.localizedDescription)")
            await handleInvalidSession()
        }
    }

    /// Handle an invalid/expired impersonation session
    /// Restores admin session and clears impersonation state
    private func handleInvalidSession() async {
        logger.info("Handling invalid impersonation session")

        // Try to restore admin session
        if let adminSession = loadAdminSession() {
            do {
                // Clear cached data before switching
                await AppCoordinator.shared.prepareForUserSwitch()

                // Restore admin session
                try await supabase.auth.setSession(
                    accessToken: adminSession.accessToken,
                    refreshToken: adminSession.refreshToken
                )

                logger.info("Admin session restored after invalid impersonation")

                // Complete the switch
                await AppCoordinator.shared.completeUserSwitch()
            } catch {
                logger.error("Failed to restore admin session: \(error.localizedDescription)")
                // Sign out completely as fallback
                try? await supabase.auth.signOut()
            }
        }

        // Clear all impersonation state
        clearKeychain()
        isImpersonating = false
        impersonatedUserName = nil
        expiresAt = nil
        sessionId = nil
    }

    // MARK: - Public API

    /// Start impersonating a target user
    /// - Parameters:
    ///   - targetUserId: The user ID to impersonate
    ///   - reason: Reason for impersonation (min 5 chars, required for audit)
    /// - Returns: The impersonation result with session details
    func startImpersonation(targetUserId: String, reason: String) async throws -> ImpersonationResult {
        guard reason.count >= 5 else {
            throw ImpersonationError.reasonTooShort
        }

        // 1. Get current admin session
        let currentSession = try await AuthSessionManager.shared.getSession()
        logger.info("Starting impersonation: admin=\(currentSession.user.id), target=\(targetUserId)")

        // 2. Store admin session in Keychain for restoration
        let adminSession = AdminSession(
            accessToken: currentSession.accessToken,
            refreshToken: currentSession.refreshToken,
            userId: currentSession.user.id.uuidString
        )
        try storeAdminSession(adminSession)

        // 3. Call the Edge Function
        // Note: Using body-based action routing since Swift SDK may not handle path-based routing
        let response: ImpersonationStartResponse = try await supabase.functions.invoke(
            "impersonation",
            options: FunctionInvokeOptions(
                body: [
                    "action": "start",
                    "targetUserId": targetUserId,
                    "reason": reason
                ]
            )
        )

        guard response.ok, let impersonated = response.impersonated else {
            // Clean up stored admin session on failure
            clearKeychain()
            throw ImpersonationError.serverError(response.error ?? "Unknown error")
        }

        // 4. Store session metadata
        if let session = response.session {
            try storeSessionMetadata(
                sessionId: session.id,
                targetUserName: impersonated.user.displayName,
                expiresAt: session.expiresAtDate
            )
        }

        // 5. Clear all cached data BEFORE swapping sessions
        // This ensures we don't show stale data from the admin user
        await AppCoordinator.shared.prepareForUserSwitch()

        // 6. Swap to impersonated user's session
        try await supabase.auth.setSession(
            accessToken: impersonated.accessToken,
            refreshToken: impersonated.refreshToken
        )

        // 7. Update published state
        isImpersonating = true
        impersonatedUserName = impersonated.user.displayName
        expiresAt = response.session?.expiresAtDate
        sessionId = response.session?.id

        // 8. Complete the user switch - reload profile and trigger sync
        await AppCoordinator.shared.completeUserSwitch()

        logger.info("Impersonation started: target=\(impersonated.user.displayName)")

        return ImpersonationResult(
            sessionId: response.session?.id ?? "",
            targetUser: impersonated.user,
            expiresAt: response.session?.expiresAtDate
        )
    }

    /// Stop the current impersonation and restore admin session
    func stopImpersonation() async throws {
        guard isImpersonating else {
            throw ImpersonationError.noActiveSession
        }

        logger.info("Stopping impersonation")

        // 1. Try to call Edge Function to end session (optional, for audit)
        // Note: Using body-based action routing since Swift SDK may not handle path-based routing
        if let currentSessionId = sessionId {
            do {
                let _: ImpersonationStopResponse = try await supabase.functions.invoke(
                    "impersonation",
                    options: FunctionInvokeOptions(
                        body: [
                            "action": "stop",
                            "sessionId": currentSessionId
                        ]
                    )
                )
            } catch {
                logger.warning("Failed to call stop endpoint: \(error.localizedDescription)")
                // Continue anyway - the important thing is restoring admin session
            }
        }

        // 2. Restore admin session from Keychain
        guard let adminSession = loadAdminSession() else {
            clearKeychain()
            throw ImpersonationError.adminSessionNotFound
        }

        // 3. Clear all cached data BEFORE swapping back to admin session
        // This ensures we don't show stale data from the impersonated user
        await AppCoordinator.shared.prepareForUserSwitch()

        // 4. Swap back to admin session
        try await supabase.auth.setSession(
            accessToken: adminSession.accessToken,
            refreshToken: adminSession.refreshToken
        )

        // 5. Clean up impersonation state
        clearKeychain()
        isImpersonating = false
        impersonatedUserName = nil
        expiresAt = nil
        sessionId = nil

        // 6. Complete the user switch - reload admin profile and trigger sync
        await AppCoordinator.shared.completeUserSwitch()

        logger.info("Impersonation stopped, admin session restored")
    }

    // MARK: - Private Keychain Operations

    private func restoreStateFromKeychain() {
        // Check if we have stored impersonation state
        guard let sessionId = getString(forKey: impersonationSessionIdKey),
              !sessionId.isEmpty else {
            return
        }

        self.sessionId = sessionId
        self.impersonatedUserName = getString(forKey: targetUserNameKey)
        self.isImpersonating = true

        if let expiresAtString = getString(forKey: expiresAtKey),
           let expiresAtDouble = Double(expiresAtString) {
            self.expiresAt = Date(timeIntervalSince1970: expiresAtDouble)
        }

        logger.info("Restored impersonation state from Keychain")
    }

    private func storeAdminSession(_ session: AdminSession) throws {
        let data = try JSONEncoder().encode(session)
        try storeData(data, forKey: adminSessionKey)
    }

    private func loadAdminSession() -> AdminSession? {
        guard let data = getData(forKey: adminSessionKey) else {
            return nil
        }
        return try? JSONDecoder().decode(AdminSession.self, from: data)
    }

    private func storeSessionMetadata(sessionId: String, targetUserName: String, expiresAt: Date?) throws {
        try storeString(sessionId, forKey: impersonationSessionIdKey)
        try storeString(targetUserName, forKey: targetUserNameKey)
        if let expiresAt {
            try storeString(String(expiresAt.timeIntervalSince1970), forKey: expiresAtKey)
        }
    }

    private func clearKeychain() {
        deleteItem(forKey: adminSessionKey)
        deleteItem(forKey: impersonationSessionIdKey)
        deleteItem(forKey: targetUserNameKey)
        deleteItem(forKey: expiresAtKey)
    }

    // MARK: - Low-Level Keychain Helpers

    private func storeData(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]

        // Delete existing
        SecItemDelete(query as CFDictionary)

        var newItem = query
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(newItem as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw ImpersonationError.serverError("Keychain store failed: \(status)")
        }
    }

    private func storeString(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        try storeData(data, forKey: key)
    }

    private func getData(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    private func getString(forKey key: String) -> String? {
        guard let data = getData(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteItem(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
