import Combine
import Foundation
import Observation
import UIKit
import os.log

extension ShiftsViewModel {

  // MARK: - Public Methods

  /// Get tariff supplement rules for a specific shift date
  /// Used by CustomSupplementsEditorSheet to show applicable tariff rules
  /// - Parameter shiftDate: ISO date string (YYYY-MM-DD)
  /// - Returns: Array of supplement rules from the applicable snapshot
  func getTariffRules(for shiftDate: String) -> [SupplementRule] {
    guard let snapshot = SnapshotsService.snapshotForDate(shiftDate, from: snapshots) else {
      return []
    }
    return snapshot.effectiveSupplements
  }

  /// Load all shifts data for current month (initial load)
  /// Reads from local repositories only - sync is triggered by AppCoordinator
  func loadShifts() async {
    guard isActiveTabVisible else {
      displayedMonthLoadPending = true
      return
    }

    // Sync tracking with current month context values
    lastObservedYear = monthContext.displayYear
    lastObservedMonth = monthContext.displayMonth

    // Clear all caches on full reload (including cachedUserId for impersonation support)
    monthCache.removeAll()
    cancelPrefetchTasks()
    cachedUserId = nil
    resetScheduleDependencies()

    if await loadShiftsFromLocal() {
      localDataNeedsReload = false
      displayedMonthLoadPending = false
    }

    // Seed adjacent months after the initial local load so first navigation can use cache.
    prefetchNeighboringMonths()
  }

  /// Refresh shifts data via sync then local reload
  /// Called by pull-to-refresh - triggers network sync, then reloads from local
  func refresh() async {
    // SwiftUI .refreshable can cancel the parent task when the view hierarchy changes.
    // Run refresh work in an unstructured task so sync can complete reliably.
    let refreshTask = Task { @MainActor [weak self] in
      guard let self else {
        return
      }
      await performRefresh()
    }

    _ = await refreshTask.result
  }

