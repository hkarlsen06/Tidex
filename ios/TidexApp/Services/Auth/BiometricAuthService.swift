import Foundation
import LocalAuthentication
import Supabase
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "BiometricAuth")

/// Service for managing biometric (Face ID / Touch ID) app lock.
///
/// Delegates biometric operations to the supabase-swift SDK's `AuthClient` biometrics API
/// while maintaining UI lock state (`isLocked`) and static flags for `PrivacyBlurManager`.
@MainActor
final class BiometricAuthService: ObservableObject {
  static let shared = BiometricAuthService()

  // MARK: - Legacy Migration

  private static let legacyKey = "biometric_lock_enabled"

  /// Whether this launch requires migrating the old UserDefaults-based biometric state
  /// to the SDK's Keychain-based storage.
  private var needsLegacyMigration: Bool = false

  // MARK: - Published State

  /// Whether biometric lock is currently enabled (delegated to SDK).
  var isEnabled: Bool {
    supabase.auth.isBiometricsEnabled
  }

  /// Whether biometrics are available on this device
  @Published private(set) var isAvailable: Bool = false

  /// The type of biometric available (Face ID or Touch ID)
  @Published private(set) var biometricType: LABiometryType = .none

  /// Whether the app is currently locked
  @Published var isLocked: Bool = false

  /// Whether biometric authentication is currently in progress (used to suppress privacy blur)
  /// Using nonisolated static for synchronous access from AppLifecycleHandler
  nonisolated(unsafe) static var isCurrentlyAuthenticating: Bool = false

  /// Static cache of isEnabled for synchronous access from AppLifecycleHandler
  nonisolated(unsafe) static var isEnabledStatic: Bool = false

  /// Syncs the static `isEnabledStatic` flag with the SDK and notifies SwiftUI observers.
  /// Call this after any operation that changes the SDK's biometric state.
  private func syncEnabledState() {
    Self.isEnabledStatic = supabase.auth.isBiometricsEnabled
    objectWillChange.send()
  }

  // MARK: - Initialization

  private init() {
    let availability = supabase.auth.biometricsAvailability()
    isAvailable = availability.isAvailable
    biometricType = availability.biometryType

    let sdkEnabled = supabase.auth.isBiometricsEnabled
    let legacyEnabled = UserDefaults.standard.bool(forKey: Self.legacyKey)

    if sdkEnabled {
      // SDK already has biometrics enabled — check if auth is actually required
      // rather than blindly locking. With .appLifecycle policy this will be true
      // on fresh launch, but acts as a defensive check against SDK state drift.
      isLocked = supabase.auth.isBiometricAuthenticationRequired()
      Self.isEnabledStatic = true
      // Clean up any lingering legacy key
      UserDefaults.standard.removeObject(forKey: Self.legacyKey)
    } else if legacyEnabled {
      // Legacy migration: old UserDefaults key present but SDK not yet configured.
      // Show lock screen; on first unlock we call enableBiometrics to migrate.
      needsLegacyMigration = true
      isLocked = true
      Self.isEnabledStatic = true
    } else {
      isLocked = false
      Self.isEnabledStatic = false
    }
  }

  // MARK: - Biometric Availability

  /// Check if biometrics are available on this device
  func checkBiometricAvailability() {
    let availability = supabase.auth.biometricsAvailability()
    isAvailable = availability.isAvailable
    biometricType = availability.biometryType
    Self.isEnabledStatic = supabase.auth.isBiometricsEnabled
  }

  /// Human-readable name for the biometric type
  var biometricTypeName: String {
    switch biometricType {
    case .faceID:
      return "Face ID"
    case .touchID:
      return "Touch ID"
    case .opticID:
      return "Optic ID"
    case .none:
      return "Biometric"
    @unknown default:
      return "Biometric"
    }
  }

  /// SF Symbol name for the biometric type
  var biometricIconName: String {
    switch biometricType {
    case .faceID:
      return "faceid"
    case .touchID:
      return "touchid"
    case .opticID:
      return "opticid"
    case .none:
      return "lock.shield"
    @unknown default:
      return "lock.shield"
    }
  }

  // MARK: - Enable/Disable

