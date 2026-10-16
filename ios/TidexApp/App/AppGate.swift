// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface no_magic_numbers
import Foundation
import os.log

private let logger = Logger(subsystem: "no.tidex.app", category: "AppGate")

/// Blocks the app while `app-config.json` on tidex.no says this version is too old
/// or the backend is down for maintenance.
/// If the file can't be fetched, the app keeps the last answer, so an outage of tidex.no never locks anyone out.
@MainActor
@Observable
final class AppGate {
  static let shared = AppGate()

  private(set) var block: AppGateBlock?

  private let appVersion =
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

  func refresh() async {
    let request = URLRequest(
      url: APIConfiguration.appConfigURL,
      cachePolicy: .reloadIgnoringLocalCacheData,
      timeoutInterval: 10
    )
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else {
        logger.warning("app-config.json returned non-200 status")
        return
      }
      let config = try JSONDecoder().decode(AppGateConfig.self, from: data)
      block = AppGateConfig.block(for: config, appVersion: appVersion)
    } catch {
      logger.warning("Failed to fetch app-config.json: \(error.localizedDescription)")
    }
  }
}

enum AppGateBlock: Equatable {
  case updateRequired
  case maintenance
}

/// The contents of `marketing/public/app-config.json`. Both fields are optional so the file can grow.
struct AppGateConfig: Decodable, Equatable {
  var minimumVersion: String?
  var maintenance: Bool?

  /// A too-old app gets the update screen even during maintenance, since it can't use the backend afterwards.
  static func block(for config: Self, appVersion: String) -> AppGateBlock? {
    if let minimumVersion = config.minimumVersion,
      isVersion(appVersion, olderThan: minimumVersion)
    {
      return .updateRequired
    }
    return config.maintenance == true ? .maintenance : nil
  }

  /// Compares dotted versions number by number, treating missing parts as 0, so "3.0" equals "3.0.0".
  static func isVersion(_ version: String, olderThan minimum: String) -> Bool {
    let lhs = version.split(separator: ".").map { Int($0) ?? 0 }
    let rhs = minimum.split(separator: ".").map { Int($0) ?? 0 }
    for index in 0..<max(lhs.count, rhs.count) {
      let left = index < lhs.count ? lhs[index] : 0
      let right = index < rhs.count ? rhs[index] : 0
      if left != right { return left < right }
    }
    return false
  }
}
