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
final class KeychainLocalStorage: AuthLocalStorage {
    private let service = APIConfiguration.keychainService
    private let sessionKey = "supabase.auth.session"

    func store(key: String, value: Data) throws {
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

    func retrieve(key: String) throws -> Data? {
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

    func remove(key: String) throws {
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
