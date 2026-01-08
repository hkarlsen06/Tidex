import Foundation

/// Represents a shift stored in shared UserDefaults for background task access
/// Used by AppDelegate to check for ongoing shifts and start Live Activities
struct StoredShift: Codable {
    let shiftId: String
    let shiftDate: String           // YYYY-MM-DD
    let startTime: String           // HH:mm
    let endTime: String             // HH:mm
    let hourlyWage: Double
    let supplementRatePerHour: Double
    let totalGrossEstimate: Double
    let locale: String
}
