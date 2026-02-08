import Foundation
import Security

/// Shared Keychain storage accessible from all targets (main app, widget, watch)
/// Uses a shared access group to allow cross-target access to auth tokens
///
/// ## Usage
/// The main app writes the JWT token after successful authentication.
/// Widget and Watch can read this token to make authenticated API calls directly.
enum SharedKeychainStorage {
  // MARK: - Configuration

  /// Shared keychain access group suffix (team ID prefix is added at runtime)
  /// Format: $(AppIdentifierPrefix)no.tidex.shared in entitlements
  private static let accessGroupSuffix = "no.tidex.shared"

  /// Keychain service identifier
  private static let service = "no.tidex.shared.auth"

  /// Key for storing the access token
  private static let accessTokenKey = "access_token"

  /// Key for storing the token expiry timestamp
  private static let tokenExpiryKey = "token_expiry"

  /// Cache the access group once discovered (team ID prefix + suffix)
  private static var cachedAccessGroup: String?

  /// Get the full access group with team ID prefix
  /// Derives the team ID at runtime by querying an existing keychain item
  private static func getAccessGroup() -> String {
    if let cached = cachedAccessGroup {
      return cached
    }

    // Try to discover team ID from an existing keychain item
    if let teamId = discoverTeamId() {
      let fullGroup = "\(teamId).\(accessGroupSuffix)"
      cachedAccessGroup = fullGroup
      return fullGroup
    }

    // Fallback: try without explicit access group (uses app's default)
    // This works when the app only has one access group
    cachedAccessGroup = accessGroupSuffix
    return accessGroupSuffix
  }

  /// Discover the team ID by creating and querying a temporary keychain item
  private static func discoverTeamId() -> String? {
    // Create a temporary item to discover the access group
    let tempKey = "__tidex_team_id_probe__"
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: tempKey,
      kSecValueData as String: Data("probe".utf8),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
      kSecReturnAttributes as String: true
    ]

    // Delete any existing probe item
    SecItemDelete(query as CFDictionary)

    // Add the item and get its attributes back
    var result: AnyObject?
    let addStatus = SecItemAdd(query as CFDictionary, &result)

    // Clean up the probe item
    SecItemDelete(query as CFDictionary)

    guard addStatus == errSecSuccess,
      let attributes = result as? [String: Any],
      let accessGroup = attributes[kSecAttrAccessGroup as String] as? String
    else {
      return nil
    }

    // Access group format is "TEAMID.bundleid" - extract the team ID
    // We want to use this team ID with our shared group suffix
    let components = accessGroup.split(separator: ".", maxSplits: 1)
    if let teamId = components.first {
      return String(teamId)
    }

    return nil
  }

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

  // MARK: - Token Retrieval (Widget/Watch)

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

    // Build query for existing item
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecAttrAccessGroup as String: getAccessGroup()
    ]

    // Delete existing item first
    SecItemDelete(query as CFDictionary)

    // Add new item with shared access
    var newItem = query
    newItem[kSecValueData as String] = data
    // Use WhenUnlocked for widget/watch background access
    newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

    let status = SecItemAdd(newItem as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw KeychainError.unableToStore(status: status)
    }
  }

  private static func getString(forKey key: String) throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecAttrAccessGroup as String: getAccessGroup(),
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne
    ]

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
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecAttrAccessGroup as String: getAccessGroup()
    ]

    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unableToDelete(status: status)
    }
  }
}
