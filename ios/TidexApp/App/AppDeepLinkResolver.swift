// swiftlint:disable:next blanket_disable_command
// swiftlint:disable conditional_returns_on_newline cyclomatic_complexity discouraged_optional_collection explicit_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_top_level_acl explicit_type_interface extension_access_modifier function_body_length
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable strict_fileprivate
import Foundation

enum AppDeepLinkResolver {
  static func resolve(_ url: URL) -> AppCoordinator.DeepLink? {
    let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

    if url.scheme?.lowercased() == "tidex" {
      switch url.host?.lowercased() {
      case "sharing":
        return sharingDeepLink(path: url.path, queryItems: queryItems)

      case "shifts":
        return shiftsDeepLink(queryItems: queryItems)

      case "add", "add-shift", "add_shift":
        return addShiftDeepLink(queryItems: queryItems)

      case "settings":
        return settingsDeepLink(path: url.path, queryItems: queryItems)

      case "admin":
        return adminDeepLink(queryItems: queryItems)

      default:
        return nil
      }
    }

    guard
      let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      url.host?.lowercased() == "app.tidex.no"
    else {
      return nil
    }

    let path = normalizedAppPath(url.path)
    if path == "/sharing" || path == "/sharing/manage" {
      return sharingDeepLink(path: path, queryItems: queryItems)
    }
    if path == "/shifts" {
      return shiftsDeepLink(queryItems: queryItems)
    }
    if path == "/add" || path == "/add-shift" || path == "/add_shift" {
      return addShiftDeepLink(queryItems: queryItems)
    }
    if path == "/admin" || path == "/settings/admin" {
      return adminDeepLink(queryItems: queryItems)
    }
    if path == "/settings" || path.hasPrefix("/settings/") {
      return settingsDeepLink(path: path, queryItems: queryItems)
    }

    return nil
  }

  private static func sharingDeepLink(
    path: String,
    queryItems: [URLQueryItem]
  ) -> AppCoordinator.DeepLink {
    let pathComponents = path.split(separator: "/")
    if path == "/manage" || path == "/sharing/manage" || pathComponents.contains("manage") {
      return .sharingManage(highlightUserId: queryItems.value(named: "highlight"))
    }

    return .sharing(
      sharerId: queryItems.value(named: "user"),
      highlightDates: queryItems.commaSeparatedValue(named: "dates"),
      changes: nil
    )
  }

  private static func shiftsDeepLink(queryItems: [URLQueryItem]) -> AppCoordinator.DeepLink {
    let actionString = queryItems.value(named: "action")?.lowercased()
    let action: AppCoordinator.ShiftDeepLinkAction =
      actionString == "highlight" ? .highlight : .open
    return .shifts(
      dates: queryItems.commaSeparatedValue(named: "dates"),
      shiftIds: queryItems.commaSeparatedValue(named: "shiftIds")
        ?? queryItems.commaSeparatedValue(named: "shift_ids")
        ?? queryItems.commaSeparatedValue(named: "shiftId")
        ?? queryItems.commaSeparatedValue(named: "shift_id"),
      action: action
    )
  }

  private static func addShiftDeepLink(queryItems: [URLQueryItem]) -> AppCoordinator.DeepLink {
    .addShift(
      mode: addShiftMode(queryItems.value(named: "mode")),
      date: queryItems.value(named: "date")
    )
  }

  private static func addShiftMode(_ rawValue: String?) -> AddShiftMode? {
    guard let rawValue else { return nil }
    switch rawValue.normalizedDeepLinkToken {
    case "single", "shift", "shifts", "vakt", "vaktskift":
      return .single

    case "event", "events", "calendar", "private_event", "privat", "avtale":
      return .events

    case "recurring", "recurring_shift", "recurring_shifts", "fast", "faste",
      "fast_vakt", "gjentakende", "gjentakende_vakt":
      return .recurring

    default:
      return nil
    }
  }

  private static func settingsDeepLink(
    path: String,
    queryItems: [URLQueryItem]
  ) -> AppCoordinator.DeepLink {
    let pathSegments = path.split(separator: "/", omittingEmptySubsequences: true)
    let pathDestination = settingsPathDestination(from: pathSegments)
    let rawDestination =
      queryItems.value(named: "destination")
      ?? queryItems.value(named: "page")
      ?? queryItems.value(named: "tab")
      ?? pathDestination

    return .settings(
      destination: settingsDestination(
        rawDestination,
        jobId: queryItems.value(named: "jobId") ?? queryItems.value(named: "job_id")
      )
    )
  }

  private static func settingsPathDestination(
    from pathSegments: [Substring]
  ) -> String? {
    guard let first = pathSegments.first else { return nil }
    if first == "settings" {
      return pathSegments.dropFirst().first.map(String.init)
    }
    return String(first)
  }

  private static func settingsDestination(
    _ rawValue: String?,
    jobId: String?
  ) -> AppCoordinator.SettingsDeepLinkDestination? {
    guard let rawValue else { return nil }
    switch rawValue.normalizedDeepLinkToken {
    case "profile", "account_profile", "name":
      return .profile

    case "security", "mfa", "auth", "account_security":
      return .security

    case "notifications", "notification", "reminders":
      return .notifications

    case "appearance", "theme", "display":
      return .appearance

    case "pay", "wage", "wages", "salary", "tax", "taxes", "workplace", "workplaces",
      "jobs", "job", "payroll", "payroll_adjustments", "adjustments", "wage_snapshots":
      return .pay(jobId: jobId)

    case "recurring", "recurring_shift", "recurring_shifts":
      return .recurringShifts

    case "calendar", "calendar_sync", "calendar_subscription":
      return .calendarSync

    case "data", "export", "import":
      return .data

    case "feedback", "support":
      return .feedback

    case "admin":
      return .admin

    default:
      return nil
    }
  }

  private static func adminDeepLink(queryItems: [URLQueryItem]) -> AppCoordinator.DeepLink {
    switch queryItems.value(named: "tab")?.lowercased() {
    case "reports":
      return .adminReport(reportId: queryItems.value(named: "reportId"))

    default:
      return .adminFeedback
    }
  }

  private static func normalizedAppPath(_ path: String) -> String {
    let segments = path.split(separator: "/", omittingEmptySubsequences: true)
    guard let first = segments.first else { return "/" }

    let strippedSegments =
      first == "en" || first == "no"
      ? Array(segments.dropFirst())
      : Array(segments)

    guard !strippedSegments.isEmpty else { return "/" }
    return "/" + strippedSegments.joined(separator: "/")
  }
}

extension Array where Element == URLQueryItem {
  fileprivate func value(named name: String) -> String? {
    first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
  }

  fileprivate func commaSeparatedValue(named name: String) -> [String]? {
    guard let value = value(named: name) else { return nil }
    let values =
      value
      .components(separatedBy: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    return values.isEmpty ? nil : values
  }
}

extension String {
  fileprivate var normalizedDeepLinkToken: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: "-", with: "_")
      .replacingOccurrences(of: " ", with: "_")
  }
}
