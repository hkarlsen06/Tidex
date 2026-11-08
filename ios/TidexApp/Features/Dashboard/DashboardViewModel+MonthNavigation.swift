import Combine
import Foundation
import Observation
import UIKit
import os.log  // swiftlint:disable:this sorted_imports

extension DashboardViewModel {

  // MARK: - Memory Management

  /// Handle memory warning by clearing the cache
  func handleMemoryWarning() {  // swiftlint:disable:this type_contents_order
    dashboardViewModelLogger.warning(
      "⚠️ Memory warning received - clearing month cache (\(self.monthCache.count) entries)")  // swiftlint:disable:this line_length multiline_arguments_brackets
    clearAllMonthCache(reason: "memory-warning")
  }

  /// Invalidate cache entries for the real current month.
  /// Keeps historical months hot while ensuring time-dependent current-month
  /// dashboard values are recomputed on next access.
  func invalidateCurrentMonthCache(reason: String) {  // swiftlint:disable:this type_contents_order
    let current = Date.currentYearMonth()  // swiftlint:disable:this explicit_type_interface
    let key = monthCacheKey(year: current.year, month: current.month)  // swiftlint:disable:this explicit_type_interface
    let removedCount = invalidateMonthCacheEntries(for: [key], reason: reason)  // swiftlint:disable:this explicit_type_interface line_length
    guard removedCount > 0 else { return }  // swiftlint:disable:this conditional_returns_on_newline

    dashboardViewModelLogger.info("♻️ Invalidated current-month cache (\(reason)): \(key)")

    // If the user is viewing the invalidated month, trigger a background
    // reload so the dashboard reflects updated time-based fields immediately.
    if displayYear == current.year, displayMonth == current.month {
      loadDashboardForDisplayedMonthNonBlocking()
    }
  }

  func monthCacheKey(year: Int, month: Int) -> String {  // swiftlint:disable:this type_contents_order
    "\(year)-\(month)"
  }

  func monthCacheKey(_ yearMonth: (year: Int, month: Int)) -> String {  // swiftlint:disable:this line_length type_contents_order
    monthCacheKey(year: yearMonth.year, month: yearMonth.month)
  }

  private func movingWindowCacheKeys(around displayYM: (year: Int, month: Int)) -> Set<String> {  // swiftlint:disable:this line_length type_contents_order
    let previousYM = Date.previousYearMonth(from: displayYM)  // swiftlint:disable:this explicit_type_interface
    let nextYM = nextYearMonth(from: displayYM)  // swiftlint:disable:this explicit_type_interface
    let previousPreviousYM = Date.previousYearMonth(from: previousYM)  // swiftlint:disable:this explicit_type_interface
    let nextPreviousYM = Date.previousYearMonth(from: nextYM)  // swiftlint:disable:this explicit_type_interface

    return Set([
      monthCacheKey(displayYM),
      monthCacheKey(previousYM),
      monthCacheKey(nextYM),
      monthCacheKey(previousPreviousYM),
      monthCacheKey(nextPreviousYM),
    ])
  }

  @discardableResult
  func invalidateMonthCacheEntries(for keys: Set<String>, reason: String) -> Int {  // swiftlint:disable:this line_length type_contents_order
    guard !keys.isEmpty else { return 0 }  // swiftlint:disable:this conditional_returns_on_newline

    incrementMonthCacheInvalidationTokens(for: keys)

    var removedCount = 0  // swiftlint:disable:this explicit_type_interface
    for key in keys {
      if monthCache.removeValue(forKey: key) != nil {
        removedCount += 1
      }
      prefetchTasks.removeValue(forKey: key)
    }

    if removedCount > 0 {
      dashboardViewModelLogger.info("♻️ Invalidated \(removedCount) dashboard cache entries (\(reason))")
    }

    return removedCount
  }

