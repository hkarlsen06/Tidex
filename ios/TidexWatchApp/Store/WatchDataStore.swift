import Foundation
import WidgetKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "WatchDataStore")

/// In-memory data store for Watch shift data
/// Receives updates from WatchConnectivityManager and notifies views
@MainActor
@Observable
final class WatchDataStore {
  static let shared = WatchDataStore()
  private static let appGroupId = "group.no.tidex.app"
  private static let payloadStorageKey = "watch_data_payload_v1"

  private(set) var userShift: WatchShiftDTO?
  private(set) var friendShifts: [WatchShiftDTO] = []
  private(set) var currencySymbol: String = "kr"
  private(set) var lastUpdated: Date?
  private(set) var lastSyncTimestamp: Date?

  /// Whether any shift data is available
  var hasData: Bool {
    userShift != nil || !friendShifts.isEmpty
  }

  /// Formatted "Updated X ago" text
  var updatedAgoText: String? {
    guard let lastUpdated = lastUpdated else { return nil }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: lastUpdated, relativeTo: Date())
  }

  private init() {
    loadPersistedPayload()
  }

  /// Update store with new payload from iPhone
  func update(from payload: WatchDataPayload) {
    self.userShift = payload.userShift
    self.friendShifts = payload.friendShifts
    self.currencySymbol = payload.currencySymbol
    self.lastUpdated = payload.timestamp
    self.lastSyncTimestamp = payload.lastSyncTimestamp
    persist(payload: payload)

    logger.info(
      "Store updated: user=\(payload.userShift != nil), friends=\(payload.friendShifts.count)")

    // Reload complications when data changes
    WidgetCenter.shared.reloadAllTimelines()
  }

  // MARK: - Persistence

  private func persist(payload: WatchDataPayload) {
    guard let userDefaults = UserDefaults(suiteName: Self.appGroupId),
      let data = try? JSONEncoder().encode(payload)
    else {
      return
    }
    userDefaults.set(data, forKey: Self.payloadStorageKey)
  }

  private func loadPersistedPayload() {
    guard let userDefaults = UserDefaults(suiteName: Self.appGroupId),
      let data = userDefaults.data(forKey: Self.payloadStorageKey),
      let payload = try? JSONDecoder().decode(WatchDataPayload.self, from: data)
    else {
      return
    }

    self.userShift = payload.userShift
    self.friendShifts = payload.friendShifts
    self.currencySymbol = payload.currencySymbol
    self.lastUpdated = payload.timestamp
    self.lastSyncTimestamp = payload.lastSyncTimestamp
  }

  // MARK: - Localization Helpers

  /// Localized string for "Shifts" title
  var shiftsTitle: String {
    String(localized: .watchShifts)
  }

  /// Localized string for "My Shift" section
  var myShiftTitle: String {
    String(localized: .watchMyShift)
  }

  /// Localized string for "Friends" section
  var friendsTitle: String {
    String(localized: .watchFriends)
  }

  /// Localized string for "No Shifts"
  var noShiftsTitle: String {
    String(localized: .watchNoShifts)
  }

  /// Localized string for sync instruction
  var syncInstructionText: String {
    String(localized: .watchSyncInstruction)
  }

  /// Localized string for "Refresh" button
  var refreshButtonTitle: String {
    String(localized: .watchRefresh)
  }

  /// Localized string for "Next Shift"
  var nextShiftTitle: String {
    String(localized: .watchNextShift)
  }

  /// Localized string for "Shift"
  var shiftTitle: String {
    String(localized: .watchShift)
  }
}
