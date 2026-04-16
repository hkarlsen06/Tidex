import Combine
import Foundation
import UIKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "ShiftsViewModel")
private let monthNameFormatter = FormatterCache.monthNameFormatter()
private let isoDateFormatter = FormatterCache.isoDateFormatter(timeZone: Date.localTimeZone)
private let hourMinuteFormatter = FormatterCache.hourMinuteFormatter(timeZone: Date.localTimeZone)

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
  case invalidEventDateRange
  case eventNotFound

  var errorDescription: String? {
    switch self {
    case .notAuthenticated:
      return "Not authenticated"
    case .dataLoadFailed(let error):
      return "Failed to load data: \(error.localizedDescription)"
    case .noLocalData:
      return "No local data available. Please wait for sync to complete."
    case .invalidEventDateRange:
      return "Invalid event date range"
    case .eventNotFound:
      return "Event not found. Please refresh and try again."
    }
  }
}

// MARK: - Month Cache Entry

/// Cache entry for a single month's computed shifts
private struct MonthCacheEntry {
  let year: Int
  let month: Int
  let shifts: [ShiftWithComputations]
  let events: [EventRow]
  let visibleRange: (start: Date, end: Date)
  let timestamp: Date
  /// Last access time for LRU eviction
  var lastAccessed: Date

  var key: String { "\(year)-\(month)" }

  /// Check if cache entry is still valid (within 5 minutes)
  var isValid: Bool {
    Date().timeIntervalSince(timestamp) < 300  // 5 minutes
  }

  init(
    year: Int,
    month: Int,
    shifts: [ShiftWithComputations],
    events: [EventRow],
    visibleRange: (start: Date, end: Date),
    timestamp: Date
  ) {
    self.year = year
    self.month = month
    self.shifts = shifts
    self.events = events
    self.visibleRange = visibleRange
    self.timestamp = timestamp
    self.lastAccessed = timestamp
  }
}

/// Lightweight prefetch cache entry - stores raw shift data without payroll computation
/// This allows fast prefetching without expensive PayrollEngine calls
private struct PrefetchCacheEntry {
  let year: Int
  let month: Int
  let rawShifts: [ShiftRow]
  let timestamp: Date

  var key: String { "\(year)-\(month)" }

  /// Check if prefetch entry is still valid (within 10 minutes)
  var isValid: Bool {
    Date().timeIntervalSince(timestamp) < 600  // 10 minutes
  }
}

/// Cached selection summary for quick header rendering.
private struct SelectionSummary {
  let net: Double
  let gross: Double
  let hasTaxEnabled: Bool
  let currencyAggregate: JobCurrencyAggregateResolution?
}

private struct MonthComputationInput {
  let year: Int
  let month: Int
  let shifts: [ShiftRow]
  let recurringShifts: [RecurringShiftRow]
  let snapshots: [WageSnapshot]
  let settings: UserSettings
  let visibleRange: (start: Date, end: Date)
  let jobs: [Job]
}

// MARK: - Shifts View Model

@MainActor
final class ShiftsViewModel: ObservableObject, MonthNavigable {

  // MARK: - Dependencies (Local-First Repositories)

  private let shiftsRepository: ShiftsRepository
  private let eventsRepository: EventsRepository
  private let jobsRepository: JobsRepository
  private let settingsRepository: SettingsRepository
  private let snapshotsRepository: SnapshotsRepository
  private let recurringShiftsRepository: RecurringShiftsRepository
  private let syncCoordinator: SyncCoordinator
  private let monthContext: SharedMonthContext

  // MARK: - Published State

  /// All shifts for the displayed month (computed with payroll)
  @Published private(set) var shifts: [ShiftWithComputations] = []
  /// Private events overlapping the currently visible calendar range.
  @Published private(set) var events: [EventRow] = []
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
  /// Set of dates (ISO strings) that have conflicts
  @Published private(set) var conflictDates: Set<String> = []

  /// Direction of last navigation (for animations) - synced from SharedMonthContext
  @Published private(set) var navigationDirection: MonthNavigationDirection?

  // MARK: - Committed Display State
  // These values only update AFTER shift data is ready, ensuring atomic rendering
  // The calendar uses these to avoid showing the new month structure before data arrives

  /// The year that is actually ready to display (data loaded)
  @Published private(set) var committedYear: Int

  /// The month that is actually ready to display (data loaded)
  @Published private(set) var committedMonth: Int

  /// Currently displayed year - synced from SharedMonthContext
  var displayYear: Int { monthContext.displayYear }

  /// Currently displayed month 1-12 - synced from SharedMonthContext
  var displayMonth: Int { monthContext.displayMonth }

  /// Whether viewing the current (real) month (based on committed state)
  var isCurrentMonth: Bool {
    let current = Date.currentYearMonth()
    return committedYear == current.year && committedMonth == current.month
  }

