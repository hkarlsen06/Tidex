import Foundation
import Security
import os.log

private let calendarSubscriptionLogger = Logger(
  subsystem: "com.tidex.app",
  category: "CalendarSubscriptionService"
)

enum CalendarSubscriptionContentMode: String, CaseIterable, Identifiable, Codable, Sendable {
  case eventsOnly = "events_only"
  case shiftsOnly = "shifts_only"
  case shiftsAndEvents = "shifts_and_events"

  var id: String { rawValue }

  var localizedTitle: String {
    switch self {
    case .eventsOnly:
      return String(localized: .calendarSubscriptionModeEventsOnly)

    case .shiftsOnly:
      return String(localized: .calendarSubscriptionModeShiftsOnly)

    case .shiftsAndEvents:
      return String(localized: .calendarSubscriptionModeShiftsAndEvents)
    }
  }
}

struct CalendarSubscriptionMetadata: Codable, Equatable, Sendable {
  let id: String
  let contentMode: CalendarSubscriptionContentMode
  let tokenSuffix: String
  let createdAt: String
  let updatedAt: String
  let lastUsedAt: String?
}

struct CalendarSubscriptionState: Equatable, Sendable {
  var metadata: CalendarSubscriptionMetadata?

  // swiftlint:disable:next redundant_type_annotation
  internal static let inactive: Self = Self(metadata: nil)

  var isActive: Bool { metadata != nil }
}

struct CalendarSubscriptionCreated: Equatable, Sendable {
  let metadata: CalendarSubscriptionMetadata
  let rawToken: String
}

enum CalendarSubscriptionSetupIntent: Hashable, Sendable {
  case setup(mode: CalendarSubscriptionContentMode, autoOpen: Bool)

  var mode: CalendarSubscriptionContentMode {
    switch self {
    case .setup(let mode, _):
      return mode
    }
  }
}

protocol CalendarSubscriptionServicing: Sendable {
  func getSubscription() async throws -> CalendarSubscriptionState
  func createSubscription(mode: CalendarSubscriptionContentMode) async throws
    -> CalendarSubscriptionCreated
  func rotateSubscription(mode: CalendarSubscriptionContentMode?) async throws
    -> CalendarSubscriptionCreated
  func setContentMode(_ mode: CalendarSubscriptionContentMode) async throws
    -> CalendarSubscriptionMetadata
  func disableSubscription() async throws -> Bool
  func webcalURL(rawToken: String) -> URL?
  func httpsURL(rawToken: String) -> URL?
}

struct CalendarSubscriptionService: CalendarSubscriptionServicing {
  // swiftlint:disable:next redundant_type_annotation
  internal static let shared: Self = Self()

  private let api: ConvexAPI

  init(api: ConvexAPI = .app) {
    self.api = api
  }

  func getSubscription() async throws -> CalendarSubscriptionState {
    let row: CalendarSubscriptionStateRow = try await api.query("calendarSubscriptions:get")
    return row.state
  }

  func createSubscription(mode: CalendarSubscriptionContentMode) async throws
    -> CalendarSubscriptionCreated
  {
    let row: CalendarSubscriptionTokenRow = try await api.mutation(
      "calendarSubscriptions:create", ContentModeArgs(contentMode: mode))
    return row.created
  }

  /// Revokes the token and issues a new one in one mutation. Without a mode, the new token
  /// keeps the current one's.
  func rotateSubscription(mode: CalendarSubscriptionContentMode?) async throws
    -> CalendarSubscriptionCreated
  {
    let row: CalendarSubscriptionTokenRow = try await api.mutation(
      "calendarSubscriptions:rotate", RotateArgs(contentMode: mode))
    return row.created
  }

  func setContentMode(_ mode: CalendarSubscriptionContentMode) async throws
    -> CalendarSubscriptionMetadata
  {
    let row: CalendarSubscriptionMetadataRow = try await api.mutation(
      "calendarSubscriptions:setContentMode", ContentModeArgs(contentMode: mode))
    return row.metadata
  }

  func disableSubscription() async throws -> Bool {
    try await api.mutation("calendarSubscriptions:disable")
  }

  /// Feed URLs point at the Convex HTTP action. Tokens issued before the move still work on
  /// the old `api.tidex.no/functions/v1/calendar-feed/` URL, which the server forwards.
  func webcalURL(rawToken: String) -> URL? {
    feedURL(rawToken: rawToken, scheme: "webcal")
  }

  func httpsURL(rawToken: String) -> URL? {
    feedURL(rawToken: rawToken, scheme: "https")
  }

  private func feedURL(rawToken: String, scheme: String) -> URL? {
    var components = URLComponents(url: ConvexAPI.configuredSiteURL, resolvingAgainstBaseURL: false)
    components?.scheme = scheme
    components?.path = "/calendar-feed/\(rawToken).ics"
    return components?.url
  }

  private struct ContentModeArgs: Encodable, Sendable {
    let contentMode: CalendarSubscriptionContentMode
    enum CodingKeys: String, CodingKey { case contentMode = "content_mode" }
  }

  /// Leaves `content_mode` out when nil, so the server keeps the current mode.
  private struct RotateArgs: Encodable, Sendable {
    let contentMode: CalendarSubscriptionContentMode?
    enum CodingKeys: String, CodingKey { case contentMode = "content_mode" }
  }
}

