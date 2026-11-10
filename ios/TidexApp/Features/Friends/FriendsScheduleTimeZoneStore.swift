import Foundation

/// Derived sharing metadata. Each viewer has a separate cache and removed shares lose their zone.
@MainActor
final class FriendsScheduleTimeZoneStore {
  static let shared = FriendsScheduleTimeZoneStore()
  private let defaults: UserDefaults
  private let prefix = "friends.scheduleTimeZones."

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  func zone(ownerId: String, viewerId: String) -> String? {
    (defaults.dictionary(forKey: prefix + viewerId) as? [String: String])?[ownerId]
  }

  func replace(_ previews: [SharerShiftPreview], viewerId: String) {
    let zones = previews.reduce(into: [String: String]()) { result, preview in
      result[preview.sharerId] = preview.ownerTimeZone
    }
    defaults.set(zones, forKey: prefix + viewerId)
  }

  func set(_ zone: String?, ownerId: String, viewerId: String) {
    var zones = defaults.dictionary(forKey: prefix + viewerId) as? [String: String] ?? [:]
    zones[ownerId] = zone
    defaults.set(zones, forKey: prefix + viewerId)
  }

  func resetForUserChange() {
    for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
      defaults.removeObject(forKey: key)
    }
  }
}
