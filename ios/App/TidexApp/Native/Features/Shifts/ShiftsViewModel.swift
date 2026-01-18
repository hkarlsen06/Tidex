import Foundation
import SwiftUI
import UIKit
import Supabase
import Combine
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "ShiftsViewModel")

// MARK: - Week Group

/// A group of shifts for a single ISO week
struct WeekGroup: Identifiable, Equatable {
    /// Unique identifier: "YYYY-WW" format
    let id: String
    /// ISO week number (1-53)
    let weekNumber: Int
    /// Year for the week (ISO week-numbering year)
    let year: Int
    /// Total gross earnings for all shifts in this week
    let totalGross: Double
    /// Shifts in this week, sorted by date (newest first)
    let shifts: [ShiftWithComputations]
}

// MARK: - Shifts Error

enum ShiftsError: Error, LocalizedError {
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
    /// Last access time for LRU eviction
    var lastAccessed: Date

    var key: String { "\(year)-\(month)" }

    /// Check if cache entry is still valid (within 5 minutes)
    var isValid: Bool {
        Date().timeIntervalSince(timestamp) < 300 // 5 minutes
    }

    init(year: Int, month: Int, shifts: [ShiftWithComputations], timestamp: Date) {
        self.year = year
        self.month = month
        self.shifts = shifts
        self.timestamp = timestamp
        self.lastAccessed = timestamp
    }
}

// MARK: - Shifts View Model

@MainActor
final class ShiftsViewModel: ObservableObject, MonthNavigable {

    // MARK: - Dependencies (Local-First Repositories)

    private let shiftsRepository: ShiftsRepository
    private let settingsRepository: SettingsRepository
    private let snapshotsRepository: SnapshotsRepository
    private let recurringShiftsRepository: RecurringShiftsRepository
    private let syncCoordinator: SyncCoordinator
    private let monthContext: SharedMonthContext

    // MARK: - Published State

    /// All shifts for the displayed month (computed with payroll)
    @Published private(set) var shifts: [ShiftWithComputations] = []
    /// Shifts grouped by ISO week
    @Published private(set) var weekGroups: [WeekGroup] = []
    /// Whether data is currently loading
    @Published private(set) var isLoading = false
    /// Error if data loading failed
    @Published private(set) var error: Error?
    /// Set of shift IDs that have conflicts (overlapping with other shifts)
    @Published private(set) var conflictingShiftIds: Set<String> = []
    /// Set of shift IDs excluded from totals (higher-earning overlapping shifts are excluded)
    @Published private(set) var excludedFromTotalIds: Set<String> = []

    /// Direction of last navigation (for animations) - synced from SharedMonthContext
    @Published private(set) var navigationDirection: MonthNavigationDirection?

    /// Currently displayed year - synced from SharedMonthContext
    var displayYear: Int { monthContext.displayYear }

    /// Currently displayed month 1-12 - synced from SharedMonthContext
    var displayMonth: Int { monthContext.displayMonth }

    /// Whether viewing the current (real) month
    var isCurrentMonth: Bool { monthContext.isCurrentMonth }

    /// Computed month name for immediate display (doesn't wait for API)
    var displayMonthName: String { monthContext.displayMonthName }

    /// The period type of the displayed month (past, current, or future)
    var monthPeriod: MonthPeriod {
        let current = Date.currentYearMonth()
        let displayedIndex = displayYear * 12 + displayMonth
        let currentIndex = current.year * 12 + current.month

        if displayedIndex < currentIndex {
            return .past
        } else if displayedIndex == currentIndex {
            return .current
        } else {
            return .future
        }
    }

    /// User's currency for formatting
    @Published private(set) var currency: String = "kr"

    /// Next upcoming shift (for countdown display)
    @Published private(set) var nextUpcomingShift: ShiftWithComputations?

    // MARK: - Selection State

    /// Selected dates (ISO strings). Persists across month navigation.
    @Published var selectedDates: Set<String> = []

    /// Whether selection mode is enabled (tap/drag to select vs swipe to navigate)
    @Published var isSelectionModeEnabled: Bool = false

    /// Two-click delete confirmation state
    @Published var confirmingDelete: Bool = false

    /// Whether we're currently deleting shifts
    @Published var isDeleting: Bool = false

    /// Single vs multi-selection mode
    var isMultiSelectMode: Bool { selectedDates.count > 1 }

