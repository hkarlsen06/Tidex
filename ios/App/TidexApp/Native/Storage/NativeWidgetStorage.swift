import Foundation
import SwiftData
import UIKit
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
    private static let currencyKey = "user_currency"

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
        // Currency is stored directly as symbol (e.g., "kr", "$", "€")
        let currencySymbol = settings?.currency ?? defaultCurrencySymbol

        // Store currency separately so widget can access it even when no shifts exist
        storeCurrency(currencySymbol)

        // Calculate date range: previous month through 90 days ahead
        let now = Date()
        let calendar = Calendar.current

        // First day of previous month - use Calendar.date(byAdding:) for safe month arithmetic
        // This correctly handles January -> December rollover without manual year/month math
        let firstDayOfCurrentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let firstDayOfPreviousMonth = calendar.date(byAdding: .month, value: -1, to: firstDayOfCurrentMonth) ?? now
        let startDate = firstDayOfPreviousMonth

        // 90 days from now
        let endDate = calendar.date(byAdding: .day, value: futureDaysWindow, to: now) ?? now

        // Fetch regular shifts in date range
        let regularShifts = shiftsRepository.getShifts(for: userId, startDate: startDate, endDate: endDate)

        // Fetch recurring shift patterns and generate virtual shifts
        let recurringRepository = RecurringShiftsRepository.shared
        let recurringPatterns = recurringRepository.getRecurringShifts(for: userId)

        // Generate virtual shifts for each month in the date range
        var virtualShifts: [ShiftRow] = []
        let monthsInRange = getMonthsInRange(startDate: startDate, endDate: endDate)

        for (year, month) in monthsInRange {
            for recurring in recurringPatterns {
                let generated = RecurringShiftGenerator.generateVirtualShiftsForMonth(
                    year: year,
                    month: month,
                    recurring: recurring
                )

                for virtual in generated {
                    // Create virtual shift row
                    let virtualRow = ShiftRow(
                        id: "virtual-\(recurring.id)-\(virtual.date)",
                        user_id: recurring.user_id,
                        shift_date: virtual.date,
                        start_time: recurring.cleanStartTime,
                        end_time: recurring.cleanEndTime,
                        custom_supplements: recurring.date_specific_supplements?[virtual.date],
                        created_at: nil,
                        recurring_id: recurring.id,
                        recurring_anchor_weekday: virtual.weekday
                    )
                    virtualShifts.append(virtualRow)
                }
            }
        }

        // Combine regular and virtual shifts, removing duplicates
        // (A real shift on a date takes precedence over a virtual one)
        let regularDates = Set(regularShifts.map { $0.shift_date })
        let dedupedVirtualShifts = virtualShifts.filter { !regularDates.contains($0.shift_date) }
        let allShifts = regularShifts + dedupedVirtualShifts

        if allShifts.isEmpty {
            logger.info("No shifts to store for widget")
            clearWidgetStorage()
            return
        }

        // Sort all shifts by date for consistent ordering
        let shifts = allShifts.sorted { $0.shift_date < $1.shift_date }

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

        // Reschedule Live Activity background task for the next upcoming shift
        // This ensures the background task is always scheduled for the soonest shift
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.scheduleNextShiftLiveActivity()
            // Also check if there's an ongoing shift that needs a Live Activity right now
            // This handles the case where the app is opened during a shift and sync just completed
            appDelegate.checkAndStartLiveActivityIfNeeded()
        }

        // Schedule shift reminder notifications for upcoming shifts
        // Pass shifts directly to avoid race condition with UserDefaults write
        Task {
            await ShiftReminderScheduler.shared.scheduleAllReminders(for: userId, shifts: storedShifts)
        }

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

        // Cancel all scheduled shift reminders
        Task {
            await ShiftReminderScheduler.shared.cancelAllReminders()
        }

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

    private static func storeCurrency(_ currency: String) {
        guard let userDefaults = sharedUserDefaults() else {
            logger.warning("Unable to access App Group UserDefaults for currency")
            return
        }
        userDefaults.set(currency, forKey: currencyKey)
        logger.debug("Stored user currency: \(currency)")
    }

    private static func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
        logger.debug("Widget timelines reloaded")
    }

    /// Get all (year, month) tuples in the date range
    /// - Parameters:
    ///   - startDate: Start of range
    ///   - endDate: End of range
    /// - Returns: Array of (year, month) tuples
    private static func getMonthsInRange(startDate: Date, endDate: Date) -> [(Int, Int)] {
        var months: [(Int, Int)] = []
        let calendar = Calendar.current

        var current = calendar.date(from: calendar.dateComponents([.year, .month], from: startDate)) ?? startDate
        let endMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: endDate)) ?? endDate

        while current <= endMonth {
            let year = calendar.component(.year, from: current)
            let month = calendar.component(.month, from: current)
            months.append((year, month))
            current = calendar.date(byAdding: .month, value: 1, to: current) ?? current
        }

        return months
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
}
