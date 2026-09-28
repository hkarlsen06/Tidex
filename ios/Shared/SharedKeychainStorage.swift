// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable sorted_enum_cases type_contents_order
import Foundation
import Security

/// Keychain storage shared by the main app and iPhone extensions.
/// Uses a shared access group to allow cross-target access to auth tokens
///
/// ## Usage
/// The main app writes the JWT token after successful authentication.
/// Extensions read this token to make authenticated API calls directly.
enum SharedKeychainStorage {
  // MARK: - Configuration

  /// Keychain service identifier
  private static let service = "no.tidex.shared.auth"

  /// Key for storing the access token
  private static let accessTokenKey = "access_token"

  /// Key for storing the token expiry timestamp
  private static let tokenExpiryKey = "token_expiry"

  // MARK: - Errors

  enum KeychainError: Error, LocalizedError {
    case unableToStore(status: OSStatus)
    case unableToRetrieve(status: OSStatus)
    case unableToDelete(status: OSStatus)
    case tokenExpired
    case tokenNotFound

    var errorDescription: String? {
      switch self {
      case .unableToStore(let status):
        return "Unable to store in Keychain: \(status)"

      case .unableToRetrieve(let status):
        return "Unable to retrieve from Keychain: \(status)"

      case .unableToDelete(let status):
        return "Unable to delete from Keychain: \(status)"

      case .tokenExpired:
        return "Access token has expired"

      case .tokenNotFound:
        return "Access token not found in Keychain"
      }
    }
  }

  // MARK: - Token Storage (Main App)

  /// Store an access token with its expiry timestamp
  /// Called by the main app after successful authentication
  /// - Parameters:
  ///   - token: The JWT access token
  ///   - expiresAt: Unix timestamp when the token expires
  static func storeAccessToken(_ token: String, expiresAt: Int) throws {
    // Store the token
    try storeString(token, forKey: accessTokenKey)

    // Store the expiry timestamp
    try storeString(String(expiresAt), forKey: tokenExpiryKey)
  }

  /// Remove the stored access token (on logout)
  static func clearAccessToken() throws {
    try deleteItem(forKey: accessTokenKey)
    try deleteItem(forKey: tokenExpiryKey)
  }

  // MARK: - Token Retrieval

  /// Retrieve the access token if it hasn't expired
  /// Returns nil if no token exists or if expired
  /// - Returns: The access token if valid, nil otherwise
  static func getValidAccessToken() -> String? {
    guard let token = try? getString(forKey: accessTokenKey),
      let expiryString = try? getString(forKey: tokenExpiryKey),
      let expiresAt = Int(expiryString)
    else {
      return nil
    }

    // Check if token is expired (with 60 second buffer)
    let now = Int(Date().timeIntervalSince1970)
    let buffer = 60  // 1 minute buffer

    guard expiresAt > (now + buffer) else {
      return nil  // Token expired or about to expire
    }

    return token
  }

  /// Check if a valid (non-expired) token exists
  static var hasValidToken: Bool {
    getValidAccessToken() != nil
  }

  // MARK: - Private Keychain Operations

  private static func storeString(_ value: String, forKey key: String) throws {
    guard let data = value.data(using: .utf8) else {
      throw KeychainError.unableToStore(status: errSecParam)
    }

    let query = baseQuery(forKey: key)

    // Delete existing item first
    SecItemDelete(query as CFDictionary)

    // Add new item with shared access
    var newItem = query
    newItem[kSecValueData as String] = data
    // Allow extensions to read the token after the first device unlock.
    newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

    let status = SecItemAdd(newItem as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw KeychainError.unableToStore(status: status)
    }
  }

  private static func getString(forKey key: String) throws -> String? {
    var query = baseQuery(forKey: key)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    switch status {
    case errSecSuccess:
      guard let data = result as? Data,
        let string = String(data: data, encoding: .utf8)
      else {
        return nil
      }
      return string

    case errSecItemNotFound:
      return nil

    default:
      throw KeychainError.unableToRetrieve(status: status)
    }
  }

  private static func deleteItem(forKey key: String) throws {
    let query = baseQuery(forKey: key)

    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unableToDelete(status: status)
    }
  }

  /// No `kSecAttrAccessGroup` here: every target that touches this keychain service has
  /// only `$(AppIdentifierPrefix)no.tidex.shared` in its keychain-access-groups entitlement,
  /// so that's the default group `SecItemAdd` uses. Omitting the attribute on queries makes
  /// them search across all of the app's access groups, so existing items stay readable.
  private static func baseQuery(forKey key: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
  }
}
