import Combine
import Foundation
import Observation
import UIKit
import os  // swiftlint:disable:this sorted_imports

extension DashboardViewModel {

  struct DashboardDataBuildInput {
    let displayedMonthShifts: [ShiftWithComputations]
    let displayedMonthEvents: [EventRow]
    let previousMonthShifts: [ShiftWithComputations]
    let previousPayrollAdjustments: [PayrollAdjustment]
    let snapshots: [WageSnapshot]
    let settings: UserSettings
    let displayYM: (year: Int, month: Int)
    let previousYM: (year: Int, month: Int)
    let currency: String
    let jobs: [Job]
  }

  struct PayrollCardVariantBuildInput {
    let displayedMonthShifts: [ShiftWithComputations]
    let previousMonthShifts: [ShiftWithComputations]
    /// Two months before the displayed month. Needed for periods such as the 16th to the 15th
    /// paid the month after.
    var earlierMonthShifts: [ShiftWithComputations] = []
    let nextMonthShifts: [ShiftWithComputations]
    let payrollAdjustmentsByPayoutMonth: [PayrollReadMonth: [PayrollAdjustment]]
    let previousPayrollAdjustments: [PayrollAdjustment]
    let snapshots: [WageSnapshot]
    let settings: UserSettings?
    let jobs: [Job]
    let displayYM: (year: Int, month: Int)
    let fallbackCurrency: String
    let fallbackPayrollDate: Date
    let fallbackPreviousGross: Double
    let fallbackPreviousNet: Double?
    let fallbackPreviousTax: Double?
    let fallbackPreviousTaxEnabled: Bool
    let fallbackPreviousHasPayrollAdjustments: Bool
    let now: Date
  }

  enum PayrollCardVariantSelectionMode {
    case primary
    case previousPassedCurrentMonth
  }

  func notifyShiftsDidChange(context: ShiftChangeContext = .fullReload) {  // swiftlint:disable:this line_length type_contents_order
    NotificationCenter.default.postShiftsDidChange(object: self, context: context)
  }

  func shiftChangeContext(  // swiftlint:disable:this type_contents_order
    for editResult: ShiftEditResult,
    existingShift: ShiftRow?
  ) -> ShiftChangeContext {
    var dates = [editResult.shiftDate, editResult.originalDate]  // swiftlint:disable:this explicit_type_interface

    if let existingShift {
      dates.append(existingShift.shift_date)
    }

    return .affecting(isoDates: dates)
  }

  func eventChangeContext(  // swiftlint:disable:this type_contents_order
    for editResult: EventEditResult,
    existingEvent: EventRow?
  ) -> ShiftChangeContext {
    var context = ShiftChangeContext.affecting(  // swiftlint:disable:this explicit_type_interface
      isoDateRangeStart: editResult.startDate,
      end: editResult.endDate
    )

    if let existingEvent {
      context = context.merging(
        .affecting(
          isoDateRangeStart: existingEvent.start_date,
          end: existingEvent.end_date
        ))  // swiftlint:disable:this multiline_arguments_brackets
    }

    return context
  }

  func applyDashboardData(_ data: DashboardData) {  // swiftlint:disable:this type_contents_order
    guard dashboardData != data else { return }  // swiftlint:disable:this conditional_returns_on_newline
    if dashboardData == nil {
      let log = OSLog(subsystem: "no.tidex.app", category: .pointsOfInterest)
      os_signpost(.event, log: log, name: "Local dashboard ready")
      Logger(subsystem: "no.tidex.app", category: "Launch").info(
        "[Launch] Local dashboard data applied")
    }
    dashboardData = data
  }

  func applyDashboardData(  // swiftlint:disable:this type_contents_order
    _ data: DashboardData,
    payrollCardSnapshot snapshot: DashboardPayrollCardSnapshot
  ) {
    if payrollCardSnapshot != snapshot {
      payrollCardSnapshot = snapshot
    }
    applyDashboardData(data)
  }

  // MARK: - Public Methods

  func setActiveTabVisible(_ isVisible: Bool) {  // swiftlint:disable:this explicit_acl type_contents_order
    guard isActiveTabVisible != isVisible else { return }  // swiftlint:disable:this conditional_returns_on_newline

    isActiveTabVisible = isVisible

    if !isVisible {
      activeNavigationTask?.cancel()
      incrementMonthCacheInvalidationTokens(for: Set(prefetchTasks.keys))
      prefetchTasks.removeAll()
      isLoading = false
      return
    }

    let dashboardMatchesDisplayed =  // swiftlint:disable:this explicit_type_interface
      dashboardData?.displayedYear == displayYear && dashboardData?.displayedMonth == displayMonth
    if localDataNeedsReload || displayedMonthLoadPending || !dashboardMatchesDisplayed {
      Task {
        await reloadFromLocalIfStale()
      }
    }
  }

  func markLocalDataStale() {  // swiftlint:disable:this explicit_acl type_contents_order
    localDataNeedsReload = true
    displayedMonthLoadPending = true
    dashboardDependenciesLoaded = false
    invalidateSharedPayrollReadCache()
  }

  func handleExternalShiftsDidChange(_ context: ShiftChangeContext) async {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    invalidateSharedPayrollReadCache()

    guard context.canUseTargetedInvalidation else {
      markLocalDataStale()
      guard isActiveTabVisible else { return }  // swiftlint:disable:this conditional_returns_on_newline
      await reloadFromLocal(showLoadingState: dashboardData == nil)
      return
    }

    let affectedKeys = Set(  // swiftlint:disable:this explicit_type_interface
      context.affectedMonths.map { monthCacheKey(year: $0.year, month: $0.month) }
    )
    invalidateMonthCacheEntries(for: affectedKeys, reason: "shift-change")

    guard
      HomeScheduleAffectedMonthResolver.dashboardDisplayedMonthDepends(
        on: context.affectedMonths,
        displayYear: displayYear,
        displayMonth: displayMonth
      )
    else {
      return
    }

    displayedMonthLoadPending = true
    guard isActiveTabVisible else { return }  // swiftlint:disable:this conditional_returns_on_newline

    displayedMonthLoadPending = false
    loadDashboardForDisplayedMonthNonBlocking()
  }

  /// Reloads data that was deferred while Home was hidden.
  /// Uses cached month data when only the displayed month changed.
  func reloadFromLocalIfStale() async {  // swiftlint:disable:this explicit_acl type_contents_order
    guard isActiveTabVisible else {
      displayedMonthLoadPending = true
      return
    }

    if localDataNeedsReload {
      await reloadFromLocal(showLoadingState: dashboardData == nil)
      return
    }

    if dashboardData == nil {
      await loadDashboard()
      return
    }

    let dashboardMatchesDisplayed =  // swiftlint:disable:this explicit_type_interface
      dashboardData?.displayedYear == displayYear && dashboardData?.displayedMonth == displayMonth
    guard displayedMonthLoadPending || !dashboardMatchesDisplayed else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    displayedMonthLoadPending = false
    loadDashboardForDisplayedMonthNonBlocking()
  }