  /// Performs pull-to-refresh sync and local reload.
  private func performRefresh() async {
    kScheduleLogger.info("🔄 Pull-to-refresh: triggering sync then local reload")

    // Store current data as fallback
    let previousShifts = shifts

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

      if case .failed(let errorMessage) = syncResult.outcome {
        kScheduleLogger.warning("⚠️ Sync had issues: \(errorMessage)")
        // Continue anyway - we still want to show local data
      }

      // Clear in-memory caches so we pick up synced data
      monthCache.removeAll()
      cancelPrefetchTasks()
      invalidateSharedPayrollReadCache(for: userId)
      resetScheduleDependencies()

      // Reload from local repositories
      if await loadShiftsFromLocal() {
        localDataNeedsReload = false
      }

      // Prefetch neighboring months
      prefetchNeighboringMonths()

      kScheduleLogger.info(
        "✅ Pull-to-refresh complete (synced \(syncResult.totalRowsProcessed) rows)")

    } catch {
      kScheduleLogger.error("❌ Pull-to-refresh failed: \(error.localizedDescription)")

      // Restore previous data so UI doesn't break
      self.shifts = previousShifts

      kScheduleLogger.info("📦 Restored previous data after refresh failure")
    }
  }

  /// Reload shifts from local data without triggering sync
  /// Called when shifts change locally (e.g., after adding a shift)
  func reloadFromLocal() async {
    guard isActiveTabVisible else {
      markLocalDataStale()
      return
    }

    let reloadID = UUID()
    let task: Task<Void, Never> = Task { @MainActor [weak self] in
      guard let self else {
        return
      }
      await performReloadFromLocal()
    }

    localReloadTask = task
    localReloadID = reloadID
    await task.value
    if localReloadID == reloadID {
      localReloadTask = nil
      localReloadID = nil
    }
  }

  private func performReloadFromLocal() async {
    kScheduleLogger.info("🔄 Reloading shifts from local data")

    // Clear all caches to pick up new data
    // Also critical for impersonation: cachedUserId must be refreshed from current session
    monthCache.removeAll()
    cancelPrefetchTasks()
    invalidateSharedPayrollReadCache()
    cachedUserId = nil  // Force re-fetch user ID from session (critical for impersonation)
    resetScheduleDependencies()

    // Reload from local repositories
    let didReload = await loadShiftsFromLocal()
    localDataNeedsReload = !didReload
    if didReload {
      displayedMonthLoadPending = false
    }

    // Prefetch neighboring months
    if didReload {
      prefetchNeighboringMonths()
    }

    if didReload {
      kScheduleLogger.info("✅ Shifts reloaded from local")
    } else {
      kScheduleLogger.warning("⚠️ Shifts local reload did not complete")
    }
  }

  func markLocalDataStale() {
    localDataNeedsReload = true
    displayedMonthLoadPending = true
    scheduleDependenciesLoaded = false
    invalidateSharedPayrollReadCache()
  }

  func handleExternalShiftsDidChange(_ context: ShiftChangeContext) async {
    invalidateSharedPayrollReadCache()

    guard context.canUseTargetedInvalidation else {
      markLocalDataStale()
      guard isActiveTabVisible else {
        return
      }
      await reloadFromLocal()
      return
    }

    let affectedKeys = scheduleCacheKeysAffected(by: context.affectedMonths)
    invalidateMonthCacheEntries(for: affectedKeys, reason: "shift-change")

    let currentDisplayKey = monthCacheKey(year: displayYear, month: displayMonth)
    guard affectedKeys.contains(currentDisplayKey) else {
      return
    }

    displayedMonthLoadPending = true
    guard isActiveTabVisible else {
      return
    }
    await reloadFromLocalIfStale()
  }

  private func monthCacheKey(year: Int, month: Int) -> String {
    "\(year)-\(month)"
  }

  private func monthCacheKey(_ month: ShiftChangeAffectedMonth) -> String {
    monthCacheKey(year: month.year, month: month.month)
  }

  private func scheduleCacheKeysAffected(
    by affectedMonths: Set<ShiftChangeAffectedMonth>
  ) -> Set<String> {
    Set(
      HomeScheduleAffectedMonthResolver.scheduleDisplayMonthsAffected(by: affectedMonths)
        .map(monthCacheKey)
    )
  }

  private func invalidateMonthCacheEntries(for keys: Set<String>, reason: String) {
    guard !keys.isEmpty else {
      return
    }

    var removedCount = 0
    for key in keys {
      if monthCache.removeValue(forKey: key) != nil {
        removedCount += 1
      }
      prefetchTasks.removeValue(forKey: key)?.cancel()
    }

    if removedCount > 0 {
      kScheduleLogger.info("♻️ Invalidated \(removedCount) schedule cache entries (\(reason))")
    }
  }

  func setActiveTabVisible(_ isVisible: Bool) {
    guard isActiveTabVisible != isVisible else {
      return
    }

    isActiveTabVisible = isVisible

    if !isVisible {
      activeNavigationTask?.cancel()
      cancelPrefetchTasks()
      isLoading = false
      return
    }

    let displayKey = "\(displayYear)-\(displayMonth)"
    let hasValidDisplayedCache = monthCache[displayKey]?.isValid == true
    let committedMatchesDisplayed = committedYear == displayYear && committedMonth == displayMonth
    if localDataNeedsReload || displayedMonthLoadPending || !hasValidDisplayedCache
      || !committedMatchesDisplayed
    {
      Task {
        await reloadFromLocalIfStale()
      }
    }
  }

  /// Reload local storage only when an external change made cached month data stale.
  /// Used on Schedule tab re-entry to preserve hot month cache when nothing changed.
  func reloadFromLocalIfStale() async {
    guard isActiveTabVisible else {
      displayedMonthLoadPending = true
      return
    }

    if let localReloadTask {
      await localReloadTask.value
      return
    }

    guard localDataNeedsReload else {
      let targetYear = displayYear
      let targetMonth = displayMonth

      if applyCachedDisplayedMonthIfValid(year: targetYear, month: targetMonth) {
        kScheduleLogger.info("📦 Preserved valid schedule cache on tab re-entry")
        displayedMonthLoadPending = false
        prefetchNeighboringMonths()
        return
      }

      kScheduleLogger.info("🔄 Schedule cache unavailable on tab re-entry, loading displayed month")
      await loadShiftsForDisplayedMonth(
        showLoadingState: false,
        targetYear: targetYear,
        targetMonth: targetMonth
      )
      displayedMonthLoadPending = false
      prefetchNeighboringMonths()
      return
    }

    await reloadFromLocal()
  }

  // MARK: - Private Loading Methods

  private func loadScheduleDependencies(  // swiftlint:disable:this type_contents_order
    for userId: String,
    forceReload: Bool = false
  ) async {
    guard forceReload || !scheduleDependenciesLoaded else {
      return
    }

    let context: PayrollReadContext = await monthlyPayrollReadService.loadContextUsingStoreActor(
      for: userId
    )
    applyScheduleDependencies(context)
  }

  private func applyScheduleDependencies(_ context: PayrollReadContext) {
    settings = context.settings
    if let userSettings = settings {
      currency = userSettings.currency ?? "kr"
    }
    snapshots = context.snapshots
    recurringShifts = context.recurringShifts
    activeJobs = context.jobs
    scheduleDependenciesLoaded = true
  }

  private func resetScheduleDependencies() {
    settings = nil
    snapshots = []
    recurringShifts = []
    activeJobs = []
    scheduleDependenciesLoaded = false
  }

  private func invalidateSharedPayrollReadCache(for userId: String? = nil) {
    monthlyPayrollReadService.invalidateSharedCache(for: userId ?? cachedUserId)
  }

  private func resolveCachedUserId() async throws -> String {
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
    return userId
  }

  /// Load raw data for the full visible calendar range (so out-of-month days show data).
  private func loadVisibleMonthWindow(
    for userId: String,
    year: Int,
    month: Int
  ) async -> PayrollRawWindowData {
    let windowData = await monthlyPayrollReadService.loadRawWindow(
      for: userId,
      window: .visibleCalendarMonth(year: year, month: month)
    )
    kScheduleLogger.info("📋 Loaded shifts for \(year)-\(month): \(windowData.shifts.count)")
    kScheduleLogger.info("📋 Loaded events for \(year)-\(month): \(windowData.events.count)")
    return windowData
  }

  /// Compute payroll for the visible month, cache it, and commit it as the displayed month.
  private func computeAndCommitMonth(
    year: Int,
    month: Int,
    window: PayrollRawWindowData,
    payrollSettings: UserSettings
  ) async throws -> [ShiftWithComputations] {
    let visibleRange = Date.visibleCalendarRange(year: year, month: month)
    let rawShifts = window.shifts
    let displayEvents = window.events
    let recurringSnapshot = recurringShifts  // swiftlint:disable:this explicit_type_interface
    let snapshotsSnapshot = snapshots  // swiftlint:disable:this explicit_type_interface
    let activeJobsSnapshot = activeJobs  // swiftlint:disable:this explicit_type_interface
    let computedShifts = try await Self.computeShiftsForMonthOffMain(
      MonthComputationInput(
        year: year,
        month: month,
        shifts: rawShifts,
        recurringShifts: recurringSnapshot,
        snapshots: snapshotsSnapshot,
        settings: payrollSettings,
        visibleRange: visibleRange,
        jobs: activeJobsSnapshot
      )
    )
    try Task.checkCancellation()

    // Cache the computed results
    let displayKey = "\(year)-\(month)"
    monthCache[displayKey] = MonthCacheEntry(
      year: year,
      month: month,
      shifts: computedShifts,
      events: displayEvents,
      visibleRange: visibleRange,
      timestamp: Date()
    )

    // Evict old cache entries if over limit
    evictCacheIfNeeded()

    // ATOMIC UPDATE: Set shifts, events, and committed state together.
    applyCommittedMonthSnapshot(
      shifts: computedShifts,
      events: displayEvents,
      year: year,
      month: month
    )

    return computedShifts
  }

  /// Load shifts data from local repositories
  @discardableResult
  private func loadShiftsFromLocal() async -> Bool {
    isLoading = true
    error = nil

    do {
      let userId = try await resolveCachedUserId()

      await loadScheduleDependencies(for: userId)
      kScheduleLogger.info("📋 Loaded settings: \(self.settings != nil ? "found" : "nil")")
      kScheduleLogger.info("📋 Loaded snapshots: \(self.snapshots.count)")
      kScheduleLogger.info("📋 Loaded recurring: \(self.recurringShifts.count)")

      // The window covers the displayed month plus the out-of-month padding days shown in the calendar
      let displayYM = (year: displayYear, month: displayMonth)

      let displayWindowData = await loadVisibleMonthWindow(
        for: userId, year: displayYM.year, month: displayYM.month)

      // Check if we have settings to compute payroll
      guard let currentSettings = self.settings else {
        kScheduleLogger.info("📭 No local settings yet - waiting for sync (userId: \(userId))")
        self.isLoading = false
        return false
      }

      let computedShifts = try await computeAndCommitMonth(
        year: displayYM.year,
        month: displayYM.month,
        window: displayWindowData,
        payrollSettings: currentSettings
      )

      self.isLoading = false

      kScheduleLogger.info(
        "📊 Loaded shifts from local: \(computedShifts.count) shifts"
      )

      return true

    } catch is CancellationError {
      kScheduleLogger.info("⏭️ Load cancelled (user navigated away)")
      return false
    } catch {
      kScheduleLogger.error("❌ Shifts local load failed: \(error.localizedDescription)")
      self.error = ShiftsError.dataLoadFailed(underlying: error)
      self.isLoading = false
      return false
    }
  }

  /// Load shifts data for the currently displayed month
  /// - Parameters:
  ///   - showLoadingState: Whether to show loading indicator
  ///   - targetYear: The year to load (for atomic commit)
  ///   - targetMonth: The month to load (for atomic commit)
  func loadShiftsForDisplayedMonth(
    showLoadingState: Bool = true, targetYear: Int? = nil, targetMonth: Int? = nil
  ) async {
    if showLoadingState {
      isLoading = true
    }
    error = nil

    // Use provided targets or fall back to current display values
    let loadYear = targetYear ?? displayYear
    let loadMonth = targetMonth ?? displayMonth

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

      await loadScheduleDependencies(for: userId)

      // Calculate date range for displayed month (includes out-of-month padding days visible in calendar)
      let displayYM = (year: loadYear, month: loadMonth)
      let visibleRange = Date.visibleCalendarRange(year: displayYM.year, month: displayYM.month)

      // Load raw data for the full visible calendar range (so out-of-month days show data)
      let displayWindowData = await monthlyPayrollReadService.loadRawWindow(
        for: userId,
        window: .visibleCalendarMonth(year: displayYM.year, month: displayYM.month)
      )
      let displayShifts = displayWindowData.shifts
      let displayEvents = displayWindowData.events

      // Ensure settings are available
      guard let currentSettings = self.settings else {
        kScheduleLogger.info("📭 No local settings yet - waiting for sync")
        self.isLoading = false
        return
      }

      let recurringSnapshot = recurringShifts  // swiftlint:disable:this explicit_type_interface
      let snapshotsSnapshot = snapshots  // swiftlint:disable:this explicit_type_interface
      let activeJobsSnapshot = activeJobs  // swiftlint:disable:this explicit_type_interface
      let computedShifts = try await Self.computeShiftsForMonthOffMain(
        MonthComputationInput(
          year: displayYM.year,
          month: displayYM.month,
          shifts: displayShifts,
          recurringShifts: recurringSnapshot,
          snapshots: snapshotsSnapshot,
          settings: currentSettings,
          visibleRange: visibleRange,
          jobs: activeJobsSnapshot
        )
      )
      try Task.checkCancellation()

      // Cache the computed results
      let displayKey = "\(displayYM.year)-\(displayYM.month)"
      monthCache[displayKey] = MonthCacheEntry(
        year: displayYM.year,
        month: displayYM.month,
        shifts: computedShifts,
        events: displayEvents,
        visibleRange: visibleRange,
        timestamp: Date()
      )

      // Evict old cache entries if over limit
      evictCacheIfNeeded()

      // ATOMIC UPDATE: Set shifts, events, and committed state together.
      applyCommittedMonthSnapshot(
        shifts: computedShifts,
        events: displayEvents,
        year: loadYear,
        month: loadMonth
      )

      self.isLoading = false

    } catch is CancellationError {
      kScheduleLogger.info("⏭️ Load cancelled (user navigated away)")
    } catch {
      kScheduleLogger.error("❌ Shifts load failed: \(error.localizedDescription)")
      self.error = ShiftsError.dataLoadFailed(underlying: error)
      self.isLoading = false
    }
  }

  // MARK: - Next Upcoming Shift

  /// Find the next upcoming shift from the current shifts.
  func findNextUpcomingShift(in shifts: [ShiftWithComputations]) -> ShiftWithComputations? {
    let now = Date()
    let calendar = Calendar.gregorianCurrent

    // Filter to shifts that haven't ended yet
    let upcomingShifts = shifts.filter { shift in
      guard let shiftDate = Date.fromISODateString(shift.shiftDate),
        let endTime = parseTime(shift.endTime)
      else {
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

      guard let shiftEnd = calendar.date(from: shiftEndComponents) else {
        return false
      }
      return shiftEnd > now
    }

    // Sort by start datetime and take the first one
    let sorted = upcomingShifts.sorted { a, b in
      guard let dateA = Date.fromISODateString(a.shiftDate),
        let dateB = Date.fromISODateString(b.shiftDate),
        let timeA = parseTime(a.startTime),
        let timeB = parseTime(b.startTime)
      else {
        return false
      }

      var componentsA = calendar.dateComponents([.year, .month, .day], from: dateA)
      componentsA.hour = calendar.component(.hour, from: timeA)
      componentsA.minute = calendar.component(.minute, from: timeA)

      var componentsB = calendar.dateComponents([.year, .month, .day], from: dateB)
      componentsB.hour = calendar.component(.hour, from: timeB)
      componentsB.minute = calendar.component(.minute, from: timeB)

      guard let startA = calendar.date(from: componentsA),
        let startB = calendar.date(from: componentsB)
      else {
        return false
      }

      return startA < startB
    }

    return sorted.first
  }

  private func parseTime(_ time: String) -> Date? {
    kScheduleHourMinuteFormatter.date(from: String(time.prefix(5)))
  }

  // MARK: - Conflict Detection

  /// Update conflict detection for the given shifts
  /// Sets conflictingShiftIds, excludedFromTotalIds, and conflictDates
  func updateConflictDetection(for shifts: [ShiftWithComputations]) {
    let analysis = ConflictExclusion.analyze(shifts: shifts)

    self.conflictingShiftIds = analysis.conflictingIds
    self.excludedFromTotalIds = analysis.excludedIds
    self.conflictDates = analysis.conflictDates

    // Update the month context so MainTabView can show the conflict indicator on the list button
    monthContext.hasConflictsInMonth = !analysis.conflictDates.isEmpty

    if !analysis.conflictingIds.isEmpty {
      kScheduleLogger.info(
        """
        ⚠️ Found \(analysis.conflictingIds.count) conflicting shifts on \(analysis.conflictDates.count) dates, \
        \(analysis.excludedIds.count) excluded from totals
        """
      )
    }

    updateSelectionSummary()
  }

  // MARK: - Prefetching

  /// Prefetch neighboring months in the background
  func prefetchNeighboringMonths() {
    guard isActiveTabVisible else {
      return
    }

    let displayYM = (year: displayYear, month: displayMonth)

    // Calculate previous and next months
    let previousYM = Date.previousYearMonth(from: displayYM)
    let nextYM = nextYearMonth(from: displayYM)

    // Prefetch both neighbors
    prefetchMonthInBackground(year: previousYM.year, month: previousYM.month)
    prefetchMonthInBackground(year: nextYM.year, month: nextYM.month)
  }

  /// Prefetch a single month's shift data with full payroll computation
  /// Computes payroll upfront so navigation is instant
  private func prefetchMonthInBackground(year: Int, month: Int) {
    let key = "\(year)-\(month)"

    // Skip if already have computed cache
    if let cached = monthCache[key], cached.isValid {
      return
    }

    // Skip if already prefetching
    if prefetchTasks[key] != nil {
      return
    }

    prefetchTasks[key] = Task { [weak self] in
      guard let self else {
        return
      }
      defer { prefetchTasks.removeValue(forKey: key) }

      guard let userId = cachedUserId,
        let currentSettings = settings
      else {
        return
      }

      // Get visible calendar range (includes out-of-month padding days)
      let visibleRange = Date.visibleCalendarRange(year: year, month: month)

      // Read raw data for the full visible calendar range
      let fetchedWindow = await monthlyPayrollReadService.loadRawWindow(
        for: userId,
        window: .visibleCalendarMonth(year: year, month: month)
      )

      let recurringSnapshot = recurringShifts  // swiftlint:disable:this explicit_type_interface
      let snapshotsSnapshot = snapshots  // swiftlint:disable:this explicit_type_interface
      let activeJobsSnapshot = activeJobs  // swiftlint:disable:this explicit_type_interface

      do {
        try Task.checkCancellation()
        let computedShifts = try await Self.computeShiftsForMonthOffMain(
          MonthComputationInput(
            year: year,
            month: month,
            shifts: fetchedWindow.shifts,
            recurringShifts: recurringSnapshot,
            snapshots: snapshotsSnapshot,
            settings: currentSettings,
            visibleRange: visibleRange,
            jobs: activeJobsSnapshot
          )
        )

        guard !Task.isCancelled else {
          kScheduleLogger.info("⏭️ Prefetch cancelled for \(key)")
          return
        }

        // Store in full computed cache
        monthCache[key] = MonthCacheEntry(
          year: year,
          month: month,
          shifts: computedShifts,
          events: fetchedWindow.events,
          visibleRange: visibleRange,
          timestamp: Date()
        )

        // Evict old entries if needed
        evictCacheIfNeeded()

        kScheduleLogger.info("📦 Prefetched \(key): \(computedShifts.count) shifts (with payroll)")
      } catch is CancellationError {
        kScheduleLogger.info("⏭️ Prefetch cancelled for \(key)")
      } catch {
        kScheduleLogger.error("❌ Prefetch failed for \(key): \(error.localizedDescription)")
      }
    }
  }

  func cancelPrefetchTasks() {
    for task in prefetchTasks.values {
      task.cancel()
    }
    prefetchTasks.removeAll()
  }

  private nonisolated static func computeShiftsForMonthOffMain(
    _ input: MonthComputationInput
  ) async throws -> [ShiftWithComputations] {
    try Task.checkCancellation()

    let computeTask = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      return PayrollEngine.computeShiftsForMonth(
        .init(
          year: input.year,
          month: input.month,
          shifts: input.shifts,
          recurring: input.recurringShifts,
          snapshots: input.snapshots,
          settings: input.settings,
          visibleRange: input.visibleRange,
          jobs: input.jobs
        )
      )
    }

    do {
      return try await computeTask.value
    } catch {
      computeTask.cancel()
      throw error
    }
  }

  /// Get next year/month (handles year rollover)
  private func nextYearMonth(from current: (year: Int, month: Int)) -> (year: Int, month: Int) {
    if current.month == 12 {
      return (year: current.year + 1, month: 1)
    }
    return (year: current.year, month: current.month + 1)
  }

  // MARK: - Private Helpers

  /// Get current authenticated user ID
  func getCurrentUserId() async throws -> String? {
    do {
      // Use AuthSessionManager to prevent concurrent refresh race conditions
      let session = try await AuthSessionManager.shared.getSession()
      return session.normalizedUserId
    } catch {
      guard AuthSessionManager.shared.isTransientSessionResolutionError(error) else {
        throw error
      }

      if let offlineUserId = AuthSessionManager.shared.offlineUserIdFallback() {
        kScheduleLogger.info("Using offline user id fallback")
        return offlineUserId
      }

      throw error
    }
  }
}
