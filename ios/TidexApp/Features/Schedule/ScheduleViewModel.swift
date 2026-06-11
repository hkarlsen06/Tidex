import Combine
import Foundation
import UIKit
import os.log

private let kScheduleLogger: Logger = Logger(
  subsystem: "com.tidex.app", category: "ShiftsViewModel")
private let kScheduleMonthNameFormatter: DateFormatter = FormatterCache.monthNameFormatter()
private let kScheduleISODateFormatter: DateFormatter = FormatterCache.isoDateFormatter(
  timeZone: Date.localTimeZone
)
private let kScheduleHourMinuteFormatter: DateFormatter = FormatterCache.hourMinuteFormatter(
  timeZone: Date.localTimeZone
)

// MARK: - Week Group

/// A group of shifts for a single ISO week
internal struct WeekGroup: Identifiable, Equatable {
  /// Unique identifier: "YYYY-WW" format
  internal let id: String
  /// ISO week number (1-53)
  internal let weekNumber: Int
  /// Year for the week (ISO week-numbering year)
  internal let year: Int
  /// Total gross earnings for all shifts in this week
  internal let totalGross: Double
  /// Shifts in this week, sorted by date (newest first)
  internal let shifts: [ShiftWithComputations]
}

// MARK: - Shifts Error

internal enum ShiftsError: Error, LocalizedError {
  case dataLoadFailed(underlying: Error)
  case eventNotFound
  case invalidEventDateRange
  case noLocalData
  case notAuthenticated

  internal var errorDescription: String? {
    switch self {
    case .dataLoadFailed(let error):
      return "Failed to load data: \(error.localizedDescription)"

    case .eventNotFound:
      return "Event not found. Please refresh and try again."

    case .invalidEventDateRange:
      return "Invalid event date range"

    case .noLocalData:
      return "No local data available. Please wait for sync to complete."

    case .notAuthenticated:
      return "Not authenticated"
    }
  }
}

// MARK: - Month Cache Entry

/// Cache entry for a single month's computed shifts
private struct MonthCacheEntry {
  private static let validityDuration: TimeInterval = 300

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
    Date().timeIntervalSince(timestamp) < Self.validityDuration
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

/// Cached selection summary for quick header rendering.
private struct SelectionSummary {
  let net: Double
  let gross: Double
  let hasTaxEnabled: Bool
  let currencyAggregate: JobCurrencyAggregateResolution?
}

internal struct CalendarPayTotals {
  internal let net: Double
  internal let gross: Double
}

internal struct ShiftsCalendarPresentation {
  internal let shiftsByDate: [String: [ShiftWithComputations]]
  internal let earningsByDate: [String: CalendarEarningsData]
  internal let hoursByDate: [String: HoursData]
  internal let monthlyTotals: CalendarPayTotals
  internal let monthlyCurrencyAggregate: JobCurrencyAggregateResolution
  internal let jobsById: [String: Job]
  internal let defaultJobId: String?
  internal let hasMultipleActiveJobs: Bool

  static func empty(currency: String = "kr") -> Self {  // swiftlint:disable:this explicit_acl
    Self(
      shiftsByDate: [:],
      earningsByDate: [:],
      hoursByDate: [:],
      monthlyTotals: CalendarPayTotals(net: 0, gross: 0),
      monthlyCurrencyAggregate: JobCurrencyAggregateResolver.resolve(
        shifts: [],
        jobs: [],
        fallbackCurrency: currency
      ),
      jobsById: [:],
      defaultJobId: nil,
      hasMultipleActiveJobs: false
    )
  }

  internal static func build(
    shifts: [ShiftWithComputations],
    year: Int,
    month: Int,
    jobs: [Job],
    currency: String,
    excludedFromTotalIds: Set<String>
  ) -> Self {
    let shiftsByDate = Dictionary(grouping: shifts, by: \.shiftDate)
    var earningsByDate: [String: CalendarEarningsData] = [:]
    var hoursByDate: [String: HoursData] = [:]
    var monthlyIncludedShifts: [ShiftWithComputations] = []
    var monthlyNet: Double = 0
    var monthlyGross: Double = 0
    var calendar = Calendar.current
    calendar.timeZone = Date.localTimeZone

    for (date, shiftsOnDate) in shiftsByDate {
      let includedShifts = shiftsOnDate.filter { !excludedFromTotalIds.contains($0.id) }

      if !includedShifts.isEmpty {
        let gross = includedShifts.reduce(0) { $0 + $1.grossPay }
        let net = includedShifts.reduce(0) { partialResult, shift in
          partialResult + (shift.taxEnabled ? shift.netPay : shift.grossPay)
        }
        earningsByDate[date] = CalendarEarningsData(
          net: net,
          gross: gross,
          hasTaxEnabled: includedShifts.contains(where: \.taxEnabled)
        )
      }

      let sorted = shiftsOnDate.sorted { $0.startTime < $1.startTime }
      let earliestStart = sorted.first?.startTime ?? ""
      let latestEnd = sorted.map(\.endTime).max() ?? ""
      let crossesMidnight = shiftsOnDate.contains { shift in
        let startMinutes = CalendarGridHelper.timeToMinutes(shift.startTime)
        let endMinutes = CalendarGridHelper.timeToMinutes(shift.endTime)
        return endMinutes <= startMinutes
      }
      hoursByDate[date] = HoursData(
        start: CalendarGridHelper.formatTime(earliestStart),
        end: CalendarGridHelper.formatTime(latestEnd),
        crossesMidnight: crossesMidnight
      )

      guard let shiftDate = Date.fromISODateString(date) else { continue }
      let components = calendar.dateComponents([.year, .month], from: shiftDate)
      guard components.year == year, components.month == month else { continue }
      monthlyIncludedShifts.append(contentsOf: includedShifts)
      monthlyGross += includedShifts.reduce(0) { $0 + $1.grossPay }
      monthlyNet += includedShifts.reduce(0) { partialResult, shift in
        partialResult + (shift.taxEnabled ? shift.netPay : shift.grossPay)
      }
    }

    return Self(
      shiftsByDate: shiftsByDate,
      earningsByDate: earningsByDate,
      hoursByDate: hoursByDate,
      monthlyTotals: CalendarPayTotals(net: monthlyNet, gross: monthlyGross),
      monthlyCurrencyAggregate: JobCurrencyAggregateResolver.resolve(
        shifts: monthlyIncludedShifts,
        jobs: jobs,
        fallbackCurrency: currency
      ),
      jobsById: Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) }),
      defaultJobId: jobs.first(where: \.is_default)?.id,
      hasMultipleActiveJobs: jobs.count > 1
    )
  }
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
// swiftlint:disable:next explicit_acl explicit_top_level_acl type_body_length
final class ShiftsViewModel: ObservableObject, MonthNavigable {

