import Combine
import Foundation
import Supabase
import SwiftUI
import UIKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "DashboardViewModel")

// MARK: - Notification Names

extension Notification.Name {
  /// Posted when shifts are created/modified and dashboard should refresh
  static let shiftsDidChange = Notification.Name("com.tidex.shiftsDidChange")
}

// MARK: - Dashboard Data

/// Computed dashboard data ready for display
struct DashboardData: Equatable {
  // Payroll Card (Previous Month)
  let payrollDate: Date
  let payrollHasPassed: Bool  // true = previous payout, false = next payout
  let previousMonthGross: Double
  let previousMonthNet: Double?  // nil if tax not enabled
  let previousMonthTax: Double?
  let previousMonthTaxEnabled: Bool

  // Total Card (Current Month)
  let currentMonthGross: Double  // All shifts (projected total)
  let currentMonthNet: Double?  // All shifts net (projected)
  let currentMonthCompletedGross: Double  // Only completed shifts (earned to date)
  let currentMonthCompletedNet: Double?  // Only completed shifts net
  let currentMonthShiftCount: Int  // Total shift count
  let currentMonthCompletedCount: Int  // Completed shifts count
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

  // User Settings
  let currency: String  // User's selected currency (e.g., "kr", "$", "€")

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
  /// Last access time for LRU eviction
  var lastAccessed: Date

  var key: String { "\(year)-\(month)" }

  /// Check if cache entry is still valid (within 5 minutes)
  var isValid: Bool {
    Date().timeIntervalSince(timestamp) < 300  // 5 minutes
  }

