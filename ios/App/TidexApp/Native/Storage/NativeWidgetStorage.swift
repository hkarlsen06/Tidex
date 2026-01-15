import Foundation
import SwiftData
import WidgetKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "NativeWidgetStorage")

// MARK: - Native Widget Storage

/// Writes shift data from SwiftData local storage to App Group UserDefaults
/// for widget consumption. This is the native-side equivalent of the WebView's
/// widget-storage.ts that writes via Capacitor.
///
/// Triggered after:
/// - Successful sync (SyncCoordinator)
/// - Local shift changes (ShiftsRepository)
@MainActor
enum NativeWidgetStorage {
    private static let appGroupId = "group.no.tidex.app"
    private static let shiftsKey = "upcoming_shifts"

    /// Default currency symbol if settings don't specify one
    private static let defaultCurrencySymbol = "kr"

    /// Storage window: previous month through 90 days ahead
    private static let futureDaysWindow = 90

    // MARK: - Public API

    /// Update widget storage with current local shift data
    /// - Parameter userId: User ID to fetch shifts for
    @MainActor
    static func updateWidgetStorage(for userId: String) {
        logger.info("Updating widget storage for user \(userId.prefix(8))...")

        // Get repositories
        let shiftsRepository = ShiftsRepository.shared
        let snapshotsRepository = SnapshotsRepository.shared
        let settingsRepository = SettingsRepository.shared

        // Get settings for currency, locale comes from iOS system settings
        let settings = settingsRepository.getSettings(for: userId)
        let locale = getAppLocale()
        let currencySymbol = settings?.effectiveCurrencySymbol ?? defaultCurrencySymbol

        // Calculate date range: previous month through 90 days ahead
        let now = Date()
        let calendar = Calendar.current

        // First day of previous month
        var components = calendar.dateComponents([.year, .month], from: now)
        components.month = (components.month ?? 1) - 1
        if components.month! < 1 {
            components.month = 12
            components.year = (components.year ?? 2024) - 1
        }
        components.day = 1
        let startDate = calendar.date(from: components) ?? now

        // 90 days from now
        let endDate = calendar.date(byAdding: .day, value: futureDaysWindow, to: now) ?? now

        // Fetch shifts in date range
        let shifts = shiftsRepository.getShifts(for: userId, startDate: startDate, endDate: endDate)

        if shifts.isEmpty {
            logger.info("No shifts to store for widget")
            clearWidgetStorage()
            return
        }

        // Get snapshots for computing wages
        let snapshots = snapshotsRepository.getSnapshots(for: userId)

        // Convert to StoredShift format with computed wages
        let storedShifts = shifts.compactMap { shift -> StoredShift? in
            // Find applicable snapshot for this shift date
            let snapshot = SnapshotsService.snapshotForDate(shift.shift_date, from: snapshots)

            // Compute payroll for the shift
            let computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)

            // Calculate weighted average supplement rate
            let supplementRate = calculateAverageSupplementRate(periods: computed.wagePeriods)

            // Calculate hourly wage from base pay
            let hourlyWage = computed.paidHours > 0
                ? computed.basePay / computed.paidHours
                : (snapshot?.hourly_wage ?? 0)

            // Get tax rate from snapshot
            let taxRate: Double?
            if let snap = snapshot, snap.tax_enabled == true {
                taxRate = (snap.tax_percentage ?? 0) / 100.0
            } else {
                taxRate = nil
            }

            return StoredShift(
                shiftId: shift.id,
                shiftDate: shift.shift_date,
                startTime: shift.start_time,
                endTime: shift.end_time,
                hourlyWage: hourlyWage,
                supplementRatePerHour: supplementRate,
                totalGrossEstimate: computed.gross,
                locale: locale,
                currencySymbol: currencySymbol,
                taxRate: taxRate
            )
        }

        // Write to App Group UserDefaults
        writeShiftsToAppGroup(storedShifts)

        // Trigger widget reload
        reloadWidgetTimelines()

        logger.info("Widget storage updated with \(storedShifts.count) shifts")
    }

    /// Clear widget storage (e.g., on logout)
    static func clearWidgetStorage() {
        guard let userDefaults = sharedUserDefaults() else {
            logger.warning("Unable to access App Group UserDefaults")
            return
        }

        userDefaults.removeObject(forKey: shiftsKey)
        reloadWidgetTimelines()

        logger.info("Widget storage cleared")
    }

    // MARK: - Private Helpers

    private static func sharedUserDefaults() -> UserDefaults? {
        guard FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) != nil else {
            logger.error("App Group container not available: \(appGroupId)")
            return nil
        }
        return UserDefaults(suiteName: appGroupId)
    }

    private static func writeShiftsToAppGroup(_ shifts: [StoredShift]) {
        guard let userDefaults = sharedUserDefaults() else {
            logger.warning("Unable to access App Group UserDefaults")
            return
        }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(shifts)
            let jsonString = String(data: data, encoding: .utf8)
            userDefaults.set(jsonString, forKey: shiftsKey)
            logger.debug("Wrote \(shifts.count) shifts to App Group")
        } catch {
            logger.error("Failed to encode shifts for widget: \(error.localizedDescription)")
        }
    }

    private static func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
        logger.debug("Widget timelines reloaded")
    }

    /// Calculate weighted average supplement rate from wage periods
    /// - Parameter periods: Array of wage periods
    /// - Returns: Weighted average supplement rate
    private static func calculateAverageSupplementRate(periods: [WagePeriod]) -> Double {
        guard !periods.isEmpty else { return 0 }

        var totalWeightedSupplement: Double = 0
        var totalMinutes: Double = 0

        for period in periods {
            totalWeightedSupplement += period.supplementRate * period.durationMinutes
            totalMinutes += period.durationMinutes
        }

        return totalMinutes > 0 ? totalWeightedSupplement / totalMinutes : 0
    }
}

// MARK: - App Locale Helper

/// Get the app's effective locale from iOS system settings
/// Uses Bundle.main.preferredLocalizations which respects the user's
/// per-app language setting in iOS Settings
private func getAppLocale() -> String {
    // preferredLocalizations returns the app's localizations ordered by user preference
    // The first item is the best match for the user's language settings
    if let preferred = Bundle.main.preferredLocalizations.first {
        // Map language codes to our widget locale format
        if preferred.hasPrefix("nb") || preferred.hasPrefix("no") || preferred.hasPrefix("nn") {
            return "no"
        }
    }
    return "en"
}

// MARK: - UserSettings Extensions

extension UserSettings {
    /// Effective locale for widget storage
    /// Uses iOS's preferred language for this app (from system settings)
    var effectiveLocale: String {
        return getAppLocale()
    }

    /// Effective currency symbol for widget storage
    var effectiveCurrencySymbol: String {
        // Map currency codes to symbols
        guard let currency = self.currency else {
            return "kr"
        }

        switch currency.uppercased() {
        case "NOK": return "kr"
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "SEK": return "kr"
        case "DKK": return "kr"
        default: return currency
        }
    }
}
