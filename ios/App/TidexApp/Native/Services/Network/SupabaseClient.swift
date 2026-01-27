import Foundation
import Supabase

/// Shared Supabase client instance for the native iOS app
/// Configured to use the Keychain for token storage (iOS best practice)
let supabase = SupabaseClient(
    supabaseURL: APIConfiguration.supabaseURL,
    supabaseKey: APIConfiguration.supabaseAnonKey,
    options: SupabaseClientOptions(
        auth: SupabaseClientOptions.AuthOptions(
            storage: KeychainLocalStorage(),
            autoRefreshToken: true,
            emitLocalSessionAsInitialSession: true
        )
    )
)

// MARK: - Keychain Storage for Supabase

/// Custom storage implementation that uses the Keychain
/// This is more secure than UserDefaults for storing auth tokens
///
/// Thread Safety: All Keychain operations are serialized through a dedicated
/// dispatch queue to prevent TOCTOU (Time-Of-Check-Time-Of-Use) race conditions.
/// Without synchronization, concurrent access could result in:
/// - Thread A deletes old token, Thread B reads nil, Thread A adds new token
/// - Corrupted or missing session data during concurrent refresh attempts
final class KeychainLocalStorage: AuthLocalStorage {
    private let service = APIConfiguration.keychainService
    private let sessionKey = "supabase.auth.session"

    /// Serial queue for synchronizing all Keychain operations
    /// Using .userInitiated QoS since auth operations are user-facing
    private let keychainQueue = DispatchQueue(label: "com.tidex.keychain", qos: .userInitiated)

    func store(key: String, value: Data) throws {
        try keychainQueue.sync {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]

            // Delete existing item first
            SecItemDelete(query as CFDictionary)

            // Add new item
            var newItem = query
            newItem[kSecValueData as String] = value
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

            let status = SecItemAdd(newItem as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.unableToStore(status: status)
            }
        }
    }

    func retrieve(key: String) throws -> Data? {
        try keychainQueue.sync {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            switch status {
            case errSecSuccess:
                return result as? Data
            case errSecItemNotFound:
                return nil
            default:
                throw KeychainError.unableToRetrieve(status: status)
            }
        }
    }

    func remove(key: String) throws {
        try keychainQueue.sync {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]

            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unableToRemove(status: status)
            }
        }
    }
}

// MARK: - Keychain Errors

enum KeychainError: Error, LocalizedError {
    case unableToStore(status: OSStatus)
    case unableToRetrieve(status: OSStatus)
    case unableToRemove(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .unableToStore(let status):
            return "Unable to store in Keychain: \(status)"
        case .unableToRetrieve(let status):
            return "Unable to retrieve from Keychain: \(status)"
        case .unableToRemove(let status):
            return "Unable to remove from Keychain: \(status)"
        }
    }
}