  func invalidateMovingWindowCache(reason: String) {  // swiftlint:disable:this type_contents_order
    let keys = movingWindowCacheKeys(around: (year: displayYear, month: displayMonth))  // swiftlint:disable:this explicit_type_interface line_length
    let removedCount = invalidateMonthCacheEntries(for: keys, reason: reason)  // swiftlint:disable:this explicit_type_interface line_length
    dashboardViewModelLogger.info(
      "♻️ Local dashboard reload invalidated \(removedCount)/\(keys.count) moving-window cache entries"
    )
  }

  func clearAllMonthCache(reason: String) {  // swiftlint:disable:this type_contents_order
    let keys = Set(monthCache.keys).union(Set(prefetchTasks.keys))  // swiftlint:disable:this explicit_type_interface
    incrementMonthCacheInvalidationTokens(for: keys)

    let removedCount = monthCache.count  // swiftlint:disable:this explicit_type_interface
    let prefetchCount = prefetchTasks.count  // swiftlint:disable:this explicit_type_interface
    monthCache.removeAll()
    prefetchTasks.removeAll()

    if removedCount > 0 || prefetchCount > 0 {
      dashboardViewModelLogger.info(
        "♻️ Cleared dashboard month cache (\(reason)): \(removedCount) entries, \(prefetchCount) prefetches"
      )
    }
  }

  func incrementMonthCacheInvalidationTokens(for keys: Set<String>) {  // swiftlint:disable:this line_length type_contents_order
    for key in keys {
      monthCacheInvalidationTokens[key, default: 0] += 1
    }
  }

  func monthCacheInvalidationToken(for key: String) -> Int {  // swiftlint:disable:this type_contents_order
    monthCacheInvalidationTokens[key] ?? 0
  }

  func isPrefetchCurrent(for key: String, token: Int) -> Bool {  // swiftlint:disable:this type_contents_order
    prefetchTasks[key] == token && monthCacheInvalidationToken(for: key) == token
  }

  func finishPrefetch(for key: String, token: Int) {  // swiftlint:disable:this type_contents_order
    guard prefetchTasks[key] == token else { return }  // swiftlint:disable:this conditional_returns_on_newline
    prefetchTasks.removeValue(forKey: key)
  }

  /// Evict least recently used cache entries if over limit
  func evictCacheIfNeeded() {  // swiftlint:disable:this type_contents_order
    guard monthCache.count > Self.maxCacheSize else { return }  // swiftlint:disable:this conditional_returns_on_newline

    // Sort by last accessed time (oldest first)
    let sortedKeys = monthCache.keys.sorted { key1, key2 in  // swiftlint:disable:this explicit_type_interface
      guard let entry1 = monthCache[key1], let entry2 = monthCache[key2] else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
      return entry1.lastAccessed < entry2.lastAccessed
    }

    // Remove oldest entries until we're under the limit
    let entriesToRemove = monthCache.count - Self.maxCacheSize  // swiftlint:disable:this explicit_type_interface
    for i in 0..<entriesToRemove {  // swiftlint:disable:this identifier_name
      let key = sortedKeys[i]  // swiftlint:disable:this explicit_type_interface
      monthCache.removeValue(forKey: key)
      dashboardViewModelLogger.info("🗑️ Evicted cache entry: \(key)")
    }
  }

  /// Navigate to the previous month (non-blocking)
  /// Delegates to SharedMonthContext - data reload happens via subscription
  func goToPreviousMonth() {  // swiftlint:disable:this explicit_acl type_contents_order
    monthContext.goToPreviousMonth()
  }

  /// Navigate to the next month (non-blocking)
  /// Delegates to SharedMonthContext - data reload happens via subscription
  func goToNextMonth() {  // swiftlint:disable:this explicit_acl type_contents_order
    monthContext.goToNextMonth()
  }

