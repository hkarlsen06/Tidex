import ActivityKit
import Foundation

/// Attributes for the Shift Live Activity
/// Static data is set when the activity starts and cannot be changed.
/// Dynamic data (ContentState) can be updated during the activity lifecycle.
///
/// NOTE: This file must be included in BOTH the main App target AND the TidexShiftWidget target.
/// If you modify this file, ensure the widget extension has access to the same definition.
public struct ShiftActivityAttributes: ActivityAttributes, Sendable {
    /// Dynamic content that updates during the activity
    /// Note: With the new auto-updating UI, these values are only used as initial/fallback values.
    /// The UI calculates real-time values from the static attributes (startDate, endDate, totalGrossEstimate).
    public struct ContentState: Codable, Hashable {
        /// Current accumulated earnings in NOK (initial/fallback value)
        public var currentEarnings: Double
        /// Minutes remaining until shift ends (initial/fallback value)
        public var remainingMinutes: Int
        /// Shift completion percentage 0-100 (initial/fallback value)
        public var progressPercent: Double

        public init(currentEarnings: Double, remainingMinutes: Int, progressPercent: Double) {
            self.currentEarnings = currentEarnings
            self.remainingMinutes = remainingMinutes
            self.progressPercent = progressPercent
        }
    }

    // MARK: - Static Attributes (set at activity start)

    /// Unique shift identifier
    public let shiftId: String
    /// Shift date in ISO format (YYYY-MM-DD)
    public let shiftDate: String
    /// Shift start time (HH:mm)
    public let startTime: String
    /// Shift end time (HH:mm)
    public let endTime: String
    /// Hourly wage in NOK
    public let hourlyWage: Double
    /// Average supplement rate per hour in NOK
    public let supplementRatePerHour: Double
    /// Total expected gross earnings for the full shift
    public let totalGrossEstimate: Double
    /// User's locale ("no" or "en")
    public let locale: String
    /// Currency symbol to display (e.g., "kr", "$", "€")
    public let currencySymbol: String?

    // MARK: - Date Attributes for Real-Time Updates

    /// Shift start date/time (for SwiftUI timer countdown)
    public let startDate: Date
    /// Shift end date/time (for SwiftUI timer countdown)
    public let endDate: Date

    public init(
        shiftId: String,
        shiftDate: String,
        startTime: String,
        endTime: String,
        hourlyWage: Double,
        supplementRatePerHour: Double,
        totalGrossEstimate: Double,
        locale: String,
        currencySymbol: String? = "kr",
        startDate: Date,
        endDate: Date
    ) {
        self.shiftId = shiftId
        self.shiftDate = shiftDate
        self.startTime = startTime
        self.endTime = endTime
        self.hourlyWage = hourlyWage
        self.supplementRatePerHour = supplementRatePerHour
        self.totalGrossEstimate = totalGrossEstimate
        self.locale = locale
        self.currencySymbol = currencySymbol
        self.startDate = startDate
        self.endDate = endDate
    }
}
