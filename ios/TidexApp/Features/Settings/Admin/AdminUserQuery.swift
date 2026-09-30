import Foundation
import Supabase

/// Matches `p_account` in `admin_list_users_api`.
enum AdminUserAccount: String, CaseIterable, Identifiable, Sendable {
  case any
  case admins
  case nonAdmins = "non_admins"
  case banned
  case notBanned = "not_banned"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .any: return "Any account"
    case .admins: return "Admins"
    case .nonAdmins: return "Not admins"
    case .banned: return "Banned"
    case .notBanned: return "Not banned"
    }
  }
}

/// Sign-in methods, matching the names in `auth.users.raw_app_meta_data.providers`.
enum AdminUserProvider: String, CaseIterable, Identifiable, Sendable {
  case apple
  case google
  case email
  case phone

  var id: String { rawValue }
  var title: String { rawValue.capitalized }
}

/// A window of days for the signup and activity filters.
enum AdminUserPeriod: Int, CaseIterable, Identifiable, Sendable {
  case day = 1
  case week = 7
  case month = 30
  case quarter = 90

  var id: Int { rawValue }
  var title: String { self == .day ? "24 hours" : "\(rawValue) days" }
}

enum AdminUserActivity: Hashable, Identifiable, Sendable {
  case activeWithin(AdminUserPeriod)
  case inactiveFor(AdminUserPeriod)

  static let allCases: [Self] = [
    .activeWithin(.day), .activeWithin(.week), .activeWithin(.month),
    .inactiveFor(.month), .inactiveFor(.quarter),
  ]

  var id: Self { self }

  var title: String {
    switch self {
    case .activeWithin(let period): return "Active in last \(period.title)"
    case .inactiveFor(let period): return "Inactive for \(period.title)+"
    }
  }
}

/// Matches `p_shifts`, `p_messages` and `p_friends` in `admin_list_users_api`.
enum AdminUserUsage: String, CaseIterable, Identifiable, Sendable {
  case any
  case with
  case without

  var id: String { rawValue }
}

/// Sort order and filters for the users list. The filters all apply together.
struct AdminUserQuery: Hashable, Sendable {
  /// `appVersion` value for users whose app hasn't reported a version.
  static let noAppVersion = "none"

  var sort: AdminUserSort = .name
  var reversed = false
  var account: AdminUserAccount = .any
  var language: AdminLanguage?
  var provider: AdminUserProvider?
  var signedUpWithin: AdminUserPeriod?
  var activity: AdminUserActivity?
  var shifts: AdminUserUsage = .any
  var messages: AdminUserUsage = .any
  var friends: AdminUserUsage = .any
  var appVersion: String?

  /// The query with the same sort and no filters.
  var withoutFilters: Self { Self(sort: sort, reversed: reversed) }
  var hasFilters: Bool { self != withoutFilters }

  var rpcParams: [String: AnyJSON] {
    var activeDays: AnyJSON = .null
    var inactiveDays: AnyJSON = .null
    switch activity {
    case .activeWithin(let period): activeDays = .integer(period.rawValue)
    case .inactiveFor(let period): inactiveDays = .integer(period.rawValue)
    case nil: break
    }
    return [
      "p_sort": .string(sort.rawValue),
      "p_reverse": .bool(reversed),
      "p_account": .string(account.rawValue),
      "p_language": language.map { AnyJSON.string($0.rawValue) } ?? .null,
      "p_provider": provider.map { AnyJSON.string($0.rawValue) } ?? .null,
      "p_signed_up_days": signedUpWithin.map { AnyJSON.integer($0.rawValue) } ?? .null,
      "p_active_days": activeDays,
      "p_inactive_days": inactiveDays,
      "p_shifts": .string(shifts.rawValue),
      "p_messages": .string(messages.rawValue),
      "p_friends": .string(friends.rawValue),
      "p_app_version": appVersion.map(AnyJSON.string) ?? .null,
    ]
  }
}
