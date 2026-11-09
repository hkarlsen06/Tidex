import Combine
import Foundation
import Observation
import UIKit
import os.log

let kScheduleLogger: Logger = Logger(
  subsystem: "com.tidex.app", category: "ShiftsViewModel")
private let kScheduleMonthNameFormatter: DateFormatter = FormatterCache.monthNameFormatter()
let kScheduleISODateFormatter: DateFormatter = FormatterCache.isoDateFormatter(
  timeZone: Date.localTimeZone
)
let kScheduleHourMinuteFormatter: DateFormatter = FormatterCache.hourMinuteFormatter(
  timeZone: Date.localTimeZone
)

// MARK: - Shifts Error

internal enum ShiftsError: Error, LocalizedError {
  case dataLoadFailed(underlying: Error)
  case eventNotFound
  case invalidEventDateRange
  case noLocalData
  case notAuthenticated

  internal var errorDescription: String? {
    switch self {
    case .dataLoadFailed:
      return String(localized: .commonErrorLoadFailed)

    case .eventNotFound:
      return String(localized: .shiftsErrorEventNotFound)

    case .invalidEventDateRange:
      return String(localized: .shiftsErrorInvalidEventDateRange)

    case .noLocalData:
      return String(localized: .commonErrorNoLocalData)

    case .notAuthenticated:
      return String(localized: .commonErrorNotAuthenticated)
    }
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
    var calendar = Calendar.gregorianCurrent
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

struct MonthComputationInput {
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
@Observable
// swiftlint:disable:next explicit_acl explicit_top_level_acl type_body_length
final class ShiftsViewModel: MonthNavigable {

  // MARK: - Dependencies (Local-First Repositories)

  let shiftsRepository: ShiftsRepository
  let eventsRepository: EventsRepository
  private let jobsRepository: JobsRepository
  private let settingsRepository: SettingsRepository
  private let snapshotsRepository: SnapshotsRepository
  let recurringShiftsRepository: RecurringShiftsRepository
  let monthlyPayrollReadService: MonthlyPayrollReadService
  let syncCoordinator: SyncCoordinator
  let authSessionManager: AuthSessionManager
  let monthContext: SharedMonthContext

  // MARK: - Published State

  /// All shifts for the displayed month (computed with payroll)
  var shifts: [ShiftWithComputations] = []
  /// Private events overlapping the currently visible calendar range.
  var events: [EventRow] = []
  /// Event presentations keyed by covered ISO date for the displayed calendar range.
  var eventCoverageByDate: [String: [EventPresentation]] = [:]
  /// Precomputed calendar maps and totals for the displayed month.
  var calendarPresentation = ShiftsCalendarPresentation.empty()
  /// Shifts grouped by ISO week
  /// Whether data is currently loading
  var isLoading = false
  /// Error if data loading failed
  var error: Error?
  /// Set of shift IDs that have conflicts (overlapping with other shifts)
  var conflictingShiftIds: Set<String> = []
  /// Set of shift IDs excluded from totals (higher-earning overlapping shifts are excluded)
  var excludedFromTotalIds: Set<String> = []
  /// Set of dates (ISO strings) that have conflicts
  var conflictDates: Set<String> = []

  /// Direction of last navigation (for animations) - synced from SharedMonthContext
  var navigationDirection: MonthNavigationDirection? { monthContext.navigationDirection }

  // MARK: - Committed Display State
  // These values only update AFTER shift data is ready, ensuring atomic rendering
  // The calendar uses these to avoid showing the new month structure before data arrives

  /// The year that is actually ready to display (data loaded)
  var committedYear: Int

  /// The month that is actually ready to display (data loaded)
  var committedMonth: Int

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
    if let date = Calendar.gregorianCurrent.date(from: components) {
      return kScheduleMonthNameFormatter.string(from: date)
    }
    return ""
  }

  /// Whether the displayed month is after the current month (used for empty-state copy).
  /// Uses committed state for stable rendering.
  var isFutureMonth: Bool {
    let current = Date.currentYearMonth()
    let displayedIndex = committedYear * 12 + committedMonth
    let currentIndex = current.year * 12 + current.month
    return displayedIndex > currentIndex
  }

  /// User's currency for formatting
  var currency: String = "kr"

  /// Next upcoming shift (for countdown display)
  var nextUpcomingShift: ShiftWithComputations?

  /// All non-deleted jobs for metadata rendering (badges/colors in shift cards).
  var activeJobs: [Job] = []

  // MARK: - Selection State

  /// Selected dates (ISO strings). Persists across month navigation.
  var selectedDates: Set<String> = [] {
    didSet {
      if oldValue != selectedDates {
        updateSelectionSummary()
      }
    }
  }

  /// Cached summary for the current selection to avoid recomputing on every access.
  private var selectionSummary: SelectionSummary?

  /// Selection mode is on while any day is selected. Taps then toggle days instead of opening them.
  var isSelectionModeEnabled: Bool {
    !selectedDates.isEmpty
  }

  /// Two-click delete confirmation state
  var confirmingDelete: Bool = false

  /// Whether we're currently deleting shifts
  var isDeleting: Bool = false

  // MARK: - Copy/Move State

  /// Whether copy mode is active (waiting for target date selection)
  var isCopyMode: Bool = false

  /// Whether move mode is active (waiting for target date selection)
  var isMoveMode: Bool = false

  /// Whether a copy operation is in progress
  var isCopying: Bool = false

  /// Whether a move operation is in progress
  var isMoving: Bool = false

  /// Target dates selected while choosing where to copy a shift.
  var copyTargetDates: Set<String> = []

  /// Whether a recurring shift update is in progress
  var isUpdatingRecurring: Bool = false

  /// Whether a recurring shift deletion is in progress
  var isDeletingRecurring: Bool = false

  /// Whether a shift update is in progress
  var isUpdatingShift: Bool = false

  /// Whether an event update is in progress
  var isUpdatingEvent = false

  /// Whether an event deletion is in progress
  var isDeletingEvent = false

  /// The shift being copied or moved (stored when entering copy/move mode)
  var shiftForOperation: ShiftWithComputations?

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

  static func visibleRange(
    _ visibleRange: (start: Date, end: Date), contains dateISO: String
  )
    -> Bool
  {
    guard let date = Date.fromISODateString(dateISO) else {
      return false
    }

    return date >= visibleRange.start && date <= visibleRange.end
  }

  static func buildEventCoverageByDate(
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
            let coveredDate = Calendar.gregorianCurrent.date(
              byAdding: .day, value: offset, to: startDate)
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
  func updateSelectionSummary() {
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

  @ObservationIgnored var settings: UserSettings?
  @ObservationIgnored var snapshots: [WageSnapshot] = []
  @ObservationIgnored var recurringShifts: [RecurringShiftRow] = []
  @ObservationIgnored var scheduleDependenciesLoaded = false
  @ObservationIgnored var cachedUserId: String?
  @ObservationIgnored var isActiveTabVisible = true
  @ObservationIgnored var displayedMonthLoadPending = false

  /// Subscription to SharedMonthContext changes
  @ObservationIgnored private var monthContextCancellable: AnyCancellable?

  /// Track the last observed month to detect changes
  @ObservationIgnored var lastObservedYear: Int = 0
  @ObservationIgnored var lastObservedMonth: Int = 0

  // MARK: - Month Cache

  /// Cache of computed shifts by month key (e.g., "2025-1")
  @ObservationIgnored var monthCache: [String: MonthCacheEntry] = [:]

  /// Maximum number of months to keep in cache (prevents unbounded memory growth)
  static let maxCacheSize = 12

  /// Background prefetch tasks keyed by month (to avoid duplicates and cancel stale work).
  @ObservationIgnored var prefetchTasks: [String: Task<Void, Never>] = [:]

  /// Memory warning observer
  @ObservationIgnored private var memoryWarningObserver: NSObjectProtocol?

  /// Shift reminder tap observer for deep linking
  @ObservationIgnored private var shiftReminderObserver: NSObjectProtocol?

  /// Whether cached month data must be rebuilt from local storage before reuse.
  @ObservationIgnored var localDataNeedsReload = false

  /// Cross-tab shift/event change observer.
  @ObservationIgnored private var shiftsDidChangeObserver: NSObjectProtocol?

  /// In-flight local reload shared by notification and tab-entry callers.
  @ObservationIgnored var localReloadTask: Task<Void, Never>?
  @ObservationIgnored var localReloadID: UUID?

  /// Track active navigation task to cancel stale fetches
  @ObservationIgnored var activeNavigationTask: Task<Void, Never>?

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
    authSessionManager: AuthSessionManager? = nil,
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
    self.authSessionManager = authSessionManager ?? AuthSessionManager.shared
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

    // Local writes can happen from other tabs.
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

        guard isActiveTabVisible else {
          displayedMonthLoadPending = true
          kScheduleLogger.info("⏸️ Deferring schedule month load while Schedule tab is hidden")
          return
        }

        // Trigger data reload for new month
        loadShiftsForDisplayedMonthNonBlocking()
      }
  }

  isolated deinit {
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

  // MARK: - Month Cache Entry

  /// Cache entry for a single month's computed shifts
  struct MonthCacheEntry {
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
}  // swiftlint:disable:this file_length
