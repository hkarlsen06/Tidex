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

  private var calendar: Calendar {
    .current
  }

  /// Whether any shift data is available
  var hasData: Bool {
    userShift != nil || !friendShifts.isEmpty
  }

  var orderedFriendShifts: [WatchShiftDTO] {
    friendShifts.sorted { lhs, rhs in
      compare(lhs, rhs) == .orderedAscending
    }
  }

  var nextRelevantShift: WatchShiftDTO? {
    allShifts
      .filter { effectiveStatus(for: $0, now: Date()) != .past }
      .min { lhs, rhs in
        compare(lhs, rhs) == .orderedAscending
      }
  }

  var activeShiftCount: Int {
    allShifts.filter { effectiveStatus(for: $0, now: Date()) == .active }.count
  }

  var isStale: Bool {
    guard let lastUpdated else { return false }
    return Date().timeIntervalSince(lastUpdated) > 60 * 60 * 6
  }

  /// Formatted "Updated X ago" text
  var updatedAgoText: String? {
    guard let lastUpdated else {
      return nil
    }
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: lastUpdated, relativeTo: Date())
  }

  private var allShifts: [WatchShiftDTO] {
    [userShift].compactMap(\.self) + friendShifts
  }

  private init() {
    loadPersistedPayload()
  }

  #if DEBUG && targetEnvironment(simulator)
    nonisolated static var isScreenshotMode: Bool {
      ProcessInfo.processInfo.arguments.contains("-ui-testing")
        && ProcessInfo.processInfo.arguments.contains("-app-store-screenshots")
    }

    /// In-memory fictional data; never persisted or requested from an account.
    func loadScreenshotFixture() {
      userShift = WatchShiftDTO(
        id: "screenshot-own-shift", personId: "screenshot-alex", personName: "Alex",
        personProfilePictureUrl: nil, personOauthAvatarUrl: nil,
        shiftDate: "2026-09-10", startTime: "09:00", endTime: "17:00",
        status: .upcoming, avatarImageData: nil
      )
      friendShifts = [
        WatchShiftDTO(
          id: "screenshot-friend-shift", personId: "screenshot-emma", personName: "Emma",
          personProfilePictureUrl: nil, personOauthAvatarUrl: nil,
          shiftDate: "2026-09-10", startTime: "10:00", endTime: "18:00",
          status: .upcoming, avatarImageData: nil
        )
      ]
      lastUpdated = Date.now.addingTimeInterval(-120)
      lastSyncTimestamp = lastUpdated
    }
  #endif

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

  var updatedTitle: String {
    String(localized: .watchUpdated)
  }

  var staleDataTitle: String {
    String(localized: .watchDataStale)
  }

  var currentlyActiveTitle: String {
    String(localized: .watchCurrentlyActive)
  }

  // MARK: - Shift Timeline Helpers

  func effectiveStatus(for shift: WatchShiftDTO, now: Date) -> ShiftPreviewStatus {
    guard let start = startDate(for: shift), let end = endDate(for: shift) else {
      return shift.status
    }

    if now >= start, now < end {
      return .active
    }
    if now < start {
      return .upcoming
    }
    return .past
  }

  func startDate(for shift: WatchShiftDTO) -> Date? {
    guard let shiftDate = parseDate(shift.shiftDate) else { return nil }
    let startParts = shift.startTime.split(separator: ":").compactMap { Int($0) }
    guard startParts.count >= 2 else { return nil }

    var components = calendar.dateComponents([.year, .month, .day], from: shiftDate)
    components.hour = startParts[0]
    components.minute = startParts[1]
    return calendar.date(from: components)
  }

  func endDate(for shift: WatchShiftDTO) -> Date? {
    guard let shiftDate = parseDate(shift.shiftDate),
      let start = startDate(for: shift)
    else { return nil }

    let endParts = shift.endTime.split(separator: ":").compactMap { Int($0) }
    guard endParts.count >= 2 else { return nil }

    var components = calendar.dateComponents([.year, .month, .day], from: shiftDate)
    components.hour = endParts[0]
    components.minute = endParts[1]

    guard var end = calendar.date(from: components) else { return nil }
    if end <= start {
      end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
    }
    return end
  }

  func formattedDate(for shift: WatchShiftDTO) -> String {
    guard let date = parseDate(shift.shiftDate) else { return shift.shiftDate }

    let formatter = DateFormatter()
    formatter.locale = formatterLocale
    formatter.dateFormat = "EEE d MMM"
    return formatter.string(from: date)
  }

  func parseDate(_ dateString: String) -> Date? {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.date(from: dateString)
  }

  private var formatterLocale: Locale {
    let identifier =
      Bundle.main.preferredLocalizations.first ?? Locale.autoupdatingCurrent.identifier
    return Locale(identifier: identifier)
  }

  private func compare(_ lhs: WatchShiftDTO, _ rhs: WatchShiftDTO) -> ComparisonResult {
    let now = Date()
    let lhsStatus = effectiveStatus(for: lhs, now: now)
    let rhsStatus = effectiveStatus(for: rhs, now: now)

    if priority(for: lhsStatus) != priority(for: rhsStatus) {
      return priority(for: lhsStatus) < priority(for: rhsStatus)
        ? .orderedAscending : .orderedDescending
    }

    let lhsDate = lhsStatus == .past ? endDate(for: lhs) : startDate(for: lhs)
    let rhsDate = rhsStatus == .past ? endDate(for: rhs) : startDate(for: rhs)

    switch (lhsDate, rhsDate) {
    case (.some(let lhsDate), .some(let rhsDate)):
      if lhsDate == rhsDate {
        return lhs.personName.localizedStandardCompare(rhs.personName)
      }
      if lhsStatus == .past {
        return lhsDate > rhsDate ? .orderedAscending : .orderedDescending
      }
      return lhsDate < rhsDate ? .orderedAscending : .orderedDescending

    case (.some, .none):
      return .orderedAscending

    case (.none, .some):
      return .orderedDescending

    case (.none, .none):
      return lhs.personName.localizedStandardCompare(rhs.personName)
    }
  }

  private func priority(for status: ShiftPreviewStatus) -> Int {
    switch status {
    case .active:
      return 0

    case .upcoming:
      return 1

    case .past:
      return 2
    }
  }
}
