import Foundation
import SwiftUI
import Supabase
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "DashboardViewModel")

// MARK: - Dashboard Data

/// Computed dashboard data ready for display
struct DashboardData: Equatable {
    // Payroll Card (Previous Month)
    let payrollDate: Date
    let payrollHasPassed: Bool         // true = previous payout, false = next payout
    let previousMonthGross: Double
    let previousMonthNet: Double?      // nil if tax not enabled
    let previousMonthTax: Double?
    let previousMonthTaxEnabled: Bool

    // Total Card (Current Month)
    let currentMonthGross: Double      // All shifts (projected total)
    let currentMonthNet: Double?       // All shifts net (projected)
    let currentMonthCompletedGross: Double  // Only completed shifts (earned to date)
    let currentMonthCompletedNet: Double?   // Only completed shifts net
    let currentMonthShiftCount: Int    // Total shift count
    let currentMonthCompletedCount: Int     // Completed shifts count
    let currentMonthPlannedCount: Int  // Future shifts
    let percentageChangeVsPrevious: Double?
    let currentMonthTaxEnabled: Bool

    // Featured Shift Card
    // For current month: next upcoming shift (or nil if none)
    // For other months: best shift (highest earnings) in that month
    let featuredShift: ShiftWithComputations?
    let isFeaturedShiftToday: Bool
    let featuredShiftIsBestShift: Bool  // true = showing best shift, false = showing next shift

    // Metadata
    let currentMonthName: String
    let previousMonthName: String

    /// Whether there are future shifts (main display should be projected total)
    var hasFutureShifts: Bool {
        currentMonthPlannedCount > 0
    }
}

// MARK: - Dashboard Error

enum DashboardError: Error, LocalizedError {
    case notAuthenticated
    case dataLoadFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .dataLoadFailed(let error):
            return "Failed to load data: \(error.localizedDescription)"
        }
    }
}

// MARK: - Month Cache Entry

/// Cache entry for a single month's computed shifts
private struct MonthCacheEntry {
    let year: Int
    let month: Int
    let shifts: [ShiftWithComputations]
    let timestamp: Date

    var key: String { "\(year)-\(month)" }

    /// Check if cache entry is still valid (within 5 minutes)
    var isValid: Bool {
        Date().timeIntervalSince(timestamp) < 300 // 5 minutes
    }
}

// MARK: - Dashboard View Model

@MainActor
final class DashboardViewModel: ObservableObject, MonthNavigable {

    // MARK: - Dependencies

    private let shiftsService: ShiftsService
    private let settingsService: SettingsService
    private let snapshotsService: SnapshotsService

    // MARK: - Published State

    @Published private(set) var dashboardData: DashboardData?
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    /// Currently displayed year (may differ from current month when navigating)
    @Published private(set) var displayYear: Int
    /// Currently displayed month 1-12 (may differ from current month when navigating)
    @Published private(set) var displayMonth: Int
    /// Direction of last navigation (for animations)
    @Published private(set) var navigationDirection: MonthNavigationDirection?
    /// Whether viewing the current (real) month
    var isCurrentMonth: Bool {
        let current = Date.currentYearMonth()
        return displayYear == current.year && displayMonth == current.month
    }

    /// Computed month name for immediate display (doesn't wait for API)
    var displayMonthName: String {
        var components = DateComponents()
        components.year = displayYear
        components.month = displayMonth
        components.day = 1
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components) else { return "" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        formatter.locale = Locale(identifier: LocalizationManager.shared.currentLocale.localeIdentifier)
        return formatter.string(from: date)
    }

    // MARK: - Private State

    private var displayedMonthShifts: [ShiftWithComputations] = []
    private var previousMonthShifts: [ShiftWithComputations] = []
    private var settings: UserSettings?
    private var snapshots: [WageSnapshot] = []
    private var recurringShifts: [RecurringShiftRow] = []
    private var cachedUserId: String?

    // MARK: - Month Cache

    /// Cache of computed shifts by month key (e.g., "2025-1")
    private var monthCache: [String: MonthCacheEntry] = [:]