  /// Enable biometric lock (requires successful authentication first)
  /// - Returns: Whether enabling was successful
  func enableBiometricLock() async -> Bool {
    guard isAvailable else {
      logger.warning("Cannot enable biometric lock: biometrics not available")
      return false
    }

    Self.isCurrentlyAuthenticating = true
    defer { Self.isCurrentlyAuthenticating = false }

    do {
      try await supabase.auth.enableBiometrics(
        title: String(localized: .securityBiometricPromptTitle),
        evaluationPolicy: .deviceOwnerAuthentication,
        policy: .appLifecycle
      )
      syncEnabledState()
      logger.info("Biometric lock enabled")
      return true
    } catch {
      logger.error("Failed to enable biometric lock: \(error.localizedDescription)")
      return false
    }
  }

  /// Disable biometric lock
  func disableBiometricLock() {
    supabase.auth.disableBiometrics()
    isLocked = false
    needsLegacyMigration = false
    UserDefaults.standard.removeObject(forKey: Self.legacyKey)
    syncEnabledState()
    logger.info("Biometric lock disabled")
  }

  // MARK: - Authentication

  /// Authenticate with biometrics.
  ///
  /// For legacy migration (old UserDefaults-based state), this calls `enableBiometrics`
  /// to migrate settings into the SDK's Keychain storage.
  /// Otherwise, it accesses the session via `AuthSessionManager`, which triggers the SDK's
  /// biometric prompt through `withBiometrics` when authentication is required.
  ///
  /// - Returns: Whether authentication was successful
  func authenticate() async -> Bool {
    Self.isCurrentlyAuthenticating = true
    defer { Self.isCurrentlyAuthenticating = false }

    if needsLegacyMigration {
      // Migrate: call enableBiometrics to store settings in SDK + authenticate
      do {
        try await supabase.auth.enableBiometrics(
          title: String(localized: .securityBiometricPromptTitle),
          evaluationPolicy: .deviceOwnerAuthentication,
          policy: .appLifecycle
        )
        needsLegacyMigration = false
        UserDefaults.standard.removeObject(forKey: Self.legacyKey)
        isLocked = false
        syncEnabledState()
        logger.info("Legacy biometric migration successful")
        AppCoordinator.shared.handleBiometricUnlock()
        return true
      } catch {
        logger.error("Legacy biometric migration failed: \(error.localizedDescription)")
        return false
      }
    }

    // Normal flow: session access triggers SDK biometric prompt via withBiometrics
    do {
      _ = try await AuthSessionManager.shared.getSession()
      isLocked = false
      AppCoordinator.shared.handleBiometricUnlock()
      return true
    } catch {
      // Biometric auth may have succeeded even though session retrieval failed
      // (e.g., token refresh failure due to no network). The SDK records biometric
      // authentication before executing the session operation, so check if the
      // biometric gate is now cleared.
      if !supabase.auth.isBiometricAuthenticationRequired() {
        logger.info("Biometric auth succeeded but session failed, unlocking anyway")
        isLocked = false
        AppCoordinator.shared.handleBiometricUnlock()
        return true
      }
      logger.error("Biometric authentication failed: \(error.localizedDescription)")
      return false
    }
  }

  // MARK: - App Lifecycle

  /// Called when app enters background - lock if enabled and invalidate biometric session
  func handleAppBackground() {
    if isEnabled {
      supabase.auth.invalidateBiometricSession()
      isLocked = true
      logger.debug("App locked on background")
    }
  }

  /// Called when app enters foreground - syncs lock state with SDK.
  /// Authentication is handled by AppLockView.task to avoid race conditions with privacy blur.
  func handleAppForeground() {
    guard isEnabled else { return }
    // Sync lock state with SDK. If the SDK says auth isn't required
    // (e.g., session still valid), don't force the lock screen.
    if isLocked && !supabase.auth.isBiometricAuthenticationRequired() {
      isLocked = false
      logger.debug("Lock state synced with SDK: auth not required")
      AppCoordinator.shared.handleBiometricUnlock()
    }
  }

  /// Lock the app immediately (e.g., when user manually locks)
  func lockApp() {
    if isEnabled {
      isLocked = true
    }
  }

  // MARK: - Sign-Out Cleanup

  /// Reset all biometric state. Called during sign-out to ensure clean state for next user.
  func reset() {
    supabase.auth.disableBiometrics()
    needsLegacyMigration = false
    UserDefaults.standard.removeObject(forKey: Self.legacyKey)
    isLocked = false
    Self.isCurrentlyAuthenticating = false
    syncEnabledState()
  }
}