  /// Computed month name for immediate display (uses committed state for stability)
  var displayMonthName: String {
    var components = DateComponents()
    components.year = committedYear
    components.month = committedMonth
    components.day = 1
    if let date = Calendar.current.date(from: components) {
      return monthNameFormatter.string(from: date)
    }
    return ""
  }

  /// The period type of the displayed month (past, current, or future)
  /// Uses committed state for stable rendering
  var monthPeriod: MonthPeriod {
    let current = Date.currentYearMonth()
    let displayedIndex = committedYear * 12 + committedMonth
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

  /// All non-deleted jobs for metadata rendering (badges/colors in shift cards).
  @Published private(set) var activeJobs: [Job] = []

  // MARK: - Selection State

  /// Selected dates (ISO strings). Persists across month navigation.
  @Published var selectedDates: Set<String> = [] {
    didSet {
      if oldValue != selectedDates {
        updateSelectionSummary()
      }
    }
  }

  /// Cached summary for the current selection to avoid recomputing on every access.
  @Published private var selectionSummary: SelectionSummary?

  /// Whether selection mode is enabled (tap/drag to select vs swipe to navigate)
  @Published var isSelectionModeEnabled: Bool = false

  /// Two-click delete confirmation state
  @Published var confirmingDelete: Bool = false

  /// Whether we're currently deleting shifts
  @Published var isDeleting: Bool = false

  // MARK: - Copy/Move State

  /// Whether copy mode is active (waiting for target date selection)
  @Published var isCopyMode: Bool = false

  /// Whether move mode is active (waiting for target date selection)
  @Published var isMoveMode: Bool = false

  /// Whether a copy operation is in progress
  @Published var isCopying: Bool = false

  /// Whether a move operation is in progress
  @Published var isMoving: Bool = false

  /// Whether a recurring shift update is in progress
  @Published var isUpdatingRecurring: Bool = false

  /// Whether a recurring shift deletion is in progress
  @Published var isDeletingRecurring: Bool = false

  /// Whether a shift update is in progress
  @Published var isUpdatingShift: Bool = false

  /// Whether an event update is in progress
  private var isUpdatingEvent = false

  /// Whether an event deletion is in progress
  private var isDeletingEvent = false

  /// The shift being copied or moved (stored when entering copy/move mode)
  private var shiftForOperation: ShiftWithComputations?

  /// Single vs multi-selection mode
  var isMultiSelectMode: Bool { selectedDates.count > 1 }

  /// Computed earnings for selected dates (for header display)
  /// Looks across ALL cached months, not just the currently displayed month
  var selectedEarnings: (net: Double, gross: Double)? {
    guard let summary = selectionSummary else { return nil }
    return (net: summary.net, gross: summary.gross)
  }

  /// Whether any selected shift has tax enabled (for header display)
  /// Looks across ALL cached months, not just the currently displayed month
  var selectedHasTaxEnabled: Bool {
    selectionSummary?.hasTaxEnabled ?? false
  }

  var selectedCurrencyAggregate: JobCurrencyAggregateResolution? {
    selectionSummary?.currencyAggregate
  }

  /// Shifts for the selected date (single selection mode)
  var selectedDateShifts: [ShiftWithComputations] {
    guard selectedDates.count == 1, let dateISO = selectedDates.first else { return [] }
    return shifts.filter { $0.shiftDate == dateISO }
  }

  var shouldShowJobIndicators: Bool {
    activeJobs.count > 1
  }

  private var activeJobsById: [String: Job] {
    Dictionary(uniqueKeysWithValues: activeJobs.map { ($0.id, $0) })
  }

  private var committedVisibleRange: (start: Date, end: Date) {
    Date.visibleCalendarRange(year: committedYear, month: committedMonth)
  }

  func jobForShift(_ shift: ShiftWithComputations) -> Job? {
    guard let jobId = shift.shift.job_id else { return nil }
    return activeJobsById[jobId]
  }

  private func visibleRangeContains(_ dateISO: String) -> Bool {
    guard let date = Date.fromISODateString(dateISO) else {
      return false
    }

    let range = committedVisibleRange
    return date >= range.start && date <= range.end
  }

  var eventCoverageByDate: [String: [EventPresentation]] {
    var result: [String: [EventPresentation]] = [:]
    for event in events {
      if event.is_all_day {
        let daySpan = max(Date.daysBetween(event.start_date, event.end_date), 0)
        for offset in 0...daySpan {
          guard
            let startDate = Date.fromISODateString(event.start_date),
            let coveredDate = Calendar.current.date(byAdding: .day, value: offset, to: startDate)
          else {
            continue
          }
          let coveredDateISO = coveredDate.toISODateString()
          guard visibleRangeContains(coveredDateISO) else { continue }
          result[coveredDateISO, default: []].append(
            EventPresentation(event: event, coveredDateISO: coveredDateISO)
          )
        }
      } else if visibleRangeContains(event.start_date) {
        result[event.start_date, default: []].append(
          EventPresentation(event: event, coveredDateISO: event.start_date)
        )
      }
    }
    return result
  }

  func mixedItems(for dateISO: String) -> [DayPresentationItem] {
    let shiftItems =
      shifts
      .filter { $0.shiftDate == dateISO }
      .map { DayPresentationItem.shift($0) }
    let eventItems = (eventCoverageByDate[dateISO] ?? []).map { DayPresentationItem.event($0) }

    return (shiftItems + eventItems).sorted { lhs, rhs in
      if lhs.isAllDayEvent != rhs.isAllDayEvent {
        return lhs.isAllDayEvent
      }
      if lhs.startSortKey != rhs.startSortKey {
        return lhs.startSortKey < rhs.startSortKey
      }
      return lhs.id < rhs.id
    }
  }

  /// Recompute cached selection summary for header UI.
  private func updateSelectionSummary() {
    guard !selectedDates.isEmpty else {
      selectionSummary = nil
      return
    }

    var seenIds = Set<String>()
    var gross: Double = 0
    var net: Double = 0
    var hasTaxEnabled = false
    var includedShifts: [ShiftWithComputations] = []

    func consume(_ shifts: [ShiftWithComputations]) {
      for shift in shifts where selectedDates.contains(shift.shiftDate) {
        if seenIds.insert(shift.id).inserted {
          if !excludedFromTotalIds.contains(shift.id) {
            gross += shift.grossPay
            net += shift.taxEnabled ? shift.netPay : shift.grossPay
            includedShifts.append(shift)
          }
          if shift.taxEnabled {
            hasTaxEnabled = true
          }
        }
      }
    }

    for (_, cacheEntry) in monthCache {
      consume(cacheEntry.shifts)
    }

    // Also check current month's shifts (may not be in cache yet)
    consume(shifts)

    let currencyAggregate =
      includedShifts.isEmpty
      ? nil
      : JobCurrencyAggregateResolver.resolve(
        shifts: includedShifts,
        jobs: activeJobs,
        fallbackCurrency: currency
      )

    selectionSummary = SelectionSummary(
      net: net,
      gross: gross,
      hasTaxEnabled: hasTaxEnabled,
      currencyAggregate: currencyAggregate
    )
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

  /// Lightweight prefetch cache - stores raw shifts without payroll computation
  /// Payroll is computed lazily when the month becomes visible
  private var prefetchCache: [String: PrefetchCacheEntry] = [:]

  /// Maximum number of months to keep in cache (prevents unbounded memory growth)
  private static let maxCacheSize = 12

  /// Background prefetch tasks (to avoid duplicate fetches)
  private var prefetchTasks: Set<String> = []

  /// Memory warning observer
  private var memoryWarningObserver: NSObjectProtocol?

  /// Shift reminder tap observer for deep linking
  private var shiftReminderObserver: NSObjectProtocol?

  /// Track active navigation task to cancel stale fetches
  private var activeNavigationTask: Task<Void, Never>?

  // MARK: - Initialization

  init(
    shiftsRepository: ShiftsRepository? = nil,
    eventsRepository: EventsRepository? = nil,
    jobsRepository: JobsRepository? = nil,
    settingsRepository: SettingsRepository? = nil,
    snapshotsRepository: SnapshotsRepository? = nil,
    recurringShiftsRepository: RecurringShiftsRepository? = nil,
    syncCoordinator: SyncCoordinator? = nil,
    monthContext: SharedMonthContext? = nil
  ) {
    // Use provided repositories or default to shared instances
    self.shiftsRepository = shiftsRepository ?? ShiftsRepository.shared
    self.eventsRepository = eventsRepository ?? EventsRepository.shared
    self.jobsRepository = jobsRepository ?? JobsRepository.shared
    self.settingsRepository = settingsRepository ?? SettingsRepository.shared
    self.snapshotsRepository = snapshotsRepository ?? SnapshotsRepository.shared
    self.recurringShiftsRepository = recurringShiftsRepository ?? RecurringShiftsRepository.shared
    self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
    self.monthContext = monthContext ?? SharedMonthContext.shared

    // Initialize committed state to current month context values
    // These will be updated atomically with shift data
    self.committedYear = self.monthContext.displayYear
    self.committedMonth = self.monthContext.displayMonth

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

    // Listen for shift reminder notification taps for deep linking
    shiftReminderObserver = NotificationCenter.default.addObserver(
      forName: NSNotification.Name("ShiftReminderTapped"),
      object: nil,
      queue: .main
    ) { [weak self] notification in
      Task { @MainActor in
        self?.handleShiftReminderTap(notification)
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
        self.loadShiftsForDisplayedMonthNonBlocking()
      }
  }

  deinit {
    // Cancel Combine subscriptions to prevent memory leaks
    monthContextCancellable?.cancel()

    if let observer = memoryWarningObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    if let observer = shiftReminderObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  // MARK: - Memory Management

  /// Handle memory warning by clearing the cache
  private func handleMemoryWarning() {
    logger.warning(
      "⚠️ Memory warning received - clearing month cache (\(self.monthCache.count) entries) and prefetch cache (\(self.prefetchCache.count) entries)"
    )
    monthCache.removeAll()
    prefetchCache.removeAll()
    prefetchTasks.removeAll()
  }

  // MARK: - Deep Linking

  /// Handle shift reminder notification tap - navigate to the shift's date
  private func handleShiftReminderTap(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
      let shiftDateString = userInfo["shift_date"] as? String
    else {
      logger.warning("Shift reminder tap missing shift_date")
      return
    }

    logger.info("Deep linking to shift date: \(shiftDateString)")

    // Parse the shift date (format: "yyyy-MM-dd")
    guard let shiftDate = isoDateFormatter.date(from: shiftDateString) else {
      logger.warning("Failed to parse shift date: \(shiftDateString)")
      return
    }

    let calendar = Calendar.current
    let year = calendar.component(.year, from: shiftDate)
    let month = calendar.component(.month, from: shiftDate)

    // Navigate to the month and select the date
    monthContext.navigateTo(year: year, month: month)
    selectedDates = [shiftDateString]
    isSelectionModeEnabled = true
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
    // Also clear copy/move state
    isCopyMode = false
    isMoveMode = false
    shiftForOperation = nil
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
      let virtualShifts = shiftsToDelete.filter(\.isVirtual)
      let regularShiftIds = shiftsToDelete.filter { !$0.isVirtual }.map(\.id)

      for shift in virtualShifts {
        if let recurringId = shift.shift.recurring_id {
          try await RecurringShiftsRepository.shared.addExclusion(
            id: recurringId,
            date: shift.shiftDate
          )
        }
      }

      if !regularShiftIds.isEmpty {
        try await shiftsRepository.deleteShifts(ids: regularShiftIds)
      }

      clearSelection()
      await reloadFromLocal()
      notifyShiftsDidChange()

      // Play deletion feedback
      Haptics.playShiftDeleted()
    } catch {
      logger.error("Failed to delete shifts: \(error.localizedDescription)")
    }

    isDeleting = false
  }

  // MARK: - Copy/Move Actions

  /// Enter copy mode - prepares to copy the selected shift to a new date
  func initiateCopy() {
    guard selectedDates.count == 1,
      let dateISO = selectedDates.first
    else { return }

    // Get the shift for this date
    let shiftsOnDate = shifts.filter { $0.shiftDate == dateISO }
    guard shiftsOnDate.count == 1, let shift = shiftsOnDate.first else {
      // Multiple shifts on date or no shift found - can't copy
      return
    }

    // Store the shift and enter copy mode
    shiftForOperation = shift
    isCopyMode = true
    confirmingDelete = false
  }

  /// Enter move mode - prepares to move the selected shift to a new date
  func initiateMove() {
    guard selectedDates.count == 1,
      let dateISO = selectedDates.first
    else { return }

    // Get the shift for this date
    let shiftsOnDate = shifts.filter { $0.shiftDate == dateISO }
    guard shiftsOnDate.count == 1, let shift = shiftsOnDate.first else {
      // Multiple shifts on date or no shift found - can't move
      return
    }

    // Store the shift and enter move mode
    shiftForOperation = shift
    isMoveMode = true
    confirmingDelete = false
  }

  /// Cancel copy/move mode and return to normal selection
  func cancelCopyMoveMode() {
    isCopyMode = false
    isMoveMode = false
    shiftForOperation = nil
    // Keep the original selection so user can try again
  }

  /// Handle date tap when in copy mode - copy shift to the tapped date
  /// - Parameter targetDateISO: The ISO date string to copy to
  func handleCopyToDate(_ targetDateISO: String) async {
    // Prevent duplicate taps
    guard !isCopying else { return }

    guard isCopyMode,
      let sourceShift = shiftForOperation
    else { return }

    // Don't copy to the same date
    guard targetDateISO != sourceShift.shiftDate else {
      cancelCopyMoveMode()
      return
    }

    isCopying = true

    do {
      // Get current user ID - use cached value or fall back to AppCoordinator
      // This guards against race conditions if user signs out mid-operation
      let userId = cachedUserId ?? AppCoordinator.shared.getCurrentUserId()
      guard let userId else {
        throw ShiftsError.notAuthenticated
      }

      // Parse the target date
      guard let targetDate = Date.fromISODateString(targetDateISO) else {
        logger.error("Invalid target date: \(targetDateISO)")
        isCopying = false
        cancelCopyMoveMode()
        return
      }

      // Create a new shift with the same times at the target date
      _ = try await shiftsRepository.createShift(
        userId: userId,
        jobId: sourceShift.shift.job_id,
        shiftDate: targetDate,
        startTime: sourceShift.startTime,
        endTime: sourceShift.endTime,
        customSupplements: sourceShift.shift.custom_supplements
      )

      logger.info("Copied shift from \(sourceShift.shiftDate) to \(targetDateISO)")

      // Exit copy mode and clear selection
      isCopyMode = false
      shiftForOperation = nil
      clearSelection()

      // Reload to show the new shift
      await reloadFromLocal()
      notifyShiftsDidChange()

    } catch {
      logger.error("Failed to copy shift: \(error.localizedDescription)")
    }

    isCopying = false
  }

  /// Handle date tap when in move mode - move shift to the tapped date
  /// - Parameter targetDateISO: The ISO date string to move to
  func handleMoveToDate(_ targetDateISO: String) async {
    // Prevent duplicate taps
    guard !isMoving else { return }

    guard isMoveMode,
      let sourceShift = shiftForOperation
    else { return }

    // Don't move to the same date
    guard targetDateISO != sourceShift.shiftDate else {
      cancelCopyMoveMode()
      return
    }

    // Virtual shifts (from recurring patterns) cannot be moved
    if sourceShift.isVirtual {
      logger.warning("Cannot move virtual shift - must move the recurring pattern")
      cancelCopyMoveMode()
      return
    }

    isMoving = true

    do {
      // Parse the target date
      guard let targetDate = Date.fromISODateString(targetDateISO) else {
        logger.error("Invalid target date: \(targetDateISO)")
        isMoving = false
        cancelCopyMoveMode()
        return
      }

      // Update the shift's date
      _ = try await shiftsRepository.updateShift(
        id: sourceShift.id,
        shiftDate: targetDate
      )

      logger.info("Moved shift from \(sourceShift.shiftDate) to \(targetDateISO)")

      // Exit move mode and clear selection
      isMoveMode = false
      shiftForOperation = nil
      clearSelection()

      // Reload to show the moved shift
      await reloadFromLocal()
      notifyShiftsDidChange()

    } catch {
      logger.error("Failed to move shift: \(error.localizedDescription)")
    }

    isMoving = false
  }

  // MARK: - Recurring Shift Editing

  /// Update a recurring shift pattern
  /// - Parameter editResult: The result from the recurring shift edit form
  func updateRecurringShift(_ editResult: RecurringShiftEditResult) async {
    // Prevent duplicate taps
    guard !isUpdatingRecurring else { return }

    isUpdatingRecurring = true
    logger.info("📝 Updating recurring shift \(editResult.recurringId)")

    do {
      _ = try await recurringShiftsRepository.updateRecurringShift(
        id: editResult.recurringId,
        startTime: editResult.startTime,
        endTime: editResult.endTime,
        repeatIntervalWeeks: editResult.repeatIntervalWeeks,
        selectedDays: editResult.selectedDays,
        endCondition: editResult.endCondition,
        exclusions: editResult.exclusions
      )

      logger.info("✅ Updated recurring shift \(editResult.recurringId)")

      // Clear recurring shifts cache so changes are picked up
      recurringShifts = []

      // Reload to show the changes
      await reloadFromLocal()

      // Post notification for other views
      notifyShiftsDidChange()

    } catch {
      logger.error("❌ Failed to update recurring shift: \(error.localizedDescription)")
    }

    isUpdatingRecurring = false
  }

  /// Delete a recurring shift pattern
  /// - Parameter recurringId: The ID of the recurring shift to delete
  func deleteRecurringShift(_ recurringId: String) async {
    // Prevent duplicate taps
    guard !isDeletingRecurring else { return }

    isDeletingRecurring = true
    logger.info("🗑️ Deleting recurring shift \(recurringId)")

    do {
      try await recurringShiftsRepository.deleteRecurringShift(id: recurringId)

      logger.info("✅ Deleted recurring shift \(recurringId)")

      // Clear recurring shifts cache so changes are picked up
      recurringShifts = []

      // Reload to show the changes
      await reloadFromLocal()

      // Post notification for other views
      notifyShiftsDidChange()

    } catch {
      logger.error("❌ Failed to delete recurring shift: \(error.localizedDescription)")
    }

    isDeletingRecurring = false
  }

  /// Get a recurring shift by ID
  /// - Parameter id: The recurring shift ID
  /// - Returns: The recurring shift if found
  func getRecurringShift(id: String) -> RecurringShiftRow? {
    recurringShiftsRepository.getRecurringShift(id: id)
  }

  // MARK: - Event Editing

  func updateEvent(_ editResult: EventEditResult) async throws {
    guard !isUpdatingEvent else { return }

    isUpdatingEvent = true
    defer { isUpdatingEvent = false }
    logger.info("📝 Updating event \(editResult.eventId)")

    guard
      let startDate = Date.fromISODateString(editResult.startDate),
      let endDate = Date.fromISODateString(editResult.endDate)
    else {
      logger.error(
        "Invalid event date range: \(editResult.startDate) - \(editResult.endDate)"
      )
      throw ShiftsError.invalidEventDateRange
    }

    do {
      guard
        try await eventsRepository.updateEvent(
          id: editResult.eventId,
          startDate: startDate,
          endDate: endDate,
          isAllDay: editResult.isAllDay,
          startTime: editResult.startTime,
          endTime: editResult.endTime,
          note: editResult.note,
          notificationMinutesArray: editResult.notificationMinutesArray,
          notificationAnchorTime: editResult.notificationAnchorTime
        ) != nil
      else {
        logger.error("❌ Event missing during update: \(editResult.eventId)")
        throw ShiftsError.eventNotFound
      }

      await reloadFromLocal()
      notifyShiftsDidChange()
    } catch {
      logger.error("❌ Failed to update event: \(error.localizedDescription)")
      throw error
    }
  }

  func deleteEvent(id: String) async throws {
    guard !isDeletingEvent else { return }

    isDeletingEvent = true
    defer { isDeletingEvent = false }

    logger.info("🗑️ Deleting event \(id)")
    try await eventsRepository.deleteEvent(id: id)
    await reloadFromLocal()
    notifyShiftsDidChange()
  }

  // MARK: - Shift Editing

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

        // Get user ID - use cached value or fall back to AppCoordinator
        // This guards against race conditions if user signs out mid-operation
        let userId = cachedUserId ?? AppCoordinator.shared.getCurrentUserId()
        guard let recurringId = editResult.recurringId,
          let userId
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

        let sourceJobId =
          shifts.first(where: { $0.id == editResult.shiftId })?.shift.job_id
          ?? recurringShifts.first(where: { $0.id == recurringId })?.job_id

        // Step 2: Create a new regular shift with the edited values
        _ = try await shiftsRepository.createShift(
          userId: userId,
          jobId: sourceJobId,
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
      notifyShiftsDidChange()

    } catch {
      logger.error("❌ Failed to update shift: \(error.localizedDescription)")
    }

    isUpdatingShift = false
  }

  /// Non-blocking month data loader
  /// Uses cache for instant display, fetches in background if needed
  /// IMPORTANT: Commits display state (year/month) atomically with shift data
  private func applyCommittedMonthSnapshot(
    shifts computedShifts: [ShiftWithComputations],
    events displayEvents: [EventRow],
    year: Int,
    month: Int
  ) {
    self.shifts = computedShifts
    self.events = displayEvents
    self.weekGroups = self.groupShiftsByWeek(computedShifts)
    self.committedYear = year
    self.committedMonth = month
  }

  private func notifyShiftsDidChange() {
    NotificationCenter.default.post(name: .shiftsDidChange, object: self)
  }

  private func loadShiftsForDisplayedMonthNonBlocking() {
    let targetYear = displayYear
    let targetMonth = displayMonth
    let displayKey = "\(targetYear)-\(targetMonth)"

    // Check if we have valid computed cache for displayed month
    if var displayCache = monthCache[displayKey], displayCache.isValid {
      // Use cached computed data - instant navigation!
      logger.info("📦 Using cached computed data for \(displayKey)")

      // Calculate conflict detection first (needed for week totals)
      updateConflictDetection(for: displayCache.shifts)

      // ATOMIC UPDATE: Set shifts and committed state together
      // This ensures the calendar structure and event data update in the same render pass.
      applyCommittedMonthSnapshot(
        shifts: displayCache.shifts,
        events: displayCache.events,
        year: targetYear,
        month: targetMonth
      )

      if self.isCurrentMonth {
        updateNextUpcomingShift(for: displayCache.shifts)
      }

      // Update last accessed time for LRU tracking
      displayCache.lastAccessed = Date()
      monthCache[displayKey] = displayCache

      // Still prefetch neighbors in background
      prefetchNeighboringMonths()
      return
    }

    // Cache miss - fetch from local in background
    // DON'T clear shifts array or update committed state - keep showing previous month until new data is ready
    // This prevents the "flash of empty state" during local SQLite reads
    logger.info("🔄 Cache miss for \(displayKey), fetching from local...")
    self.isLoading = true

    // Cancel any previous navigation task
    activeNavigationTask?.cancel()

    // Start background fetch
    activeNavigationTask = Task { [weak self] in
      guard let self = self else { return }

      // Check if this task is still relevant
      guard !Task.isCancelled,
        self.displayYear == targetYear,
        self.displayMonth == targetMonth
      else {
        logger.info("⏭️ Skipping stale fetch for \(displayKey)")
        return
      }

      await self.loadShiftsForDisplayedMonth(
        showLoadingState: false, targetYear: targetYear, targetMonth: targetMonth)

      // Check again after fetch
      guard !Task.isCancelled,
        self.displayYear == targetYear,
        self.displayMonth == targetMonth
      else {
        logger.info("⏭️ Skipping prefetch - user navigated during fetch")
        return
      }

      // Prefetch neighbors after successful load
      self.prefetchNeighboringMonths()
    }
  }

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
    // Sync tracking with current month context values
    lastObservedYear = monthContext.displayYear
    lastObservedMonth = monthContext.displayMonth
    navigationDirection = nil

    // Clear all caches on full reload (including cachedUserId for impersonation support)
    monthCache.removeAll()
    prefetchCache.removeAll()
    prefetchTasks.removeAll()
    cachedUserId = nil
    activeJobs = []

    await loadShiftsFromLocal()

    // Prefetch neighboring months in the background
    prefetchNeighboringMonths()
  }

  /// Refresh shifts data via sync then local reload
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
      prefetchCache.removeAll()
      prefetchTasks.removeAll()
      settings = nil
      snapshots = []
      recurringShifts = []
      activeJobs = []

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

    // Clear all caches to pick up new data
    // Also critical for impersonation: cachedUserId must be refreshed from current session
    monthCache.removeAll()
    prefetchCache.removeAll()
    prefetchTasks.removeAll()
    cachedUserId = nil  // Force re-fetch user ID from session (critical for impersonation)
    activeJobs = []

    // Also clear in-memory recurring shifts cache so exclusions are picked up
    recurringShifts = []

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

      activeJobs = jobsRepository.getNonDeletedJobs(for: userId)

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

      // Calculate date range for displayed month (includes out-of-month padding days visible in calendar)
      let displayYM = (year: displayYear, month: displayMonth)
      let visibleRange = Date.visibleCalendarRange(year: displayYM.year, month: displayYM.month)

      // Load shifts for the full visible calendar range (so out-of-month days show shift data)
      let displayShifts = await shiftsRepository.getShiftsOffMain(
        for: userId,
        startDate: visibleRange.start,
        endDate: visibleRange.end
      )
      let displayEvents = await eventsRepository.getEventsOffMain(
        for: userId,
        startDate: visibleRange.start,
        endDate: visibleRange.end
      )
      logger.info(
        "📋 Loaded shifts for \(displayYM.year)-\(displayYM.month): \(displayShifts.count)")
      logger.info(
        "📋 Loaded events for \(displayYM.year)-\(displayYM.month): \(displayEvents.count)")

      // Check if we have settings to compute payroll
      guard let currentSettings = self.settings else {
        logger.info("📭 No local settings yet - waiting for sync (userId: \(userId))")
        self.isLoading = false
        return
      }

      let recurringSnapshot = recurringShifts
      let snapshotsSnapshot = snapshots
      let activeJobsSnapshot = activeJobs
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

      // Calculate conflict detection first (needed for week totals)
      updateConflictDetection(for: computedShifts)

      // ATOMIC UPDATE: Set shifts, events, and committed state together.
      applyCommittedMonthSnapshot(
        shifts: computedShifts,
        events: displayEvents,
        year: displayYM.year,
        month: displayYM.month
      )

      // Find next upcoming shift (only on current month)
      if isCurrentMonth {
        updateNextUpcomingShift(for: computedShifts)
      }

      self.isLoading = false

      logger.info(
        "📊 Loaded shifts from local: \(computedShifts.count) shifts, \(self.weekGroups.count) weeks"
      )

    } catch is CancellationError {
      logger.info("⏭️ Load cancelled (user navigated away)")
    } catch {
      logger.error("❌ Shifts local load failed: \(error.localizedDescription)")
      self.error = ShiftsError.dataLoadFailed(underlying: error)
      self.isLoading = false
    }
  }

  /// Load shifts data for the currently displayed month
  /// - Parameters:
  ///   - showLoadingState: Whether to show loading indicator
  ///   - targetYear: The year to load (for atomic commit)
  ///   - targetMonth: The month to load (for atomic commit)
  private func loadShiftsForDisplayedMonth(
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

      activeJobs = jobsRepository.getNonDeletedJobs(for: userId)

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

      // Calculate date range for displayed month (includes out-of-month padding days visible in calendar)
      let displayYM = (year: loadYear, month: loadMonth)
      let visibleRange = Date.visibleCalendarRange(year: displayYM.year, month: displayYM.month)

      // Load shifts for the full visible calendar range (so out-of-month days show shift data)
      let displayShifts = await shiftsRepository.getShiftsOffMain(
        for: userId,
        startDate: visibleRange.start,
        endDate: visibleRange.end
      )
      let displayEvents = await eventsRepository.getEventsOffMain(
        for: userId,
        startDate: visibleRange.start,
        endDate: visibleRange.end
      )

      // Ensure settings are available
      guard let currentSettings = self.settings else {
        logger.info("📭 No local settings yet - waiting for sync")
        self.isLoading = false
        return
      }

      let recurringSnapshot = recurringShifts
      let snapshotsSnapshot = snapshots
      let activeJobsSnapshot = activeJobs
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

      // Calculate conflict detection first (needed for week totals)
      updateConflictDetection(for: computedShifts)

      // ATOMIC UPDATE: Set shifts, events, and committed state together.
      applyCommittedMonthSnapshot(
        shifts: computedShifts,
        events: displayEvents,
        year: loadYear,
        month: loadMonth
      )

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

      guard let shiftEnd = calendar.date(from: shiftEndComponents) else { return false }
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

    self.nextUpcomingShift = sorted.first
  }

  private func parseTime(_ time: String) -> Date? {
    hourMinuteFormatter.date(from: String(time.prefix(5)))
  }

  // MARK: - Conflict Detection

  /// Update conflict detection for the given shifts
  /// Sets conflictingShiftIds, excludedFromTotalIds, and conflictDates
  private func updateConflictDetection(for shifts: [ShiftWithComputations]) {
    let analysis = ConflictExclusion.analyze(shifts: shifts)

    self.conflictingShiftIds = analysis.conflictingIds
    self.excludedFromTotalIds = analysis.excludedIds
    self.conflictDates = analysis.conflictDates

    // Update shared context for MainTabView to show conflict indicator on list button
    SharedMonthContext.shared.hasConflictsInMonth = !analysis.conflictDates.isEmpty

    if !analysis.conflictingIds.isEmpty {
      logger.info(
        "⚠️ Found \(analysis.conflictingIds.count) conflicting shifts on \(analysis.conflictDates.count) dates, \(analysis.excludedIds.count) excluded from totals"
      )
    }

    updateSelectionSummary()
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

  /// Prefetch a single month's shift data with full payroll computation
  /// Computes payroll upfront so navigation is instant
  private func prefetchMonthInBackground(year: Int, month: Int) {
    let key = "\(year)-\(month)"

    // Skip if already have computed cache
    if let cached = monthCache[key], cached.isValid {
      return
    }

    // Skip if already prefetching
    if prefetchTasks.contains(key) {
      return
    }

    prefetchTasks.insert(key)

    Task {
      defer { prefetchTasks.remove(key) }

      guard let userId = cachedUserId,
        let currentSettings = self.settings
      else {
        return
      }

      // Get visible calendar range (includes out-of-month padding days)
      let visibleRange = Date.visibleCalendarRange(year: year, month: month)

      // Read shifts for the full visible calendar range
      let fetchedShifts = await shiftsRepository.getShiftsOffMain(
        for: userId,
        startDate: visibleRange.start,
        endDate: visibleRange.end
      )
      let fetchedEvents = await eventsRepository.getEventsOffMain(
        for: userId,
        startDate: visibleRange.start,
        endDate: visibleRange.end
      )

      let recurringSnapshot = self.recurringShifts
      let snapshotsSnapshot = self.snapshots
      let activeJobsSnapshot = self.activeJobs

      do {
        let computedShifts = try await Self.computeShiftsForMonthOffMain(
          MonthComputationInput(
            year: year,
            month: month,
            shifts: fetchedShifts,
            recurringShifts: recurringSnapshot,
            snapshots: snapshotsSnapshot,
            settings: currentSettings,
            visibleRange: visibleRange,
            jobs: activeJobsSnapshot
          )
        )

        guard !Task.isCancelled else {
          logger.info("⏭️ Prefetch cancelled for \(key)")
          return
        }

        // Store in full computed cache
        self.monthCache[key] = MonthCacheEntry(
          year: year,
          month: month,
          shifts: computedShifts,
          events: fetchedEvents,
          visibleRange: visibleRange,
          timestamp: Date()
        )

        // Evict old entries if needed
        self.evictCacheIfNeeded()

        logger.info("📦 Prefetched \(key): \(computedShifts.count) shifts (with payroll)")
      } catch is CancellationError {
        logger.info("⏭️ Prefetch cancelled for \(key)")
      } catch {
        logger.error("❌ Prefetch failed for \(key): \(error.localizedDescription)")
      }
    }
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

    // Convert to WeekGroup array (excluding conflicting shifts from totals)
    let groups = weekMap.map { key, value in
      WeekGroup(
        id: key,
        weekNumber: value.weekNumber,
        year: value.year,
        totalGross: value.shifts.reduce(0) { total, shift in
          // Don't include excluded shifts in week totals
          self.excludedFromTotalIds.contains(shift.id) ? total : total + shift.grossPay
        },
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
    // Use AuthSessionManager to prevent concurrent refresh race conditions
    let session = try await AuthSessionManager.shared.getSession()
    return session.normalizedUserId
  }
}