  /// Load all dashboard data for current month (initial load)
  /// Reads from local repositories only - sync is triggered by AppCoordinator
  /// Also prefetches neighboring months for instant navigation
  func loadDashboard() async {  // swiftlint:disable:this explicit_acl type_contents_order
    guard isActiveTabVisible else {
      displayedMonthLoadPending = true
      return
    }

    // Sync tracking with current month context values
    lastObservedYear = monthContext.displayYear
    lastObservedMonth = monthContext.displayMonth

    // Clear cache on full reload (including cachedUserId for impersonation support)
    clearAllMonthCache(reason: "full-load")
    if dashboardData == nil {
      payrollCardSnapshot = nil
    }
    cachedUserId = nil
    resetDashboardDependencies(preservingDisplayJobs: dashboardData != nil)
    previousPayrollAdjustments = []
    payrollAdjustmentsByPayoutMonth.removeAll()

    await loadDashboardFromLocal()
    localDataNeedsReload = false
    displayedMonthLoadPending = false

    // Prefetch neighboring months in the background
    prefetchNeighboringMonths()
  }

  /// Refresh dashboard data via sync then local reload
  /// Called by pull-to-refresh - triggers network sync, then reloads from local
  func refresh() async {  // swiftlint:disable:this explicit_acl type_contents_order
    // SwiftUI .refreshable can cancel the parent task when the view hierarchy changes.
    // Run refresh work in an unstructured task so sync can complete reliably.
    let refreshTask = Task { @MainActor [weak self] in  // swiftlint:disable:this explicit_type_interface
      guard let self else { return }  // swiftlint:disable:this conditional_returns_on_newline
      await performRefresh()
    }

    _ = await refreshTask.result
  }