    /// Computed earnings for selected dates (for header display)
    /// Looks across ALL cached months, not just the currently displayed month
    var selectedEarnings: (net: Double, gross: Double)? {
        guard !selectedDates.isEmpty else { return nil }

        // Collect all shifts from all cached months that match selected dates
        var allSelectedShifts: [ShiftWithComputations] = []

        for (_, cacheEntry) in monthCache {
            let matchingShifts = cacheEntry.shifts.filter { selectedDates.contains($0.shiftDate) }
            allSelectedShifts.append(contentsOf: matchingShifts)
        }

        // Also check current month's shifts (may not be in cache yet)
        let currentMonthMatches = shifts.filter { selectedDates.contains($0.shiftDate) }
        for shift in currentMonthMatches {
            // Avoid duplicates (shift might already be in cache)
            if !allSelectedShifts.contains(where: { $0.id == shift.id }) {
                allSelectedShifts.append(shift)
            }
        }

        let gross = allSelectedShifts.reduce(0) { $0 + $1.grossPay }
        let net = allSelectedShifts.reduce(0) { $0 + ($1.taxEnabled ? $1.netPay : $1.grossPay) }

        return (net: net, gross: gross)
    }

    /// Whether any selected shift has tax enabled (for header display)
    /// Looks across ALL cached months, not just the currently displayed month
    var selectedHasTaxEnabled: Bool {
        guard !selectedDates.isEmpty else { return false }

        // Check all cached months for tax-enabled shifts
        for (_, cacheEntry) in monthCache {
            if cacheEntry.shifts.contains(where: { selectedDates.contains($0.shiftDate) && $0.taxEnabled }) {
                return true
            }
        }

        // Also check current month's shifts
        if shifts.contains(where: { selectedDates.contains($0.shiftDate) && $0.taxEnabled }) {
            return true
        }

        return false
    }

    /// Shifts for the selected date (single selection mode)
    var selectedDateShifts: [ShiftWithComputations] {
        guard selectedDates.count == 1, let dateISO = selectedDates.first else { return [] }
        return shifts.filter { $0.shiftDate == dateISO }
    }

    // MARK: - Private State

    private var settings: UserSettings?
    private var snapshots: [WageSnapshot] = []
    private var recurringShifts: [RecurringShiftRow] = []
    private var cachedUserId: String?

    /// Subscription to SharedMonthContext changes
    private var monthContextCancellable: AnyCancellable?

    /// Track the last observed month to detect changes
    private var lastObservedYear: Int = 0
    private var lastObservedMonth: Int = 0

    // MARK: - Month Cache

    /// Cache of computed shifts by month key (e.g., "2025-1")
    private var monthCache: [String: MonthCacheEntry] = [:]

    /// Maximum number of months to keep in cache (prevents unbounded memory growth)
    private static let maxCacheSize = 12

    /// Background prefetch tasks (to avoid duplicate fetches)
    private var prefetchTasks: Set<String> = []

    /// Memory warning observer
    private var memoryWarningObserver: NSObjectProtocol?