  // MARK: - Dependencies (Local-First Repositories)

  private let shiftsRepository: ShiftsRepository
  private let eventsRepository: EventsRepository
  private let jobsRepository: JobsRepository
  private let settingsRepository: SettingsRepository
  private let snapshotsRepository: SnapshotsRepository
  private let recurringShiftsRepository: RecurringShiftsRepository
  private let monthlyPayrollReadService: MonthlyPayrollReadService
  private let syncCoordinator: SyncCoordinator
  private let monthContext: SharedMonthContext

  // MARK: - Published State

  /// All shifts for the displayed month (computed with payroll)
  private(set) var shifts: [ShiftWithComputations] = []
  /// Private events overlapping the currently visible calendar range.
  private(set) var events: [EventRow] = []
  /// Event presentations keyed by covered ISO date for the displayed calendar range.
  private(set) var eventCoverageByDate: [String: [EventPresentation]] = [:]
  /// Precomputed calendar maps and totals for the displayed month.
  private(set) var calendarPresentation = ShiftsCalendarPresentation.empty()
  /// Shifts grouped by ISO week
  private(set) var weekGroups: [WeekGroup] = []
  /// Whether data is currently loading
  @Published private(set) var isLoading = false
  /// Error if data loading failed
  @Published private(set) var error: Error?
  /// Set of shift IDs that have conflicts (overlapping with other shifts)
  private(set) var conflictingShiftIds: Set<String> = []
  /// Set of shift IDs excluded from totals (higher-earning overlapping shifts are excluded)
  private(set) var excludedFromTotalIds: Set<String> = []
  /// Set of dates (ISO strings) that have conflicts
  private(set) var conflictDates: Set<String> = []

  /// Direction of last navigation (for animations) - synced from SharedMonthContext
  @Published private(set) var navigationDirection: MonthNavigationDirection?

  // MARK: - Committed Display State
  // These values only update AFTER shift data is ready, ensuring atomic rendering
  // The calendar uses these to avoid showing the new month structure before data arrives

  /// The year that is actually ready to display (data loaded)
  private(set) var committedYear: Int