  /// Performs pull-to-refresh sync and local reload.
  private func performRefresh() async {  // swiftlint:disable:this type_contents_order
    dashboardViewModelLogger.info("🔄 Pull-to-refresh: triggering sync then local reload")

    // Store current data as fallback in case of failure
    let previousDashboardData = dashboardData  // swiftlint:disable:this explicit_type_interface

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
      let syncResult = await syncCoordinator.sync(reason: .manualRefresh, userId: userId)  // swiftlint:disable:this explicit_type_interface line_length

      if case .failed(let errorMessage) = syncResult.outcome {
        dashboardViewModelLogger.warning("⚠️ Sync had issues: \(errorMessage)")
        // Continue anyway - we still want to show local data
      }

      // Clear in-memory caches so we pick up synced data
      clearAllMonthCache(reason: "manual-refresh")
      invalidateSharedPayrollReadCache(for: userId)
      resetDashboardDependencies(preservingDisplayJobs: dashboardData != nil)

      // Reload from local repositories
      await loadDashboardFromLocal()

      // Prefetch neighboring months in the background
      prefetchNeighboringMonths()

      dashboardViewModelLogger.info(
        "✅ Pull-to-refresh complete (synced \(syncResult.totalRowsProcessed) rows)")

    } catch {
      dashboardViewModelLogger.error("❌ Pull-to-refresh failed: \(error.localizedDescription)")

      // Restore previous data so UI doesn't break
      if let previousDashboardData {
        applyDashboardData(previousDashboardData)
      } else {
        self.dashboardData = nil
      }

      // Don't show error state - just log it and keep showing previous data
      // The user can try again, but they'll still see their data
      dashboardViewModelLogger.info("📦 Restored previous data after refresh failure")
    }
  }

  private func loadDashboardDependencies(  // swiftlint:disable:this type_contents_order
    for userId: String,
    forceReload: Bool = false
  ) async {
    guard forceReload || !dashboardDependenciesLoaded else {
      return
    }

    let context = await monthlyPayrollReadService.loadContextUsingStoreActor(for: userId)  // swiftlint:disable:this explicit_type_interface line_length
    applyDashboardDependencies(context)
  }

  private func applyDashboardDependencies(  // swiftlint:disable:this type_contents_order
    _ context: PayrollReadContext
  ) {
    settings = context.settings
    snapshots = context.snapshots
    recurringShifts = context.recurringShifts
    displayJobs = context.jobs
    shouldShowDashboardClockButtons = settings?.effectiveShowDashboardClockButtons ?? true
    dashboardDependenciesLoaded = true
  }

  /// Invalidates dependency reads. Preserve displayed jobs while existing dashboard data remains
  /// visible so workplace badges do not flicker during local reloads.
  func resetDashboardDependencies(preservingDisplayJobs: Bool = false) {  // swiftlint:disable:this line_length type_contents_order
    settings = nil
    snapshots = []
    recurringShifts = []
    if !preservingDisplayJobs {
      displayJobs = []
    }
    dashboardDependenciesLoaded = false
  }

  private func invalidateSharedPayrollReadCache(for userId: String? = nil) {  // swiftlint:disable:this line_length type_contents_order
    monthlyPayrollReadService.invalidateSharedCache(for: userId ?? cachedUserId)
  }

  private func dashboardDependenciesDiffer(from context: PayrollReadContext) -> Bool {  // swiftlint:disable:this line_length type_contents_order
    guard dashboardDependenciesLoaded else { return true }  // swiftlint:disable:this conditional_returns_on_newline

    return settings != context.settings
      || snapshots != context.snapshots
      || recurringShifts != context.recurringShifts
      || displayJobs != context.jobs
  }

  private func consumeInitialSyncCompletionTransition() -> Bool {  // swiftlint:disable:this type_contents_order
    let initialSyncComplete = AppCoordinator.shared.initialSyncComplete  // swiftlint:disable:this explicit_type_interface line_length
    defer {
      hasObservedInitialSyncCompletion = initialSyncComplete
    }

    return initialSyncComplete && !hasObservedInitialSyncCompletion
  }

  private func fullCacheInvalidationReasonForLocalReload(  // swiftlint:disable:this type_contents_order
    previousUserId: String?,
    currentUserId: String?,
    initialSyncJustCompleted: Bool,
    dependenciesChanged: Bool
  ) -> String? {
    guard let currentUserId, !currentUserId.isEmpty else {
      return "local-reload-user-unavailable"
    }

    guard let previousUserId, !previousUserId.isEmpty else {
      return "local-reload-user-uncached"
    }

    guard previousUserId == currentUserId else {
      return "local-reload-user-changed"
    }

    if initialSyncJustCompleted {
      return "initial-sync-complete"
    }

    if dependenciesChanged {
      return "local-reload-dependencies-changed"
    }

    return nil
  }

  private func fetchShiftRows(  // swiftlint:disable:this type_contents_order
    for userId: String,
    year: Int,
    month: Int
  ) async -> [ShiftRow] {
    await monthlyPayrollReadService.loadShiftRows(
      for: userId,
      year: year,
      month: month
    )
  }

  private func fetchMonthRawWindows(  // swiftlint:disable:this type_contents_order
    for userId: String,
    displayYM: (year: Int, month: Int),
    previousYM: (year: Int, month: Int)
  ) async -> (  // swiftlint:disable:this large_tuple
    display: PayrollRawWindowData, previous: PayrollRawWindowData, earlier: PayrollRawWindowData,
    next: PayrollRawWindowData
  ) {
    let displayWindow = PayrollReadWindow.month(year: displayYM.year, month: displayYM.month)  // swiftlint:disable:this explicit_type_interface line_length
    let previousWindow = PayrollReadWindow.month(year: previousYM.year, month: previousYM.month)  // swiftlint:disable:this explicit_type_interface line_length
    let earlierYM = Date.previousYearMonth(from: previousYM)  // swiftlint:disable:this explicit_type_interface
    let earlierWindow = PayrollReadWindow.month(year: earlierYM.year, month: earlierYM.month)  // swiftlint:disable:this explicit_type_interface line_length

    async let displayData = monthlyPayrollReadService.loadRawWindow(  // swiftlint:disable:this explicit_type_interface
      for: userId,
      window: displayWindow
    )
    async let previousData = monthlyPayrollReadService.loadRawWindow(  // swiftlint:disable:this explicit_type_interface
      for: userId,
      window: previousWindow
    )
    async let earlierData = monthlyPayrollReadService.loadRawWindow(  // swiftlint:disable:this explicit_type_interface
      for: userId,
      window: earlierWindow
    )

    let nextYM = Date.nextYearMonth(from: displayYM)
    async let nextData = monthlyPayrollReadService.loadRawWindow(
      for: userId, window: .month(year: nextYM.year, month: nextYM.month))

    return await (displayData, previousData, earlierData, nextData)
  }

  private func fetchPayrollAdjustmentsForPayoutMonth(  // swiftlint:disable:this type_contents_order
    userId: String,
    year: Int,
    month: Int
  ) -> [PayrollAdjustment] {
    let start = Date.firstDayOfMonthDate(year: year, month: month)  // swiftlint:disable:this explicit_type_interface
    let end =  // swiftlint:disable:this explicit_type_interface
      Calendar(identifier: .gregorian).date(byAdding: .month, value: 1, to: start)
      ?? Date.lastDayOfMonthDate(year: year, month: month)

    return payrollAdjustmentsRepository.getAdjustments(
      for: userId,
      payoutStart: start,
      payoutEnd: end
    )
  }

  func fetchPayrollAdjustmentsForPayoutMonths(  // swiftlint:disable:this type_contents_order
    userId: String,
    months: Set<PayrollReadMonth>
  ) -> [PayrollReadMonth: [PayrollAdjustment]] {
    months.reduce(into: [PayrollReadMonth: [PayrollAdjustment]]()) { result, month in
      result[month] = fetchPayrollAdjustmentsForPayoutMonth(
        userId: userId,
        year: month.year,
        month: month.month
      )
    }
  }

  func payrollPayoutMonthsToLoad(  // swiftlint:disable:this type_contents_order
    displayYM: (year: Int, month: Int)
  ) -> Set<PayrollReadMonth> {
    var months: Set<PayrollReadMonth> = [
      PayrollReadMonth(year: displayYM.year, month: displayYM.month)
    ]

    let current = Date.currentYearMonth()  // swiftlint:disable:this explicit_type_interface
    if displayYM.year == current.year, displayYM.month == current.month {
      let nextYM = nextYearMonth(from: displayYM)  // swiftlint:disable:this explicit_type_interface
      months.insert(PayrollReadMonth(year: nextYM.year, month: nextYM.month))
    }

    return months
  }

  func payrollTaxSettings(  // swiftlint:disable:this type_contents_order
    from shifts: [ShiftWithComputations],
    fallbackDate: String,
    jobId: String?
  ) -> PayoutTaxSettings {
    Self.payrollTaxSettings(
      from: shifts,
      fallbackDate: fallbackDate,
      snapshots: snapshots,
      jobs: displayJobs,
      jobId: jobId
    )
  }

  func payrollTaxSettings(  // swiftlint:disable:this type_contents_order
    for adjustment: PayrollAdjustment,
    fallback: PayoutTaxSettings,
    jobId: String?,
    defaultJobId: String?
  ) -> PayoutTaxSettings {
    Self.payrollTaxSettings(
      for: adjustment,
      fallback: fallback,
      snapshots: snapshots,
      jobs: displayJobs,
      jobId: jobId,
      defaultJobId: defaultJobId
    )
  }

  nonisolated static func payrollTaxSettings(  // swiftlint:disable:this type_contents_order
    from shifts: [ShiftWithComputations],
    fallbackDate: String,
    snapshots: [WageSnapshot],
    jobs: [Job],
    jobId: String?
  ) -> PayoutTaxSettings {
    if let firstTaxedShift = shifts.first(where: \.taxEnabled) {
      return PayoutTaxSettings(
        enabled: true,
        percentage: firstTaxedShift.taxPercentage
      )
    }

    let scopedSnapshots = payrollSnapshotsForJob(jobId: jobId, snapshots: snapshots, jobs: jobs)  // swiftlint:disable:this explicit_type_interface line_length
    let snapshot = SnapshotsService.snapshotForDate(fallbackDate, from: scopedSnapshots)  // swiftlint:disable:this explicit_type_interface line_length
    return PayoutTaxSettings(
      enabled: snapshot?.effectiveTaxEnabled ?? false,
      percentage: snapshot?.effectiveTaxPercentage ?? 0
    )
  }

  nonisolated static func payrollTaxSettings(  // swiftlint:disable:this function_parameter_count line_length type_contents_order
    for adjustment: PayrollAdjustment,
    fallback: PayoutTaxSettings,
    snapshots: [WageSnapshot],
    jobs: [Job],
    jobId: String?,
    defaultJobId: String?
  ) -> PayoutTaxSettings {
    let effectiveJobId = jobId ?? adjustment.job_id ?? defaultJobId  // swiftlint:disable:this explicit_type_interface
    let scopedSnapshots = payrollSnapshotsForJob(  // swiftlint:disable:this explicit_type_interface
      jobId: effectiveJobId,
      snapshots: snapshots,
      jobs: jobs
    )
    guard
      let snapshot = SnapshotsService.snapshotForDate(adjustment.payout_date, from: scopedSnapshots)
    else {
      return fallback
    }
    return PayoutTaxSettings(
      enabled: snapshot.effectiveTaxEnabled,
      percentage: snapshot.effectiveTaxPercentage
    )
  }

  nonisolated private static func payrollSnapshotsForJob(  // swiftlint:disable:this type_contents_order
    jobId: String?,
    snapshots: [WageSnapshot],
    jobs: [Job]
  ) -> [WageSnapshot] {
    let snapshotsByJobId = Dictionary(grouping: snapshots, by: { $0.job_id })  // swiftlint:disable:this explicit_type_interface line_length
    let legacyNilJobSnapshots = snapshotsByJobId[nil] ?? []  // swiftlint:disable:this explicit_type_interface

    guard let jobId else {
      return legacyNilJobSnapshots.isEmpty ? snapshots : legacyNilJobSnapshots
    }

    if let scoped = snapshotsByJobId[jobId], !scoped.isEmpty {
      return scoped
    }

    let defaultJobId = jobs.first(where: \.is_default)?.id  // swiftlint:disable:this explicit_type_interface
    if let defaultJobId, let defaultScoped = snapshotsByJobId[defaultJobId], !defaultScoped.isEmpty
    {
      return defaultScoped
    }

    return legacyNilJobSnapshots.isEmpty ? snapshots : legacyNilJobSnapshots
  }

  /// Reload dashboard from local data without triggering sync
  /// Called when shifts change locally (e.g., after adding a shift) or after initial sync completes
  /// - Parameter showLoadingState: Whether to show loading indicator (false for seamless updates after sync)
  func reloadFromLocal(  // swiftlint:disable:this explicit_acl type_contents_order
    showLoadingState: Bool = true
  ) async {
    guard isActiveTabVisible else {
      markLocalDataStale()
      return
    }

    dashboardViewModelLogger.info("🔄 Reloading dashboard from local data")

    // Set loading state if not already set (e.g., by prepareForReload)
    if showLoadingState, !isLoading {
      isLoading = true
    }

    let previousUserId = cachedUserId  // swiftlint:disable:this explicit_type_interface
    let currentUserId = try? await getCurrentUserId()  // swiftlint:disable:this explicit_type_interface
    invalidateSharedPayrollReadCache(for: currentUserId)
    let initialSyncJustCompleted = consumeInitialSyncCompletionTransition()  // swiftlint:disable:this explicit_type_interface line_length
    let refreshedContext: PayrollReadContext?
    if let currentUserId {
      refreshedContext = await monthlyPayrollReadService.loadContextUsingStoreActor(
        for: currentUserId)
    } else {
      refreshedContext = nil
    }
    let dependenciesChanged = refreshedContext.map(dashboardDependenciesDiffer(from:)) ?? true  // swiftlint:disable:this explicit_type_interface line_length

    if let fullInvalidationReason = fullCacheInvalidationReasonForLocalReload(
      previousUserId: previousUserId,
      currentUserId: currentUserId,
      initialSyncJustCompleted: initialSyncJustCompleted,
      dependenciesChanged: dependenciesChanged
    ) {
      clearAllMonthCache(reason: fullInvalidationReason)
    } else {
      invalidateMovingWindowCache(reason: "local-reload")
    }

    cachedUserId = currentUserId  // Refreshed from session for impersonation correctness.
    if let refreshedContext {
      applyDashboardDependencies(refreshedContext)
    } else {
      resetDashboardDependencies()
    }

    // Reload from local repositories (pass false since we already set loading state)
    await loadDashboardFromLocal(showLoadingState: false)
    localDataNeedsReload = false
    displayedMonthLoadPending = false

    prefetchNeighboringMonths()

    dashboardViewModelLogger.info("✅ Dashboard reloaded from local")
  }

  /// Load dashboard data from local repositories
  /// This is the core local-first read path - no network calls
  /// - Parameters:
  ///   - showLoadingState: Whether to show/update loading indicator (false for seamless background updates)
  ///   - expectedDisplayYM: Set by month navigation. Skips the load when the user has already moved
  ///     to another month, and skips the settings retry because navigation runs after a full load.
  func loadDashboardFromLocal(  // swiftlint:disable:this cyclomatic_complexity function_body_length line_length type_contents_order
    showLoadingState: Bool = true,
    expectedDisplayYM: (year: Int, month: Int)? = nil
  ) async {
    if showLoadingState {
      isLoading = true
    }
    // A navigation load clears the error only once settings exist, so it doesn't hide the
    // noLocalData error of a full load that is still waiting for them.
    if expectedDisplayYM == nil {
      error = nil
    }

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

      // Load settings from repositories
      await loadDashboardDependencies(for: userId)
      dashboardViewModelLogger.info("📋 Loaded settings: \(self.settings != nil ? "found" : "nil")")

      // Sync completion reloads the local read model once settings have been saved.
      guard self.settings != nil else {
        if expectedDisplayYM == nil, AppCoordinator.shared.initialSyncComplete {
          dashboardViewModelLogger.error("❌ No local settings - cannot load dashboard")
          self.error = DashboardError.noLocalData
        } else {
          dashboardViewModelLogger.info("📭 No local settings yet - waiting for sync")
        }
        self.isLoading = false
        return
      }
      error = nil

      updateUserAvatarFromSettings()
      dashboardViewModelLogger.info("📋 Loaded snapshots: \(self.snapshots.count)")
      dashboardViewModelLogger.info("📋 Loaded recurring: \(self.recurringShifts.count)")

      // Calculate date ranges for displayed month
      let displayYM = (year: displayYear, month: displayMonth)  // swiftlint:disable:this explicit_type_interface
      if let expectedDisplayYM,
        displayYM.year != expectedDisplayYM.year || displayYM.month != expectedDisplayYM.month
      {
        dashboardViewModelLogger.info("⏭️ Skipping stale dashboard load before fetch")
        return
      }
      let previousYM = Date.previousYearMonth(from: displayYM)  // swiftlint:disable:this explicit_type_interface

      // Load shifts through the repository/DAL path (after settings retry to avoid stale empty reads)
      let fetchedRawWindows = await fetchMonthRawWindows(  // swiftlint:disable:this explicit_type_interface
        for: userId,
        displayYM: displayYM,
        previousYM: previousYM
      )
      let displayShifts = fetchedRawWindows.display.shifts  // swiftlint:disable:this explicit_type_interface
      dashboardViewModelLogger.info(
        "📋 Loaded shifts for \(displayYM.year)-\(displayYM.month): \(displayShifts.count)")  // swiftlint:disable:this line_length multiline_arguments_brackets
      let fetchedPreviousShifts = fetchedRawWindows.previous.shifts  // swiftlint:disable:this explicit_type_interface
      let fetchedEarlierShifts = fetchedRawWindows.earlier.shifts  // swiftlint:disable:this explicit_type_interface
      let earlierYM = Date.previousYearMonth(from: previousYM)  // swiftlint:disable:this explicit_type_interface
      let nextYM = Date.nextYearMonth(from: displayYM)
      let fetchedNextShifts = fetchedRawWindows.next.shifts
      let displayEvents = fetchedRawWindows.display.events  // swiftlint:disable:this explicit_type_interface
      let previousEvents = fetchedRawWindows.previous.events  // swiftlint:disable:this explicit_type_interface
      let fetchedPayrollAdjustmentsByMonth = fetchPayrollAdjustmentsForPayoutMonths(  // swiftlint:disable:this explicit_type_interface line_length
        userId: userId,
        months: payrollPayoutMonthsToLoad(displayYM: displayYM)
      )
      let fetchedPayrollAdjustments =  // swiftlint:disable:this explicit_type_interface
        fetchedPayrollAdjustmentsByMonth[
          PayrollReadMonth(year: displayYM.year, month: displayYM.month)
        ] ?? []

      // Read settings again after the fetch, together with the other inputs. A concurrent
      // refresh can reset dependencies during the await and then load them itself.
      guard let currentSettings = self.settings else {
        dashboardViewModelLogger.info("⏭️ Skipping dashboard load while dependencies reload")
        return
      }
      let capturedRecurring = recurringShifts  // swiftlint:disable:this explicit_type_interface
      let capturedSnapshots = snapshots  // swiftlint:disable:this explicit_type_interface
      let capturedCurrency = currentSettings.currency ?? "kr"  // swiftlint:disable:this explicit_type_interface
      let capturedJobs = displayJobs  // swiftlint:disable:this explicit_type_interface
      let capturedPayrollAdjustments = fetchedPayrollAdjustments  // swiftlint:disable:this explicit_type_interface
      let capturedPayrollAdjustmentsByPayoutMonth = fetchedPayrollAdjustmentsByMonth  // swiftlint:disable:this explicit_type_interface line_length

      let result = await Task.detached(priority: .userInitiated) {  // swiftlint:disable:this closure_body_length explicit_type_interface line_length
        let displayComputed = PayrollEngine.computeShiftsForMonth(  // swiftlint:disable:this explicit_type_interface
          .init(
            year: displayYM.year,
            month: displayYM.month,
            shifts: displayShifts,
            recurring: capturedRecurring,
            snapshots: capturedSnapshots,
            settings: currentSettings,
            jobs: capturedJobs
          )
        )

        let previousComputed = PayrollEngine.computeShiftsForMonth(  // swiftlint:disable:this explicit_type_interface
          .init(
            year: previousYM.year,
            month: previousYM.month,
            shifts: fetchedPreviousShifts,
            recurring: capturedRecurring,
            snapshots: capturedSnapshots,
            settings: currentSettings,
            jobs: capturedJobs
          )
        )

        let earlierComputed = PayrollEngine.computeShiftsForMonth(  // swiftlint:disable:this explicit_type_interface
          .init(
            year: earlierYM.year,
            month: earlierYM.month,
            shifts: fetchedEarlierShifts,
            recurring: capturedRecurring,
            snapshots: capturedSnapshots,
            settings: currentSettings,
            jobs: capturedJobs
          )
        )

        let nextComputed = PayrollEngine.computeShiftsForMonth(
          .init(
            year: nextYM.year, month: nextYM.month, shifts: fetchedNextShifts,
            recurring: capturedRecurring, snapshots: capturedSnapshots,
            settings: currentSettings, jobs: capturedJobs))

        let dashboardData = Self.buildDashboardDataOffMain(  // swiftlint:disable:this explicit_type_interface
          .init(
            displayedMonthShifts: displayComputed,
            displayedMonthEvents: displayEvents,
            previousMonthShifts: previousComputed,
            previousPayrollAdjustments: capturedPayrollAdjustments,
            snapshots: capturedSnapshots,
            settings: currentSettings,
            displayYM: displayYM,
            previousYM: previousYM,
            currency: capturedCurrency,
            jobs: capturedJobs
          ))  // swiftlint:disable:this multiline_arguments_brackets

        let payrollCardSnapshot = Self.buildPayrollCardSnapshot(  // swiftlint:disable:this explicit_type_interface
          .init(
            displayedMonthShifts: displayComputed,
            previousMonthShifts: previousComputed,
            earlierMonthShifts: earlierComputed,
            nextMonthShifts: nextComputed,
            payrollAdjustmentsByPayoutMonth: capturedPayrollAdjustmentsByPayoutMonth,
            previousPayrollAdjustments: capturedPayrollAdjustments,
            snapshots: capturedSnapshots,
            settings: currentSettings,
            jobs: capturedJobs,
            displayYM: displayYM,
            fallbackCurrency: dashboardData.currency,
            fallbackPayrollDate: dashboardData.payrollDate,
            fallbackPreviousGross: dashboardData.previousMonthGross,
            fallbackPreviousNet: dashboardData.previousMonthNet,
            fallbackPreviousTax: dashboardData.previousMonthTax,
            fallbackPreviousTaxEnabled: dashboardData.previousMonthTaxEnabled,
            fallbackPreviousHasPayrollAdjustments: dashboardData.previousMonthHasPayrollAdjustments,
            now: Date()
          ))  // swiftlint:disable:this multiline_arguments_brackets

        return (
          display: displayComputed,
          displayEvents: displayEvents,
          previous: previousComputed,
          previousEvents: previousEvents,
          earlier: earlierComputed,
          next: nextComputed,
          dashboardData: dashboardData,
          payrollCardSnapshot: payrollCardSnapshot
        )
      }.value

      // The user may have changed month during the awaits above. Applying this result would
      // show the old month under the new month's header.
      guard !Task.isCancelled, cachedUserId == userId,
        displayYear == displayYM.year, displayMonth == displayYM.month
      else {
        dashboardViewModelLogger.info("⏭️ Skipping stale dashboard payload after fetch")
        return
      }

      self.displayedMonthShifts = result.display
      self.displayedMonthEvents = result.displayEvents
      self.previousMonthShifts = result.previous
      self.previousPayrollAdjustments = fetchedPayrollAdjustments
      self.payrollAdjustmentsByPayoutMonth = fetchedPayrollAdjustmentsByMonth

      // Cache the computed results
      let displayKey = "\(displayYM.year)-\(displayYM.month)"  // swiftlint:disable:this explicit_type_interface
      let previousKey = "\(previousYM.year)-\(previousYM.month)"  // swiftlint:disable:this explicit_type_interface
      monthCache[displayKey] = MonthCacheEntry(
        year: displayYM.year,
        month: displayYM.month,
        shifts: result.display,
        events: result.displayEvents,
        timestamp: Date()
      )
      monthCache[previousKey] = MonthCacheEntry(
        year: previousYM.year,
        month: previousYM.month,
        shifts: result.previous,
        events: result.previousEvents,
        timestamp: Date()
      )
      monthCache[monthCacheKey(year: earlierYM.year, month: earlierYM.month)] = MonthCacheEntry(
        year: earlierYM.year,
        month: earlierYM.month,
        shifts: result.earlier,
        events: fetchedRawWindows.earlier.events,
        timestamp: Date()
      )
      monthCache[monthCacheKey(nextYM)] = MonthCacheEntry(
        year: nextYM.year, month: nextYM.month, shifts: result.next,
        events: fetchedRawWindows.next.events, timestamp: Date())

      // Evict old cache entries if over limit
      evictCacheIfNeeded()

      // Build dashboard data and clear loading state
      // Always clear isLoading on success since we have data to show
      applyDashboardData(result.dashboardData, payrollCardSnapshot: result.payrollCardSnapshot)
      self.maybeTriggerCelebration()
      await refreshClockActiveState(referenceDate: Date())
      self.isLoading = false

      dashboardViewModelLogger.info(
        "📊 Loaded dashboard from local: \(displayShifts.count) shifts for \(displayKey)")

    } catch is CancellationError {
      dashboardViewModelLogger.info("⏭️ Load cancelled (user navigated away)")
      // Don't clear isLoading on cancellation - another load should be in progress
    } catch let urlError as URLError where urlError.code == .cancelled {
      dashboardViewModelLogger.info("⏭️ Request cancelled (user navigated away)")
      // Don't clear isLoading on cancellation - another load should be in progress
    } catch {
      dashboardViewModelLogger.error("❌ Dashboard local load failed: \(error.localizedDescription)")
      self.error = DashboardError.dataLoadFailed(underlying: error)
      // Always clear loading state on completion
      self.isLoading = false
    }
  }

  /// Prefetch neighboring months in the background
  /// This enables instant navigation when the user swipes
  func prefetchNeighboringMonths() {  // swiftlint:disable:this type_contents_order
    guard isActiveTabVisible else { return }  // swiftlint:disable:this conditional_returns_on_newline

    let displayYM = (year: displayYear, month: displayMonth)  // swiftlint:disable:this explicit_type_interface

    // Calculate previous and next months
    let previousYM = Date.previousYearMonth(from: displayYM)  // swiftlint:disable:this explicit_type_interface
    let nextYM = nextYearMonth(from: displayYM)  // swiftlint:disable:this explicit_type_interface

    // Also get the months needed for the payroll card of each neighbor.
    // Pay periods can reach two months back, so the previous month needs three months before it.
    let prevPrevYM = Date.previousYearMonth(from: previousYM)  // swiftlint:disable:this explicit_type_interface
    let prevPrevPrevYM = Date.previousYearMonth(from: prevPrevYM)  // swiftlint:disable:this explicit_type_interface
    let nextPrevYM = Date.previousYearMonth(from: nextYM)  // swiftlint:disable:this explicit_type_interface

    // Prefetch all needed months
    prefetchMonthInBackground(year: previousYM.year, month: previousYM.month)
    prefetchMonthInBackground(year: nextYM.year, month: nextYM.month)
    prefetchMonthInBackground(year: prevPrevYM.year, month: prevPrevYM.month)
    prefetchMonthInBackground(year: prevPrevPrevYM.year, month: prevPrevPrevYM.month)
    prefetchMonthInBackground(year: nextPrevYM.year, month: nextPrevYM.month)
  }

  /// Prefetch a single month's data in the background from local repository
  private func prefetchMonthInBackground(year: Int, month: Int) {  // swiftlint:disable:this function_body_length line_length type_contents_order
    let key = monthCacheKey(year: year, month: month)  // swiftlint:disable:this explicit_type_interface

    // Skip if already cached and valid
    if let cached = monthCache[key], cached.isValid {
      return
    }

    // Skip if already prefetching
    let token = monthCacheInvalidationToken(for: key)  // swiftlint:disable:this explicit_type_interface
    if prefetchTasks[key] == token {
      return
    }

    prefetchTasks[key] = token

    // Local reads are fast, but we run in a Task to not block UI
    Task {  // swiftlint:disable:this closure_body_length
      defer {
        self.finishPrefetch(for: key, token: token)
      }

      guard let userId = cachedUserId else {
        return
      }

      // Compute shifts with payroll
      guard let settings = self.settings else {
        return
      }

      let fetchedWindow = await monthlyPayrollReadService.loadRawWindow(  // swiftlint:disable:this explicit_type_interface line_length
        for: userId,
        window: .month(year: year, month: month)
      )

      guard self.isPrefetchCurrent(for: key, token: token) else {
        return
      }

      let monthShifts = fetchedWindow.shifts  // swiftlint:disable:this explicit_type_interface
      let monthEvents = fetchedWindow.events  // swiftlint:disable:this explicit_type_interface
      let capturedRecurring = recurringShifts  // swiftlint:disable:this explicit_type_interface
      let capturedSnapshots = snapshots  // swiftlint:disable:this explicit_type_interface
      let capturedJobs = displayJobs  // swiftlint:disable:this explicit_type_interface

      let computedShifts = await Task.detached(priority: .utility) {  // swiftlint:disable:this explicit_type_interface
        PayrollEngine.computeShiftsForMonth(
          .init(
            year: year,
            month: month,
            shifts: monthShifts,
            recurring: capturedRecurring,
            snapshots: capturedSnapshots,
            settings: settings,
            jobs: capturedJobs
          )
        )
      }.value

      guard self.isPrefetchCurrent(for: key, token: token) else {
        return
      }

      // Store in cache
      let entry = MonthCacheEntry(  // swiftlint:disable:this explicit_type_interface
        year: year,
        month: month,
        shifts: computedShifts,
        events: monthEvents,
        timestamp: Date()
      )
      self.monthCache[key] = entry

      // Evict old cache entries if over limit
      self.evictCacheIfNeeded()

      dashboardViewModelLogger.info(
        "📦 Prefetched \(key) with \(computedShifts.count) shifts from local")
    }
  }

  /// Get next year/month (handles year rollover)
  func nextYearMonth(from current: (year: Int, month: Int)) -> (year: Int, month: Int) {  // swiftlint:disable:this line_length type_contents_order
    if current.month == 12 {  // swiftlint:disable:this no_magic_numbers
      return (year: current.year + 1, month: 1)
    }
    return (year: current.year, month: current.month + 1)
  }

  // MARK: - Private Methods

  /// Get current authenticated user ID and update user profile data
  func getCurrentUserId() async throws -> String? {  // swiftlint:disable:this type_contents_order
    let session: AuthSession
    if let local = AuthSessionManager.shared.localPresentationSession() {
      session = local
    } else {
      do {
        session = try await AuthSessionManager.shared.getSession()
      } catch {
        guard AuthSessionManager.shared.isTransientSessionResolutionError(error) else {
          throw error
        }

        if let offlineUserId = AuthSessionManager.shared.offlineUserIdFallback() {
          if self.userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.userDisplayName = "User"
          }
          dashboardViewModelLogger.info("Using offline user id fallback")
          return offlineUserId
        }

        throw error
      }
    }
    let user = session.user  // swiftlint:disable:this explicit_type_interface

    // Use the profile name, or fall back to the email
    let displayName: String
    if let name = user.name, !name.isEmpty {
      displayName = name
    } else if let email = user.email {
      // Use the part before @ for email
      displayName = email.components(separatedBy: "@").first ?? email
    } else {
      displayName = "User"
    }

    // Update published properties
    self.userDisplayName = displayName

    return user.normalizedId
  }

  /// Update user avatar URL from settings (called after settings are loaded)
  private func updateUserAvatarFromSettings() {  // swiftlint:disable:this type_contents_order
    self.userAvatarUrl = settings?.profile_picture_url
  }

  /// Trigger shift completion celebration for current month (if applicable)
  func maybeTriggerCelebration() {  // swiftlint:disable:this type_contents_order
    let resolvedUserId = cachedUserId ?? resolveUserIdForPayrollVariants()  // swiftlint:disable:this explicit_type_interface line_length
    guard let userId = resolvedUserId, !userId.isEmpty else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    cachedUserId = userId
    guard let dashboardData, let settings else { return }  // swiftlint:disable:this conditional_returns_on_newline

    let current = Date.currentYearMonth()  // swiftlint:disable:this explicit_type_interface
    guard displayYear == current.year, displayMonth == current.month else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    guard dashboardData.displayedYear == current.year,
      dashboardData.displayedMonth == current.month
    else {
      return
    }

    let display = CelebrationDetector.displayValue(dashboardData: dashboardData)  // swiftlint:disable:this explicit_type_interface line_length
    let currency = settings.currency ?? dashboardData.currency  // swiftlint:disable:this explicit_type_interface
    let currentMonthShifts = displayedMonthShifts.filter { shift in  // swiftlint:disable:this explicit_type_interface
      guard let date = Date.fromISODateString(shift.shiftDate) else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
      let components = Self.gregorianCalendar.dateComponents([.year, .month], from: date)  // swiftlint:disable:this explicit_type_interface line_length
      return components.year == current.year && components.month == current.month
    }

    ShiftCompletionCelebrationManager.shared.checkForCelebration(
      userId: userId,
      month: current,
      shifts: currentMonthShifts,
      displayValue: display.value,
      displayTaxEnabled: display.taxEnabled,
      currency: currency,
      includeVirtual: true
    )
  }

  /// Build the final dashboard data from computed shifts
  /// Uses PayrollEngine.summarizeShiftTotals for correct half-tax and conflict exclusion
  func buildDashboardData() -> DashboardData {  // swiftlint:disable:this function_body_length line_length type_contents_order
    let today = todayISO()  // swiftlint:disable:this explicit_type_interface
    let now = Date()  // swiftlint:disable:this explicit_type_interface
    let payrollDay = settings?.effectivePayrollDay ?? 1  // swiftlint:disable:this explicit_type_interface
    let halfTaxMonth = settings?.half_tax_month  // swiftlint:disable:this explicit_type_interface
    let displayYM = (year: displayYear, month: displayMonth)  // swiftlint:disable:this explicit_type_interface
    let previousYM = Date.previousYearMonth(from: displayYM)  // swiftlint:disable:this explicit_type_interface
    let previousAdjustments = previousPayrollAdjustments  // swiftlint:disable:this explicit_type_interface

    // Calculate payroll date for displayed month
    let payrollDate = calculatePayrollDate(  // swiftlint:disable:this explicit_type_interface
      year: displayYM.year, month: displayYM.month, day: payrollDay)  // swiftlint:disable:this line_length multiline_arguments_brackets
    let payrollHasPassed = now > payrollDate  // swiftlint:disable:this explicit_type_interface

    // Previous month totals using PayrollEngine (for payroll card)
    // This correctly applies half-tax and conflict exclusion
    let prevTotals = PayrollEngine.summarizeShiftTotals(  // swiftlint:disable:this explicit_type_interface
      shifts: previousMonthShifts,
      halfTaxMonth: halfTaxMonth,
      earningsMonth: previousYM.month,
      now: now
    )
    let fallbackTaxSettings = payrollTaxSettings(  // swiftlint:disable:this explicit_type_interface
      from: previousMonthShifts,
      fallbackDate: payrollDate.toISODateString(),
      jobId: nil
    )
    let adjustmentTotals = PayrollAdjustmentCalculator.totals(  // swiftlint:disable:this explicit_type_interface
      adjustments: previousAdjustments,
      taxSettings: { adjustment in
        payrollTaxSettings(
          for: adjustment,
          fallback: fallbackTaxSettings,
          jobId: adjustment.job_id,
          defaultJobId: displayJobs.first(where: \.is_default)?.id
        )
      },
      halfTaxMonth: halfTaxMonth,
      payoutMonth: displayYM.month,
      jobs: displayJobs
    )
    let prevTaxEnabled =  // swiftlint:disable:this explicit_type_interface
      previousMonthShifts.contains(where: \.taxEnabled) || adjustmentTotals.taxEnabled
    let previousGross = prevTotals.gross + adjustmentTotals.gross  // swiftlint:disable:this explicit_type_interface
    let previousNet = prevTotals.net + adjustmentTotals.net  // swiftlint:disable:this explicit_type_interface
    let prevTax: Double? = prevTaxEnabled ? previousGross - previousNet : nil

    let fallbackCurrency = settings?.currency ?? "kr"  // swiftlint:disable:this explicit_type_interface
    let earnings = EarningsTotals.compute(  // swiftlint:disable:this explicit_type_interface
      shiftsByMonth: [(displayYM.month, displayedMonthShifts)],
      jobs: displayJobs,
      fallbackCurrency: fallbackCurrency,
      halfTaxMonth: halfTaxMonth,
      now: now
    )
    let currentMonthAggregate = earnings.aggregate  // swiftlint:disable:this explicit_type_interface
    let displayTotals = earnings.totals  // swiftlint:disable:this explicit_type_interface
    let displayTaxEnabled = earnings.taxEnabled  // swiftlint:disable:this explicit_type_interface
    let completedShiftsCount = currentMonthAggregate.primary.completedShiftCount  // swiftlint:disable:this explicit_type_interface line_length
    let plannedShiftsCount = currentMonthAggregate.primary.plannedShiftCount  // swiftlint:disable:this explicit_type_interface line_length

    // Same computation as Stats: gross shift pay in the primary currency, without payroll adjustments.
    let percentChange = MonthlyEarningsChange.percent(  // swiftlint:disable:this explicit_type_interface
      monthShifts: displayedMonthShifts,
      previousMonthShifts: previousMonthShifts,
      jobs: displayJobs,
      fallbackCurrency: fallbackCurrency,
      halfTaxMonth: halfTaxMonth,
      currentMonth: displayYM.month,
      previousMonth: previousYM.month,
      now: now
    )

    // Featured shift logic:
    // - Current month: show next upcoming shift
    // - Other months: show best shift (highest earnings)
    let current = Date.currentYearMonth()  // swiftlint:disable:this explicit_type_interface
    let isViewingCurrentMonth = displayYM.year == current.year && displayYM.month == current.month  // swiftlint:disable:this explicit_type_interface line_length

    let featuredSelection = DashboardFeaturedItemSelector.select(  // swiftlint:disable:this explicit_type_interface
      shifts: displayedMonthShifts,
      events: displayedMonthEvents,
      isViewingCurrentMonth: isViewingCurrentMonth,
      todayISO: today,
      now: now
    )

    // Month names for display
    let displayMonthName = monthName(year: displayYM.year, month: displayYM.month)  // swiftlint:disable:this explicit_type_interface line_length
    let previousMonthName = monthName(year: previousYM.year, month: previousYM.month)  // swiftlint:disable:this explicit_type_interface line_length

    return DashboardData(
      displayedYear: displayYM.year,
      displayedMonth: displayYM.month,
      payrollDate: payrollDate,
      payrollHasPassed: payrollHasPassed,
      previousMonthGross: previousGross,
      previousMonthNet: prevTaxEnabled ? previousNet : nil,
      previousMonthTax: prevTax,
      previousMonthTaxEnabled: prevTaxEnabled,
      previousMonthHasPayrollAdjustments: !previousAdjustments.isEmpty,
      currentMonthGross: displayTotals.gross,
      currentMonthNet: displayTaxEnabled ? displayTotals.net : nil,
      currentMonthCompletedGross: displayTotals.completedGross,
      currentMonthCompletedNet: displayTaxEnabled ? displayTotals.completedNet : nil,
      currentMonthShiftCount: currentMonthAggregate.primary.shiftCount,
      currentMonthCompletedCount: completedShiftsCount,
      currentMonthPlannedCount: plannedShiftsCount,
      percentageChangeVsPrevious: percentChange,
      currentMonthTaxEnabled: displayTaxEnabled,
      featuredItem: featuredSelection.item,
      featuredShift: featuredSelection.item?.shift,
      isFeaturedItemToday: featuredSelection.isToday,
      featuredShiftIsBestShift: featuredSelection.isBestShift,
      currentMonthName: displayMonthName,
      previousMonthName: previousMonthName,
      currency: currentMonthAggregate.primary.currency,
      currentMonthCurrencyAggregate: currentMonthAggregate
    )
  }

  /// Build dashboard data off the main actor to avoid blocking animations.
  nonisolated static func buildDashboardDataOffMain(  // swiftlint:disable:this function_body_length line_length type_contents_order
    _ input: DashboardDataBuildInput
  ) -> DashboardData {
    let displayedMonthShifts = input.displayedMonthShifts  // swiftlint:disable:this explicit_type_interface
    let displayedMonthEvents = input.displayedMonthEvents  // swiftlint:disable:this explicit_type_interface
    let previousMonthShifts = input.previousMonthShifts  // swiftlint:disable:this explicit_type_interface
    let previousPayrollAdjustments = input.previousPayrollAdjustments  // swiftlint:disable:this explicit_type_interface
    let snapshots = input.snapshots  // swiftlint:disable:this explicit_type_interface
    let settings = input.settings  // swiftlint:disable:this explicit_type_interface
    let displayYM = input.displayYM  // swiftlint:disable:this explicit_type_interface
    let previousYM = input.previousYM  // swiftlint:disable:this explicit_type_interface
    let currency = input.currency  // swiftlint:disable:this explicit_type_interface
    let jobs = input.jobs  // swiftlint:disable:this explicit_type_interface

    let today = todayISO()  // swiftlint:disable:this explicit_type_interface
    let now = Date()  // swiftlint:disable:this explicit_type_interface
    let payrollDay = settings.effectivePayrollDay  // swiftlint:disable:this explicit_type_interface
    let halfTaxMonth = settings.half_tax_month  // swiftlint:disable:this explicit_type_interface

    let payrollDate = PayrollDateAdjuster.adjustPayrollDate(  // swiftlint:disable:this explicit_type_interface
      payrollDay: payrollDay,
      month: displayYM.month,
      year: displayYM.year
    )
    let payrollHasPassed = now > payrollDate  // swiftlint:disable:this explicit_type_interface

    let prevTotals = PayrollEngine.summarizeShiftTotals(  // swiftlint:disable:this explicit_type_interface
      shifts: previousMonthShifts,
      halfTaxMonth: halfTaxMonth,
      earningsMonth: previousYM.month,
      now: now
    )
    let fallbackTaxSettings = payrollTaxSettings(  // swiftlint:disable:this explicit_type_interface
      from: previousMonthShifts,
      fallbackDate: payrollDate.toISODateString(),
      snapshots: snapshots,
      jobs: jobs,
      jobId: nil
    )
    let adjustmentTotals = PayrollAdjustmentCalculator.totals(  // swiftlint:disable:this explicit_type_interface
      adjustments: previousPayrollAdjustments,
      taxSettings: { adjustment in
        payrollTaxSettings(
          for: adjustment,
          fallback: fallbackTaxSettings,
          snapshots: snapshots,
          jobs: jobs,
          jobId: adjustment.job_id,
          defaultJobId: jobs.first(where: \.is_default)?.id
        )
      },
      halfTaxMonth: halfTaxMonth,
      payoutMonth: displayYM.month,
      jobs: jobs
    )
    let prevTaxEnabled =  // swiftlint:disable:this explicit_type_interface
      previousMonthShifts.contains(where: \.taxEnabled) || adjustmentTotals.taxEnabled
    let previousGross = prevTotals.gross + adjustmentTotals.gross  // swiftlint:disable:this explicit_type_interface
    let previousNet = prevTotals.net + adjustmentTotals.net  // swiftlint:disable:this explicit_type_interface
    let prevTax: Double? = prevTaxEnabled ? previousGross - previousNet : nil

    let earnings = EarningsTotals.compute(  // swiftlint:disable:this explicit_type_interface
      shiftsByMonth: [(displayYM.month, displayedMonthShifts)],
      jobs: jobs,
      fallbackCurrency: currency,
      halfTaxMonth: halfTaxMonth,
      now: now
    )
    let currentMonthAggregate = earnings.aggregate  // swiftlint:disable:this explicit_type_interface
    let displayTotals = earnings.totals  // swiftlint:disable:this explicit_type_interface
    let displayTaxEnabled = earnings.taxEnabled  // swiftlint:disable:this explicit_type_interface
    let completedShiftsCount = currentMonthAggregate.primary.completedShiftCount  // swiftlint:disable:this explicit_type_interface line_length
    let plannedShiftsCount = currentMonthAggregate.primary.plannedShiftCount  // swiftlint:disable:this explicit_type_interface line_length

    // Same computation as Stats: gross shift pay in the primary currency, without payroll adjustments.
    let percentChange = MonthlyEarningsChange.percent(  // swiftlint:disable:this explicit_type_interface
      monthShifts: displayedMonthShifts,
      previousMonthShifts: previousMonthShifts,
      jobs: jobs,
      fallbackCurrency: currency,
      halfTaxMonth: halfTaxMonth,
      currentMonth: displayYM.month,
      previousMonth: previousYM.month,
      now: now
    )

    let current = Date.currentYearMonth()  // swiftlint:disable:this explicit_type_interface
    let isViewingCurrentMonth = displayYM.year == current.year && displayYM.month == current.month  // swiftlint:disable:this explicit_type_interface line_length

    let featuredSelection = DashboardFeaturedItemSelector.select(  // swiftlint:disable:this explicit_type_interface
      shifts: displayedMonthShifts,
      events: displayedMonthEvents,
      isViewingCurrentMonth: isViewingCurrentMonth,
      todayISO: today,
      now: now
    )

    let displayMonthName = monthNameStatic(year: displayYM.year, month: displayYM.month)  // swiftlint:disable:this explicit_type_interface line_length
    let previousMonthName = monthNameStatic(year: previousYM.year, month: previousYM.month)  // swiftlint:disable:this explicit_type_interface line_length

    return DashboardData(
      displayedYear: displayYM.year,
      displayedMonth: displayYM.month,
      payrollDate: payrollDate,
      payrollHasPassed: payrollHasPassed,
      previousMonthGross: previousGross,
      previousMonthNet: prevTaxEnabled ? previousNet : nil,
      previousMonthTax: prevTax,
      previousMonthTaxEnabled: prevTaxEnabled,
      previousMonthHasPayrollAdjustments: !previousPayrollAdjustments.isEmpty,
      currentMonthGross: displayTotals.gross,
      currentMonthNet: displayTaxEnabled ? displayTotals.net : nil,
      currentMonthCompletedGross: displayTotals.completedGross,
      currentMonthCompletedNet: displayTaxEnabled ? displayTotals.completedNet : nil,
      currentMonthShiftCount: currentMonthAggregate.primary.shiftCount,
      currentMonthCompletedCount: completedShiftsCount,
      currentMonthPlannedCount: plannedShiftsCount,
      percentageChangeVsPrevious: percentChange,
      currentMonthTaxEnabled: displayTaxEnabled,
      featuredItem: featuredSelection.item,
      featuredShift: featuredSelection.item?.shift,
      isFeaturedItemToday: featuredSelection.isToday,
      featuredShiftIsBestShift: featuredSelection.isBestShift,
      currentMonthName: displayMonthName,
      previousMonthName: previousMonthName,
      currency: currentMonthAggregate.primary.currency,
      currentMonthCurrencyAggregate: currentMonthAggregate
    )
  }

  nonisolated private static func monthNameStatic(year: Int, month: Int) -> String {  // swiftlint:disable:this line_length type_contents_order
    var components = DateComponents()  // swiftlint:disable:this explicit_type_interface
    components.year = year
    components.month = month
    components.day = 1
    guard let date = gregorianCalendar.date(from: components) else { return "" }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return FormatterCache.monthNameFormatter(locale: .appLocale).string(from: date)
  }

  nonisolated private static func findBestShiftStatic(in shifts: [ShiftWithComputations])  // swiftlint:disable:this line_length type_contents_order
    -> ShiftWithComputations?
  {
    guard !shifts.isEmpty else { return nil }  // swiftlint:disable:this conditional_returns_on_newline

    let maxGross = shifts.map(\.grossPay).max() ?? 0  // swiftlint:disable:this explicit_type_interface
    guard maxGross > 0 else { return shifts.first }  // swiftlint:disable:this conditional_returns_on_newline

    let bestShifts =  // swiftlint:disable:this explicit_type_interface
      shifts
      .filter { $0.grossPay == maxGross }
      .sorted { $0.shiftDate < $1.shiftDate }

    return bestShifts.first
  }
}
