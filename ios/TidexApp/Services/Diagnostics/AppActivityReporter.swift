import Foundation
import Supabase
import UIKit
import UserNotifications
import WidgetKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "AppActivityReporter")

/// Records an app open with `record_app_activity`. The admin user screen shows the build,
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

    var params: [String: AnyJSON] = [
      "p_app_version": optional(info?["CFBundleShortVersionString"] as? String),
      "p_build_number": optional(info?["CFBundleVersion"] as? String),
      "p_os_version": .string("iOS \(UIDevice.current.systemVersion)"),
      "p_device_model": .string(deviceModel()),
      "p_locale": .string(Locale.autoupdatingCurrent.identifier),
      "p_time_zone": .string(TimeZone.current.identifier),
      "p_app_language": optional(Bundle.main.preferredLocalizations.first),
      "p_notification_permission": .string(notificationPermissionCode(notificationStatus)),
      "p_background_refresh": .string(backgroundRefreshCode(UIApplication.shared.backgroundRefreshStatus)),
      "p_appearance": optional(style == .dark ? "dark" : style == .light ? "light" : nil),
      "p_text_size": .string(textSizeCode(UIApplication.shared.preferredContentSizeCategory)),
      "p_reduce_motion": .bool(UIAccessibility.isReduceMotionEnabled),
    ]
    if let widgetKinds {
      params["p_widget_kinds"] = .array(widgetKinds.map(AnyJSON.string))
    }

    do {
      try await supabase.rpc("record_app_activity", params: params).execute()
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

  private static func optional(_ value: String?) -> AnyJSON {
    value.map(AnyJSON.string) ?? .null
  }
}