    /// Background prefetch tasks (to avoid duplicate fetches)
    private var prefetchTasks: Set<String> = []

    // MARK: - Initialization

    init(
        shiftsService: ShiftsService? = nil,
        settingsService: SettingsService? = nil,
        snapshotsService: SnapshotsService? = nil
    ) {
        // Use provided services or default to shared instances
        // Using optional parameters avoids Swift 6 MainActor isolation errors
        self.shiftsService = shiftsService ?? ShiftsService.shared
        self.settingsService = settingsService ?? SettingsService.shared
        self.snapshotsService = snapshotsService ?? SnapshotsService.shared

        // Initialize to current month
        let current = Date.currentYearMonth()
        self.displayYear = current.year
        self.displayMonth = current.month
    }

    // MARK: - Month Navigation

    /// Navigate to the previous month
    func goToPreviousMonth() async {
        navigationDirection = .previous

        if displayMonth == 1 {
            displayMonth = 12
            displayYear -= 1
        } else {
            displayMonth -= 1
        }

        await loadDashboardForDisplayedMonthWithCache()

        // Prefetch the next month we might navigate to
        prefetchNeighboringMonths()
    }

    /// Navigate to the next month
    func goToNextMonth() async {
        navigationDirection = .next

        if displayMonth == 12 {
            displayMonth = 1
            displayYear += 1
        } else {
            displayMonth += 1
        }

        await loadDashboardForDisplayedMonthWithCache()

        // Prefetch the next month we might navigate to
        prefetchNeighboringMonths()
    }

    /// Reset to current month
    func goToCurrentMonth() async {
        let current = Date.currentYearMonth()

        // Determine navigation direction for animation
        let displayedMonthIndex = displayYear * 12 + displayMonth
        let currentMonthIndex = current.year * 12 + current.month

        // Always set a direction - if already on current month, use .next as default
        if displayedMonthIndex < currentMonthIndex {
            navigationDirection = .next
        } else if displayedMonthIndex > currentMonthIndex {
            navigationDirection = .previous
        } else {
            // Already on current month - no navigation needed
            return
        }

        displayYear = current.year
        displayMonth = current.month

        await loadDashboardForDisplayedMonthWithCache()
    }

    // MARK: - Public Methods

    /// Load all dashboard data for current month (initial load)
    /// Also prefetches neighboring months for instant navigation
    func loadDashboard() async {
        // Reset to current month on initial load
        let current = Date.currentYearMonth()
        displayYear = current.year
        displayMonth = current.month
        navigationDirection = nil

        // Clear cache on full reload
        monthCache.removeAll()
        prefetchTasks.removeAll()

        await loadDashboardForDisplayedMonth()

        // Prefetch neighboring months in the background
        prefetchNeighboringMonths()
    }

