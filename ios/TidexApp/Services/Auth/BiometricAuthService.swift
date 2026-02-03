import Foundation
import LocalAuthentication
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "BiometricAuth")

/// Service for managing biometric (Face ID / Touch ID) app lock
@MainActor
final class BiometricAuthService: ObservableObject {
    static let shared = BiometricAuthService()

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let biometricLockEnabled = "biometric_lock_enabled"
    }

    // MARK: - Published State

    /// Whether biometric lock is currently enabled
    @Published private(set) var isEnabled: Bool

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

    // MARK: - Initialization

    private init() {
        let enabled = UserDefaults.standard.bool(forKey: Keys.biometricLockEnabled)
        isEnabled = enabled
        Self.isEnabledStatic = enabled
        // Start locked if biometric is enabled (app launch = should require auth)
        isLocked = enabled
        checkBiometricAvailability()
    }

    // MARK: - Biometric Availability

    /// Check if biometrics are available on this device
    func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?

        isAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        biometricType = context.biometryType

        if let error = error {
            logger.debug("Biometric not available: \(error.localizedDescription)")
        }
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

        // Require authentication to enable
        let authenticated = await authenticate(reason: .enabling)
        if authenticated {
            UserDefaults.standard.set(true, forKey: Keys.biometricLockEnabled)
            isEnabled = true
            Self.isEnabledStatic = true
            logger.info("Biometric lock enabled")
            return true
        }

        return false
    }

    /// Disable biometric lock
    func disableBiometricLock() {
        UserDefaults.standard.set(false, forKey: Keys.biometricLockEnabled)
        isEnabled = false
        Self.isEnabledStatic = false
        isLocked = false
        logger.info("Biometric lock disabled")
    }

    // MARK: - Authentication

    enum AuthReason {
        case unlocking
        case enabling

        var localizedReason: String {
            switch self {
            case .unlocking:
                return "Unlock Tidex to view your earnings"
            case .enabling:
                return "Authenticate to enable app lock"
            }
        }
    }

    /// Authenticate with biometrics
    /// - Parameter reason: The reason for authentication
    /// - Returns: Whether authentication was successful
    func authenticate(reason: AuthReason = .unlocking) async -> Bool {
        Self.isCurrentlyAuthenticating = true
        defer { Self.isCurrentlyAuthenticating = false }

        let context = LAContext()

        // Allow fallback to device passcode
        context.localizedFallbackTitle = "Use Passcode"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,  // Allows passcode fallback
                localizedReason: reason.localizedReason
            )

            if success {
                logger.info("Biometric authentication successful")
                isLocked = false
            }

            return success
        } catch {
            logger.error("Biometric authentication failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - App Lifecycle

    /// Called when app enters background - lock if enabled
    func handleAppBackground() {
        if isEnabled {
            isLocked = true
            logger.debug("App locked on background")
        }
    }

    /// Called when app enters foreground - no longer triggers auth here
    /// Authentication is handled by AppLockView.task to avoid race conditions with privacy blur
    func handleAppForeground() {
        // Auth is triggered by AppLockView, not here
        // This prevents race conditions where sceneWillResignActive
        // is called before isCurrentlyAuthenticating is set
    }

    /// Lock the app immediately (e.g., when user manually locks)
    func lockApp() {
        if isEnabled {
            isLocked = true
        }
    }
}
