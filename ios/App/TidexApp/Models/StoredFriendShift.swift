import Foundation

/// A friend's shift stored in App Group UserDefaults for widget consumption.
/// Contains the "best" shift (active > upcoming > past) for each friend.
struct StoredFriendShift: Codable {
    /// ID of the friend who owns this shift
    let sharerId: String

    /// The shift ID
    let shiftId: String

    /// Shift date in YYYY-MM-DD format
    let shiftDate: String

    /// Start time in HH:mm format
    let startTime: String

    /// End time in HH:mm format
    let endTime: String

    /// Gross earnings for the shift
    let gross: Double

    /// User's locale ("no" or "en")
    let locale: String

    /// Currency symbol (e.g., "kr", "$", "€")
    let currencySymbol: String?

    /// Whether the viewer can see earnings
    let showEarnings: Bool

    /// Shift status: "active", "upcoming", or "past"
    let status: String
}

// MARK: - Factory from SharerShiftPreview

extension StoredFriendShift {
    /// Create from a SharerShiftPreview
    /// - Parameters:
    ///   - preview: The shift preview from the API
    ///   - locale: The user's locale
    ///   - currencySymbol: The user's currency symbol
    /// - Returns: A StoredFriendShift, or nil if the preview has no shift
    static func from(
        preview: SharerShiftPreview,
        locale: String,
        currencySymbol: String?
    ) -> StoredFriendShift? {
        guard let shift = preview.shift else { return nil }

        return StoredFriendShift(
            sharerId: preview.sharerId,
            shiftId: shift.id,
            shiftDate: shift.shift_date,
            startTime: shift.start_time,
            endTime: shift.end_time,
            gross: shift.computed.gross,
            locale: locale,
            currencySymbol: currencySymbol,
            showEarnings: preview.showEarnings,
            status: preview.status?.rawValue ?? "upcoming"
        )
    }
}
