import Foundation
import UIKit
import UserNotifications
import WidgetKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "AppActivityReporter")

/// Records an app open with `appActivity:record`. The admin user screen shows the build,
/// device and settings sent here, and the admin home charts count the opens.
@MainActor
enum AppActivityReporter {
  static func record() async {
    let info = Bundle.main.infoDictionary
    let notificationStatus = await UNUserNotificationCenter.current().notificationSettings()
      .authorizationStatus
    let widgetKinds = (try? await WidgetCenter.shared.currentConfigurations())
      .map { Set($0.map(\.kind)).sorted() }
    let style = UIApplication.shared.connectedScenes
      .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.traitCollection.userInterfaceStyle

    // Convex rejects null for an optional argument, so a missing value is left out.
    var params: [String: AnyJSON] = [
      "os_version": .string("iOS \(UIDevice.current.systemVersion)"),
      "device_model": .string(deviceModel()),
      "locale": .string(Locale.autoupdatingCurrent.identifier),
      "time_zone": .string(TimeZone.current.identifier),
      "notification_permission": .string(notificationPermissionCode(notificationStatus)),
      "background_refresh": .string(backgroundRefreshCode(UIApplication.shared.backgroundRefreshStatus)),
      "text_size": .string(textSizeCode(UIApplication.shared.preferredContentSizeCategory)),
      "reduce_motion": .bool(UIAccessibility.isReduceMotionEnabled),
    ]
    if let version = info?["CFBundleShortVersionString"] as? String {
      params["app_version"] = .string(version)
    }
    if let build = info?["CFBundleVersion"] as? String {
      params["build_number"] = .string(build)
    }
    if let language = Bundle.main.preferredLocalizations.first {
      params["app_language"] = .string(language)
    }
    if style == .dark || style == .light {
      params["appearance"] = .string(style == .dark ? "dark" : "light")
    }
    if let widgetKinds {
      params["widget_kinds"] = .array(widgetKinds.map(AnyJSON.string))
    }

    do {
      _ = try await ConvexAPI.app.mutation(
        "appActivity:record", params, as: ConvexAPI.Ignored.self)
    } catch {
      logger.debug("Failed to record app activity: \(error.localizedDescription)")
    }
  }

  static func notificationPermissionCode(_ status: UNAuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "not_determined"
    case .denied: return "denied"
    case .authorized: return "authorized"
    case .provisional: return "provisional"
    case .ephemeral: return "ephemeral"
    @unknown default: return "unknown"
    }
  }

  static func backgroundRefreshCode(_ status: UIBackgroundRefreshStatus) -> String {
    switch status {
    case .available: return "available"
    case .denied: return "denied"
    case .restricted: return "restricted"
    @unknown default: return "unknown"
    }
  }

  /// "L" for the default size, "AccessibilityXL" and so on for larger ones.
  static func textSizeCode(_ category: UIContentSizeCategory) -> String {
    category.rawValue.replacing("UICTContentSizeCategory", with: "")
  }

  /// Hardware identifier such as "iPhone17,1". `UIDevice.model` only says "iPhone".
  private static func deviceModel() -> String {
    var system = utsname()
    uname(&system)
    return withUnsafeBytes(of: system.machine) {
      String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) ?? ""
    }
  }
}
