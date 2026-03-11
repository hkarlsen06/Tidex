import Foundation

protocol FriendsMessagingCapabilityProviding {
  var canSendShiftSnapshots: Bool { get }
}

struct FriendsMessagingCapabilities: FriendsMessagingCapabilityProviding {
  private enum InfoKeys {
    static let shiftSnapshotsEnabled = "FRIENDS_SHIFT_SNAPSHOTS_ENABLED"
    static let shiftSnapshotsMinimumVersion = "FRIENDS_SHIFT_SNAPSHOTS_MINIMUM_APP_VERSION"
  }

  private enum DefaultsKeys {
    static let shiftSnapshotsEnabled = "friends.messaging.shiftSnapshots.enabled"
    static let shiftSnapshotsMinimumVersion = "friends.messaging.shiftSnapshots.minimumAppVersion"
  }

  static let shared = FriendsMessagingCapabilities()

  private let bundle: Bundle
  private let userDefaults: UserDefaults

  init(bundle: Bundle = .main, userDefaults: UserDefaults = .standard) {
    self.bundle = bundle
    self.userDefaults = userDefaults
  }

  var canSendShiftSnapshots: Bool {
    shiftSnapshotsFeatureFlagEnabled && meetsMinimumShiftSnapshotVersion
  }

  private var shiftSnapshotsFeatureFlagEnabled: Bool {
    if let value = userDefaults.object(forKey: DefaultsKeys.shiftSnapshotsEnabled) as? Bool {
      return value
    }

    if let value = bundle.object(forInfoDictionaryKey: InfoKeys.shiftSnapshotsEnabled) as? Bool {
      return value
    }

    return false
  }

  private var minimumShiftSnapshotVersion: String? {
    if let value = userDefaults.string(forKey: DefaultsKeys.shiftSnapshotsMinimumVersion),
      !value.isEmpty
    {
      return value
    }

    if let value = bundle.object(forInfoDictionaryKey: InfoKeys.shiftSnapshotsMinimumVersion)
      as? String,
      !value.isEmpty
    {
      return value
    }

    return nil
  }

  private var meetsMinimumShiftSnapshotVersion: Bool {
    guard let minimumShiftSnapshotVersion else { return false }
    let currentVersion =
      bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "0"

    return Self.compareVersion(currentVersion, minimumShiftSnapshotVersion) != .orderedAscending
  }

  private static func compareVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
    let lhsComponents = lhs.split(separator: ".").map { Int($0) ?? 0 }
    let rhsComponents = rhs.split(separator: ".").map { Int($0) ?? 0 }
    let maxCount = max(lhsComponents.count, rhsComponents.count)

    for index in 0..<maxCount {
      let lhsValue = index < lhsComponents.count ? lhsComponents[index] : 0
      let rhsValue = index < rhsComponents.count ? rhsComponents[index] : 0

      if lhsValue < rhsValue {
        return .orderedAscending
      }

      if lhsValue > rhsValue {
        return .orderedDescending
      }
    }

    return .orderedSame
  }
}
