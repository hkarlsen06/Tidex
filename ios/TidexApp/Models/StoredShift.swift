/// Represents a shift stored in shared UserDefaults for background task access
/// Used by AppDelegate to check for ongoing shifts and start Live Activities
/// Also used by ShiftHomeWidget to display the next shift
struct StoredShift: Codable, Equatable {
  let shiftId: String
  let shiftDate: String  // YYYY-MM-DD
  let startTime: String  // HH:mm
  let endTime: String  // HH:mm
  let hourlyWage: Double
  let supplementRatePerHour: Double
  let totalGrossEstimate: Double
  let currencySymbol: String?  // e.g., "kr", "$", "€"
  let taxRate: Double?  // User's tax rate (0.0-1.0)
}
