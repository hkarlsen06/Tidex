import Foundation
import SwiftUI
import Supabase

/// Central coordinator for app-wide authentication state and navigation
/// Manages the flow: Splash -> Login -> MFA (if needed) -> Dashboard
@MainActor
final class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator()

    // MARK: - Navigation State

    enum AppState: Equatable {
        case loading           // Initial app load, checking session
        case unauthenticated   // No valid session, show login
        case mfaRequired       // User logged in but needs MFA verification
        case authenticated     // Fully authenticated, show main app
    }

    @Published private(set) var appState: AppState = .loading

    // MARK: - MFA State

    /// MFA factor to verify (when state is .mfaRequired)
    @Published private(set) var pendingMFAFactor: AuthService.MFAFactor?

    // MARK: - User Profile State

    /// User's display name (for UserMenuButton)
    @Published private(set) var userDisplayName: String = ""
    /// User's profile picture URL (for UserMenuButton)
    @Published private(set) var userAvatarUrl: String?

    // MARK: - Dependencies

    private let authService: AuthService
    private let settingsService: SettingsService

    // MARK: - Private

    private var authStateTask: Task<Void, Never>?

    // MARK: - Initialization

    private init(authService: AuthService? = nil, settingsService: SettingsService? = nil) {
        self.authService = authService ?? AuthService.shared
        self.settingsService = settingsService ?? SettingsService.shared
        setupAuthStateListener()
        setupInitialSessionCheck()
    }

    deinit {
        authStateTask?.cancel()
    }

    // MARK: - Initial Session Check

    /// Fallback check in case authStateChanges doesn't emit .initialSession promptly
    private func setupInitialSessionCheck() {
        Task { [weak self] in
            // Give authStateChanges a moment to emit
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            guard let self = self else { return }

            // If still loading, do a manual check
            if self.appState == .loading {
                print("[AppCoordinator] Initial session check - manually checking session")
                await self.performInitialSessionCheck()
            }
        }
    }

    /// Perform initial session check directly
    private func performInitialSessionCheck() async {
        do {
            // session is non-optional - throws if no session exists
            _ = try await supabase.auth.session
            print("[AppCoordinator] Session check result: has session")
            await checkMFAAndUpdateState()
        } catch {
            print("[AppCoordinator] Session check error: \(error)")
            appState = .unauthenticated
        }
    }

    // MARK: - Auth State Listener

    private func setupAuthStateListener() {
        authStateTask = Task { [weak self] in
            for await (event, session) in supabase.auth.authStateChanges {
                guard let self = self else { return }

                print("[AppCoordinator] Auth event: \(event), session: \(session != nil ? "present" : "nil")")

                switch event {
                case .initialSession:
                    // On app launch, check if we have a valid session
                    if session != nil {
                        await self.checkMFAAndUpdateState()
                    } else {
                        self.appState = .unauthenticated
                    }

                case .signedIn:
                    // User just signed in, check MFA
                    await self.checkMFAAndUpdateState()

                case .signedOut:
                    self.appState = .unauthenticated
                    self.pendingMFAFactor = nil

                case .tokenRefreshed:
                    // Token refreshed, state unchanged
                    break

                case .mfaChallengeVerified:
                    // MFA verified, user is now fully authenticated
                    self.appState = .authenticated
                    self.pendingMFAFactor = nil

                case .userUpdated, .userDeleted, .passwordRecovery:
                    // Handle other events as needed
                    break
                }
            }
        }
    }

    // MARK: - MFA Check

    /// Check MFA status and update app state accordingly
    private func checkMFAAndUpdateState() async {
        do {
            let mfaStatus = try await authService.getMFAStatus()

            if mfaStatus.requiresVerification {
                // User needs to complete MFA
                // Find the first verified TOTP factor
                if let factor = mfaStatus.factors.first(where: { $0.status == "verified" }) {
                    self.pendingMFAFactor = factor
                    self.appState = .mfaRequired
                } else {
                    // No verified factors, but MFA is required - shouldn't happen normally
                    // Fall back to authenticated (backend will handle enforcement)
                    self.appState = .authenticated
                    await updateUserProfile()
                }
            } else {
                // No MFA required, user is fully authenticated
                self.appState = .authenticated
                await updateUserProfile()
            }
        } catch {
            // If MFA check fails, assume authenticated and let backend handle it
            print("[AppCoordinator] MFA check failed: \(error)")
            self.appState = .authenticated
            await updateUserProfile()
        }
    }

    // MARK: - User Profile

    /// Update user profile data (display name and avatar)
    private func updateUserProfile() async {
        do {
            let session = try await supabase.auth.session
            let user = session.user

            // Extract display name from user metadata or fall back to email
            if let fullName = user.userMetadata["full_name"]?.value as? String, !fullName.isEmpty {
                userDisplayName = fullName
            } else if let name = user.userMetadata["name"]?.value as? String, !name.isEmpty {
                userDisplayName = name
            } else if let email = user.email {
                // Use the part before @ for email
                userDisplayName = email.components(separatedBy: "@").first ?? email
            } else if let phone = user.phone {
                userDisplayName = phone
            } else {
                userDisplayName = "User"
            }

            // Fetch settings to get profile picture URL
            let userId = user.id.uuidString.lowercased()
            if let settings = try await settingsService.fetchSettings(for: userId) {
                userAvatarUrl = settings.profile_picture_url
            }

        } catch {
            print("[AppCoordinator] Failed to update user profile: \(error)")
            userDisplayName = "User"
        }
    }

    // MARK: - Public Actions

    /// Called when login is successful
    /// The auth state listener will handle the transition
    func handleLoginSuccess() async {
        await checkMFAAndUpdateState()
    }

    /// Called when MFA verification is successful
    func handleMFASuccess() {
        appState = .authenticated
        pendingMFAFactor = nil
        Task {
            await updateUserProfile()
        }
    }

    /// Sign out the user
    func signOut() async {
        do {
            try await authService.signOut()
            // Auth state listener will update appState to .unauthenticated
        } catch {
            print("[AppCoordinator] Sign out failed: \(error)")
            // Force state change even if sign out fails
            appState = .unauthenticated
        }
    }

    /// Force a session check (useful for debugging or manual refresh)
    func checkSession() async {
        appState = .loading

        do {
            if let _ = try await authService.getSession() {
                await checkMFAAndUpdateState()
            } else {
                appState = .unauthenticated
            }
        } catch {
            appState = .unauthenticated
        }
    }
}
