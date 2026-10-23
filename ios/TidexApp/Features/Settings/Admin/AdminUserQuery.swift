import Foundation

/// Matches `account` in `admin:listUsers`.
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

/// Sign-in methods, matching the provider names on the users row.
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

/// Matches `shifts`, `messages` and `friends` in `admin:listUsers`.
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

  /// Arguments for `admin:listUsers`. Convex rejects null, so unset filters are left out.
  var convexArgs: [String: AnyJSON] {
    var args: [String: AnyJSON] = [
      "sort": .string(sort.rawValue),
      "reverse": .bool(reversed),
      "account": .string(account.rawValue),
      "shifts": .string(shifts.rawValue),
      "messages": .string(messages.rawValue),
      "friends": .string(friends.rawValue),
    ]
    if let language { args["language"] = .string(language.rawValue) }
    if let provider { args["provider"] = .string(provider.rawValue) }
    if let signedUpWithin { args["signed_up_days"] = .integer(signedUpWithin.rawValue) }
    if let appVersion { args["app_version"] = .string(appVersion) }
    switch activity {
    case .activeWithin(let period): args["active_days"] = .integer(period.rawValue)
    case .inactiveFor(let period): args["inactive_days"] = .integer(period.rawValue)
    case nil: break
    }
    return args
  }
}