  init(year: Int, month: Int, shifts: [ShiftWithComputations], timestamp: Date) {
    self.year = year
    self.month = month
    self.shifts = shifts
    self.timestamp = timestamp
    self.lastAccessed = timestamp
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
  private let monthContext: SharedMonthContext
  nonisolated private static let gregorianCalendar = Calendar(identifier: .gregorian)

  // MARK: - Published State

  @Published private(set) var dashboardData: DashboardData?
  @Published private(set) var isLoading = false
  @Published private(set) var error: Error?

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
    // Using optional parameters avoids Swift 6 MainActor isolation errors
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
        guard newMonth.year != self.lastObservedYear || newMonth.month != self.lastObservedMonth
        else {
          return
        }

        // Update tracking
        self.lastObservedYear = newMonth.year
        self.lastObservedMonth = newMonth.month

        // Sync navigation direction from context
        self.navigationDirection = self.monthContext.navigationDirection

        // Trigger data reload for new month
        self.loadDashboardForDisplayedMonthNonBlocking()
      }
  }

  deinit {
    // Cancel Combine subscriptions to prevent memory leaks
    monthContextCancellable?.cancel()

    // Cancel any active navigation task to prevent orphaned operations
    activeNavigationTask?.cancel()

    if let observer = memoryWarningObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  // MARK: - Memory Management

  /// Handle memory warning by clearing the cache
  private func handleMemoryWarning() {
    logger.warning(
      "⚠️ Memory warning received - clearing month cache (\(self.monthCache.count) entries)")
    monthCache.removeAll()
    prefetchTasks.removeAll()
  }

  /// Evict least recently used cache entries if over limit
  private func evictCacheIfNeeded() {
    guard monthCache.count > Self.maxCacheSize else { return }

    // Sort by last accessed time (oldest first)
    let sortedKeys = monthCache.keys.sorted { key1, key2 in
      guard let entry1 = monthCache[key1], let entry2 = monthCache[key2] else { return false }
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

  /// Track active navigation task to cancel stale fetches
  private var activeNavigationTask: Task<Void, Never>?

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

  /// Non-blocking month data loader
  /// Uses cache for instant display, fetches in background if needed
  private func loadDashboardForDisplayedMonthNonBlocking() {
    let targetYear = displayYear
    let targetMonth = displayMonth
    let displayKey = "\(targetYear)-\(targetMonth)"
    let previousYM = Date.previousYearMonth(from: (year: targetYear, month: targetMonth))
    let previousKey = "\(previousYM.year)-\(previousYM.month)"

    // Check if we have valid cache for both displayed and previous months
    if var displayCache = monthCache[displayKey], displayCache.isValid,
      var previousCache = monthCache[previousKey], previousCache.isValid
    {
      // Use cached data - instant navigation!
      logger.info("📦 Using cached data for \(displayKey)")
      self.displayedMonthShifts = displayCache.shifts
      self.previousMonthShifts = previousCache.shifts

      // Update last accessed time for LRU tracking
      displayCache.lastAccessed = Date()
      previousCache.lastAccessed = Date()
      monthCache[displayKey] = displayCache
      monthCache[previousKey] = previousCache

      if let currentSettings = settings {
        let capturedDisplay = displayCache.shifts
        let capturedPrevious = previousCache.shifts
        let capturedCurrency = currentSettings.currency ?? "kr"

        Task.detached(priority: .userInitiated) {
          [
            displayYM = (year: targetYear, month: targetMonth), previousYM, currentSettings,
            capturedCurrency, capturedDisplay, capturedPrevious
          ] in
          let data = Self.buildDashboardDataOffMain(
            displayedMonthShifts: capturedDisplay,
            previousMonthShifts: capturedPrevious,
            settings: currentSettings,
            displayYM: displayYM,
            previousYM: previousYM,
            currency: capturedCurrency
          )
          await MainActor.run {
            self.dashboardData = data
            self.maybeTriggerCelebration()
          }
        }
      } else {
        self.dashboardData = buildDashboardData()
        self.maybeTriggerCelebration()
      }

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

      do {
        // Check cancellation at the start
        try Task.checkCancellation()

        // Check if this task is still relevant (user hasn't navigated away)
        guard self.displayYear == targetYear,
          self.displayMonth == targetMonth
        else {
          logger.info("⏭️ Skipping stale fetch for \(displayKey)")
          return
        }

        await self.loadDashboardForDisplayedMonth(showLoadingState: false)

        // Check cancellation after async operation
        try Task.checkCancellation()

        // Check again after fetch - user may have navigated during the async operation
        guard self.displayYear == targetYear,
          self.displayMonth == targetMonth
        else {
          logger.info("⏭️ Skipping prefetch - user navigated during fetch")
          return
        }

        // Prefetch neighbors after successful load
        self.prefetchNeighboringMonths()
      } catch is CancellationError {
        logger.info("⏭️ Navigation task was cancelled for \(displayKey)")
      } catch {
        logger.error("Navigation task failed for \(displayKey): \(error.localizedDescription)")
      }
    }
  }

  // MARK: - Public Methods

  /// Load all dashboard data for current month (initial load)
  /// Reads from local repositories only - sync is triggered by AppCoordinator
  /// Also prefetches neighboring months for instant navigation
  func loadDashboard() async {
    // Sync tracking with current month context values
    lastObservedYear = monthContext.displayYear
    lastObservedMonth = monthContext.displayMonth
    navigationDirection = nil

    // Clear cache on full reload (including cachedUserId for impersonation support)
    monthCache.removeAll()
    prefetchTasks.removeAll()
    cachedUserId = nil

    await loadDashboardFromLocal()

    // Prefetch neighboring months in the background
    prefetchNeighboringMonths()
  }

  /// Refresh dashboard data via sync then local reload
  /// Called by pull-to-refresh - triggers network sync, then reloads from local
  func refresh() async {
    // SwiftUI .refreshable can cancel the parent task when the view hierarchy changes.
    // Run refresh work in an unstructured task so sync can complete reliably.
    let refreshTask = Task { @MainActor [weak self] in
      guard let self = self else { return }
      await self.performRefresh()
    }

    _ = await refreshTask.result
  }

  /// Performs pull-to-refresh sync and local reload.
  private func performRefresh() async {
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

  /// Prepare for reload by setting loading state synchronously
  /// Call this BEFORE starting a Task to reload, to prevent empty state flash
  /// This ensures the loading indicator shows immediately when sync completes
  func prepareForReload() {
    isLoading = true
  }

  /// Reload dashboard from local data without triggering sync
  /// Called when shifts change locally (e.g., after adding a shift) or after initial sync completes
  /// - Parameter showLoadingState: Whether to show loading indicator (false for seamless updates after sync)
  func reloadFromLocal(showLoadingState: Bool = true) async {
    logger.info("🔄 Reloading dashboard from local data")

    // Set loading state if not already set (e.g., by prepareForReload)
    if showLoadingState && !isLoading {
      isLoading = true
    }

    // Clear ALL in-memory caches to pick up new data from sync
    // This is critical after initial sync completes - settings/snapshots may now exist
    // Also critical for impersonation: cachedUserId must be refreshed from current session
    monthCache.removeAll()
    prefetchTasks.removeAll()
    cachedUserId = nil  // Force re-fetch user ID from session (critical for impersonation)
    settings = nil  // Force re-read settings from repository
    snapshots = []  // Force re-read snapshots from repository
    recurringShifts = []  // Force re-read recurring shifts from repository

    // Reload from local repositories (pass false since we already set loading state)
    await loadDashboardFromLocal(showLoadingState: false)

    // Prefetch neighboring months after launch animations settle
    Task {
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      prefetchNeighboringMonths()
    }

    logger.info("✅ Dashboard reloaded from local")
  }

  /// Load dashboard data from local repositories
  /// This is the core local-first read path - no network calls
  /// - Parameter showLoadingState: Whether to show/update loading indicator (false for seamless background updates)
  private func loadDashboardFromLocal(showLoadingState: Bool = true) async {
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

      // Load settings from local store
      if settings == nil {
        settings = await LocalStore.shared.storeActor.fetchUserSettings(userId: userId)
        logger.info("📋 Loaded settings: \(self.settings != nil ? "found" : "nil")")
      }

      // Check if we have any data to show
      // Note: Empty shifts is OK, but missing settings means we can't compute payroll
      if self.settings == nil {
        // No settings yet - retry multiple times with delays
        // This handles the race condition where sync completes but data isn't readable yet
        for attempt in 1...5 {
          logger.info("📭 No local settings yet - retry \(attempt)/5 in 400ms (userId: \(userId))")

          do {
            try await Task.sleep(nanoseconds: 400_000_000)  // 400ms
          } catch {
            // Sleep was cancelled - exit retry loop
            logger.info("⏭️ Retry sleep cancelled")
            break
          }

          // Retry loading settings
          settings = await LocalStore.shared.storeActor.fetchUserSettings(userId: userId)
          if settings != nil {
            logger.info("📋 Settings found on retry \(attempt)")
            break
          }
        }
      }

      guard let currentSettings = self.settings else {
        // Still no settings after all retries - this is a real error
        logger.error("❌ No settings after retries - cannot load dashboard")
        self.error = DashboardError.noLocalData
        self.isLoading = false
        return
      }

      updateUserAvatarFromSettings()

      // Load snapshots from local store
      if snapshots.isEmpty {
        snapshots = await LocalStore.shared.storeActor.fetchSnapshots(userId: userId)
        logger.info("📋 Loaded snapshots: \(self.snapshots.count)")
      }

      // Load recurring shifts from local store
      if recurringShifts.isEmpty {
        recurringShifts = await LocalStore.shared.storeActor.fetchRecurringShifts(userId: userId)
        logger.info("📋 Loaded recurring: \(self.recurringShifts.count)")
      }

      // Calculate date ranges for displayed month
      let displayYM = (year: displayYear, month: displayMonth)
      let previousYM = Date.previousYearMonth(from: displayYM)

      let displayStartDate = Date.firstDayOfMonthDate(year: displayYM.year, month: displayYM.month)
      let displayEndDate = Date.lastDayOfMonthDate(year: displayYM.year, month: displayYM.month)
      let previousStartDate = Date.firstDayOfMonthDate(
        year: previousYM.year, month: previousYM.month)
      let previousEndDate = Date.lastDayOfMonthDate(year: previousYM.year, month: previousYM.month)

      // Load shifts from local store (after settings retry to avoid stale empty reads)
      let displayShifts = await LocalStore.shared.storeActor.fetchShifts(
        userId: userId,
        startDate: displayStartDate,
        endDate: displayEndDate
      )
      logger.info(
        "📋 Loaded shifts for \(displayYM.year)-\(displayYM.month): \(displayShifts.count)")

      let fetchedPreviousShifts = await LocalStore.shared.storeActor.fetchShifts(
        userId: userId,
        startDate: previousStartDate,
        endDate: previousEndDate
      )

      let capturedRecurring = recurringShifts
      let capturedSnapshots = snapshots
      let capturedCurrency = currentSettings.currency ?? "kr"

      let result = await Task.detached(priority: .userInitiated) {
        let displayComputed = PayrollEngine.computeShiftsForMonth(
          year: displayYM.year,
          month: displayYM.month,
          shifts: displayShifts,
          recurring: capturedRecurring,
          snapshots: capturedSnapshots,
          settings: currentSettings
        )

        let previousComputed = PayrollEngine.computeShiftsForMonth(
          year: previousYM.year,
          month: previousYM.month,
          shifts: fetchedPreviousShifts,
          recurring: capturedRecurring,
          snapshots: capturedSnapshots,
          settings: currentSettings
        )

        let dashboardData = Self.buildDashboardDataOffMain(
          displayedMonthShifts: displayComputed,
          previousMonthShifts: previousComputed,
          settings: currentSettings,
          displayYM: displayYM,
          previousYM: previousYM,
          currency: capturedCurrency
        )

        return (display: displayComputed, previous: previousComputed, dashboardData: dashboardData)
      }.value

      self.displayedMonthShifts = result.display
      self.previousMonthShifts = result.previous

      // Cache the computed results
      let displayKey = "\(displayYM.year)-\(displayYM.month)"
      let previousKey = "\(previousYM.year)-\(previousYM.month)"
      monthCache[displayKey] = MonthCacheEntry(
        year: displayYM.year,
        month: displayYM.month,
        shifts: result.display,
        timestamp: Date()
      )
      monthCache[previousKey] = MonthCacheEntry(
        year: previousYM.year,
        month: previousYM.month,
        shifts: result.previous,
        timestamp: Date()
      )

      // Evict old cache entries if over limit
      evictCacheIfNeeded()

      // Build dashboard data and clear loading state
      // Always clear isLoading on success since we have data to show
      self.dashboardData = result.dashboardData
      self.maybeTriggerCelebration()
      self.isLoading = false

      logger.info("📊 Loaded dashboard from local: \(displayShifts.count) shifts for \(displayKey)")

    } catch is CancellationError {
      logger.info("⏭️ Load cancelled (user navigated away)")
      // Don't clear isLoading on cancellation - another load should be in progress
    } catch let urlError as URLError where urlError.code == .cancelled {
      logger.info("⏭️ Request cancelled (user navigated away)")
      // Don't clear isLoading on cancellation - another load should be in progress
    } catch {
      logger.error("❌ Dashboard local load failed: \(error.localizedDescription)")
      self.error = DashboardError.dataLoadFailed(underlying: error)
      // Always clear loading state on completion
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
        settings = await LocalStore.shared.storeActor.fetchUserSettings(userId: userId)
        updateUserAvatarFromSettings()
      }

      if snapshots.isEmpty {
        snapshots = await LocalStore.shared.storeActor.fetchSnapshots(userId: userId)
      }

      // Load recurring shifts if not cached
      if recurringShifts.isEmpty {
        recurringShifts = await LocalStore.shared.storeActor.fetchRecurringShifts(userId: userId)
      }

      // Calculate date ranges for displayed month
      let displayYM = (year: displayYear, month: displayMonth)
      let previousYM = Date.previousYearMonth(from: displayYM)

      let displayStartDate = Date.firstDayOfMonthDate(year: displayYM.year, month: displayYM.month)
      let displayEndDate = Date.lastDayOfMonthDate(year: displayYM.year, month: displayYM.month)
      let previousStartDate = Date.firstDayOfMonthDate(
        year: previousYM.year, month: previousYM.month)
      let previousEndDate = Date.lastDayOfMonthDate(year: previousYM.year, month: previousYM.month)

      // Load shifts from local repositories
      let displayShifts = await LocalStore.shared.storeActor.fetchShifts(
        userId: userId,
        startDate: displayStartDate,
        endDate: displayEndDate
      )

      let fetchedPreviousShifts = await LocalStore.shared.storeActor.fetchShifts(
        userId: userId,
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

      let capturedRecurring = recurringShifts
      let capturedSnapshots = snapshots
      let capturedCurrency = currentSettings.currency ?? "kr"

      let result = await Task.detached(priority: .userInitiated) {
        let displayComputed = PayrollEngine.computeShiftsForMonth(
          year: displayYM.year,
          month: displayYM.month,
          shifts: displayShifts,
          recurring: capturedRecurring,
          snapshots: capturedSnapshots,
          settings: currentSettings
        )

        let previousComputed = PayrollEngine.computeShiftsForMonth(
          year: previousYM.year,
          month: previousYM.month,
          shifts: fetchedPreviousShifts,
          recurring: capturedRecurring,
          snapshots: capturedSnapshots,
          settings: currentSettings
        )

        let dashboardData = Self.buildDashboardDataOffMain(
          displayedMonthShifts: displayComputed,
          previousMonthShifts: previousComputed,
          settings: currentSettings,
          displayYM: displayYM,
          previousYM: previousYM,
          currency: capturedCurrency
        )

        return (display: displayComputed, previous: previousComputed, dashboardData: dashboardData)
      }.value

      self.displayedMonthShifts = result.display
      self.previousMonthShifts = result.previous

      // Cache the computed results
      let displayKey = "\(displayYM.year)-\(displayYM.month)"
      let previousKey = "\(previousYM.year)-\(previousYM.month)"
      monthCache[displayKey] = MonthCacheEntry(
        year: displayYM.year,
        month: displayYM.month,
        shifts: result.display,
        timestamp: Date()
      )
      monthCache[previousKey] = MonthCacheEntry(
        year: previousYM.year,
        month: previousYM.month,
        shifts: result.previous,
        timestamp: Date()
      )

      // Evict old cache entries if over limit
      evictCacheIfNeeded()

      // Build dashboard data and clear loading state
      self.dashboardData = result.dashboardData
      self.maybeTriggerCelebration()
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

      // Read from local store off the main actor
      let fetchedShifts = await LocalStore.shared.storeActor.fetchShifts(
        userId: userId,
        startDate: startDate,
        endDate: endDate
      )

      // Compute shifts with payroll
      guard let settings = self.settings else {
        prefetchTasks.remove(key)
        return
      }

      let capturedRecurring = recurringShifts
      let capturedSnapshots = snapshots

      let computedShifts = await Task.detached(priority: .utility) {
        PayrollEngine.computeShiftsForMonth(
          year: year,
          month: month,
          shifts: fetchedShifts,
          recurring: capturedRecurring,
          snapshots: capturedSnapshots,
          settings: settings
        )
      }.value

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

  // MARK: - Private Methods

  /// Get current authenticated user ID and update user profile data
  private func getCurrentUserId() async throws -> String? {
    // Use AuthSessionManager to prevent concurrent refresh race conditions
    let session = try await AuthSessionManager.shared.getSession()
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

    return user.normalizedId
  }

  /// Update user avatar URL from settings (called after settings are loaded)
  private func updateUserAvatarFromSettings() {
    self.userAvatarUrl = settings?.profile_picture_url
  }

  /// Trigger shift completion celebration for current month (if applicable)
  private func maybeTriggerCelebration() {
    guard let userId = cachedUserId, !userId.isEmpty else { return }
    guard let dashboardData = dashboardData, let settings = settings else { return }

    let current = Date.currentYearMonth()
    guard displayYear == current.year && displayMonth == current.month else { return }

    let display = CelebrationDetector.displayValue(dashboardData: dashboardData)
    let currency = settings.currency ?? dashboardData.currency

    ShiftCompletionCelebrationManager.shared.checkForCelebration(
      userId: userId,
      month: current,
      shifts: displayedMonthShifts,
      displayValue: display.value,
      displayTaxEnabled: display.taxEnabled,
      currency: currency,
      includeVirtual: true
    )
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
    let payrollDate = calculatePayrollDate(
      year: displayYM.year, month: displayYM.month, day: payrollDay)
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
    let percentChange: Double? =
      prevTotals.gross > 0
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
      previousMonthName: previousMonthName,
      currency: settings?.currency ?? "kr"
    )
  }

  /// Build dashboard data off the main actor to avoid blocking animations.
  nonisolated private static func buildDashboardDataOffMain(
    displayedMonthShifts: [ShiftWithComputations],
    previousMonthShifts: [ShiftWithComputations],
    settings: UserSettings,
    displayYM: (year: Int, month: Int),
    previousYM: (year: Int, month: Int),
    currency: String
  ) -> DashboardData {
    let today = todayISO()
    let now = Date()
    let payrollDay = settings.effectivePayrollDay
    let halfTaxMonth = settings.half_tax_month

    let payrollDate = PayrollDateAdjuster.adjustPayrollDate(
      payrollDay: payrollDay,
      month: displayYM.month,
      year: displayYM.year
    )
    let payrollHasPassed = now > payrollDate

    let prevTotals = PayrollEngine.summarizeShiftTotals(
      shifts: previousMonthShifts,
      halfTaxMonth: halfTaxMonth,
      earningsMonth: previousYM.month,
      now: now
    )
    let prevTaxEnabled = previousMonthShifts.first?.taxEnabled ?? false
    let prevTax: Double? = prevTaxEnabled ? prevTotals.gross - prevTotals.net : nil

    let displayTotals = PayrollEngine.summarizeShiftTotals(
      shifts: displayedMonthShifts,
      halfTaxMonth: halfTaxMonth,
      earningsMonth: displayYM.month,
      now: now
    )
    let displayTaxEnabled = displayedMonthShifts.first?.taxEnabled ?? false

    let completedShifts = displayedMonthShifts.filter { shift in
      Date.hasShiftEnded(
        shiftDate: shift.shiftDate,
        startTime: shift.startTime,
        endTime: shift.endTime,
        referenceDate: now
      )
    }
    let plannedShifts = displayedMonthShifts.filter { $0.shiftDate > today }

    let percentChange: Double? =
      prevTotals.gross > 0
      ? ((displayTotals.gross - prevTotals.gross) / prevTotals.gross) * 100
      : nil

    let current = Date.currentYearMonth()
    let isViewingCurrentMonth = displayYM.year == current.year && displayYM.month == current.month

    let featuredShift: ShiftWithComputations?
    let isFeaturedShiftToday: Bool
    let featuredShiftIsBestShift: Bool

    if isViewingCurrentMonth {
      featuredShift = displayedMonthShifts.first { $0.shiftDate >= today }
      isFeaturedShiftToday = featuredShift?.shiftDate == today
      featuredShiftIsBestShift = false
    } else {
      featuredShift = findBestShiftStatic(in: displayedMonthShifts)
      isFeaturedShiftToday = false
      featuredShiftIsBestShift = true
    }

    let displayMonthName = monthNameStatic(year: displayYM.year, month: displayYM.month)
    let previousMonthName = monthNameStatic(year: previousYM.year, month: previousYM.month)

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
      previousMonthName: previousMonthName,
      currency: currency
    )
  }

  nonisolated private static func monthNameStatic(year: Int, month: Int) -> String {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = 1
    guard let date = gregorianCalendar.date(from: components) else { return "" }
    return FormatterCache.monthNameFormatter(locale: .appLocale).string(from: date)
  }

  nonisolated private static func findBestShiftStatic(in shifts: [ShiftWithComputations])
    -> ShiftWithComputations?
  {
    guard !shifts.isEmpty else { return nil }

    let maxGross = shifts.map { $0.grossPay }.max() ?? 0
    guard maxGross > 0 else { return shifts.first }

    let bestShifts =
      shifts
      .filter { $0.grossPay == maxGross }
      .sorted { $0.shiftDate < $1.shiftDate }

    return bestShifts.first
  }

  // MARK: - Shift Operations

  /// Whether a shift update is in progress
  @Published private(set) var isUpdatingShift = false

  /// Get tariff supplement rules for a specific shift date
  /// Used by ShiftDetailsSheet to show applicable tariff rules
  /// - Parameter shiftDate: ISO date string (YYYY-MM-DD)
  /// - Returns: Array of supplement rules from the applicable snapshot
  func getTariffRules(for shiftDate: String) -> [SupplementRule] {
    guard let snapshot = SnapshotsService.snapshotForDate(shiftDate, from: snapshots) else {
      return []
    }
    return snapshot.effectiveSupplements
  }

  /// Get a recurring shift by ID
  /// - Parameter id: The recurring shift ID
  /// - Returns: The recurring shift if found
  func getRecurringShift(id: String) -> RecurringShiftRow? {
    recurringShiftsRepository.getRecurringShift(id: id)
  }

  /// Update a shift with new date/time values
  /// - Parameter editResult: The result from the shift edit form
  func updateShift(_ editResult: ShiftEditResult) async {
    // Prevent duplicate taps
    guard !isUpdatingShift else { return }

    isUpdatingShift = true
    logger.info("📝 Updating shift \(editResult.shiftId)")

    do {
      // Parse the new date
      guard let newDate = Date.fromISODateString(editResult.shiftDate) else {
        logger.error("Invalid date format: \(editResult.shiftDate)")
        isUpdatingShift = false
        return
      }

      if editResult.isVirtualShiftConversion {
        // Virtual shift conversion:
        // 1. Add exclusion to the recurring shift for the original date
        // 2. Create a new regular shift with the edited values
        logger.info("🔄 Converting virtual shift to regular shift")

        // Get user ID
        guard let recurringId = editResult.recurringId,
          let userId = cachedUserId
        else {
          logger.error("Missing recurringId or userId for virtual shift conversion")
          isUpdatingShift = false
          return
        }

        // Step 1: Add exclusion for the original date
        try await RecurringShiftsRepository.shared.addExclusion(
          id: recurringId,
          date: editResult.originalDate
        )
        logger.info("✅ Added exclusion for \(editResult.originalDate)")

        // Step 2: Create a new regular shift with the edited values
        _ = try await shiftsRepository.createShift(
          userId: userId,
          shiftDate: newDate,
          startTime: editResult.startTime,
          endTime: editResult.endTime,
          customSupplements: editResult.customSupplements
        )
        logger.info("✅ Created new shift on \(editResult.shiftDate)")

      } else {
        // Regular shift update - just update the existing shift
        _ = try await shiftsRepository.updateShift(
          id: editResult.shiftId,
          shiftDate: newDate,
          startTime: editResult.startTime,
          endTime: editResult.endTime,
          customSupplements: editResult.customSupplements
        )
        logger.info("✅ Updated shift \(editResult.shiftId)")
      }

      // Reload to show the changes
      await reloadFromLocal()

      // Post notification for other views
      NotificationCenter.default.post(name: .shiftsDidChange, object: nil)

    } catch {
      logger.error("❌ Failed to update shift: \(error.localizedDescription)")
    }

    isUpdatingShift = false
  }

  // MARK: - Helper Methods

  /// Calculate the adjusted payroll date for a given month
  /// Adjusts backwards if the date falls on a weekend, Monday, or Norwegian public holiday
  private func calculatePayrollDate(year: Int, month: Int, day: Int) -> Date {
    return PayrollDateAdjuster.adjustPayrollDate(payrollDay: day, month: month, year: year)
  }

  private func monthName(year: Int, month: Int) -> String {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = 1
    guard let date = Self.gregorianCalendar.date(from: components) else { return "" }
    return FormatterCache.monthNameFormatter(locale: .appLocale).string(from: date)
  }

  /// Find the best (highest earnings) shift in a collection
  /// Returns the first shift chronologically if multiple have the same max earnings
  private func findBestShift(in shifts: [ShiftWithComputations]) -> ShiftWithComputations? {
    guard !shifts.isEmpty else { return nil }

    // Find max gross earnings
    let maxGross = shifts.map { $0.grossPay }.max() ?? 0
    guard maxGross > 0 else { return shifts.first }

    // Get all shifts with max earnings, sorted chronologically
    let bestShifts =
      shifts
      .filter { $0.grossPay == maxGross }
      .sorted { $0.shiftDate < $1.shiftDate }

    return bestShifts.first
  }
}