    /// Track active navigation task to cancel stale fetches
    private var activeNavigationTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        shiftsRepository: ShiftsRepository? = nil,
        settingsRepository: SettingsRepository? = nil,
        snapshotsRepository: SnapshotsRepository? = nil,
        recurringShiftsRepository: RecurringShiftsRepository? = nil,
        syncCoordinator: SyncCoordinator? = nil,
        monthContext: SharedMonthContext? = nil
    ) {
        // Use provided repositories or default to shared instances
        self.shiftsRepository = shiftsRepository ?? ShiftsRepository.shared
        self.settingsRepository = settingsRepository ?? SettingsRepository.shared
        self.snapshotsRepository = snapshotsRepository ?? SnapshotsRepository.shared
        self.recurringShiftsRepository = recurringShiftsRepository ?? RecurringShiftsRepository.shared
        self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
        self.monthContext = monthContext ?? SharedMonthContext.shared

        // Initialize tracking to current month context values
        self.lastObservedYear = self.monthContext.displayYear
        self.lastObservedMonth = self.monthContext.displayMonth

        // Subscribe to month context changes
        setupMonthContextSubscription()

        // Listen for memory warnings to clear cache
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleMemoryWarning()
            }
        }
    }

    /// Subscribe to SharedMonthContext changes to reload data when month changes
    private func setupMonthContextSubscription() {
        monthContextCancellable = monthContext.monthChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newMonth in
                guard let self = self else { return }

                // Only reload if month actually changed
                guard newMonth.year != self.lastObservedYear || newMonth.month != self.lastObservedMonth else {
                    return
                }

                // Update tracking
                self.lastObservedYear = newMonth.year
                self.lastObservedMonth = newMonth.month

                // Sync navigation direction from context
                self.navigationDirection = self.monthContext.navigationDirection

                // Trigger data reload for new month
                self.loadShiftsForDisplayedMonthNonBlocking()
            }
    }

    deinit {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Memory Management

    /// Handle memory warning by clearing the cache
    private func handleMemoryWarning() {
        logger.warning("⚠️ Memory warning received - clearing month cache (\(self.monthCache.count) entries)")
        monthCache.removeAll()
        prefetchTasks.removeAll()
    }

    /// Evict least recently used cache entries if over limit
    private func evictCacheIfNeeded() {
        guard monthCache.count > Self.maxCacheSize else { return }

        // Sort by last accessed time (oldest first)
        let sortedKeys = monthCache.keys.sorted { key1, key2 in
            let entry1 = monthCache[key1]!
            let entry2 = monthCache[key2]!
            return entry1.lastAccessed < entry2.lastAccessed
        }

        // Remove oldest entries until we're under the limit
        let entriesToRemove = monthCache.count - Self.maxCacheSize
        for i in 0..<entriesToRemove {
            let key = sortedKeys[i]
            monthCache.removeValue(forKey: key)
            logger.info("🗑️ Evicted cache entry: \(key)")
        }
    }

    // MARK: - Month Navigation

    /// Navigate to the previous month (non-blocking)
    /// Delegates to SharedMonthContext - data reload happens via subscription
    func goToPreviousMonth() {
        monthContext.goToPreviousMonth()
    }

    /// Navigate to the next month (non-blocking)
    /// Delegates to SharedMonthContext - data reload happens via subscription
    func goToNextMonth() {
        monthContext.goToNextMonth()
    }

    /// Reset to current month (non-blocking)
    /// Delegates to SharedMonthContext - data reload happens via subscription
    func goToCurrentMonth() {
        monthContext.goToCurrentMonth()
    }

    // MARK: - Selection Actions

    /// Handle day tap - manages single/multi selection logic
    func handleDayTapped(dateISO: String, shiftsOnDay: [ShiftWithComputations]) {
        // Reset delete confirmation on any tap
        confirmingDelete = false

        // If tapping a date with no shifts, ignore (don't clear selection)
        guard !shiftsOnDay.isEmpty else { return }

        // If no current selection, select this date
        if selectedDates.isEmpty {
            selectedDates = [dateISO]
            return
        }

        // If tapping already selected date
        if selectedDates.contains(dateISO) {
            if selectedDates.count == 1 {
                // Single selection - deselect
                clearSelection()
            } else {
                // Multi-selection - remove this date
                selectedDates.remove(dateISO)
            }
            return
        }

        // Tapping a different date - add to selection (enter multi-select)
        selectedDates.insert(dateISO)
    }

    /// Clear all selection state
    func clearSelection() {
        selectedDates.removeAll()
        confirmingDelete = false
        isSelectionModeEnabled = false
    }

    /// Handle date range selection from long-press + drag gesture
    /// - Parameter dates: Array of ISO date strings to select
    func handleDateRangeSelected(_ dates: [String]) {
        // Reset delete confirmation
        confirmingDelete = false

        // Filter to only dates with shifts
        let datesWithShifts = dates.filter { dateISO in
            shifts.contains { $0.shiftDate == dateISO }
        }

        guard !datesWithShifts.isEmpty else { return }

        // Add to existing selection (union, not replace)
        selectedDates.formUnion(datesWithShifts)
    }

    /// Delete all shifts for selected dates
    func deleteSelectedShifts() async {
        let shiftsToDelete = shifts.filter { selectedDates.contains($0.shiftDate) }
        guard !shiftsToDelete.isEmpty else { return }

        isDeleting = true

        do {
            for shift in shiftsToDelete {
                if shift.isVirtual, let recurringId = shift.shift.recurring_id {
                    try await RecurringShiftsRepository.shared.addExclusion(
                        id: recurringId,
                        date: shift.shiftDate
                    )
                } else {
                    try await ShiftsRepository.shared.deleteShift(id: shift.id)
                }
            }

            clearSelection()
            await reloadFromLocal()
            NotificationCenter.default.post(name: .shiftsDidChange, object: nil)
        } catch {
            logger.error("Failed to delete shifts: \(error.localizedDescription)")
        }

        isDeleting = false
    }

    /// Non-blocking month data loader
    /// Uses cache for instant display, fetches in background if needed
    private func loadShiftsForDisplayedMonthNonBlocking() {
        let targetYear = displayYear
        let targetMonth = displayMonth
        let displayKey = "\(targetYear)-\(targetMonth)"

        // Check if we have valid cache for displayed month
        if var displayCache = monthCache[displayKey], displayCache.isValid {
            // Use cached data - instant navigation!
            logger.info("📦 Using cached data for \(displayKey)")
            self.shifts = displayCache.shifts
            self.weekGroups = groupShiftsByWeek(displayCache.shifts)

            // Update last accessed time for LRU tracking
            displayCache.lastAccessed = Date()
            monthCache[displayKey] = displayCache

            // Still prefetch neighbors in background
            prefetchNeighboringMonths()
            return
        }

        // Cache miss - show loading state and fetch
        logger.info("🔄 Cache miss for \(displayKey), fetching in background...")

        // Clear data and show loading state
        self.shifts = []
        self.weekGroups = []
        self.isLoading = true

        // Cancel any previous navigation task
        activeNavigationTask?.cancel()

        // Start background fetch
        activeNavigationTask = Task { [weak self] in
            guard let self = self else { return }

            // Check if this task is still relevant
            guard !Task.isCancelled,
                  self.displayYear == targetYear,
                  self.displayMonth == targetMonth else {
                logger.info("⏭️ Skipping stale fetch for \(displayKey)")
                return
            }

            await self.loadShiftsForDisplayedMonth(showLoadingState: false)

            // Check again after fetch
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

    /// Load all shifts data for current month (initial load)
    /// Reads from local repositories only - sync is triggered by AppCoordinator
    func loadShifts() async {
        // Sync tracking with current month context values
        lastObservedYear = monthContext.displayYear
        lastObservedMonth = monthContext.displayMonth
        navigationDirection = nil

        // Clear cache on full reload
        monthCache.removeAll()
        prefetchTasks.removeAll()

        await loadShiftsFromLocal()

        // Prefetch neighboring months in the background
        prefetchNeighboringMonths()
    }

    /// Refresh shifts data via sync then local reload
    /// Called by pull-to-refresh - triggers network sync, then reloads from local
    func refresh() async {
        logger.info("🔄 Pull-to-refresh: triggering sync then local reload")

        // Store current data as fallback
        let previousShifts = shifts
        let previousWeekGroups = weekGroups

        do {
            // Get user ID
            if cachedUserId == nil {
                guard let userId = try await getCurrentUserId() else {
                    throw ShiftsError.notAuthenticated
                }
                cachedUserId = userId
            }

            guard let userId = cachedUserId else {
                throw ShiftsError.notAuthenticated
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
            settings = nil
            snapshots = []
            recurringShifts = []

            // Reload from local repositories
            await loadShiftsFromLocal()

            // Prefetch neighboring months
            prefetchNeighboringMonths()

            logger.info("✅ Pull-to-refresh complete (synced \(syncResult.totalRowsProcessed) rows)")

        } catch {
            logger.error("❌ Pull-to-refresh failed: \(error.localizedDescription)")

            // Restore previous data so UI doesn't break
            self.shifts = previousShifts
            self.weekGroups = previousWeekGroups

            logger.info("📦 Restored previous data after refresh failure")
        }
    }

    /// Reload shifts from local data without triggering sync
    /// Called when shifts change locally (e.g., after adding a shift)
    func reloadFromLocal() async {
        logger.info("🔄 Reloading shifts from local data")

        // Clear in-memory caches to pick up new data
        monthCache.removeAll()
        prefetchTasks.removeAll()

        // Reload from local repositories
        await loadShiftsFromLocal()

        // Prefetch neighboring months
        prefetchNeighboringMonths()

        logger.info("✅ Shifts reloaded from local")
    }

    // MARK: - Private Loading Methods

    /// Load shifts data from local repositories
    private func loadShiftsFromLocal() async {
        isLoading = true
        error = nil

        do {
            // Get or cache user ID
            if cachedUserId == nil {
                guard let userId = try await getCurrentUserId() else {
                    throw ShiftsError.notAuthenticated
                }
                cachedUserId = userId
            }

            guard let userId = cachedUserId else {
                throw ShiftsError.notAuthenticated
            }

            // Load settings from local store
            if settings == nil {
                settings = settingsRepository.getSettings(for: userId)
                logger.info("📋 Loaded settings: \(self.settings != nil ? "found" : "nil")")
                if let userSettings = settings {
                    currency = userSettings.currency ?? "kr"
                }
            }

            // Load snapshots from local store
            if snapshots.isEmpty {
                snapshots = snapshotsRepository.getSnapshots(for: userId)
                logger.info("📋 Loaded snapshots: \(self.snapshots.count)")
            }

            // Load recurring shifts from local store
            if recurringShifts.isEmpty {
                recurringShifts = recurringShiftsRepository.getRecurringShifts(for: userId)
                logger.info("📋 Loaded recurring: \(self.recurringShifts.count)")
            }

            // Calculate date range for displayed month
            let displayYM = (year: displayYear, month: displayMonth)
            let displayStartDate = Date.firstDayOfMonthDate(year: displayYM.year, month: displayYM.month)
            let displayEndDate = Date.lastDayOfMonthDate(year: displayYM.year, month: displayYM.month)

            // Load shifts from local store
            let displayShifts = shiftsRepository.getShifts(
                for: userId,
                startDate: displayStartDate,
                endDate: displayEndDate
            )
            logger.info("📋 Loaded shifts for \(displayYM.year)-\(displayYM.month): \(displayShifts.count)")

            // Check if we have settings to compute payroll
            guard let currentSettings = self.settings else {
                logger.info("📭 No local settings yet - waiting for sync (userId: \(userId))")
                self.isLoading = false
                return
            }

            // Compute shifts with payroll using PayrollEngine
            let computedShifts = PayrollEngine.computeShiftsForMonth(
                year: displayYM.year,
                month: displayYM.month,
                shifts: displayShifts,
                recurring: recurringShifts,
                snapshots: snapshots,
                settings: currentSettings
            )

            // Cache the computed results
            let displayKey = "\(displayYM.year)-\(displayYM.month)"
            monthCache[displayKey] = MonthCacheEntry(
                year: displayYM.year,
                month: displayYM.month,
                shifts: computedShifts,
                timestamp: Date()
            )

            // Evict old cache entries if over limit
            evictCacheIfNeeded()

            // Update published state
            self.shifts = computedShifts
            self.weekGroups = groupShiftsByWeek(computedShifts)

            // Calculate conflict detection
            updateConflictDetection(for: computedShifts)

            // Find next upcoming shift (only on current month)
            if isCurrentMonth {
                updateNextUpcomingShift(for: computedShifts)
            }

            self.isLoading = false

            logger.info("📊 Loaded shifts from local: \(computedShifts.count) shifts, \(self.weekGroups.count) weeks")

        } catch is CancellationError {
            logger.info("⏭️ Load cancelled (user navigated away)")
        } catch {
            logger.error("❌ Shifts local load failed: \(error.localizedDescription)")
            self.error = ShiftsError.dataLoadFailed(underlying: error)
            self.isLoading = false
        }
    }

    /// Load shifts data for the currently displayed month
    /// - Parameter showLoadingState: Whether to show loading indicator
    private func loadShiftsForDisplayedMonth(showLoadingState: Bool = true) async {
        if showLoadingState {
            isLoading = true
        }
        error = nil

        do {
            // Get or cache user ID
            if cachedUserId == nil {
                guard let userId = try await getCurrentUserId() else {
                    throw ShiftsError.notAuthenticated
                }
                cachedUserId = userId
            }

            guard let userId = cachedUserId else {
                throw ShiftsError.notAuthenticated
            }

            // Load settings and snapshots from local if not cached
            if settings == nil {
                settings = settingsRepository.getSettings(for: userId)
                if let userSettings = settings {
                    currency = userSettings.currency ?? "kr"
                }
            }

            if snapshots.isEmpty {
                snapshots = snapshotsRepository.getSnapshots(for: userId)
            }

            if recurringShifts.isEmpty {
                recurringShifts = recurringShiftsRepository.getRecurringShifts(for: userId)
            }

            // Calculate date range for displayed month
            let displayYM = (year: displayYear, month: displayMonth)
            let displayStartDate = Date.firstDayOfMonthDate(year: displayYM.year, month: displayYM.month)
            let displayEndDate = Date.lastDayOfMonthDate(year: displayYM.year, month: displayYM.month)

            // Load shifts from local repository
            let displayShifts = shiftsRepository.getShifts(
                for: userId,
                startDate: displayStartDate,
                endDate: displayEndDate
            )

            // Ensure settings are available
            guard let currentSettings = self.settings else {
                logger.info("📭 No local settings yet - waiting for sync")
                self.isLoading = false
                return
            }

            // Compute shifts with payroll
            let computedShifts = PayrollEngine.computeShiftsForMonth(
                year: displayYM.year,
                month: displayYM.month,
                shifts: displayShifts,
                recurring: recurringShifts,
                snapshots: snapshots,
                settings: currentSettings
            )

            // Cache the computed results
            let displayKey = "\(displayYM.year)-\(displayYM.month)"
            monthCache[displayKey] = MonthCacheEntry(
                year: displayYM.year,
                month: displayYM.month,
                shifts: computedShifts,
                timestamp: Date()
            )

            // Evict old cache entries if over limit
            evictCacheIfNeeded()

            // Update published state
            self.shifts = computedShifts
            self.weekGroups = groupShiftsByWeek(computedShifts)

            // Calculate conflict detection
            updateConflictDetection(for: computedShifts)

            // Find next upcoming shift (only on current month)
            if isCurrentMonth {
                updateNextUpcomingShift(for: computedShifts)
            }

            self.isLoading = false

        } catch is CancellationError {
            logger.info("⏭️ Load cancelled (user navigated away)")
        } catch {
            logger.error("❌ Shifts load failed: \(error.localizedDescription)")
            self.error = ShiftsError.dataLoadFailed(underlying: error)
            self.isLoading = false
        }
    }

    // MARK: - Next Upcoming Shift

    /// Find and update the next upcoming shift from the current shifts
    private func updateNextUpcomingShift(for shifts: [ShiftWithComputations]) {
        let now = Date()
        let calendar = Calendar.current

        // Filter to shifts that haven't ended yet
        let upcomingShifts = shifts.filter { shift in
            guard let shiftDate = Date.fromISODateString(shift.shiftDate),
                  let endTime = parseTime(shift.endTime) else {
                return false
            }

            // Combine date and time
            var shiftEndComponents = calendar.dateComponents([.year, .month, .day], from: shiftDate)
            shiftEndComponents.hour = calendar.component(.hour, from: endTime)
            shiftEndComponents.minute = calendar.component(.minute, from: endTime)

            // Handle cross-midnight shifts
            if shift.endTime <= shift.startTime {
                shiftEndComponents.day = (shiftEndComponents.day ?? 0) + 1
            }

            guard let shiftEnd = calendar.date(from: shiftEndComponents) else { return false }
            return shiftEnd > now
        }

        // Sort by start datetime and take the first one
        let sorted = upcomingShifts.sorted { a, b in
            guard let dateA = Date.fromISODateString(a.shiftDate),
                  let dateB = Date.fromISODateString(b.shiftDate),
                  let timeA = parseTime(a.startTime),
                  let timeB = parseTime(b.startTime) else {
                return false
            }

            var componentsA = calendar.dateComponents([.year, .month, .day], from: dateA)
            componentsA.hour = calendar.component(.hour, from: timeA)
            componentsA.minute = calendar.component(.minute, from: timeA)

            var componentsB = calendar.dateComponents([.year, .month, .day], from: dateB)
            componentsB.hour = calendar.component(.hour, from: timeB)
            componentsB.minute = calendar.component(.minute, from: timeB)

            guard let startA = calendar.date(from: componentsA),
                  let startB = calendar.date(from: componentsB) else {
                return false
            }

            return startA < startB
        }

        self.nextUpcomingShift = sorted.first
    }

    private func parseTime(_ time: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.date(from: String(time.prefix(5)))
    }

    // MARK: - Conflict Detection

    /// Update conflict detection for the given shifts
    /// Sets conflictingShiftIds and excludedFromTotalIds
    private func updateConflictDetection(for shifts: [ShiftWithComputations]) {
        // Find all overlapping shifts
        var conflicting = Set<String>()

        // Group shifts by date
        var shiftsByDate: [String: [ShiftWithComputations]] = [:]
        for shift in shifts {
            shiftsByDate[shift.shiftDate, default: []].append(shift)
        }

        // Check each date for overlapping shifts
        for (_, shiftsOnDate) in shiftsByDate {
            guard shiftsOnDate.count >= 2 else { continue }

            // Check all pairs for overlap
            for i in 0..<shiftsOnDate.count {
                for j in (i + 1)..<shiftsOnDate.count {
                    if ConflictExclusion.shiftsOverlap(shiftsOnDate[i], shiftsOnDate[j]) {
                        conflicting.insert(shiftsOnDate[i].id)
                        conflicting.insert(shiftsOnDate[j].id)
                    }
                }
            }
        }

        // Build excluded set (using existing ConflictExclusion logic)
        let excluded = ConflictExclusion.buildExcludedShiftIds(shifts: shifts)

        self.conflictingShiftIds = conflicting
        self.excludedFromTotalIds = excluded

        if !conflicting.isEmpty {
            logger.info("⚠️ Found \(conflicting.count) conflicting shifts, \(excluded.count) excluded from totals")
        }
    }

    // MARK: - Prefetching

    /// Prefetch neighboring months in the background
    private func prefetchNeighboringMonths() {
        let displayYM = (year: displayYear, month: displayMonth)

        // Calculate previous and next months
        let previousYM = Date.previousYearMonth(from: displayYM)
        let nextYM = nextYearMonth(from: displayYM)

        // Prefetch both neighbors
        prefetchMonthInBackground(year: previousYM.year, month: previousYM.month)
        prefetchMonthInBackground(year: nextYM.year, month: nextYM.month)
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

            // Evict old cache entries if over limit
            self.evictCacheIfNeeded()

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

    // MARK: - Week Grouping

    /// Group shifts by ISO week
    /// - Parameter shifts: Shifts to group
    /// - Returns: Array of WeekGroup, sorted by week (oldest first, ascending)
    private func groupShiftsByWeek(_ shifts: [ShiftWithComputations]) -> [WeekGroup] {
        guard !shifts.isEmpty else { return [] }

        // Group shifts by ISO week key
        var weekMap: [String: (weekNumber: Int, year: Int, shifts: [ShiftWithComputations])] = [:]

        for shift in shifts {
            guard let date = Date.fromISODateString(shift.shiftDate) else { continue }

            let (weekNumber, weekYear) = getIsoWeek(from: date)
            let key = "\(weekYear)-W\(String(format: "%02d", weekNumber))"

            if var existing = weekMap[key] {
                existing.shifts.append(shift)
                weekMap[key] = existing
            } else {
                weekMap[key] = (weekNumber: weekNumber, year: weekYear, shifts: [shift])
            }
        }

        // Convert to WeekGroup array
        let groups = weekMap.map { key, value in
            WeekGroup(
                id: key,
                weekNumber: value.weekNumber,
                year: value.year,
                totalGross: value.shifts.reduce(0) { $0 + $1.grossPay },
                shifts: value.shifts.sorted { $0.shiftDate < $1.shiftDate }
            )
        }

        // Sort by week (oldest first, ascending)
        return groups.sorted { $0.id < $1.id }
    }

    /// Get ISO week number and year for a date
    /// Uses ISO 8601 week numbering (Monday is first day, week 1 has at least 4 days in year)
    private func getIsoWeek(from date: Date) -> (weekNumber: Int, year: Int) {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2  // Monday
        calendar.minimumDaysInFirstWeek = 4

        let weekOfYear = calendar.component(.weekOfYear, from: date)
        let yearForWeekOfYear = calendar.component(.yearForWeekOfYear, from: date)

        return (weekOfYear, yearForWeekOfYear)
    }

    // MARK: - Private Helpers

    /// Get current authenticated user ID
    private func getCurrentUserId() async throws -> String? {
        let session = try await supabase.auth.session
        return session.user.id.uuidString.lowercased()
    }
}
