import Foundation

/// Authentication state for the native app
enum AuthState: Equatable {
    /// User is not authenticated
    case unauthenticated

    /// User is authenticated but needs MFA verification
    case requiresMFA(factorId: String)

    /// User is fully authenticated
    case authenticated(userId: String)

    /// Authentication is in progress
    case loading
}

/// MFA factor types
enum MFAFactorType: String {
    case totp = "totp"
}

/// MFA factor status
enum MFAFactorStatus: String {
    case verified = "verified"
    case unverified = "unverified"
}
