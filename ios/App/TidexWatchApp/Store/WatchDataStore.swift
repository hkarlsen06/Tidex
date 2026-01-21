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

    private(set) var userShift: WatchShiftDTO?
    private(set) var friendShifts: [WatchShiftDTO] = []
    private(set) var locale: String = "no"
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

    private init() {}

    /// Update store with new payload from iPhone
    func update(from payload: WatchDataPayload) {
        self.userShift = payload.userShift
        self.friendShifts = payload.friendShifts
        self.locale = payload.locale
        self.currencySymbol = payload.currencySymbol
        self.lastUpdated = payload.timestamp
        self.lastSyncTimestamp = payload.lastSyncTimestamp

        logger.info("Store updated: user=\(payload.userShift != nil), friends=\(payload.friendShifts.count)")

        // Reload complications when data changes
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Localization Helpers

    /// Localized string for "Shifts" title
    var shiftsTitle: String {
        locale == "no" ? "Vakter" : "Shifts"
    }

    /// Localized string for "My Shift" section
    var myShiftTitle: String {
        locale == "no" ? "Min vakt" : "My Shift"
    }

    /// Localized string for "Friends" section
    var friendsTitle: String {
        locale == "no" ? "Venner" : "Friends"
    }

    /// Localized string for "No Shifts"
    var noShiftsTitle: String {
        locale == "no" ? "Ingen vakter" : "No Shifts"
    }

    /// Localized string for sync instruction
    var syncInstructionText: String {
        locale == "no"
            ? "Åpne Tidex på iPhone for å synkronisere"
            : "Open Tidex on iPhone to sync"
    }

    /// Localized string for "Refresh" button
    var refreshButtonTitle: String {
        locale == "no" ? "Oppdater" : "Refresh"
    }

    /// Localized string for "Next Shift"
    var nextShiftTitle: String {
        locale == "no" ? "Neste vakt" : "Next Shift"
    }

    /// Localized string for "Shift"
    var shiftTitle: String {
        locale == "no" ? "Vakt" : "Shift"
    }
}