struct CalendarSubscriptionKeychainToken: Codable, Equatable, Sendable {
  let userId: String
  let subscriptionId: String
  let tokenSuffix: String
  let rawToken: String
}

protocol CalendarSubscriptionTokenStoring {
  func loadToken(userId: String, metadata: CalendarSubscriptionMetadata)
    -> CalendarSubscriptionKeychainToken?
  func saveToken(_ token: CalendarSubscriptionKeychainToken) throws
  func deleteToken(userId: String, metadata: CalendarSubscriptionMetadata)
  func clearAllTokens()
}

final class CalendarSubscriptionKeychainStore: CalendarSubscriptionTokenStoring, Sendable {
  static let shared = CalendarSubscriptionKeychainStore()

  private let service = "\(APIConfiguration.keychainService).calendar-subscriptions"
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  private init() {}

  func loadToken(userId: String, metadata: CalendarSubscriptionMetadata)
    -> CalendarSubscriptionKeychainToken?
  {
    var query = baseQuery(account: account(userId: userId, metadata: metadata))
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { return nil }

    guard let token = try? decoder.decode(CalendarSubscriptionKeychainToken.self, from: data),
      token.userId == userId,
      token.subscriptionId == metadata.id,
      token.tokenSuffix == metadata.tokenSuffix
    else {
      deleteToken(userId: userId, metadata: metadata)
      return nil
    }

    return token
  }

  func saveToken(_ token: CalendarSubscriptionKeychainToken) throws {
    let data = try encoder.encode(token)
    let account = account(userId: token.userId, subscriptionId: token.subscriptionId)
    SecItemDelete(baseQuery(account: account) as CFDictionary)

    var item = baseQuery(account: account)
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    let status = SecItemAdd(item as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw CalendarSubscriptionKeychainError.storeFailed(status)
    }
  }

  func deleteToken(userId: String, metadata: CalendarSubscriptionMetadata) {
    SecItemDelete(baseQuery(account: account(userId: userId, metadata: metadata)) as CFDictionary)
  }

  func clearAllTokens() {
    SecItemDelete(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
      ] as CFDictionary)
  }

  private func baseQuery(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  private func account(userId: String, metadata: CalendarSubscriptionMetadata) -> String {
    account(userId: userId, subscriptionId: metadata.id)
  }

  private func account(userId: String, subscriptionId: String) -> String {
    "\(userId):\(subscriptionId)"
  }
}

enum CalendarSubscriptionKeychainError: Error {
  case storeFailed(OSStatus)
}

private struct CalendarSubscriptionStateRow: Decodable {
  let isActive: Bool
  let id: String?
  let contentMode: CalendarSubscriptionContentMode?
  let tokenSuffix: String?
  let createdAt: String?
  let updatedAt: String?
  let lastUsedAt: String?

  enum CodingKeys: String, CodingKey {
    case isActive = "is_active"
    case id
    case contentMode = "content_mode"
    case tokenSuffix = "token_suffix"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case lastUsedAt = "last_used_at"
  }

  var state: CalendarSubscriptionState {
    guard isActive, let id, let contentMode, let tokenSuffix, let createdAt, let updatedAt else {
      return .inactive
    }

    return CalendarSubscriptionState(
      metadata: CalendarSubscriptionMetadata(
        id: id,
        contentMode: contentMode,
        tokenSuffix: tokenSuffix,
        createdAt: createdAt,
        updatedAt: updatedAt,
        lastUsedAt: lastUsedAt
      ))
  }
}

private struct CalendarSubscriptionMetadataRow: Decodable {
  let id: String
  let contentMode: CalendarSubscriptionContentMode
  let tokenSuffix: String
  let createdAt: String
  let updatedAt: String
  let lastUsedAt: String?

  enum CodingKeys: String, CodingKey {
    case id
    case contentMode = "content_mode"
    case tokenSuffix = "token_suffix"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
    case lastUsedAt = "last_used_at"
  }

  var metadata: CalendarSubscriptionMetadata {
    CalendarSubscriptionMetadata(
      id: id,
      contentMode: contentMode,
      tokenSuffix: tokenSuffix,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastUsedAt: lastUsedAt
    )
  }
}

private struct CalendarSubscriptionTokenRow: Decodable {
  let id: String
  let contentMode: CalendarSubscriptionContentMode
  let tokenSuffix: String
  let rawToken: String
  let createdAt: String

  enum CodingKeys: String, CodingKey {
    case id
    case contentMode = "content_mode"
    case tokenSuffix = "token_suffix"
    case rawToken = "raw_token"
    case createdAt = "created_at"
  }

  var created: CalendarSubscriptionCreated {
    CalendarSubscriptionCreated(
      metadata: CalendarSubscriptionMetadata(
        id: id,
        contentMode: contentMode,
        tokenSuffix: tokenSuffix,
        createdAt: createdAt,
        updatedAt: createdAt,
        lastUsedAt: nil
      ),
      rawToken: rawToken
    )
  }
}

extension CalendarSubscriptionService {
  static func isDuplicateActiveSubscriptionError(_ error: Error) -> Bool {
    if let failure = error as? ConvexAPI.Failure, failure.code == "already_exists" {
      return true
    }

    return error.localizedDescription.localizedCaseInsensitiveContains(
      "active calendar subscription already exists")
  }
}
