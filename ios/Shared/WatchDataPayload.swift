import Foundation

/// Complete data payload sent from iOS to Watch
struct WatchDataPayload: Codable, Sendable {
    let timestamp: Date
    let lastSyncTimestamp: Date?
    let userShift: WatchShiftDTO?
    let friendShifts: [WatchShiftDTO]
    let locale: String
    let currencySymbol: String

    /// Human-readable "Updated X ago" for Watch display
    var updatedAgoText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}