  /// The month that is actually ready to display (data loaded)
  private(set) var committedMonth: Int

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
      return kScheduleMonthNameFormatter.string(from: date)
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
    }
    if displayedIndex == currentIndex {
      return .current
    }
    return .future
  }

  /// User's currency for formatting
  @Published private(set) var currency: String = "kr"

  /// Next upcoming shift (for countdown display)
  private(set) var nextUpcomingShift: ShiftWithComputations?

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

  /// Target dates selected while choosing where to copy a shift.
  @Published var copyTargetDates: Set<String> = []

  /// Whether a recurring shift update is in progress
  @Published var isUpdatingRecurring: Bool = false

  /// Whether a recurring shift deletion is in progress
  @Published var isDeletingRecurring: Bool = false

  /// Whether a shift update is in progress
  @Published var isUpdatingShift: Bool = false

  /// Whether to show the month limit sheet for copy operations.
  @Published var showMonthLimitSheet = false

  /// Set of existing months when the paywall is triggered.
  @Published private(set) var existingShiftMonths: Set<DateComponents> = []

  /// Target month the user is trying to copy shifts to.
  @Published private(set) var targetMonth = DateComponents()  // swiftlint:disable:this explicit_acl explicit_type_interface line_length type_contents_order

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
    guard let summary = selectionSummary else {
      return nil
    }
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

  /// Earnings preview for the shift currently being copied to selected target dates.
  var copyPreviewEarnings: [String: CalendarEarningsData] {
    guard isCopyMode, let sourceShift = shiftForOperation else {
      return [:]
    }

    var result: [String: CalendarEarningsData] = [:]
    for dateISO in copyTargetDates {
      if let earnings = computeCopyPreviewEarnings(for: dateISO, sourceShift: sourceShift) {
        result[dateISO] = earnings
      }
    }
    return result
  }

  /// Target dates where the copied shift would overlap an existing shift.
  var copyPreviewConflictDates: Set<String> {
    guard isCopyMode,
      let sourceShift = shiftForOperation,
      !copyTargetDates.isEmpty
    else {
      return []
    }

    return ShiftConflictDetector.detectConflicts(
      dates: Array(copyTargetDates),
      startTime: sourceShift.startTime,
      endTime: sourceShift.endTime,
      existingShifts: shifts.map(\.shift),
      existingRecurringShifts: recurringShifts
    )
  }

  /// Shifts for the selected date (single selection mode)
  var selectedDateShifts: [ShiftWithComputations] {
    guard selectedDates.count == 1, let dateISO = selectedDates.first else {
      return []
    }
    return shifts.filter { $0.shiftDate == dateISO }
  }

  var shouldShowJobIndicators: Bool {
    activeJobs.count > 1
  }

  private var activeJobsById: [String: Job] {
    Dictionary(uniqueKeysWithValues: activeJobs.map { ($0.id, $0) })
  }

  func jobForShift(_ shift: ShiftWithComputations) -> Job? {
    guard let jobId = shift.shift.job_id else {
      return nil
    }
    return activeJobsById[jobId]
  }

  private static func visibleRange(
    _ visibleRange: (start: Date, end: Date), contains dateISO: String
  )
    -> Bool
  {
    guard let date = Date.fromISODateString(dateISO) else {
      return false
    }

    return date >= visibleRange.start && date <= visibleRange.end
  }

  private static func buildEventCoverageByDate(
    events: [EventRow],
    visibleRange: (start: Date, end: Date)
  ) -> [String: [EventPresentation]] {
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
          guard Self.visibleRange(visibleRange, contains: coveredDateISO) else { continue }
          result[coveredDateISO, default: []].append(
            EventPresentation(event: event, coveredDateISO: coveredDateISO)
          )
        }
      } else if Self.visibleRange(visibleRange, contains: event.start_date) {
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
  private var scheduleDependenciesLoaded = false
  private var cachedUserId: String?
  private var isActiveTabVisible = true
  private var displayedMonthLoadPending = false

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

  /// Background prefetch tasks keyed by month (to avoid duplicates and cancel stale work).
  private var prefetchTasks: [String: Task<Void, Never>] = [:]

  /// Memory warning observer
  private var memoryWarningObserver: NSObjectProtocol?

  /// Shift reminder tap observer for deep linking
  private var shiftReminderObserver: NSObjectProtocol?

  /// Whether cached month data must be rebuilt from local storage before reuse.
  private var localDataNeedsReload = false

  /// Cross-tab shift/event change observer.
  private var shiftsDidChangeObserver: NSObjectProtocol?

  /// In-flight local reload shared by notification and tab-entry callers.
  private var localReloadTask: Task<Void, Never>?
  private var localReloadID: UUID?

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
    monthlyPayrollReadService: MonthlyPayrollReadService? = nil,
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
    self.monthlyPayrollReadService =
      monthlyPayrollReadService
      ?? MonthlyPayrollReadService(
        shiftsRepository: self.shiftsRepository,
        eventsRepository: self.eventsRepository,
        settingsRepository: self.settingsRepository,
        snapshotsRepository: self.snapshotsRepository,
        recurringShiftsRepository: self.recurringShiftsRepository,
        jobsRepository: self.jobsRepository
      )
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

    // Local writes can happen from other tabs, including Wagey-driven event creation.
    // Reload from local storage so cached month data reflects those writes immediately.
    shiftsDidChangeObserver = NotificationCenter.default.addObserver(
      forName: .shiftsDidChange,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      Task { @MainActor in
        guard let self else {
          return
        }
        if let sender = notification.object as AnyObject?, sender === self {
          return
        }
        await self.handleExternalShiftsDidChange(notification.shiftChangeContext)
      }
    }
  }

  /// Subscribe to SharedMonthContext changes to reload data when month changes
  private func setupMonthContextSubscription() {
    monthContextCancellable = monthContext.monthChanged
      .receive(on: DispatchQueue.main)
      .sink { [weak self] newMonth in
        guard let self else {
          return
        }

        // Only reload if month actually changed
        guard newMonth.year != lastObservedYear || newMonth.month != lastObservedMonth
        else {
          return
        }

        // Update tracking
        lastObservedYear = newMonth.year
        lastObservedMonth = newMonth.month

        // Sync navigation direction from context
        navigationDirection = monthContext.navigationDirection

        guard isActiveTabVisible else {
          displayedMonthLoadPending = true
          kScheduleLogger.info("⏸️ Deferring schedule month load while Schedule tab is hidden")
          return
        }

        // Trigger data reload for new month
        loadShiftsForDisplayedMonthNonBlocking()
      }
  }

  deinit {
    // Cancel Combine subscriptions to prevent memory leaks
    monthContextCancellable?.cancel()
    localReloadTask?.cancel()
    activeNavigationTask?.cancel()
    for task in prefetchTasks.values {
      task.cancel()
    }

    if let observer = memoryWarningObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    if let observer = shiftReminderObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    if let observer = shiftsDidChangeObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  // MARK: - Memory Management

  /// Handle memory warning by clearing the cache
  private func handleMemoryWarning() {
    kScheduleLogger.warning(
      "⚠️ Memory warning received - clearing month cache (\(self.monthCache.count) entries)"
    )
    monthCache.removeAll()
    cancelPrefetchTasks()
  }

  // MARK: - Deep Linking

  /// Handle shift reminder notification tap - navigate to the shift's date
  private func handleShiftReminderTap(_ notification: Notification) {
    guard let userInfo = notification.userInfo,
      let shiftDateString = userInfo["shift_date"] as? String
    else {
      kScheduleLogger.warning("Shift reminder tap missing shift_date")
      return
    }

    kScheduleLogger.info("Deep linking to shift date: \(shiftDateString)")

    // Parse the shift date (format: "yyyy-MM-dd")
    guard let shiftDate = kScheduleISODateFormatter.date(from: shiftDateString) else {
      kScheduleLogger.warning("Failed to parse shift date: \(shiftDateString)")
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
    guard monthCache.count > Self.maxCacheSize else {
      return
    }

    // Sort by last accessed time (oldest first)
    let sortedKeys = monthCache.keys.sorted { key1, key2 in
      guard let entry1 = monthCache[key1], let entry2 = monthCache[key2] else {
        return false
      }
      return entry1.lastAccessed < entry2.lastAccessed
    }

    // Remove oldest entries until we're under the limit
    let entriesToRemove = monthCache.count - Self.maxCacheSize
    for i in 0..<entriesToRemove {
      let key = sortedKeys[i]
      monthCache.removeValue(forKey: key)
      kScheduleLogger.info("🗑️ Evicted cache entry: \(key)")
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
    guard !shiftsOnDay.isEmpty else {
      return
    }

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
    copyTargetDates.removeAll()
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

    guard !datesWithShifts.isEmpty else {
      return
    }

    // Add to existing selection (union, not replace)
    selectedDates.formUnion(datesWithShifts)
  }

  /// Delete all shifts for selected dates
  func deleteSelectedShifts() async {
    let shiftsToDelete = shifts.filter { selectedDates.contains($0.shiftDate) }
    guard !shiftsToDelete.isEmpty else {
      return
    }

    isDeleting = true

    do {
      let virtualExclusions = shiftsToDelete.compactMap {
        shift -> (recurringId: String, date: String)? in
        guard shift.isVirtual, let recurringId = shift.shift.recurring_id else {
          return nil
        }
        return (recurringId, shift.shiftDate)
      }
      let virtualExclusionsByRecurringId = Dictionary(
        grouping: virtualExclusions,
        by: { $0.recurringId }
      ).mapValues { exclusions in
        exclusions.map(\.date)
      }
      let regularShiftIds = shiftsToDelete.filter { !$0.isVirtual }.map(\.id)

      for (recurringId, dates) in virtualExclusionsByRecurringId {
        try await recurringShiftsRepository.addExclusions(
          id: recurringId,
          dates: dates
        )
      }

      if !regularShiftIds.isEmpty {
        try await shiftsRepository.deleteShifts(ids: regularShiftIds)
      }

      clearSelection()
      await reloadFromLocal()
      notifyShiftsDidChange(
        context: .affecting(
          isoDates: shiftsToDelete.map(\.shiftDate)
        ))

      // Play deletion feedback
      Haptics.playShiftDeleted()
    } catch {
      kScheduleLogger.error("Failed to delete shifts: \(error.localizedDescription)")
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
    copyTargetDates.removeAll()
    isCopyMode = true
    isMoveMode = false
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
    copyTargetDates.removeAll()
    isCopyMode = false
    isMoveMode = true
    confirmingDelete = false
  }

  /// Cancel copy/move mode and return to normal selection
  func cancelCopyMoveMode() {
    isCopyMode = false
    isMoveMode = false
    copyTargetDates.removeAll()
    shiftForOperation = nil
    // Keep the original selection so user can try again
  }

  /// Toggle a target date while choosing where to copy the selected shift.
  /// - Parameter targetDateISO: The ISO date string to copy to.
  func toggleCopyTargetDate(_ targetDateISO: String) {
    guard isCopyMode, let sourceShift = shiftForOperation else {
      return
    }
    guard targetDateISO != sourceShift.shiftDate else {
      return
    }

    if copyTargetDates.contains(targetDateISO) {
      copyTargetDates.remove(targetDateISO)
    } else {
      copyTargetDates.insert(targetDateISO)
    }
  }

  /// Finish copy mode by copying the selected shift to all chosen target dates.
  func finishCopyToSelectedDates() async {
    // Prevent duplicate taps
    guard !isCopying else {
      return
    }

    guard isCopyMode,
      let sourceShift = shiftForOperation,
      !copyTargetDates.isEmpty
    else { return }

    isCopying = true
    defer {
      isCopying = false
    }

    do {
      // Get current user ID - use cached value or fall back to AppCoordinator
      // This guards against race conditions if user signs out mid-operation
      let userId = cachedUserId ?? AppCoordinator.shared.getCurrentUserId()
      guard let userId else {
        throw ShiftsError.notAuthenticated
      }

      let sortedTargetDates = copyTargetDates.sorted()
      let tier = EntitlementService.shared.effectiveTier
      if let blockedTargetDate = firstBlockedCopyTargetDate(
        sortedTargetDates,
        userId: userId,
        tier: tier
      ) {
        presentMonthLimitSheet(for: blockedTargetDate, userId: userId)
        return
      }

      for targetDateISO in sortedTargetDates {
        guard let targetDate = Date.fromISODateString(targetDateISO) else {
          kScheduleLogger.error("Invalid target date: \(targetDateISO)")
          continue
        }

        // Create a new shift with the same times at the target date
        _ = try await shiftsRepository.createShiftWithTierCheck(
          userId: userId,
          jobId: sourceShift.shift.job_id,
          shiftDate: targetDate,
          startTime: sourceShift.startTime,
          endTime: sourceShift.endTime,
          customSupplements: sourceShift.shift.custom_supplements,
          tier: tier
        )
      }

      kScheduleLogger.info(
        "Copied shift from \(sourceShift.shiftDate) to \(self.copyTargetDates.count) target dates")

      // Exit copy mode and clear selection
      isCopyMode = false
      copyTargetDates.removeAll()
      shiftForOperation = nil
      clearSelection()

      // Reload to show the new shift
      await reloadFromLocal()
      notifyShiftsDidChange(context: .affecting(isoDates: sortedTargetDates))

    } catch ShiftCreationError.monthLimitReached(let months) {
      existingShiftMonths = months
      if let firstDateISO = copyTargetDates.min(),
        let date = Date.fromISODateString(firstDateISO)
      {
        targetMonth = Calendar.current.dateComponents([.year, .month], from: date)
      }
      showMonthLimitSheet = true
      Haptics.play(.error)
    } catch {
      kScheduleLogger.error("Failed to copy shift: \(error.localizedDescription)")
    }
  }

  private func firstBlockedCopyTargetDate(
    _ targetDateISOs: [String],
    userId: String,
    tier: SubscriptionTier
  ) -> Date? {
    guard tier == .free else {
      return nil
    }

    for targetDateISO in targetDateISOs {
      guard let targetDate = Date.fromISODateString(targetDateISO) else { continue }
      if !shiftsRepository.canCreateShift(userId: userId, targetDate: targetDate, tier: tier) {
        return targetDate
      }
    }

    return nil
  }

  private func presentMonthLimitSheet(for targetDate: Date, userId: String) {
    existingShiftMonths = shiftsRepository.getExistingShiftMonths(for: userId)
    targetMonth = Calendar.current.dateComponents([.year, .month], from: targetDate)
    showMonthLimitSheet = true
    Haptics.play(.error)
  }

  /// Delete shifts in other months and retry the pending copy operation.
  func deleteShiftsInOtherMonthsForCopy() async -> Bool {
    guard let userId = AppCoordinator.shared.getCurrentUserId() else {
      kScheduleLogger.warning("Cannot delete shifts: no user ID")
      return false
    }

    do {
      let deletedCount = try await shiftsRepository.deleteShiftsInOtherMonths(
        userId: userId,
        targetMonth: targetMonth
      )

      kScheduleLogger.info("Deleted \(deletedCount) shifts in other months before copying")
      existingShiftMonths.removeAll()
      await reloadFromLocal()
      notifyShiftsDidChange(context: .fullReload)
      return true
    } catch {
      kScheduleLogger.error(
        "Failed to delete shifts in other months: \(error.localizedDescription)")
      return false
    }
  }

  func onCopyMonthLimitDeleteComplete() {
    Task {
      await finishCopyToSelectedDates()
    }
  }

  func onCopyMonthLimitUpgradeComplete() {
    Task {
      await finishCopyToSelectedDates()
    }
  }

  private func computeCopyPreviewEarnings(
    for dateISO: String,
    sourceShift: ShiftWithComputations
  ) -> CalendarEarningsData? {
    let jobId = sourceShift.shift.job_id
    let scopedSnapshots = snapshotsForJob(jobId)

    let wageSnapshot = SnapshotsService.snapshotForDate(dateISO, from: scopedSnapshots)
    let payoutDate = PayrollEngine.calculatePayoutDate(
      shiftDate: dateISO,
      payrollDay: payrollDay(for: jobId)
    )
    let taxSnapshot = SnapshotsService.snapshotForDate(payoutDate, from: scopedSnapshots)

    let shift = ShiftRow(
      id: "copy-preview-\(dateISO)",
      user_id: sourceShift.shift.user_id,
      job_id: jobId,
      shift_date: dateISO,
      start_time: sourceShift.startTime,
      end_time: sourceShift.endTime,
      custom_supplements: sourceShift.shift.custom_supplements
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: wageSnapshot)
    let taxEnabled = taxSnapshot?.effectiveTaxEnabled ?? false
    let net = computed.netPay(
      taxEnabled: taxEnabled,
      taxPercentage: taxSnapshot?.effectiveTaxPercentage ?? 0
    )

    return CalendarEarningsData(net: net, gross: computed.gross, hasTaxEnabled: taxEnabled)
  }

  private func snapshotsForJob(_ jobId: String?) -> [WageSnapshot] {
    let jobSnapshots = snapshots.filter { $0.job_id == jobId }
    if !jobSnapshots.isEmpty {
      return jobSnapshots
    }

    let defaultJobId = activeJobs.first(where: \.is_default)?.id  // swiftlint:disable:this explicit_type_interface
    if defaultJobId == jobId {
      return snapshots.filter { $0.job_id == nil }
    }

    return []
  }

  private func payrollDay(for jobId: String?) -> Int {
    if let jobId, let jobPayrollDay = activeJobs.first(where: { $0.id == jobId })?.payroll_day {
      return jobPayrollDay
    }
    return settings?.effectivePayrollDay ?? 1
  }

  /// Handle date tap when in move mode - move shift to the tapped date
  /// - Parameter targetDateISO: The ISO date string to move to
  func handleMoveToDate(_ targetDateISO: String) async {
    // Prevent duplicate taps
    guard !isMoving else {
      return
    }

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
      kScheduleLogger.warning("Cannot move virtual shift - must move the recurring pattern")
      cancelCopyMoveMode()
      return
    }

    isMoving = true

    do {
      // Parse the target date
      guard let targetDate = Date.fromISODateString(targetDateISO) else {
        kScheduleLogger.error("Invalid target date: \(targetDateISO)")
        isMoving = false
        cancelCopyMoveMode()
        return
      }

      // Update the shift's date
      _ = try await shiftsRepository.updateShift(
        id: sourceShift.id,
        shiftDate: targetDate
      )

      kScheduleLogger.info("Moved shift from \(sourceShift.shiftDate) to \(targetDateISO)")

      // Exit move mode and clear selection
      isMoveMode = false
      shiftForOperation = nil
      clearSelection()

      // Reload to show the moved shift
      await reloadFromLocal()
      notifyShiftsDidChange(
        context: .affecting(
          isoDates: [sourceShift.shiftDate, targetDateISO]
        ))

    } catch {
      kScheduleLogger.error("Failed to move shift: \(error.localizedDescription)")
    }

    isMoving = false
  }

  // MARK: - Recurring Shift Editing

  /// Update a recurring shift pattern
  /// - Parameter editResult: The result from the recurring shift edit form
  func updateRecurringShift(_ editResult: RecurringShiftEditResult) async {
    // Prevent duplicate taps
    guard !isUpdatingRecurring else {
      return
    }

    isUpdatingRecurring = true
    kScheduleLogger.info("📝 Updating recurring shift \(editResult.recurringId)")

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

      kScheduleLogger.info("✅ Updated recurring shift \(editResult.recurringId)")

      // Clear recurring shifts cache so changes are picked up
      recurringShifts = []
      scheduleDependenciesLoaded = false

      // Reload to show the changes
      await reloadFromLocal()

      // Post notification for other views
      notifyShiftsDidChange(context: .fullReload)

    } catch {
      kScheduleLogger.error("❌ Failed to update recurring shift: \(error.localizedDescription)")
    }

    isUpdatingRecurring = false
  }

  func stopRecurringShiftAfterDate(recurringId: String, occurrenceDate: String) async throws {
    guard !isUpdatingRecurring else { throw ShiftSaveError.alreadyInProgress }

    isUpdatingRecurring = true
    defer { isUpdatingRecurring = false }
    kScheduleLogger.info("📝 Ending recurring shift \(recurringId) after \(occurrenceDate)")

    do {
      _ = try await recurringShiftsRepository.updateRecurringShift(
        id: recurringId,
        endCondition: .endDate(date: occurrenceDate)
      )

      recurringShifts = []
      scheduleDependenciesLoaded = false

      await reloadFromLocal()
      notifyShiftsDidChange(context: .fullReload)
    } catch {
      kScheduleLogger.error("❌ Failed to end recurring shift: \(error.localizedDescription)")
      throw error
    }
  }

  /// Delete a recurring shift pattern
  /// - Parameter recurringId: The ID of the recurring shift to delete
  func deleteRecurringShift(_ recurringId: String) async {
    // Prevent duplicate taps
    guard !isDeletingRecurring else {
      return
    }

    isDeletingRecurring = true
    kScheduleLogger.info("🗑️ Deleting recurring shift \(recurringId)")

    do {
      try await recurringShiftsRepository.deleteRecurringShift(id: recurringId)

      kScheduleLogger.info("✅ Deleted recurring shift \(recurringId)")

      // Clear recurring shifts cache so changes are picked up
      recurringShifts = []
      scheduleDependenciesLoaded = false

      // Reload to show the changes
      await reloadFromLocal()

      // Post notification for other views
      notifyShiftsDidChange(context: .fullReload)

    } catch {
      kScheduleLogger.error("❌ Failed to delete recurring shift: \(error.localizedDescription)")
    }

    isDeletingRecurring = false
  }

  /// Get a recurring shift by ID
  /// - Parameter id: The recurring shift ID
  /// - Returns: The recurring shift if found
  func getRecurringShift(id: String) -> RecurringShiftRow? {
    recurringShiftsRepository.getRecurringShift(id: id)
  }

  func getDisplayedShift(id: String) -> ShiftWithComputations? {
    shifts.first(where: { $0.id == id })
  }

  // MARK: - Event Editing

  func updateEvent(_ editResult: EventEditResult) async throws {
    guard !isUpdatingEvent else {
      return
    }

    isUpdatingEvent = true
    defer { isUpdatingEvent = false }
    kScheduleLogger.info("📝 Updating event \(editResult.eventId)")
    let existingEvent = events.first(where: { $0.id == editResult.eventId })

    guard
      let startDate = Date.fromISODateString(editResult.startDate),
      let endDate = Date.fromISODateString(editResult.endDate)
    else {
      kScheduleLogger.error(
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
        kScheduleLogger.error("❌ Event missing during update: \(editResult.eventId)")
        throw ShiftsError.eventNotFound
      }

      await reloadFromLocal()
      notifyShiftsDidChange(
        context: eventChangeContext(
          for: editResult,
          existingEvent: existingEvent
        ))
    } catch {
      kScheduleLogger.error("❌ Failed to update event: \(error.localizedDescription)")
      throw error
    }
  }

  func deleteEvent(_ event: EventRow) async throws {
    guard !isDeletingEvent else {
      return
    }

    isDeletingEvent = true
    defer { isDeletingEvent = false }

    kScheduleLogger.info("🗑️ Deleting event \(event.id)")

    try await eventsRepository.deleteEvent(id: event.id)
    await reloadFromLocal()
    notifyShiftsDidChange(
      context: .affecting(
        isoDateRangeStart: event.start_date,
        end: event.end_date
      ))
  }

  // MARK: - Shift Editing

  /// Update a shift with new date/time values
  /// - Parameter editResult: The result from the shift edit form
  func updateShift(_ editResult: ShiftEditResult) async throws {
    // Prevent duplicate taps
    guard !isUpdatingShift else { throw ShiftSaveError.alreadyInProgress }

    isUpdatingShift = true
    defer { isUpdatingShift = false }
    kScheduleLogger.info("📝 Updating shift \(editResult.shiftId)")

    do {
      // Parse the new date
      guard let newDate = Date.fromISODateString(editResult.shiftDate) else {
        kScheduleLogger.error("Invalid date format: \(editResult.shiftDate)")
        throw ShiftSaveError.invalidDate
      }

      let currentShift = shifts.first(where: { $0.id == editResult.shiftId })?.shift
      let hasTimeOrDateChanges =
        editResult.shiftDate != currentShift?.shift_date
        || editResult.startTime != currentShift.map { String($0.start_time.prefix(5)) }
        || editResult.endTime != currentShift.map { String($0.end_time.prefix(5)) }
      let resolvedNote = editResult.noteWasEdited ? editResult.note : currentShift?.note

      if editResult.isVirtualShiftConversion {
        // Virtual shift conversion:
        // 1. Add exclusion to the recurring shift for the original date
        // 2. Create a new regular shift with the edited values
        kScheduleLogger.info("🔄 Converting virtual shift to regular shift")

        // Get user ID - use cached value or fall back to AppCoordinator
        // This guards against race conditions if user signs out mid-operation
        let userId = cachedUserId ?? AppCoordinator.shared.getCurrentUserId()
        guard let recurringId = editResult.recurringId,
          let userId
        else {
          kScheduleLogger.error("Missing recurringId or userId for virtual shift conversion")
          throw ShiftSaveError.missingRecurringInfo
        }

        let recurringShift =
          recurringShifts.first(where: { $0.id == recurringId })
          ?? recurringShiftsRepository.getRecurringShift(id: recurringId)

        if !hasTimeOrDateChanges, editResult.customSupplements == nil, editResult.noteWasEdited {
          var updatedNotes = recurringShift?.date_specific_notes ?? [:]
          if let resolvedNote {
            updatedNotes[editResult.originalDate] = resolvedNote
          } else {
            updatedNotes.removeValue(forKey: editResult.originalDate)
          }

          _ = try await recurringShiftsRepository.updateDateSpecificNotes(
            id: recurringId,
            dateSpecificNotes: updatedNotes
          )
          kScheduleLogger.info("✅ Updated recurring note for \(editResult.originalDate)")
        } else {
          if var updatedNotes = recurringShift?.date_specific_notes {
            updatedNotes.removeValue(forKey: editResult.originalDate)
            _ = try await recurringShiftsRepository.updateDateSpecificNotes(
              id: recurringId,
              dateSpecificNotes: updatedNotes
            )
          }

          // Step 1: Add exclusion for the original date
          try await RecurringShiftsRepository.shared.addExclusion(
            id: recurringId,
            date: editResult.originalDate
          )
          kScheduleLogger.info("✅ Added exclusion for \(editResult.originalDate)")

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
            note: resolvedNote,
            customSupplements: editResult.customSupplements
          )
          kScheduleLogger.info("✅ Created new shift on \(editResult.shiftDate)")

          if var updatedNotes = recurringShift?.date_specific_notes {
            updatedNotes.removeValue(forKey: editResult.originalDate)
            _ = try await recurringShiftsRepository.updateDateSpecificNotes(
              id: recurringId,
              dateSpecificNotes: updatedNotes
            )
          }
        }

      } else {
        // Regular shift update - just update the existing shift
        _ = try await shiftsRepository.updateShift(
          id: editResult.shiftId,
          shiftDate: newDate,
          startTime: editResult.startTime,
          endTime: editResult.endTime,
          note: editResult.note,
          noteWasEdited: editResult.noteWasEdited,
          customSupplements: editResult.customSupplements
        )
        kScheduleLogger.info("✅ Updated shift \(editResult.shiftId)")
      }

      // Reload to show the changes
      await reloadFromLocal()

      // Post notification for other views
      notifyShiftsDidChange(
        context: shiftChangeContext(
          for: editResult,
          existingShift: currentShift
        ))

    } catch {
      kScheduleLogger.error("❌ Failed to update shift: \(error.localizedDescription)")
      throw error
    }
  }

  func updateShiftPause(_ editResult: ShiftPauseEditResult) async {
    guard !isUpdatingShift else {
      return
    }

    isUpdatingShift = true
    defer { isUpdatingShift = false }

    kScheduleLogger.info("⏸️ Updating shift pause windows")
    let changeContext: ShiftChangeContext

    switch editResult.target {
    case .standalone(let shiftId):
      if let shift = shifts.first(where: { $0.id == shiftId }) {
        changeContext = .affecting(isoDate: shift.shiftDate)
      } else {
        changeContext = .fullReload
      }

    case .recurringOccurrence(_, let date):
      changeContext = .affecting(isoDate: date)
    }

    do {
      switch editResult.target {
      case .standalone(let shiftId):
        _ = try await shiftsRepository.updateCustomPauseWindows(
          id: shiftId,
          customPauseWindows: editResult.customPauseWindows
        )

      case .recurringOccurrence(let recurringId, let date):
        guard
          let recurringShift = recurringShifts.first(where: { $0.id == recurringId })
            ?? recurringShiftsRepository.getRecurringShift(id: recurringId)
        else {
          kScheduleLogger.error("Recurring shift not found for pause update: \(recurringId)")
          return
        }

        var updatedPauseWindows = recurringShift.date_specific_pause_windows ?? [:]
        if let normalized = PauseWindowSupport.normalize(editResult.customPauseWindows) {
          updatedPauseWindows[date] = normalized
        } else {
          updatedPauseWindows.removeValue(forKey: date)
        }

        _ = try await recurringShiftsRepository.updateDateSpecificPauseWindows(
          id: recurringId,
          dateSpecificPauseWindows: PauseWindowSupport.normalize(updatedPauseWindows)
        )
      }

      await reloadFromLocal()
      notifyShiftsDidChange(context: changeContext)
    } catch {
      kScheduleLogger.error("❌ Failed to update shift pause windows: \(error.localizedDescription)")
    }
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
    let visibleRange = Date.visibleCalendarRange(year: year, month: month)
    let currentMonth = Date.currentYearMonth()
    let nextUpcomingShift =
      currentMonth.year == year && currentMonth.month == month
      ? findNextUpcomingShift(in: computedShifts)
      : nil

    objectWillChange.send()
    updateConflictDetection(for: computedShifts)
    self.shifts = computedShifts
    self.events = displayEvents
    self.eventCoverageByDate = Self.buildEventCoverageByDate(
      events: displayEvents,
      visibleRange: visibleRange
    )
    self.weekGroups = self.groupShiftsByWeek(computedShifts)
    self.calendarPresentation = ShiftsCalendarPresentation.build(
      shifts: computedShifts,
      year: year,
      month: month,
      jobs: activeJobs,
      currency: currency,
      excludedFromTotalIds: excludedFromTotalIds
    )
    self.committedYear = year
    self.committedMonth = month
    self.nextUpcomingShift = nextUpcomingShift
    if !selectedDates.isEmpty {
      updateSelectionSummary()
    }
  }

  private func notifyShiftsDidChange(context: ShiftChangeContext = .fullReload) {
    NotificationCenter.default.postShiftsDidChange(object: self, context: context)
  }

  private func shiftChangeContext(
    for editResult: ShiftEditResult,
    existingShift: ShiftRow?
  ) -> ShiftChangeContext {
    var dates = [editResult.shiftDate, editResult.originalDate]

    if let existingShift {
      dates.append(existingShift.shift_date)
    }

    return .affecting(isoDates: dates)
  }

  private func eventChangeContext(
    for editResult: EventEditResult,
    existingEvent: EventRow?
  ) -> ShiftChangeContext {
    var context = ShiftChangeContext.affecting(
      isoDateRangeStart: editResult.startDate,
      end: editResult.endDate
    )

    if let existingEvent {
      context = context.merging(
        .affecting(
          isoDateRangeStart: existingEvent.start_date,
          end: existingEvent.end_date
        ))
    }

    return context
  }

  @discardableResult
  private func applyCachedDisplayedMonthIfValid(year: Int, month: Int) -> Bool {
    let displayKey = "\(year)-\(month)"

    guard var displayCache = monthCache[displayKey], displayCache.isValid else {
      return false
    }

    kScheduleLogger.info("📦 Using cached computed data for \(displayKey)")

    // ATOMIC UPDATE: Set shifts and committed state together
    // This ensures the calendar structure and event data update in the same render pass.
    applyCommittedMonthSnapshot(
      shifts: displayCache.shifts,
      events: displayCache.events,
      year: year,
      month: month
    )

    // Update last accessed time for LRU tracking
    displayCache.lastAccessed = Date()
    monthCache[displayKey] = displayCache

    return true
  }

  private func loadShiftsForDisplayedMonthNonBlocking() {
    guard isActiveTabVisible else {
      displayedMonthLoadPending = true
      kScheduleLogger.info("⏸️ Deferring schedule month load while Schedule tab is hidden")
      return
    }

    let targetYear = displayYear
    let targetMonth = displayMonth
    let displayKey = "\(targetYear)-\(targetMonth)"

    // Check if we have valid computed cache for displayed month
    if applyCachedDisplayedMonthIfValid(year: targetYear, month: targetMonth) {
      // Still prefetch neighbors in background
      prefetchNeighboringMonths()
      return
    }

    // Cache miss - fetch from local in background
    // DON'T clear shifts array or update committed state - keep showing previous month until new data is ready
    // This prevents the "flash of empty state" during local SQLite reads
    kScheduleLogger.info("🔄 Cache miss for \(displayKey), fetching from local...")
    self.isLoading = true

    // Cancel any previous navigation task
    activeNavigationTask?.cancel()

    // Start background fetch
    activeNavigationTask = Task { [weak self] in
      guard let self else {
        return
      }

      // Check if this task is still relevant
      guard !Task.isCancelled,
        displayYear == targetYear,
        displayMonth == targetMonth
      else {
        kScheduleLogger.info("⏭️ Skipping stale fetch for \(displayKey)")
        return
      }

      await loadShiftsForDisplayedMonth(
        showLoadingState: false, targetYear: targetYear, targetMonth: targetMonth)

      // Check again after fetch
      guard !Task.isCancelled,
        displayYear == targetYear,
        displayMonth == targetMonth
      else {
        kScheduleLogger.info("⏭️ Skipping prefetch - user navigated during fetch")
        return
      }

      // Prefetch neighbors after successful load
      prefetchNeighboringMonths()
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
    guard isActiveTabVisible else {
      displayedMonthLoadPending = true
      return
    }

    // Sync tracking with current month context values
    lastObservedYear = monthContext.displayYear
    lastObservedMonth = monthContext.displayMonth
    navigationDirection = nil

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
      objectWillChange.send()
      self.shifts = previousShifts
      self.weekGroups = previousWeekGroups

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

    let context: PayrollReadContext = await monthlyPayrollReadService.loadContextOffMain(
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

  /// Load shifts data from local repositories
  @discardableResult
  private func loadShiftsFromLocal() async -> Bool {
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

      await loadScheduleDependencies(for: userId)
      kScheduleLogger.info("📋 Loaded settings: \(self.settings != nil ? "found" : "nil")")
      kScheduleLogger.info("📋 Loaded snapshots: \(self.snapshots.count)")
      kScheduleLogger.info("📋 Loaded recurring: \(self.recurringShifts.count)")

      // Calculate date range for displayed month (includes out-of-month padding days visible in calendar)
      let displayYM = (year: displayYear, month: displayMonth)
      let visibleRange = Date.visibleCalendarRange(year: displayYM.year, month: displayYM.month)

      // Load raw data for the full visible calendar range (so out-of-month days show data)
      let displayWindowData = await monthlyPayrollReadService.loadRawWindow(
        for: userId,
        window: .visibleCalendarMonth(year: displayYM.year, month: displayYM.month)
      )
      let displayShifts = displayWindowData.shifts
      let displayEvents = displayWindowData.events
      kScheduleLogger.info(
        "📋 Loaded shifts for \(displayYM.year)-\(displayYM.month): \(displayShifts.count)")
      kScheduleLogger.info(
        "📋 Loaded events for \(displayYM.year)-\(displayYM.month): \(displayEvents.count)")

      // Check if we have settings to compute payroll
      guard let currentSettings = self.settings else {
        kScheduleLogger.info("📭 No local settings yet - waiting for sync (userId: \(userId))")
        self.isLoading = false
        return false
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
        year: displayYM.year,
        month: displayYM.month
      )

      self.isLoading = false

      kScheduleLogger.info(
        "📊 Loaded shifts from local: \(computedShifts.count) shifts, \(self.weekGroups.count) weeks"
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
  private func findNextUpcomingShift(in shifts: [ShiftWithComputations]) -> ShiftWithComputations? {
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
  private func updateConflictDetection(for shifts: [ShiftWithComputations]) {
    let analysis = ConflictExclusion.analyze(shifts: shifts)

    self.conflictingShiftIds = analysis.conflictingIds
    self.excludedFromTotalIds = analysis.excludedIds
    self.conflictDates = analysis.conflictDates

    // Update shared context for MainTabView to show conflict indicator on list button
    SharedMonthContext.shared.hasConflictsInMonth = !analysis.conflictDates.isEmpty

    if !analysis.conflictingIds.isEmpty {
      kScheduleLogger.info(
        "⚠️ Found \(analysis.conflictingIds.count) conflicting shifts on \(analysis.conflictDates.count) dates, \(analysis.excludedIds.count) excluded from totals"
      )
    }

    updateSelectionSummary()
  }

  // MARK: - Prefetching

  /// Prefetch neighboring months in the background
  private func prefetchNeighboringMonths() {
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

  private func cancelPrefetchTasks() {
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

  // MARK: - Week Grouping

  /// Group shifts by ISO week
  /// - Parameter shifts: Shifts to group
  /// - Returns: Array of WeekGroup, sorted by week (oldest first, ascending)
  private func groupShiftsByWeek(_ shifts: [ShiftWithComputations]) -> [WeekGroup] {
    guard !shifts.isEmpty else {
      return []
    }

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
}  // swiftlint:disable:this file_length