  /// Non-blocking month data loader
  /// Uses cache for instant display, fetches in background if needed
  func loadDashboardForDisplayedMonthNonBlocking() {  // swiftlint:disable:this cyclomatic_complexity function_body_length line_length type_contents_order
    guard isActiveTabVisible else {
      displayedMonthLoadPending = true
      dashboardViewModelLogger.info("⏸️ Deferring dashboard month load while Home tab is hidden")
      return
    }

    let targetYear = displayYear  // swiftlint:disable:this explicit_type_interface
    let targetMonth = displayMonth  // swiftlint:disable:this explicit_type_interface
    let displayKey = "\(targetYear)-\(targetMonth)"  // swiftlint:disable:this explicit_type_interface
    let previousYM = Date.previousYearMonth(from: (year: targetYear, month: targetMonth))  // swiftlint:disable:this explicit_type_interface line_length
    let previousKey = "\(previousYM.year)-\(previousYM.month)"  // swiftlint:disable:this explicit_type_interface
    let earlierKey = monthCacheKey(Date.previousYearMonth(from: previousYM))  // swiftlint:disable:this explicit_type_interface line_length

    let nextKey = monthCacheKey(Date.nextYearMonth(from: (year: targetYear, month: targetMonth)))

    // Require every month used to calculate the payout cards.
    if var displayCache = monthCache[displayKey], displayCache.isValid,
      var previousCache = monthCache[previousKey], previousCache.isValid,
      let earlierCache = monthCache[earlierKey], earlierCache.isValid,
      let nextCache = monthCache[nextKey], nextCache.isValid
    {
      // Use cached data - instant navigation!
      dashboardViewModelLogger.info("📦 Using cached data for \(displayKey)")
      // An earlier load for another month skips its result once the month changes,
      // so it never clears the loading state it set.
      activeNavigationTask?.cancel()
      self.isLoading = false
      self.displayedMonthShifts = displayCache.shifts
      self.displayedMonthEvents = displayCache.events
      self.previousMonthShifts = previousCache.shifts
      if let userId = cachedUserId {
        let adjustmentMonths = payrollPayoutMonthsToLoad(  // swiftlint:disable:this explicit_type_interface
          displayYM: (year: targetYear, month: targetMonth)
        )
        self.payrollAdjustmentsByPayoutMonth = fetchPayrollAdjustmentsForPayoutMonths(
          userId: userId,
          months: adjustmentMonths
        )
        self.previousPayrollAdjustments =
          payrollAdjustmentsByPayoutMonth[
            PayrollReadMonth(year: targetYear, month: targetMonth)
          ] ?? []
      }

      // Update last accessed time for LRU tracking
      displayCache.lastAccessed = Date()
      previousCache.lastAccessed = Date()
      monthCache[displayKey] = displayCache
      monthCache[previousKey] = previousCache

      if let currentSettings = settings {
        let capturedDisplay = displayCache.shifts  // swiftlint:disable:this explicit_type_interface
        let capturedDisplayEvents = displayCache.events  // swiftlint:disable:this explicit_type_interface
        let capturedPrevious = previousCache.shifts  // swiftlint:disable:this explicit_type_interface
        let capturedEarlier = earlierCache.shifts  // swiftlint:disable:this explicit_type_interface
        let capturedNext = nextCache.shifts
        let capturedCurrency = currentSettings.currency ?? "kr"  // swiftlint:disable:this explicit_type_interface
        let capturedJobs = displayJobs  // swiftlint:disable:this explicit_type_interface
        let capturedAdjustments = previousPayrollAdjustments  // swiftlint:disable:this explicit_type_interface
        let capturedAdjustmentsByPayoutMonth = payrollAdjustmentsByPayoutMonth  // swiftlint:disable:this explicit_type_interface line_length
        let capturedSnapshots = snapshots  // swiftlint:disable:this explicit_type_interface

        Task.detached(priority: .userInitiated) {  // swiftlint:disable:this closure_body_length
          [
            displayYM = (year: targetYear, month: targetMonth), previousYM, currentSettings,
            capturedCurrency, capturedJobs, capturedDisplay, capturedDisplayEvents,
            capturedPrevious, capturedEarlier, capturedNext, capturedAdjustments,
            capturedAdjustmentsByPayoutMonth, capturedSnapshots
          ] in
          let data = Self.buildDashboardDataOffMain(  // swiftlint:disable:this explicit_type_interface
            .init(
              displayedMonthShifts: capturedDisplay,
              displayedMonthEvents: capturedDisplayEvents,
              previousMonthShifts: capturedPrevious,
              previousPayrollAdjustments: capturedAdjustments,
              snapshots: capturedSnapshots,
              settings: currentSettings,
              displayYM: displayYM,
              previousYM: previousYM,
              currency: capturedCurrency,
              jobs: capturedJobs
            ))  // swiftlint:disable:this multiline_arguments_brackets
          let payrollCardSnapshot = Self.buildPayrollCardSnapshot(  // swiftlint:disable:this explicit_type_interface
            .init(
              displayedMonthShifts: capturedDisplay,
              previousMonthShifts: capturedPrevious,
              earlierMonthShifts: capturedEarlier,
              nextMonthShifts: capturedNext,
              payrollAdjustmentsByPayoutMonth: capturedAdjustmentsByPayoutMonth,
              previousPayrollAdjustments: capturedAdjustments,
              snapshots: capturedSnapshots,
              settings: currentSettings,
              jobs: capturedJobs,
              displayYM: displayYM,
              fallbackCurrency: data.currency,
              fallbackPayrollDate: data.payrollDate,
              fallbackPreviousGross: data.previousMonthGross,
              fallbackPreviousNet: data.previousMonthNet,
              fallbackPreviousTax: data.previousMonthTax,
              fallbackPreviousTaxEnabled: data.previousMonthTaxEnabled,
              fallbackPreviousHasPayrollAdjustments: data.previousMonthHasPayrollAdjustments,
              now: Date()
            ))  // swiftlint:disable:this multiline_arguments_brackets
          await MainActor.run {
            guard self.displayYear == targetYear, self.displayMonth == targetMonth else {
              dashboardViewModelLogger.info("⏭️ Skipping stale cached dashboard payload for \(displayKey)")
              return
            }
            self.applyDashboardData(data, payrollCardSnapshot: payrollCardSnapshot)
            self.maybeTriggerCelebration()
          }
        }
      } else {
        self.applyDashboardData(buildDashboardData())
        self.maybeTriggerCelebration()
      }

      // Still prefetch neighbors in background
      prefetchNeighboringMonths()
      return
    }

    // Cache miss - fetch in background while keeping the currently rendered
    // dashboard content visible (matches Shifts tab behavior).
    // This avoids a brief full-screen skeleton flash on first month change
    // after cold start or after cache expiry.
    dashboardViewModelLogger.info("🔄 Cache miss for \(displayKey), fetching in background...")

    self.isLoading = true

    // Cancel any previous navigation task
    activeNavigationTask?.cancel()

    // Start background fetch
    activeNavigationTask = Task { [weak self] in
      guard let self else { return }  // swiftlint:disable:this conditional_returns_on_newline

      do {
        // Check cancellation at the start
        try Task.checkCancellation()

        // Check if this task is still relevant (user hasn't navigated away)
        guard displayYear == targetYear,
          displayMonth == targetMonth
        else {
          dashboardViewModelLogger.info("⏭️ Skipping stale fetch for \(displayKey)")
          return
        }

        await loadDashboardFromLocal(
          showLoadingState: false,
          expectedDisplayYM: (year: targetYear, month: targetMonth)
        )

        // Check cancellation after async operation
        try Task.checkCancellation()

        // Check again after fetch - user may have navigated during the async operation
        guard displayYear == targetYear,
          displayMonth == targetMonth
        else {
          dashboardViewModelLogger.info("⏭️ Skipping prefetch - user navigated during fetch")
          return
        }

        // Prefetch neighbors after successful load
        prefetchNeighboringMonths()
      } catch is CancellationError {
        dashboardViewModelLogger.info("⏭️ Navigation task was cancelled for \(displayKey)")
      } catch {
        dashboardViewModelLogger.error("Navigation task failed for \(displayKey): \(error.localizedDescription)")
      }
    }
  }
}
