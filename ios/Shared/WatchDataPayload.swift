// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_acl explicit_top_level_acl explicit_type_interface
import Foundation

/// Complete data payload sent from iOS to Watch
struct WatchDataPayload: Codable, Sendable {
  let timestamp: Date
  let lastSyncTimestamp: Date?
  let userShift: WatchShiftDTO?
  let friendShifts: [WatchShiftDTO]
  let currencySymbol: String

  /// Human-readable "Updated X ago" for Watch display
  var updatedAgoText: String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter.localizedString(for: timestamp, relativeTo: Date())
  }
}
