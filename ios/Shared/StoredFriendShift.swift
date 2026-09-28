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

  /// Currency symbol (e.g., "kr", "$", "€")
  let currencySymbol: String?

  /// Whether the viewer can see earnings
  let showEarnings: Bool

  /// Shift status: "active", "upcoming", or "past"
  let status: String
}
