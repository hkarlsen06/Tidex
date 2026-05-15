import Foundation
import Security
import Supabase
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
      return String(localized: "calendar.subscription.mode.events_only")
    case .shiftsOnly:
      return String(localized: "calendar.subscription.mode.shifts_only")
    case .shiftsAndEvents:
      return String(localized: "calendar.subscription.mode.shifts_and_events")
    }
  }
}

struct CalendarSubscriptionMetadata: Equatable, Sendable {
  let id: String
  let contentMode: CalendarSubscriptionContentMode
  let tokenSuffix: String
  let createdAt: String
  let updatedAt: String
  let lastUsedAt: String?
}

struct CalendarSubscriptionState: Equatable, Sendable {
  var metadata: CalendarSubscriptionMetadata?

  static let inactive = CalendarSubscriptionState(metadata: nil)

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

protocol CalendarSubscriptionServicing {
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
  static let shared = CalendarSubscriptionService()

  private let supabaseClient: SupabaseClient

  init(supabaseClient: SupabaseClient = supabase) {
    self.supabaseClient = supabaseClient
  }

  func getSubscription() async throws -> CalendarSubscriptionState {
    _ = try await AuthSessionManager.shared.getSession()

    let row: CalendarSubscriptionStateRow =
      try await supabaseClient
      .rpc("get_my_calendar_subscription")
      .single()
      .execute()
      .value

    return row.state
  }

  func createSubscription(mode: CalendarSubscriptionContentMode) async throws
    -> CalendarSubscriptionCreated
  {
    _ = try await AuthSessionManager.shared.getSession()

    let row: CalendarSubscriptionTokenRow =
      try await supabaseClient
      .rpc("create_my_calendar_subscription", params: contentModeParams(mode))
      .single()
      .execute()
      .value

    return row.created
  }

  func rotateSubscription(mode: CalendarSubscriptionContentMode?) async throws
    -> CalendarSubscriptionCreated
  {
    _ = try await AuthSessionManager.shared.getSession()

    let row: CalendarSubscriptionTokenRow =
      try await supabaseClient
      .rpc(
        "rotate_my_calendar_subscription",
        params: ["p_content_mode": mode.map { AnyJSON.string($0.rawValue) } ?? AnyJSON.null]
      )
      .single()
      .execute()
      .value

    return row.created
  }

  func setContentMode(_ mode: CalendarSubscriptionContentMode) async throws
    -> CalendarSubscriptionMetadata
  {
    _ = try await AuthSessionManager.shared.getSession()

    let row: CalendarSubscriptionMetadataRow =
      try await supabaseClient
      .rpc("set_my_calendar_subscription_content_mode", params: contentModeParams(mode))
      .single()
      .execute()
      .value

    return try row.metadata
  }

  func disableSubscription() async throws -> Bool {
    _ = try await AuthSessionManager.shared.getSession()

    let disabled: Bool =
      try await supabaseClient
      .rpc("disable_my_calendar_subscription")
      .execute()
      .value

    return disabled
  }

  func webcalURL(rawToken: String) -> URL? {
    URL(string: "webcal://identity.tidex.no/functions/v1/calendar-feed/\(rawToken).ics")
  }

  func httpsURL(rawToken: String) -> URL? {
    URL(string: "https://identity.tidex.no/functions/v1/calendar-feed/\(rawToken).ics")
  }

  private func contentModeParams(_ mode: CalendarSubscriptionContentMode) -> [String: AnyJSON] {
    ["p_content_mode": .string(mode.rawValue)]
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

final class CalendarSubscriptionKeychainStore: CalendarSubscriptionTokenStoring {
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
    get throws {
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
    if let postgrestError = error as? PostgrestError {
      return postgrestError.message.localizedCaseInsensitiveContains(
        "active calendar subscription already exists")
    }

    return error.localizedDescription.localizedCaseInsensitiveContains(
      "active calendar subscription already exists")
  }
}
