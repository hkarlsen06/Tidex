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
    case noLocalData

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .dataLoadFailed(let error):
            return "Failed to load data: \(error.localizedDescription)"
        case .noLocalData:
            return "No local data available. Please wait for sync to complete."
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

    // MARK: - Dependencies (Local-First Repositories)

    private let shiftsRepository: ShiftsRepository
    private let settingsRepository: SettingsRepository
    private let snapshotsRepository: SnapshotsRepository
    private let recurringShiftsRepository: RecurringShiftsRepository
    private let syncCoordinator: SyncCoordinator

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

    // MARK: - User Profile Data (for UserMenuButton)

    /// User's display name (derived from email or metadata)
    @Published private(set) var userDisplayName: String = ""
    /// User's profile picture URL
    @Published private(set) var userAvatarUrl: String?

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
        shiftsRepository: ShiftsRepository? = nil,
        settingsRepository: SettingsRepository? = nil,
        snapshotsRepository: SnapshotsRepository? = nil,
        recurringShiftsRepository: RecurringShiftsRepository? = nil,
        syncCoordinator: SyncCoordinator? = nil
    ) {
        // Use provided repositories or default to shared instances
        // Using optional parameters avoids Swift 6 MainActor isolation errors
        self.shiftsRepository = shiftsRepository ?? ShiftsRepository.shared
        self.settingsRepository = settingsRepository ?? SettingsRepository.shared
        self.snapshotsRepository = snapshotsRepository ?? SnapshotsRepository.shared
        self.recurringShiftsRepository = recurringShiftsRepository ?? RecurringShiftsRepository.shared
        self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared

        // Initialize to current month
        let current = Date.currentYearMonth()
        self.displayYear = current.year
        self.displayMonth = current.month
    }

    // MARK: - Month Navigation

    /// Track active navigation task to cancel stale fetches
    private var activeNavigationTask: Task<Void, Never>?

    /// Navigate to the previous month (non-blocking)
    func goToPreviousMonth() {
        navigationDirection = .previous

        if displayMonth == 1 {
            displayMonth = 12
            displayYear -= 1
        } else {
            displayMonth -= 1
        }

        loadDashboardForDisplayedMonthNonBlocking()
    }

    /// Navigate to the next month (non-blocking)
    func goToNextMonth() {
        navigationDirection = .next

        if displayMonth == 12 {
            displayMonth = 1
            displayYear += 1
        } else {
            displayMonth += 1
        }

        loadDashboardForDisplayedMonthNonBlocking()
    }

    /// Reset to current month (non-blocking)
    func goToCurrentMonth() {
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

        loadDashboardForDisplayedMonthNonBlocking()
    }

    /// Non-blocking month data loader
    /// Uses cache for instant display, fetches in background if needed
    private func loadDashboardForDisplayedMonthNonBlocking() {
        let targetYear = displayYear
        let targetMonth = displayMonth
        let displayKey = "\(targetYear)-\(targetMonth)"
        let previousYM = Date.previousYearMonth(from: (year: targetYear, month: targetMonth))
        let previousKey = "\(previousYM.year)-\(previousYM.month)"

        // Check if we have valid cache for both displayed and previous months
        if let displayCache = monthCache[displayKey], displayCache.isValid,
           let previousCache = monthCache[previousKey], previousCache.isValid {
            // Use cached data - instant navigation!
            logger.info("📦 Using cached data for \(displayKey)")
            self.displayedMonthShifts = displayCache.shifts
            self.previousMonthShifts = previousCache.shifts
            self.dashboardData = buildDashboardData()

            // Still prefetch neighbors in background
            prefetchNeighboringMonths()
            return
        }

        // Cache miss - clear stale data and show loading state
        logger.info("🔄 Cache miss for \(displayKey), fetching in background...")

        // Clear dashboard data so we show loading state instead of stale data
        self.dashboardData = nil
        self.isLoading = true

        // Cancel any previous navigation task
        activeNavigationTask?.cancel()

        // Start background fetch
        activeNavigationTask = Task { [weak self] in
            guard let self = self else { return }

            // Check if this task is still relevant (user hasn't navigated away)
            guard !Task.isCancelled,
                  self.displayYear == targetYear,
                  self.displayMonth == targetMonth else {
                logger.info("⏭️ Skipping stale fetch for \(displayKey)")
                return
            }

            await self.loadDashboardForDisplayedMonth(showLoadingState: false)

            // Check again after fetch - user may have navigated during the async operation
            guard !Task.isCancelled,
                  self.displayYear == targetYear,
                  self.displayMonth == targetMonth else {
                logger.info("⏭️ Skipping prefetch - user navigated during fetch")
                return
            }

            // Prefetch neighbors after successful load
            self.prefetchNeighboringMonths()
        }
    }

    // MARK: - Public Methods

    /// Load all dashboard data for current month (initial load)
    /// Reads from local repositories only - sync is triggered by AppCoordinator
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

        await loadDashboardFromLocal()

        // Prefetch neighboring months in the background
        prefetchNeighboringMonths()
    }

    /// Refresh dashboard data via sync then local reload
    /// Called by pull-to-refresh - triggers network sync, then reloads from local
    func refresh() async {
        logger.info("🔄 Pull-to-refresh: triggering sync then local reload")

        // Store current data as fallback in case of failure
        let previousDashboardData = dashboardData

        do {
            // Get user ID
            if cachedUserId == nil {
                guard let userId = try await getCurrentUserId() else {
                    throw DashboardError.notAuthenticated
                }
                cachedUserId = userId
            }

            guard let userId = cachedUserId else {
                throw DashboardError.notAuthenticated
            }

            // Trigger sync to pull/push changes
            let syncResult = await syncCoordinator.sync(reason: .manualRefresh, userId: userId)

            if !syncResult.success, let errorMessage = syncResult.error {
                logger.warning("⚠️ Sync had issues: \(errorMessage)")
                // Continue anyway - we still want to show local data
            }

            // Clear in-memory caches so we pick up synced data
            monthCache.removeAll()
            prefetchTasks.removeAll()
            settings = nil  // Force reload from local
            snapshots = []
            recurringShifts = []

            // Reload from local repositories
            await loadDashboardFromLocal()

            // Prefetch neighboring months in the background
            prefetchNeighboringMonths()

            logger.info("✅ Pull-to-refresh complete (synced \(syncResult.totalRowsProcessed) rows)")

        } catch {
            logger.error("❌ Pull-to-refresh failed: \(error.localizedDescription)")

            // Restore previous data so UI doesn't break
            self.dashboardData = previousDashboardData

            // Don't show error state - just log it and keep showing previous data
            // The user can try again, but they'll still see their data
            logger.info("📦 Restored previous data after refresh failure")
        }
    }

    /// Load dashboard data from local repositories
    /// This is the core local-first read path - no network calls
    private func loadDashboardFromLocal() async {
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

            // Load settings from local store
            if settings == nil {
                settings = settingsRepository.getSettings(for: userId)
                updateUserAvatarFromSettings()
            }

            // Load snapshots from local store
            if snapshots.isEmpty {
                snapshots = snapshotsRepository.getSnapshots(for: userId)
            }

            // Load recurring shifts from local store
            if recurringShifts.isEmpty {
                let localRecurring = recurringShiftsRepository.getRecurringShifts(for: userId)
                recurringShifts = localRecurring
            }

            // Calculate date ranges for displayed month
            let displayYM = (year: displayYear, month: displayMonth)
            let previousYM = Date.previousYearMonth(from: displayYM)

            let displayStartDate = Date.firstDayOfMonthDate(year: displayYM.year, month: displayYM.month)
            let displayEndDate = Date.lastDayOfMonthDate(year: displayYM.year, month: displayYM.month)
            let previousStartDate = Date.firstDayOfMonthDate(year: previousYM.year, month: previousYM.month)
            let previousEndDate = Date.lastDayOfMonthDate(year: previousYM.year, month: previousYM.month)

            // Load shifts from local store
            let displayShifts = shiftsRepository.getShifts(
                for: userId,
                startDate: displayStartDate,
                endDate: displayEndDate
            )

            let fetchedPreviousShifts = shiftsRepository.getShifts(
                for: userId,
                startDate: previousStartDate,
                endDate: previousEndDate
            )

            // Check if we have any data to show
            // Note: Empty shifts is OK, but missing settings means we can't compute payroll
            guard let currentSettings = self.settings else {
                // No settings yet - sync may not have completed
                // Show a softer message instead of hard error
                logger.info("📭 No local settings yet - waiting for sync")
                self.isLoading = false
                // Leave dashboardData as nil to show empty state
                return
            }

            // Compute displayed month shifts with payroll using PayrollEngine
            self.displayedMonthShifts = PayrollEngine.computeShiftsForMonth(
                year: displayYM.year,
                month: displayYM.month,
                shifts: displayShifts,
                recurring: recurringShifts,
                snapshots: snapshots,
                settings: currentSettings
            )

            // Compute previous month shifts with payroll using PayrollEngine
            self.previousMonthShifts = PayrollEngine.computeShiftsForMonth(
                year: previousYM.year,
                month: previousYM.month,
                shifts: fetchedPreviousShifts,
                recurring: recurringShifts,
                snapshots: snapshots,
                settings: currentSettings
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
            self.isLoading = false

            logger.info("📊 Loaded dashboard from local: \(displayShifts.count) shifts for \(displayKey)")

        } catch is CancellationError {
            logger.info("⏭️ Load cancelled (user navigated away)")
        } catch let urlError as URLError where urlError.code == .cancelled {
            logger.info("⏭️ Request cancelled (user navigated away)")
        } catch {
            logger.error("❌ Dashboard local load failed: \(error.localizedDescription)")
            self.error = DashboardError.dataLoadFailed(underlying: error)
            self.isLoading = false
        }
    }

    /// Load dashboard data for the currently displayed month from local repositories
    /// - Parameter showLoadingState: Whether to show loading indicator (false for background navigation loads)
    private func loadDashboardForDisplayedMonth(showLoadingState: Bool = true) async {
        if showLoadingState {
            isLoading = true
        }
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

            // Load settings and snapshots from local if not cached
            if settings == nil {
                settings = settingsRepository.getSettings(for: userId)
                updateUserAvatarFromSettings()
            }

            if snapshots.isEmpty {
                snapshots = snapshotsRepository.getSnapshots(for: userId)
            }

            // Load recurring shifts if not cached
            if recurringShifts.isEmpty {
                recurringShifts = recurringShiftsRepository.getRecurringShifts(for: userId)
            }

            // Calculate date ranges for displayed month
            let displayYM = (year: displayYear, month: displayMonth)
            let previousYM = Date.previousYearMonth(from: displayYM)

            let displayStartDate = Date.firstDayOfMonthDate(year: displayYM.year, month: displayYM.month)
            let displayEndDate = Date.lastDayOfMonthDate(year: displayYM.year, month: displayYM.month)
            let previousStartDate = Date.firstDayOfMonthDate(year: previousYM.year, month: previousYM.month)
            let previousEndDate = Date.lastDayOfMonthDate(year: previousYM.year, month: previousYM.month)

            // Load shifts from local repositories
            let displayShifts = shiftsRepository.getShifts(
                for: userId,
                startDate: displayStartDate,
                endDate: displayEndDate
            )

            let fetchedPreviousShifts = shiftsRepository.getShifts(
                for: userId,
                startDate: previousStartDate,
                endDate: previousEndDate
            )

            // Ensure settings are available before computing payroll
            guard let currentSettings = self.settings else {
                // No settings yet - sync may not have completed
                logger.info("📭 No local settings yet - waiting for sync")
                self.isLoading = false
                return
            }

            // Compute displayed month shifts with payroll using PayrollEngine
            self.displayedMonthShifts = PayrollEngine.computeShiftsForMonth(
                year: displayYM.year,
                month: displayYM.month,
                shifts: displayShifts,
                recurring: recurringShifts,
                snapshots: snapshots,
                settings: currentSettings
            )

            // Compute previous month shifts with payroll using PayrollEngine
            self.previousMonthShifts = PayrollEngine.computeShiftsForMonth(
                year: previousYM.year,
                month: previousYM.month,
                shifts: fetchedPreviousShifts,
                recurring: recurringShifts,
                snapshots: snapshots,
                settings: currentSettings
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

            // Build dashboard data and clear loading state
            self.dashboardData = buildDashboardData()
            self.isLoading = false

        } catch is CancellationError {
            // Task was cancelled due to rapid navigation - this is expected, not an error
            // Don't reset isLoading here - the new navigation task will handle its own state
            logger.info("⏭️ Load cancelled (user navigated away)")
        } catch {
            logger.error("❌ Dashboard load failed: \(error.localizedDescription)")
            self.error = DashboardError.dataLoadFailed(underlying: error)
            self.isLoading = false
        }
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

    /// Prefetch a single month's data in the background from local repository
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

        // Local reads are fast, but we run in a Task to not block UI
        Task {
            guard let userId = cachedUserId else {
                prefetchTasks.remove(key)
                return
            }

            let startDate = Date.firstDayOfMonthDate(year: year, month: month)
            let endDate = Date.lastDayOfMonthDate(year: year, month: month)

            // Read from local repository
            let fetchedShifts = shiftsRepository.getShifts(
                for: userId,
                startDate: startDate,
                endDate: endDate
            )

            // Compute shifts with payroll
            guard let settings = self.settings else {
                prefetchTasks.remove(key)
                return
            }

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
            self.monthCache[key] = entry
            self.prefetchTasks.remove(key)

            logger.info("📦 Prefetched \(key) with \(computedShifts.count) shifts from local")
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

    /// Get current authenticated user ID and update user profile data
    private func getCurrentUserId() async throws -> String? {
        let session = try await supabase.auth.session
        let user = session.user

        // Extract display name from user metadata or fall back to email
        let displayName: String
        if let fullName = user.userMetadata["full_name"]?.value as? String, !fullName.isEmpty {
            displayName = fullName
        } else if let name = user.userMetadata["name"]?.value as? String, !name.isEmpty {
            displayName = name
        } else if let email = user.email {
            // Use the part before @ for email
            displayName = email.components(separatedBy: "@").first ?? email
        } else if let phone = user.phone {
            displayName = phone
        } else {
            displayName = "User"
        }

        // Update published properties
        self.userDisplayName = displayName

        return user.id.uuidString.lowercased()
    }

    /// Update user avatar URL from settings (called after settings are loaded)
    private func updateUserAvatarFromSettings() {
        self.userAvatarUrl = settings?.profile_picture_url
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
        components.timeZone = Date.localTimeZone
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