    /// Refresh dashboard data with full cache invalidation
    /// Called by pull-to-refresh - preserves existing data until fetch succeeds
    func refresh() async {
        logger.info("🔄 Pull-to-refresh: refreshing data")

        // Store current data as fallback in case of failure
        let previousSettings = settings
        let previousSnapshots = snapshots
        let previousRecurringShifts = recurringShifts
        let previousDashboardData = dashboardData

        // Clear caches to force fresh fetch
        monthCache.removeAll()
        prefetchTasks.removeAll()

        // Mark settings as needing refresh (but keep values until success)
        let needsSettingsRefresh = true

        do {
            // Get or cache user ID
            if cachedUserId == nil {
                guard let userId = try await getCurrentUserId() else {
                    throw DashboardError.notAuthenticated
                }
                cachedUserId = userId
            }

            guard let userId = cachedUserId else {
                throw DashboardError.notAuthenticated
            }

            // Fetch fresh settings and snapshots
            if needsSettingsRefresh {
                let fetchedSettings = try await settingsService.fetchSettings(for: userId)
                let fetchedSnapshots = try await snapshotsService.fetchSnapshots(for: userId)
                self.settings = fetchedSettings
                self.snapshots = fetchedSnapshots
            }

            // Calculate date ranges for displayed month
            let displayYM = (year: displayYear, month: displayMonth)
            let previousYM = Date.previousYearMonth(from: displayYM)

            let displayStartDate = Date.firstDayOfMonth(year: displayYM.year, month: displayYM.month)
            let displayEndDate = Date.lastDayOfMonth(year: displayYM.year, month: displayYM.month)
            let previousStartDate = Date.firstDayOfMonth(year: previousYM.year, month: previousYM.month)
            let previousEndDate = Date.lastDayOfMonth(year: previousYM.year, month: previousYM.month)

            // Fetch shifts for displayed month
            let displayShiftsData = try await shiftsService.fetchAllShifts(
                for: userId,
                startDate: displayStartDate,
                endDate: displayEndDate
            )

            // Store recurring shifts
            self.recurringShifts = displayShiftsData.recurring

            // Fetch shifts for previous month (for comparison)
            let fetchedPreviousShifts = try await shiftsService.fetchShifts(
                for: userId,
                startDate: previousStartDate,
                endDate: previousEndDate
            )

            // Compute displayed month shifts with payroll using PayrollEngine
            self.displayedMonthShifts = PayrollEngine.computeShiftsForMonth(
                year: displayYM.year,
                month: displayYM.month,
                shifts: displayShiftsData.shifts,
                recurring: recurringShifts,
                snapshots: snapshots,
                settings: settings!
            )

            // Compute previous month shifts with payroll using PayrollEngine
            self.previousMonthShifts = PayrollEngine.computeShiftsForMonth(
                year: previousYM.year,
                month: previousYM.month,
                shifts: fetchedPreviousShifts,
                recurring: recurringShifts,
                snapshots: snapshots,
                settings: settings!
            )

            // Cache the computed results
            let displayKey = "\(displayYM.year)-\(displayYM.month)"
            let previousKey = "\(previousYM.year)-\(previousYM.month)"
            monthCache[displayKey] = MonthCacheEntry(
                year: displayYM.year,
                month: displayYM.month,
                shifts: displayedMonthShifts,
                timestamp: Date()
            )
            monthCache[previousKey] = MonthCacheEntry(
                year: previousYM.year,
                month: previousYM.month,
                shifts: previousMonthShifts,
                timestamp: Date()
            )

            // Build dashboard data - success!
            self.dashboardData = buildDashboardData()
            self.error = nil

            // Prefetch neighboring months in the background
            prefetchNeighboringMonths()

            logger.info("✅ Pull-to-refresh complete")

        } catch {
            logger.error("❌ Pull-to-refresh failed: \(error.localizedDescription)")

            // Restore previous data so UI doesn't break
            self.settings = previousSettings
            self.snapshots = previousSnapshots
            self.recurringShifts = previousRecurringShifts
            self.dashboardData = previousDashboardData

            // Don't show error state - just log it and keep showing previous data
            // The user can try again, but they'll still see their data
            logger.info("📦 Restored previous data after refresh failure")
        }
    }

    /// Load dashboard data for the currently displayed month
    private func loadDashboardForDisplayedMonth() async {
        isLoading = true
        error = nil

        do {
            // Get or cache user ID
            if cachedUserId == nil {
                guard let userId = try await getCurrentUserId() else {
                    throw DashboardError.notAuthenticated
                }
                cachedUserId = userId
            }

            guard let userId = cachedUserId else {
                throw DashboardError.notAuthenticated
            }

            // Fetch settings and snapshots if not cached
            if settings == nil || snapshots.isEmpty {
                let fetchedSettings = try await settingsService.fetchSettings(for: userId)
                let fetchedSnapshots = try await snapshotsService.fetchSnapshots(for: userId)
                self.settings = fetchedSettings
                self.snapshots = fetchedSnapshots
            }

            // Calculate date ranges for displayed month
            let displayYM = (year: displayYear, month: displayMonth)
            let previousYM = Date.previousYearMonth(from: displayYM)

            let displayStartDate = Date.firstDayOfMonth(year: displayYM.year, month: displayYM.month)
            let displayEndDate = Date.lastDayOfMonth(year: displayYM.year, month: displayYM.month)
            let previousStartDate = Date.firstDayOfMonth(year: previousYM.year, month: previousYM.month)
            let previousEndDate = Date.lastDayOfMonth(year: previousYM.year, month: previousYM.month)

            // Fetch shifts for displayed month
            let displayShiftsData = try await shiftsService.fetchAllShifts(
                for: userId,
                startDate: displayStartDate,
                endDate: displayEndDate
            )

            // Store recurring shifts
            self.recurringShifts = displayShiftsData.recurring

            // Fetch shifts for previous month (for comparison)
            let fetchedPreviousShifts = try await shiftsService.fetchShifts(
                for: userId,
                startDate: previousStartDate,
                endDate: previousEndDate
            )

            // Compute displayed month shifts with payroll using PayrollEngine
            self.displayedMonthShifts = PayrollEngine.computeShiftsForMonth(
                year: displayYM.year,
                month: displayYM.month,
                shifts: displayShiftsData.shifts,
                recurring: recurringShifts,
                snapshots: snapshots,
                settings: settings!
            )

            // Compute previous month shifts with payroll using PayrollEngine
            self.previousMonthShifts = PayrollEngine.computeShiftsForMonth(
                year: previousYM.year,
                month: previousYM.month,
                shifts: fetchedPreviousShifts,
                recurring: recurringShifts,
                snapshots: snapshots,
                settings: settings!
            )

            // Cache the computed results
            let displayKey = "\(displayYM.year)-\(displayYM.month)"
            let previousKey = "\(previousYM.year)-\(previousYM.month)"
            monthCache[displayKey] = MonthCacheEntry(
                year: displayYM.year,
                month: displayYM.month,
                shifts: displayedMonthShifts,
                timestamp: Date()
            )
            monthCache[previousKey] = MonthCacheEntry(
                year: previousYM.year,
                month: previousYM.month,
                shifts: previousMonthShifts,
                timestamp: Date()
            )

            // Build dashboard data
            self.dashboardData = buildDashboardData()

        } catch {
            logger.error("❌ Dashboard load failed: \(error.localizedDescription)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    logger.error("   DecodingError.keyNotFound: key '\(key.stringValue)' not found, path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .typeMismatch(let type, let context):
                    logger.error("   DecodingError.typeMismatch: expected \(type), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .valueNotFound(let type, let context):
                    logger.error("   DecodingError.valueNotFound: expected \(type), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                case .dataCorrupted(let context):
                    logger.error("   DecodingError.dataCorrupted: \(context.debugDescription), path: \(context.codingPath.map { $0.stringValue }.joined(separator: "."))")
                @unknown default:
                    logger.error("   DecodingError: unknown")
                }
            }
            self.error = DashboardError.dataLoadFailed(underlying: error)
        }

        isLoading = false
    }

    /// Load dashboard data using cache when available
    /// Falls back to full fetch if cache miss or expired
    private func loadDashboardForDisplayedMonthWithCache() async {
        let displayKey = "\(displayYear)-\(displayMonth)"
        let previousYM = Date.previousYearMonth(from: (year: displayYear, month: displayMonth))
        let previousKey = "\(previousYM.year)-\(previousYM.month)"

        // Check if we have valid cache for both displayed and previous months
        if let displayCache = monthCache[displayKey], displayCache.isValid,
           let previousCache = monthCache[previousKey], previousCache.isValid {
            // Use cached data - instant navigation!
            logger.info("📦 Using cached data for \(displayKey)")
            self.displayedMonthShifts = displayCache.shifts
            self.previousMonthShifts = previousCache.shifts
            self.dashboardData = buildDashboardData()
            return
        }

        // Cache miss - do full fetch
        logger.info("🔄 Cache miss for \(displayKey), fetching...")
        await loadDashboardForDisplayedMonth()
    }

    /// Prefetch neighboring months in the background
    /// This enables instant navigation when the user swipes
    private func prefetchNeighboringMonths() {
        let displayYM = (year: displayYear, month: displayMonth)

        // Calculate previous and next months
        let previousYM = Date.previousYearMonth(from: displayYM)
        let nextYM = nextYearMonth(from: displayYM)

        // Also get the months needed for the payroll card of each neighbor
        let prevPrevYM = Date.previousYearMonth(from: previousYM)
        let nextPrevYM = Date.previousYearMonth(from: nextYM)

        // Prefetch all needed months
        prefetchMonthInBackground(year: previousYM.year, month: previousYM.month)
        prefetchMonthInBackground(year: nextYM.year, month: nextYM.month)
        prefetchMonthInBackground(year: prevPrevYM.year, month: prevPrevYM.month)
        prefetchMonthInBackground(year: nextPrevYM.year, month: nextPrevYM.month)
    }

    /// Prefetch a single month's data in the background
    private func prefetchMonthInBackground(year: Int, month: Int) {
        let key = "\(year)-\(month)"

        // Skip if already cached and valid
        if let cached = monthCache[key], cached.isValid {
            return
        }

        // Skip if already prefetching
        if prefetchTasks.contains(key) {
            return
        }

        prefetchTasks.insert(key)

        Task {
            do {
                guard let userId = cachedUserId else { return }

                let startDate = Date.firstDayOfMonth(year: year, month: month)
                let endDate = Date.lastDayOfMonth(year: year, month: month)

                let fetchedShifts = try await shiftsService.fetchShifts(
                    for: userId,
                    startDate: startDate,
                    endDate: endDate
                )

                // Compute shifts with payroll
                guard let settings = self.settings else { return }
                let computedShifts = PayrollEngine.computeShiftsForMonth(
                    year: year,
                    month: month,
                    shifts: fetchedShifts,
                    recurring: recurringShifts,
                    snapshots: snapshots,
                    settings: settings
                )

                // Store in cache
                let entry = MonthCacheEntry(
                    year: year,
                    month: month,
                    shifts: computedShifts,
                    timestamp: Date()
                )
                await MainActor.run {
                    self.monthCache[key] = entry
                    self.prefetchTasks.remove(key)
                }

                logger.info("📦 Prefetched \(key) with \(computedShifts.count) shifts")
            } catch {
                logger.error("⚠️ Prefetch failed for \(key): \(error.localizedDescription)")
                await MainActor.run {
                    self.prefetchTasks.remove(key)
                }
            }
        }
    }

    /// Get next year/month (handles year rollover)
    private func nextYearMonth(from current: (year: Int, month: Int)) -> (year: Int, month: Int) {
        if current.month == 12 {
            return (year: current.year + 1, month: 1)
        }
        return (year: current.year, month: current.month + 1)
    }

    // MARK: - Private Methods

    /// Get current authenticated user ID
    private func getCurrentUserId() async throws -> String? {
        let session = try await supabase.auth.session
        return session.user.id.uuidString.lowercased()
    }

    /// Build the final dashboard data from computed shifts
    /// Uses PayrollEngine.summarizeShiftTotals for correct half-tax and conflict exclusion
    private func buildDashboardData() -> DashboardData {
        let today = todayISO()
        let now = Date()
        let payrollDay = settings?.effectivePayrollDay ?? 1
        let halfTaxMonth = settings?.half_tax_month
        let displayYM = (year: displayYear, month: displayMonth)
        let previousYM = Date.previousYearMonth(from: displayYM)

        // Calculate payroll date for displayed month
        let payrollDate = calculatePayrollDate(year: displayYM.year, month: displayYM.month, day: payrollDay)
        let payrollHasPassed = now > payrollDate

        // Previous month totals using PayrollEngine (for payroll card)
        // This correctly applies half-tax and conflict exclusion
        let prevTotals = PayrollEngine.summarizeShiftTotals(
            shifts: previousMonthShifts,
            halfTaxMonth: halfTaxMonth,
            earningsMonth: previousYM.month,
            now: now
        )
        let prevTaxEnabled = previousMonthShifts.first?.taxEnabled ?? false
        let prevTax: Double? = prevTaxEnabled ? prevTotals.gross - prevTotals.net : nil

        // Displayed month totals using PayrollEngine
        // This correctly applies half-tax and conflict exclusion
        let displayTotals = PayrollEngine.summarizeShiftTotals(
            shifts: displayedMonthShifts,
            halfTaxMonth: halfTaxMonth,
            earningsMonth: displayYM.month,
            now: now
        )
        let displayTaxEnabled = displayedMonthShifts.first?.taxEnabled ?? false

        // Count completed and planned shifts
        let completedShifts = displayedMonthShifts.filter { shift in
            Date.hasShiftEnded(
                shiftDate: shift.shiftDate,
                startTime: shift.startTime,
                endTime: shift.endTime,
                referenceDate: now
            )
        }
        let plannedShifts = displayedMonthShifts.filter { $0.shiftDate > today }

        // Percentage change vs previous month (comparing projected totals)
        let percentChange: Double? = prevTotals.gross > 0
            ? ((displayTotals.gross - prevTotals.gross) / prevTotals.gross) * 100
            : nil

        // Featured shift logic:
        // - Current month: show next upcoming shift
        // - Other months: show best shift (highest earnings)
        let current = Date.currentYearMonth()
        let isViewingCurrentMonth = displayYM.year == current.year && displayYM.month == current.month

        let featuredShift: ShiftWithComputations?
        let isFeaturedShiftToday: Bool
        let featuredShiftIsBestShift: Bool

        if isViewingCurrentMonth {
            // Current month: show next upcoming shift
            featuredShift = displayedMonthShifts.first { $0.shiftDate >= today }
            isFeaturedShiftToday = featuredShift?.shiftDate == today
            featuredShiftIsBestShift = false
        } else {
            // Non-current month: show best shift (highest earnings)
            featuredShift = findBestShift(in: displayedMonthShifts)
            isFeaturedShiftToday = false
            featuredShiftIsBestShift = true
        }

        // Month names for display
        let displayMonthName = monthName(year: displayYM.year, month: displayYM.month)
        let previousMonthName = monthName(year: previousYM.year, month: previousYM.month)

        return DashboardData(
            payrollDate: payrollDate,
            payrollHasPassed: payrollHasPassed,
            previousMonthGross: prevTotals.gross,
            previousMonthNet: prevTaxEnabled ? prevTotals.net : nil,
            previousMonthTax: prevTax,
            previousMonthTaxEnabled: prevTaxEnabled,
            currentMonthGross: displayTotals.gross,
            currentMonthNet: displayTaxEnabled ? displayTotals.net : nil,
            currentMonthCompletedGross: displayTotals.completedGross,
            currentMonthCompletedNet: displayTaxEnabled ? displayTotals.completedNet : nil,
            currentMonthShiftCount: displayedMonthShifts.count,
            currentMonthCompletedCount: completedShifts.count,
            currentMonthPlannedCount: plannedShifts.count,
            percentageChangeVsPrevious: percentChange,
            currentMonthTaxEnabled: displayTaxEnabled,
            featuredShift: featuredShift,
            isFeaturedShiftToday: isFeaturedShiftToday,
            featuredShiftIsBestShift: featuredShiftIsBestShift,
            currentMonthName: displayMonthName,
            previousMonthName: previousMonthName
        )
    }

    // MARK: - Helper Methods

    private func calculatePayrollDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = Date.osloTimeZone
        return Calendar(identifier: .gregorian).date(from: components) ?? Date()
    }

    private func monthName(year: Int, month: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components) else { return "" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        formatter.locale = Locale(identifier: LocalizationManager.shared.currentLocale.localeIdentifier)
        return formatter.string(from: date)
    }

    /// Find the best (highest earnings) shift in a collection
    /// Returns the first shift chronologically if multiple have the same max earnings
    private func findBestShift(in shifts: [ShiftWithComputations]) -> ShiftWithComputations? {
        guard !shifts.isEmpty else { return nil }

        // Find max gross earnings
        let maxGross = shifts.map { $0.grossPay }.max() ?? 0
        guard maxGross > 0 else { return shifts.first }

        // Get all shifts with max earnings, sorted chronologically
        let bestShifts = shifts
            .filter { $0.grossPay == maxGross }
            .sorted { $0.shiftDate < $1.shiftDate }

        return bestShifts.first
    }
}
