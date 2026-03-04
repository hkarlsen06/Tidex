import Combine
import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "AddShiftViewModel")

enum AddShiftCompletion {
  case single
  case recurring
}

// MARK: - Calendar Display Data

/// Pre-computed display data for calendar cells to avoid redundant computation
struct CalendarDisplayData {
  /// Set of dates that have existing shifts
  let existingShiftDates: Set<String>
  /// Earnings by date for existing shifts
  let existingShiftEarnings: [String: CalendarEarningsData]
  /// Start/end hour range by date for existing shifts
  let existingShiftHours: [String: HoursData]
  /// Virtual shifts with computed earnings (cached)
  let virtualShifts: [VirtualShiftWithEarnings]
  /// Year and month this data is for
  let year: Int
  let month: Int
  /// Timestamp for cache invalidation
  let timestamp: Date

  /// Virtual shift with computed earnings
  struct VirtualShiftWithEarnings {
    let date: String
    let earnings: CalendarEarningsData
  }

  /// Check if cache is valid for the given month
  func isValid(for year: Int, month: Int) -> Bool {
    self.year == year && self.month == month
  }
}

/// ViewModel for the Add Shift screen
/// Manages state for both single and recurring shift modes
@MainActor
final class AddShiftViewModel: ObservableObject {

  // MARK: - Dependencies

  private let shiftsRepository: ShiftsRepository
  private let recurringRepository: RecurringShiftsRepository
  private let jobsRepository: JobsRepository
  private let settingsRepository: SettingsRepository
  private let snapshotsRepository: SnapshotsRepository
  private let monthContext: SharedMonthContext
  private let addShiftCoordinator: AddShiftCoordinator

  // MARK: - Mode State

  @Published var mode: AddShiftMode = .single {
    didSet {
      publishStateToCoordinator()
      scheduleDraftSave()
    }
  }

  // MARK: - Shared State

  @Published var startTime: Date? = nil {
    didSet {
      // Debounce time changes - schedule recomputation
      schedulePreviewUpdate()
      publishStateToCoordinator()
      scheduleDraftSave()
    }
  }
  @Published var endTime: Date? = nil {
    didSet {
      // Debounce time changes - schedule recomputation
      schedulePreviewUpdate()
      publishStateToCoordinator()
      scheduleDraftSave()
    }
  }
  @Published var isLoading = false {
    didSet { publishStateToCoordinator() }
  }
  @Published var error: String?

  /// Active (non-archived, non-deleted) jobs for the current user.
  @Published private(set) var activeJobs: [Job] = []

  /// Number of distinct start/end time pairs the user has used across all shifts.
  @Published private(set) var distinctShiftTimePairCount: Int = 0

  /// Selected job for new shift creation.
  /// For single-job users this is auto-assigned.
  @Published var selectedJobId: String? {
    didSet {
      guard oldValue != selectedJobId else { return }
      publishStateToCoordinator()
      scheduleDraftSave()
      scheduleConflictsAndPreviewsRecompute()
    }
  }

  // MARK: - Time Input Debouncing

  /// Debounce timer for time input changes
  private var previewUpdateTask: Task<Void, Never>?

  /// Guards against applying stale async preview/conflict computations.
  private var previewComputationVersion: UInt64 = 0

  /// Guards against applying stale async calendar display computations.
  private var displayComputationVersion: UInt64 = 0

  /// Debounce delay when user is actively typing (partial input)
  private static let activeTypingDelay: UInt64 = 150_000_000  // 150ms

  /// Minimal delay when form is complete (instant feedback)
  private static let completedFormDelay: UInt64 = 50_000_000  // 50ms

  private struct CalendarDisplayComputationInput {
    let year: Int
    let month: Int
    let shifts: [ShiftRow]
    let recurringShifts: [RecurringShiftRow]
    let snapshots: [WageSnapshot]
    let jobs: [Job]
    let settings: UserSettings?
  }

  private struct ConflictsAndPreviewsComputationInput {
    let mode: AddShiftMode
    let selectedDates: [String]
    let selectedDays: [String: String]
    let repeatInterval: Int
    let displayMonth: Date
    let endCondition: EndCondition?
    let hasValidTimes: Bool
    let startTime: String
    let endTime: String
    let requiresExplicitJobSelection: Bool
    let selectedJobId: String?
    let effectiveJobId: String?
    let existingShifts: [ShiftRow]
    let existingRecurringShifts: [RecurringShiftRow]
    let snapshots: [WageSnapshot]
    let jobs: [Job]
    let settings: UserSettings?
  }

  private struct ConflictsAndPreviewsComputationResult {
    let projectedRecurringDates: [String]?
    let anchorEarnings: [String: CalendarEarningsData]?
    let conflictDates: Set<String>
    let previewEarnings: [String: CalendarEarningsData]
  }

  private struct EarningsComputationContext {
    let requiresExplicitJobSelection: Bool
    let selectedJobId: String?
    let effectiveJobId: String?
    let snapshots: [WageSnapshot]
    let jobs: [Job]
    let settings: UserSettings?
  }

  // MARK: - Draft Persistence

  /// Debounce timer for draft saving
  private var draftSaveTask: Task<Void, Never>?

  /// Debounce delay for draft saving (500ms)
  private static let draftSaveDebounceDelay: UInt64 = 500_000_000

  /// Display month as Date - computed from SharedMonthContext
  /// Setter updates the SharedMonthContext to sync with other tabs
  var displayMonth: Date {
    get {
      var components = DateComponents()
      components.year = monthContext.displayYear
      components.month = monthContext.displayMonth
      components.day = 1
      return Calendar.current.date(from: components) ?? Date()
    }
    set {
      let calendar = Calendar.current
      let components = calendar.dateComponents([.year, .month], from: newValue)
      if let year = components.year, let month = components.month {
        // Update tracking immediately to prevent the subscription from double-triggering
        lastObservedYear = year
        lastObservedMonth = month

        // Update shared context (this will trigger other tabs)
        monthContext.navigateTo(year: year, month: month)

        // Notify SwiftUI that the view should update
        objectWillChange.send()
      }
    }
  }

  /// Subscription to SharedMonthContext changes
  private var monthContextCancellable: AnyCancellable?

  /// Subscription to tab bar add action trigger
  private var addActionCancellable: AnyCancellable?

  /// Track the last observed month to detect changes
  private var lastObservedYear: Int = 0
  private var lastObservedMonth: Int = 0

  /// Direction of last navigation (for animations) - synced from SharedMonthContext
  @Published private(set) var navigationDirection: MonthNavigationDirection?

  // MARK: - Display Properties (from SharedMonthContext)

  /// Currently displayed year - synced from SharedMonthContext
  var displayYear: Int { monthContext.displayYear }

  /// Currently displayed month 1-12 - synced from SharedMonthContext
  var displayMonthNumber: Int { monthContext.displayMonth }

  /// Whether viewing the current (real) month
  var isCurrentMonth: Bool { monthContext.isCurrentMonth }

  /// Computed month name for display
  var displayMonthName: String { monthContext.displayMonthName }

  /// User-selected currency for display formatting in Add tab UI.
  @Published private(set) var currency: String = "kr"

  // MARK: - Single Mode State

  @Published var selectedDates: Set<String> = [] {  // ISO dates (YYYY-MM-DD)
    didSet {
      publishStateToCoordinator()
      scheduleDraftSave()
    }
  }

  // MARK: - Paywall State

  /// Whether to show the month limit sheet
  @Published var showMonthLimitSheet = false

  /// Set of existing months when paywall is triggered (for display purposes)
  @Published private(set) var existingShiftMonths: Set<DateComponents> = []

  /// Target month the user is trying to add shifts to (for month limit sheet)
  @Published private(set) var targetMonth: DateComponents = DateComponents()

  // MARK: - Recurring Mode State

  @Published var repeatInterval: Int = 1 {  // 0 = weekly, 1 = biweekly, etc. Default: biweekly
    didSet {
      scheduleDraftSave()
      // Update projected dates immediately when interval changes
      updateProjectedRecurringDates()
    }
  }
  @Published var selectedDays: [String: String] = [:] {  // weekday "0"-"6" -> anchor ISO date
    didSet {
      publishStateToCoordinator()
      scheduleDraftSave()
    }
  }
  @Published var endCondition: EndCondition? = nil {  // Default: indefinite
    didSet {
      scheduleDraftSave()
      // Update projected dates immediately when end condition changes
      updateProjectedRecurringDates()
    }
  }
  @Published var showPreviewSheet = false
  @Published var showSubmitJobChooser = false

  // MARK: - Cached Data

  /// Triggers view updates when cached data changes
  /// We use this instead of making cachedShifts @Published to avoid exposing internal data
  @Published private var cacheVersion: Int = 0

  private var cachedShifts: [ShiftRow] = []
  private var cachedRecurringShifts: [RecurringShiftRow] = []
  private var cachedSnapshots: [WageSnapshot] = []
  private var cachedSettings: UserSettings?

  // MARK: - Performance Optimized Caches

  /// Cached calendar display data - computed once per month, not per view update
  @Published private(set) var cachedDisplayData: CalendarDisplayData?

  /// Cached conflict dates - only recomputed when dates or times change
  @Published private(set) var cachedConflictDatesForCalendar: Set<String> = []

  /// Cached preview earnings - only recomputed when selection or times change
  @Published private(set) var cachedPreviewEarnings: [String: CalendarEarningsData] = [:]

  /// Cached projected recurring dates for calendar display (current month only)
  @Published private(set) var cachedProjectedRecurringDates: [String] = []

  /// Cached earnings per anchor weekday - computed once per anchor, shared by all projected dates
  @Published private(set) var cachedAnchorEarnings: [String: CalendarEarningsData] = [:]

  // MARK: - Preview Cache (computed only when preview sheet is shown)

  /// Cached projected dates for preview sheet - computed once when preview is shown
  @Published private(set) var cachedProjectedDates: [String] = []
  /// Cached conflict dates for preview sheet
  @Published private(set) var cachedConflictDates: Set<String> = []

  // MARK: - Navigation Callback

  /// Called when shifts are successfully created.
  var onShiftsCreated: ((AddShiftCompletion) -> Void)?

  // MARK: - Initialization

  init(
    shiftsRepository: ShiftsRepository? = nil,
    recurringRepository: RecurringShiftsRepository? = nil,
    jobsRepository: JobsRepository? = nil,
    settingsRepository: SettingsRepository? = nil,
    snapshotsRepository: SnapshotsRepository? = nil,
    monthContext: SharedMonthContext? = nil,
    addShiftCoordinator: AddShiftCoordinator? = nil
  ) {
    self.shiftsRepository = shiftsRepository ?? ShiftsRepository.shared
    self.recurringRepository = recurringRepository ?? RecurringShiftsRepository.shared
    self.jobsRepository = jobsRepository ?? JobsRepository.shared
    self.settingsRepository = settingsRepository ?? SettingsRepository.shared
    self.snapshotsRepository = snapshotsRepository ?? SnapshotsRepository.shared
    self.monthContext = monthContext ?? SharedMonthContext.shared
    self.addShiftCoordinator = addShiftCoordinator ?? AddShiftCoordinator.shared

    // Initialize tracking to current month context values
    self.lastObservedYear = self.monthContext.displayYear
    self.lastObservedMonth = self.monthContext.displayMonth

    // Subscribe to month context changes
    setupMonthContextSubscription()

    // Subscribe to tab bar add action trigger
    setupAddActionSubscription()
  }

  deinit {
    monthContextCancellable?.cancel()
    addActionCancellable?.cancel()
    previewUpdateTask?.cancel()
    draftSaveTask?.cancel()
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

        // Sync navigation direction from context (for animations)
        self.navigationDirection = self.monthContext.navigationDirection

        // Trigger objectWillChange to refresh calendar views
        self.objectWillChange.send()

        // Reload shifts for conflict detection in the new month
        self.reloadShiftsForDisplayedMonth()
      }
  }

  /// Subscribe to tab bar add action trigger
  private func setupAddActionSubscription() {
    addActionCancellable = addShiftCoordinator.triggerAddAction
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        self?.handleTabBarAddTrigger()
      }
  }

  /// Handle the add action triggered from tab bar
  private func handleTabBarAddTrigger() {
    // Haptic feedback
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.impactOccurred()

    switch mode {
    case .single:
      Task {
        await submitSingleShifts()
      }
    case .recurring:
      showPreview()
    }
  }

  /// Publish current state to the coordinator (call after state changes)
  private func publishStateToCoordinator() {
    let canSubmit = mode == .single ? canSubmitSingle : canSubmitRecurring
    addShiftCoordinator.updateCanSubmit(canSubmit)
    addShiftCoordinator.updateMode(mode)
    addShiftCoordinator.updateIsLoading(isLoading)
    addShiftCoordinator.updateJobSelection(
      selectedJobId: effectiveSelectedJobId,
      requiresJobSelection: requiresExplicitJobSelection
    )
    addShiftCoordinator.updateSubmitBlockers(
      mode: mode,
      hasSelectedDates: !selectedDates.isEmpty,
      hasSelectedDays: !selectedDays.isEmpty,
      hasValidTimes: hasValidTimes,
      hasAvailableJobs: !activeJobs.isEmpty,
      hasSelectedJob: effectiveSelectedJobId != nil
    )
  }

  // MARK: - Month Navigation

  /// Navigate to the previous month
  /// Delegates to SharedMonthContext - data reload happens via subscription
  func goToPreviousMonth() {
    monthContext.goToPreviousMonth()
  }

  /// Navigate to the next month
  /// Delegates to SharedMonthContext - data reload happens via subscription
  func goToNextMonth() {
    monthContext.goToNextMonth()
  }

  /// Reset to current month
  /// Delegates to SharedMonthContext - data reload happens via subscription
  func goToCurrentMonth() {
    monthContext.goToCurrentMonth()
  }

  // MARK: - Computed Properties

  /// Whether the single shift form can be submitted
  var canSubmitSingle: Bool {
    !selectedDates.isEmpty
      && hasValidTimes
      && !activeJobs.isEmpty
      && effectiveSelectedJobId != nil
  }

  /// Whether the recurring shift form can be submitted
  var canSubmitRecurring: Bool {
    !selectedDays.isEmpty
      && hasValidTimes
      && !activeJobs.isEmpty
      && effectiveSelectedJobId != nil
  }

  /// Selected job object for display and contextual calculations.
  var selectedJob: Job? {
    guard let selectedJobId else { return nil }
    return activeJobs.first(where: { $0.id == selectedJobId })
  }

  /// User must explicitly pick a job when multiple active jobs exist.
  private var requiresExplicitJobSelection: Bool {
    activeJobs.count > 1
  }

  /// When explicit selection isn't required, use the only available job automatically.
  private var effectiveSelectedJobId: String? {
    if requiresExplicitJobSelection {
      return selectedJobId
    }
    return selectedJobId ?? activeJobs.first?.id
  }

  var submissionJobs: [Job] {
    activeJobs
  }

  func selectJobForShiftCreation(_ jobId: String) {
    selectedJobId = jobId
    showSubmitJobChooser = false
  }

  func dismissJobSelection() {
    showSubmitJobChooser = false
  }

  func presentJobSelection() {
    guard requiresExplicitJobSelection else { return }
    showSubmitJobChooser = true
  }

  /// Whether both start and end times have been entered
  private var hasValidTimes: Bool {
    startTime != nil && endTime != nil
  }

  /// Whether the form has any content that can be cleared
  /// Used to conditionally show the undo/clear button
  var hasContent: Bool {
    switch mode {
    case .single:
      return !selectedDates.isEmpty || startTime != nil || endTime != nil
    case .recurring:
      return !selectedDays.isEmpty || startTime != nil || endTime != nil
    }
  }

  /// Show hint until user has created at least 3 distinct start/end combinations.
  var shouldShowSingleTimeScopeHint: Bool {
    distinctShiftTimePairCount < 3
  }

  /// Start time as HH:mm string
  var startTimeString: String {
    guard let time = startTime else { return "" }
    return formatTimeAsHHmm(time)
  }

  /// End time as HH:mm string
  /// Returns "24:00" when end is midnight and start is not (end-of-day convention)
  var endTimeString: String {
    guard let time = endTime else { return "" }
    let formatted = formatTimeAsHHmm(time)
    if formatted == "00:00", let start = startTime, formatTimeAsHHmm(start) != "00:00" {
      return "24:00"
    }
    return formatted
  }

  /// Set of dates that have existing shifts - uses cached data for performance
  var existingShiftDates: Set<String> {
    cachedDisplayData?.existingShiftDates ?? Set<String>()
  }

  /// Computed earnings for existing shifts by date - uses cached data for performance
  var existingShiftEarnings: [String: CalendarEarningsData] {
    cachedDisplayData?.existingShiftEarnings ?? [:]
  }

  /// Start/end hours for existing shifts by date - uses cached data for performance
  var existingShiftHours: [String: HoursData] {
    cachedDisplayData?.existingShiftHours ?? [:]
  }

  /// Start/end hours for currently entered times (used for add-calendar previews)
  var enteredHours: HoursData? {
    guard hasValidTimes else { return nil }

    let start = CalendarGridHelper.formatTime(startTimeString)
    let end = CalendarGridHelper.formatTime(endTimeString)
    let crossesMidnight =
      CalendarGridHelper.timeToMinutes(endTimeString)
      <= CalendarGridHelper.timeToMinutes(startTimeString)

    return HoursData(
      start: start,
      end: end,
      crossesMidnight: crossesMidnight
    )
  }

  /// Set of dates that would conflict with the current time selection - uses cached data
  var conflictDates: Set<String> {
    cachedConflictDatesForCalendar
  }

  /// Projected dates for the recurring pattern - uses cached data
  var projectedRecurringDates: [String] {
    cachedProjectedRecurringDates
  }

  /// Number of conflicts in the current selection
  var conflictCount: Int {
    cachedConflictDatesForCalendar.count
  }

  /// Preview earnings for selected dates (single mode) - uses cached data
  var previewEarnings: [String: CalendarEarningsData] {
    cachedPreviewEarnings
  }

  // MARK: - Toolbar Monthly Total

  /// Combined monthly total (existing shifts + preview earnings) for toolbar display.
  /// Uses `ConflictExclusion.combinedEarnings` so the "lowest gross wins" rule
  /// is applied consistently with the rest of the app.
  var toolbarTotals: CalendarHeaderTotals? {
    let existingEarnings = cachedDisplayData?.existingShiftEarnings ?? [:]

    // Build preview earnings map for the current mode
    let previewByDate: [String: CalendarEarningsData] = {
      switch mode {
      case .single:
        return cachedPreviewEarnings
      case .recurring:
        var map: [String: CalendarEarningsData] = [:]
        for dateISO in cachedProjectedRecurringDates {
          let weekday = weekdayFromDate(dateISO)
          if let earnings = cachedAnchorEarnings[weekday] {
            map[dateISO] = earnings
          }
        }
        return map
      }
    }()

    let totals = ConflictExclusion.combinedEarnings(
      existingByDate: existingEarnings,
      previewByDate: previewByDate,
      conflictDates: cachedConflictDatesForCalendar
    )

    guard totals.gross > 0 else { return nil }

    let baselineTotals = ConflictExclusion.combinedEarnings(
      existingByDate: existingEarnings,
      previewByDate: [:],
      conflictDates: []
    )

    let primaryAmount = totals.hasTaxEnabled ? totals.net : totals.gross
    let baselinePrimary = baselineTotals.hasTaxEnabled ? baselineTotals.net : baselineTotals.gross
    let secondaryAmount: Double? = {
      guard !previewByDate.isEmpty else { return nil }
      let delta = max(primaryAmount - baselinePrimary, 0)
      return delta > 0 ? delta : nil
    }()

    return CalendarHeaderTotals(
      primary: primaryAmount,
      secondary: secondaryAmount
    )
  }

  /// Get earnings for a recurring date by looking up its anchor's earnings
  /// All dates on the same weekday share the same earnings
  func earningsForRecurringDate(_ dateISO: String) -> CalendarEarningsData? {
    let weekday = weekdayFromDate(dateISO)
    return cachedAnchorEarnings[weekday]
  }

  // MARK: - Data Loading

  /// Load initial data from repositories
  func loadData() async {  // swiftlint:disable:this async_without_await
    guard let userId = AppCoordinator.shared.getCurrentUserId() else {
      logger.warning("Cannot load data: no user ID")
      return
    }

    // Load any saved draft first (before other data to set mode correctly)
    loadDraft()

    // Load settings
    cachedSettings = settingsRepository.getSettings(for: userId)
    currency = cachedSettings?.currency ?? "kr"

    // Load active jobs before snapshots/preview computations.
    activeJobs = jobsRepository.getActiveJobs(for: userId)
    reconcileSelectedJob()

    // Load snapshots
    cachedSnapshots = snapshotsRepository.getSnapshots(for: userId)

    // Load existing shifts for displayed month (for conflict detection)
    reloadShiftsForDisplayedMonth()
    refreshDistinctShiftTimePairCount(for: userId)

    // Load recurring shifts
    cachedRecurringShifts = recurringRepository.getRecurringShifts(for: userId)

    // Build cached display data for the current month
    scheduleCalendarDisplayRebuild()
    scheduleConflictsAndPreviewsRecompute()

    // Check for pre-selected date from SharedMonthContext (e.g., tapping empty day in Shifts tab)
    applyPreselectedDate()

    // Trigger view update now that cached data is loaded
    cacheVersion += 1

    publishStateToCoordinator()

    logger.info(
      "Loaded data: \(self.cachedShifts.count) shifts, \(self.cachedRecurringShifts.count) recurring, \(self.cachedSnapshots.count) snapshots, \(self.activeJobs.count) jobs"
    )
  }

  /// Refresh cached repository data while preserving current in-progress form state.
  func refreshData() async {  // swiftlint:disable:this async_without_await
    guard let userId = AppCoordinator.shared.getCurrentUserId() else {
      logger.warning("Cannot refresh data: no user ID")
      return
    }

    // Reload cache sources without touching draft-driven UI state.
    cachedSettings = settingsRepository.getSettings(for: userId)
    currency = cachedSettings?.currency ?? "kr"
    activeJobs = jobsRepository.getActiveJobs(for: userId)
    reconcileSelectedJob()
    cachedSnapshots = snapshotsRepository.getSnapshots(for: userId)
    cachedRecurringShifts = recurringRepository.getRecurringShifts(for: userId)
    reloadShiftsForDisplayedMonth()
    refreshDistinctShiftTimePairCount(for: userId)

    publishStateToCoordinator()

    logger.info(
      "Refreshed add tab data: \(self.cachedShifts.count) shifts, \(self.cachedRecurringShifts.count) recurring, \(self.cachedSnapshots.count) snapshots, \(self.activeJobs.count) jobs"
    )
  }

  /// Check and apply any pre-selected date from SharedMonthContext
  /// Called from onAppear when tab becomes visible
  func checkPreselectedDate() {
    applyPreselectedDate()
  }

  /// Apply and consume the pre-selected date from SharedMonthContext
  /// Called when the user taps an empty day in the Shifts calendar
  private func applyPreselectedDate() {
    guard let dateISO = monthContext.preselectedDate else { return }

    // Consume the pre-selected date (one-time use)
    monthContext.preselectedDate = nil

    // Ensure we're in single mode for date selection
    mode = .single

    // Add the date to selection
    selectedDates.insert(dateISO)

    // Navigate to the month containing the pre-selected date
    if let date = Date.fromISODateString(dateISO) {
      let calendar = Calendar.current
      let components = calendar.dateComponents([.year, .month], from: date)
      if let year = components.year, let month = components.month {
        monthContext.navigateTo(year: year, month: month)
      }
    }

    logger.info("Applied pre-selected date: \(dateISO)")
  }

  /// Reload shifts for the currently displayed month
  /// Call this when navigating to a new month
  func reloadShiftsForDisplayedMonth() {
    guard let userId = AppCoordinator.shared.getCurrentUserId() else { return }

    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month], from: displayMonth)
    guard let year = components.year, let month = components.month else { return }

    let startDate = Date.firstDayOfMonthDate(year: year, month: month)
    let endDate = Date.lastDayOfMonthDate(year: year, month: month)

    cachedShifts = shiftsRepository.getShifts(for: userId, startDate: startDate, endDate: endDate)

    // Rebuild display data and previews asynchronously to avoid blocking UI
    scheduleCalendarDisplayRebuild()
    scheduleConflictsAndPreviewsRecompute()

    // Trigger view update for new month's shift indicators
    cacheVersion += 1
  }

  /// Refresh number of distinct start/end pairs used in historical shifts.
  private func refreshDistinctShiftTimePairCount(for userId: String) {
    let allShifts = shiftsRepository.getAllShifts(for: userId)
    let distinctPairs = Set(
      allShifts.compactMap { shift -> String? in
        let start = shift.start_time.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = shift.end_time.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !start.isEmpty, !end.isEmpty else { return nil }
        return "\(start)|\(end)"
      })
    distinctShiftTimePairCount = distinctPairs.count
  }

  // MARK: - Single Shift Actions

  /// Toggle selection of a date (single tap behavior)
  func toggleDate(_ dateISO: String) {
    // Toggle single date
    if selectedDates.contains(dateISO) {
      selectedDates.remove(dateISO)
      // Incremental update: remove from preview earnings
      cachedPreviewEarnings.removeValue(forKey: dateISO)
      // Update conflicts after removing date
      updateConflictsIncrementally(removedDate: dateISO)
    } else {
      selectedDates.insert(dateISO)
      // Incremental update: only compute earnings for this new date
      updatePreviewEarningsIncrementally(addedDate: dateISO)
      // Update conflicts after adding date
      updateConflictsIncrementally(addedDate: dateISO)
    }

    // Recompute from full current state so any in-flight async result with stale inputs
    // is invalidated and cannot overwrite the latest incremental updates.
    scheduleConflictsAndPreviewsRecompute()

    // Haptic feedback
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()
  }

  /// Clear all selected dates
  func clearSelectedDates() {
    selectedDates.removeAll()
    cachedPreviewEarnings.removeAll()
    cachedConflictDatesForCalendar.removeAll()
  }

  /// Submit single shifts
  func submitSingleShifts() async {
    guard canSubmitSingle else { return }

    let userId: String
    do {
      userId = try AppCoordinator.shared.requireUserId()
    } catch {
      self.error = error.localizedDescription
      return
    }

    isLoading = true
    error = nil

    // Get current tier for gating
    let tier = EntitlementService.shared.effectiveTier

    do {
      let sortedDates = selectedDates.sorted()
      let jobId = effectiveSelectedJobId

      for dateISO in sortedDates {
        guard let shiftDate = Date.fromISODateString(dateISO) else {
          logger.warning("Invalid date: \(dateISO)")
          continue
        }

        // Use tier-checked creation for free users
        _ = try await shiftsRepository.createShiftWithTierCheck(
          userId: userId,
          jobId: jobId,
          shiftDate: shiftDate,
          startTime: startTimeString,
          endTime: endTimeString,
          customSupplements: nil,
          tier: tier
        )
      }

      logger.info("Created \(sortedDates.count) shifts")

      // Trigger celebration with the dates that were added
      // Use the current display month as the origin for confetti
      CelebrationManager.shared.celebrate(
        dates: Set(sortedDates),
        originMonth: (year: displayYear, month: displayMonthNumber)
      )

      // Refresh month cache so newly created shifts are immediately visible in Add calendar.
      reloadShiftsForDisplayedMonth()
      refreshDistinctShiftTimePairCount(for: userId)

      // Clear form
      clearForm()

      // Success haptic
      Haptics.playShiftCreationSuccess()

      // Notify that shifts changed (for dashboard refresh)
      NotificationCenter.default.post(name: .shiftsDidChange, object: nil)

      // Notify completion
      onShiftsCreated?(.single)

    } catch ShiftCreationError.monthLimitReached(let months) {
      // Show month limit sheet instead of error
      logger.info(
        "Month limit reached, showing month limit sheet. Existing months: \(months.count)")
      existingShiftMonths = months

      // Calculate target month from first selected date
      if let firstDate = selectedDates.min(),
        let date = Date.fromISODateString(firstDate)
      {
        let calendar = Calendar.current
        targetMonth = calendar.dateComponents([.year, .month], from: date)
      }

      showMonthLimitSheet = true
    } catch {
      logger.error("Failed to create shifts: \(error.localizedDescription)")
      self.error = error.localizedDescription
      Haptics.play(.error)
    }

    isLoading = false
  }

  // MARK: - Recurring Shift Actions

  /// Toggle anchor date for a weekday
  func toggleAnchorDate(_ dateISO: String) {
    let weekday = weekdayFromDate(dateISO)

    if selectedDays[weekday] == dateISO {
      // Remove this anchor
      selectedDays.removeValue(forKey: weekday)
      cachedAnchorEarnings.removeValue(forKey: weekday)
    } else {
      // Set or replace anchor for this weekday
      selectedDays[weekday] = dateISO
    }

    // Update projected dates for the new anchor configuration
    updateProjectedRecurringDates()

    // Haptic feedback
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()
  }

  /// Remove anchor for a specific weekday
  func removeAnchor(weekday: String) {
    selectedDays.removeValue(forKey: weekday)
    cachedAnchorEarnings.removeValue(forKey: weekday)

    // Update projected dates
    updateProjectedRecurringDates()

    // Haptic feedback
    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()
  }

  /// Clear all anchors
  func clearAnchors() {
    selectedDays.removeAll()
    cachedAnchorEarnings.removeAll()
    cachedProjectedRecurringDates.removeAll()
    cachedConflictDatesForCalendar.removeAll()
  }

  /// Show the preview sheet - computes projected dates once
  func showPreview() {
    guard canSubmitRecurring else { return }

    // Compute projected dates once when showing preview
    cachedProjectedDates = RecurringShiftProjector.generateDates(
      selectedDays: selectedDays,
      repeatInterval: repeatInterval,
      endCondition: endCondition
    )

    // Compute conflicts once
    cachedConflictDates = ShiftConflictDetector.detectConflicts(
      dates: cachedProjectedDates,
      startTime: startTimeString,
      endTime: endTimeString,
      existingShifts: cachedShifts,
      existingRecurringShifts: cachedRecurringShifts
    )

    showPreviewSheet = true
  }

  /// Submit recurring shift
  func submitRecurringShift() async {
    guard canSubmitRecurring else { return }

    let userId: String
    do {
      userId = try AppCoordinator.shared.requireUserId()
    } catch {
      self.error = error.localizedDescription
      return
    }

    isLoading = true
    error = nil

    do {
      // Use cached conflicts from preview
      let conflicts = cachedConflictDates

      _ = try await recurringRepository.createRecurringShift(
        userId: userId,
        jobId: effectiveSelectedJobId,
        startTime: startTimeString,
        endTime: endTimeString,
        repeatIntervalWeeks: repeatInterval,
        selectedDays: selectedDays,
        endCondition: endCondition,
        exclusions: Array(conflicts),
        dateSpecificSupplements: nil
      )

      logger.info(
        "Created recurring shift with \(self.cachedProjectedDates.count) projected dates, \(conflicts.count) exclusions"
      )

      // Get non-excluded dates for celebration (the ones actually created)
      let createdDates = Set(cachedProjectedDates).subtracting(conflicts)

      // Trigger celebration with created dates
      // Use the current display month as the origin for confetti
      CelebrationManager.shared.celebrate(
        dates: createdDates,
        originMonth: (year: displayYear, month: displayMonthNumber)
      )

      refreshDistinctShiftTimePairCount(for: userId)

      // Clear form
      clearForm()

      // Dismiss preview sheet
      showPreviewSheet = false

      // Success haptic
      Haptics.playShiftCreationSuccess()

      // Notify that shifts changed (for dashboard refresh)
      NotificationCenter.default.post(name: .shiftsDidChange, object: nil)

      // Notify completion
      onShiftsCreated?(.recurring)

    } catch {
      logger.error("Failed to create recurring shift: \(error.localizedDescription)")
      self.error = error.localizedDescription
      Haptics.play(.error)
    }

    isLoading = false
  }

  // MARK: - Delete Shifts (Month Limit)

  /// Delete shifts in other months (when free tier user chooses this option)
  /// Returns true if successful
  func deleteShiftsInOtherMonths() async -> Bool {
    guard let userId = AppCoordinator.shared.getCurrentUserId() else {
      logger.warning("Cannot delete shifts: no user ID")
      return false
    }

    do {
      let deletedCount = try await shiftsRepository.deleteShiftsInOtherMonths(
        userId: userId,
        targetMonth: targetMonth
      )

      logger.info("Deleted \(deletedCount) shifts in other months")

      // Clear existing months since they're now deleted
      existingShiftMonths.removeAll()

      // Reload cached data to reflect deletions in UI
      reloadShiftsForDisplayedMonth()
      refreshDistinctShiftTimePairCount(for: userId)

      // Notify that shifts changed (for other views like dashboard)
      NotificationCenter.default.post(name: .shiftsDidChange, object: nil)

      return true
    } catch {
      logger.error("Failed to delete shifts in other months: \(error.localizedDescription)")
      return false
    }
  }

  /// Called when deletion is complete and user wants to proceed with creating shifts
  func onDeleteComplete() {
    // Re-attempt shift creation now that other months are cleared
    Task {
      await submitSingleShifts()
    }
  }

  /// Called when user upgrades successfully - auto-retry shift creation
  func onUpgradeComplete() {
    // Re-attempt shift creation now that user has paid tier
    Task {
      await submitSingleShifts()
    }
  }

  // MARK: - Private Helpers

  private func reconcileSelectedJob() {
    guard !activeJobs.isEmpty else {
      selectedJobId = nil
      return
    }

    if requiresExplicitJobSelection {
      // Keep a previously selected active job; otherwise require explicit new selection.
      if let selectedJobId, activeJobs.contains(where: { $0.id == selectedJobId }) {
        return
      }
      selectedJobId = nil
      return
    }

    if let selectedJobId, activeJobs.contains(where: { $0.id == selectedJobId }) {
      return
    }

    selectedJobId = activeJobs.first?.id
  }

  private func snapshotsForJob(_ jobId: String?) -> [WageSnapshot] {
    guard let jobId else { return cachedSnapshots }

    let jobSnapshots = cachedSnapshots.filter { $0.job_id == jobId }
    if !jobSnapshots.isEmpty {
      return jobSnapshots
    }

    // Rollout fallback for legacy local rows that may not yet have job_id populated.
    // Nil job rows are treated as default-job rows only.
    let defaultJobId = activeJobs.first(where: { $0.is_default })?.id
    if defaultJobId == jobId {
      return cachedSnapshots.filter { $0.job_id == nil }
    }

    return []
  }

  private func snapshotForDate(_ dateISO: String, jobId: String?) -> WageSnapshot? {
    SnapshotsService.snapshotForDate(dateISO, from: snapshotsForJob(jobId))
  }

  private func payrollDay(for jobId: String?) -> Int {
    if let jobId, let jobPayrollDay = activeJobs.first(where: { $0.id == jobId })?.payroll_day {
      return jobPayrollDay
    }
    return cachedSettings?.effectivePayrollDay ?? 1
  }

  /// Format Date to HH:mm string
  private func formatTimeAsHHmm(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }

  /// Get weekday string ("0"-"6") from ISO date
  private func weekdayFromDate(_ dateISO: String) -> String {
    guard let date = Date.fromISODateString(dateISO) else { return "0" }
    let calendar = Calendar.current
    let weekday = calendar.component(.weekday, from: date)
    // Calendar weekday is 1=Sun, 2=Mon, ..., 7=Sat
    // JavaScript weekday is 0=Sun, 1=Mon, ..., 6=Sat
    return String((weekday - 1) % 7)
  }

  /// Compute earnings for a single date (net + gross)
  /// Uses wage snapshot from shift date, tax snapshot from payout date (shift month + 1)
  private func computeEarningsForDate(_ dateISO: String) -> CalendarEarningsData? {
    // Multi-job users must choose a workplace before previews become job-scoped.
    // Until then, cells keep the checkmark-only selected style.
    if requiresExplicitJobSelection && selectedJobId == nil {
      return nil
    }

    let jobId = effectiveSelectedJobId

    // Wage/supplements from shift date
    let wageSnapshot = snapshotForDate(dateISO, jobId: jobId)

    // Tax settings from payout date (shift month + 1)
    let payrollDay = payrollDay(for: jobId)
    let payoutDate = PayrollEngine.calculatePayoutDate(shiftDate: dateISO, payrollDay: payrollDay)
    let taxSnapshot = snapshotForDate(payoutDate, jobId: jobId)

    let shift = ShiftRow(
      id: "preview-\(dateISO)",
      user_id: nil,
      job_id: jobId,
      shift_date: dateISO,
      start_time: startTimeString,
      end_time: endTimeString,
      custom_supplements: nil
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: wageSnapshot)
    let gross = computed.gross
    let taxEnabled = taxSnapshot?.effectiveTaxEnabled ?? false
    let net = computed.netPay(
      taxEnabled: taxSnapshot?.effectiveTaxEnabled ?? false,
      taxPercentage: taxSnapshot?.effectiveTaxPercentage ?? 0
    )
    return CalendarEarningsData(net: net, gross: gross, hasTaxEnabled: taxEnabled)
  }

  private nonisolated static func computeCalendarDisplayDataOffMain(
    _ input: CalendarDisplayComputationInput
  ) async -> CalendarDisplayData {
    await Task.detached(priority: .userInitiated) {
      Self.buildCalendarDisplayData(input)
    }.value
  }

  private nonisolated static func buildCalendarDisplayData(
    _ input: CalendarDisplayComputationInput
  ) -> CalendarDisplayData {
    var existingDates = Set<String>()
    var existingNetEarnings: [String: Double] = [:]
    var existingGrossEarnings: [String: Double] = [:]
    var existingHasTax: [String: Bool] = [:]
    var shiftTimesByDate: [String: [(start: String, end: String)]] = [:]

    for shift in input.shifts {
      existingDates.insert(shift.shift_date)

      let wageSnapshot = Self.snapshotForDate(
        shift.shift_date,
        jobId: shift.job_id,
        snapshots: input.snapshots,
        jobs: input.jobs
      )
      let computed = PayrollCalculator.computeShift(shift, snapshot: wageSnapshot)

      let payrollDay = Self.payrollDay(
        for: shift.job_id, jobs: input.jobs, settings: input.settings)
      let payoutDate = PayrollEngine.calculatePayoutDate(
        shiftDate: shift.shift_date,
        payrollDay: payrollDay
      )
      let taxSnapshot = Self.snapshotForDate(
        payoutDate,
        jobId: shift.job_id,
        snapshots: input.snapshots,
        jobs: input.jobs
      )

      let taxEnabled = taxSnapshot?.effectiveTaxEnabled ?? false
      existingNetEarnings[shift.shift_date, default: 0] += computed.netPay(
        taxEnabled: taxEnabled,
        taxPercentage: taxSnapshot?.effectiveTaxPercentage ?? 0
      )
      existingGrossEarnings[shift.shift_date, default: 0] += computed.gross
      existingHasTax[shift.shift_date, default: false] =
        existingHasTax[shift.shift_date, default: false] || taxEnabled
      shiftTimesByDate[shift.shift_date, default: []].append(
        (start: shift.start_time, end: shift.end_time)
      )
    }

    var virtualShiftsWithEarnings: [CalendarDisplayData.VirtualShiftWithEarnings] = []

    for recurring in input.recurringShifts {
      let virtualShifts = RecurringShiftGenerator.generateVirtualShiftsForMonth(
        year: input.year,
        month: input.month,
        recurring: recurring
      )

      for virtualShift in virtualShifts {
        existingDates.insert(virtualShift.date)

        let shift = ShiftRow(
          id: "virtual-\(virtualShift.date)",
          user_id: nil,
          job_id: recurring.job_id,
          shift_date: virtualShift.date,
          start_time: recurring.start_time,
          end_time: recurring.end_time,
          custom_supplements: nil
        )

        let wageSnapshot = Self.snapshotForDate(
          virtualShift.date,
          jobId: recurring.job_id,
          snapshots: input.snapshots,
          jobs: input.jobs
        )
        let computed = PayrollCalculator.computeShift(shift, snapshot: wageSnapshot)

        let payrollDay = Self.payrollDay(
          for: recurring.job_id,
          jobs: input.jobs,
          settings: input.settings
        )
        let payoutDate = PayrollEngine.calculatePayoutDate(
          shiftDate: virtualShift.date,
          payrollDay: payrollDay
        )
        let taxSnapshot = Self.snapshotForDate(
          payoutDate,
          jobId: recurring.job_id,
          snapshots: input.snapshots,
          jobs: input.jobs
        )

        let taxEnabled = taxSnapshot?.effectiveTaxEnabled ?? false
        let netEarnings = computed.netPay(
          taxEnabled: taxEnabled,
          taxPercentage: taxSnapshot?.effectiveTaxPercentage ?? 0
        )
        let earnings = CalendarEarningsData(
          net: netEarnings,
          gross: computed.gross,
          hasTaxEnabled: taxEnabled
        )

        virtualShiftsWithEarnings.append(
          CalendarDisplayData.VirtualShiftWithEarnings(date: virtualShift.date, earnings: earnings)
        )

        existingNetEarnings[virtualShift.date, default: 0] += netEarnings
        existingGrossEarnings[virtualShift.date, default: 0] += computed.gross
        existingHasTax[virtualShift.date, default: false] =
          existingHasTax[virtualShift.date, default: false] || taxEnabled
        shiftTimesByDate[virtualShift.date, default: []].append(
          (start: recurring.cleanStartTime, end: recurring.cleanEndTime)
        )
      }
    }

    var existingEarnings: [String: CalendarEarningsData] = [:]
    for (date, net) in existingNetEarnings {
      existingEarnings[date] = CalendarEarningsData(
        net: net,
        gross: existingGrossEarnings[date] ?? net,
        hasTaxEnabled: existingHasTax[date] ?? false
      )
    }

    var existingHours: [String: HoursData] = [:]
    for (date, shiftsOnDate) in shiftTimesByDate {
      guard !shiftsOnDate.isEmpty else { continue }

      let sortedByStart = shiftsOnDate.sorted {
        CalendarGridHelper.timeToMinutes($0.start) < CalendarGridHelper.timeToMinutes($1.start)
      }
      let earliestStart = sortedByStart.first?.start ?? ""
      let latestEnd =
        shiftsOnDate.max(by: { lhs, rhs in
          let lhsStart = CalendarGridHelper.timeToMinutes(lhs.start)
          let lhsEnd = CalendarGridHelper.timeToMinutes(lhs.end)
          let lhsAdjustedEnd = lhsEnd <= lhsStart ? lhsEnd + 24 * 60 : lhsEnd

          let rhsStart = CalendarGridHelper.timeToMinutes(rhs.start)
          let rhsEnd = CalendarGridHelper.timeToMinutes(rhs.end)
          let rhsAdjustedEnd = rhsEnd <= rhsStart ? rhsEnd + 24 * 60 : rhsEnd

          return lhsAdjustedEnd < rhsAdjustedEnd
        })?.end ?? ""
      let crossesMidnight = shiftsOnDate.contains {
        CalendarGridHelper.timeToMinutes($0.end) <= CalendarGridHelper.timeToMinutes($0.start)
      }

      existingHours[date] = HoursData(
        start: CalendarGridHelper.formatTime(earliestStart),
        end: CalendarGridHelper.formatTime(latestEnd),
        crossesMidnight: crossesMidnight
      )
    }

    return CalendarDisplayData(
      existingShiftDates: existingDates,
      existingShiftEarnings: existingEarnings,
      existingShiftHours: existingHours,
      virtualShifts: virtualShiftsWithEarnings,
      year: input.year,
      month: input.month,
      timestamp: Date()
    )
  }

  private nonisolated static func computeConflictsAndPreviewsOffMain(
    _ input: ConflictsAndPreviewsComputationInput
  ) async -> ConflictsAndPreviewsComputationResult {
    await Task.detached(priority: .userInitiated) {
      Self.buildConflictsAndPreviews(input)
    }.value
  }

  private nonisolated static func buildConflictsAndPreviews(
    _ input: ConflictsAndPreviewsComputationInput
  ) -> ConflictsAndPreviewsComputationResult {
    let earningsContext = EarningsComputationContext(
      requiresExplicitJobSelection: input.requiresExplicitJobSelection,
      selectedJobId: input.selectedJobId,
      effectiveJobId: input.effectiveJobId,
      snapshots: input.snapshots,
      jobs: input.jobs,
      settings: input.settings
    )

    let projectedRecurringDates: [String]?
    let anchorEarnings: [String: CalendarEarningsData]?
    let datesToCheck: [String]

    switch input.mode {
    case .single:
      projectedRecurringDates = nil
      anchorEarnings = nil
      datesToCheck = input.selectedDates
    case .recurring:
      if !input.selectedDays.isEmpty {
        let generated = RecurringShiftProjector.generateDatesForCalendarDisplay(
          selectedDays: input.selectedDays,
          repeatInterval: input.repeatInterval,
          displayMonth: input.displayMonth,
          endCondition: input.endCondition
        )
        projectedRecurringDates = generated
        datesToCheck = generated

        if input.hasValidTimes {
          var computedByAnchor: [String: CalendarEarningsData] = [:]
          for (weekday, anchorISO) in input.selectedDays {
            if let earnings = Self.computeEarningsForDate(
              anchorISO,
              startTime: input.startTime,
              endTime: input.endTime,
              context: earningsContext
            ) {
              computedByAnchor[weekday] = earnings
            }
          }
          anchorEarnings = computedByAnchor
        } else {
          anchorEarnings = nil
        }
      } else {
        projectedRecurringDates = []
        anchorEarnings = [:]
        datesToCheck = []
      }
    }

    guard input.hasValidTimes, !datesToCheck.isEmpty else {
      return ConflictsAndPreviewsComputationResult(
        projectedRecurringDates: projectedRecurringDates,
        anchorEarnings: anchorEarnings,
        conflictDates: [],
        previewEarnings: [:]
      )
    }

    let conflicts = ShiftConflictDetector.detectConflicts(
      dates: datesToCheck,
      startTime: input.startTime,
      endTime: input.endTime,
      existingShifts: input.existingShifts,
      existingRecurringShifts: input.existingRecurringShifts
    )

    var previewEarnings: [String: CalendarEarningsData] = [:]
    if input.mode == .single {
      for dateISO in input.selectedDates {
        if let earnings = Self.computeEarningsForDate(
          dateISO,
          startTime: input.startTime,
          endTime: input.endTime,
          context: earningsContext
        ) {
          previewEarnings[dateISO] = earnings
        }
      }
    }

    return ConflictsAndPreviewsComputationResult(
      projectedRecurringDates: projectedRecurringDates,
      anchorEarnings: anchorEarnings,
      conflictDates: conflicts,
      previewEarnings: previewEarnings
    )
  }

  private nonisolated static func computeEarningsForDate(
    _ dateISO: String,
    startTime: String,
    endTime: String,
    context: EarningsComputationContext
  ) -> CalendarEarningsData? {
    if context.requiresExplicitJobSelection && context.selectedJobId == nil {
      return nil
    }

    let wageSnapshot = Self.snapshotForDate(
      dateISO,
      jobId: context.effectiveJobId,
      snapshots: context.snapshots,
      jobs: context.jobs
    )

    let payrollDay = Self.payrollDay(
      for: context.effectiveJobId,
      jobs: context.jobs,
      settings: context.settings
    )
    let payoutDate = PayrollEngine.calculatePayoutDate(shiftDate: dateISO, payrollDay: payrollDay)
    let taxSnapshot = Self.snapshotForDate(
      payoutDate,
      jobId: context.effectiveJobId,
      snapshots: context.snapshots,
      jobs: context.jobs
    )

    let shift = ShiftRow(
      id: "preview-\(dateISO)",
      user_id: nil,
      job_id: context.effectiveJobId,
      shift_date: dateISO,
      start_time: startTime,
      end_time: endTime,
      custom_supplements: nil
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: wageSnapshot)
    let taxEnabled = taxSnapshot?.effectiveTaxEnabled ?? false
    let net = computed.netPay(
      taxEnabled: taxEnabled,
      taxPercentage: taxSnapshot?.effectiveTaxPercentage ?? 0
    )

    return CalendarEarningsData(net: net, gross: computed.gross, hasTaxEnabled: taxEnabled)
  }

  private nonisolated static func snapshotsForJob(
    _ jobId: String?,
    snapshots: [WageSnapshot],
    jobs: [Job]
  ) -> [WageSnapshot] {
    guard let jobId else { return snapshots }

    let jobSnapshots = snapshots.filter { $0.job_id == jobId }
    if !jobSnapshots.isEmpty {
      return jobSnapshots
    }

    let defaultJobId = jobs.first(where: { $0.is_default })?.id
    if defaultJobId == jobId {
      return snapshots.filter { $0.job_id == nil }
    }

    return []
  }

  private nonisolated static func snapshotForDate(
    _ dateISO: String,
    jobId: String?,
    snapshots: [WageSnapshot],
    jobs: [Job]
  ) -> WageSnapshot? {
    SnapshotsService.snapshotForDate(
      dateISO, from: snapshotsForJob(jobId, snapshots: snapshots, jobs: jobs))
  }

  private nonisolated static func payrollDay(
    for jobId: String?,
    jobs: [Job],
    settings: UserSettings?
  ) -> Int {
    if let jobId, let jobPayrollDay = jobs.first(where: { $0.id == jobId })?.payroll_day {
      return jobPayrollDay
    }
    return settings?.effectivePayrollDay ?? 1
  }

  /// Virtual shift with computed earnings
  struct VirtualShiftWithEarnings {
    let date: String
    let earnings: CalendarEarningsData
  }

  /// Generate virtual shift dates from recurring patterns for display
  private func generateVirtualShiftDatesForDisplay() -> Set<String> {
    Set(generateVirtualShiftsForDisplay().map { $0.date })
  }

  /// Generate virtual shifts with computed earnings from recurring patterns (net after tax)
  /// Uses wage snapshot from shift date, tax snapshot from payout date (shift month + 1)
  private func generateVirtualShiftsForDisplay() -> [VirtualShiftWithEarnings] {
    var results: [VirtualShiftWithEarnings] = []

    // Only generate for the currently displayed month
    let year = displayYear
    let month = displayMonthNumber

    for recurring in cachedRecurringShifts {
      let virtualShifts = RecurringShiftGenerator.generateVirtualShiftsForMonth(
        year: year,
        month: month,
        recurring: recurring
      )

      for virtualShift in virtualShifts {
        // Create a temporary shift to compute earnings
        let shift = ShiftRow(
          id: "virtual-\(virtualShift.date)",
          user_id: nil,
          job_id: recurring.job_id,
          shift_date: virtualShift.date,
          start_time: recurring.start_time,
          end_time: recurring.end_time,
          custom_supplements: nil
        )

        // Wage/supplements from shift date
        let wageSnapshot = snapshotForDate(virtualShift.date, jobId: recurring.job_id)
        let computed = PayrollCalculator.computeShift(shift, snapshot: wageSnapshot)

        // Tax settings from payout date (shift month + 1)
        let payrollDay = payrollDay(for: recurring.job_id)
        let payoutDate = PayrollEngine.calculatePayoutDate(
          shiftDate: virtualShift.date, payrollDay: payrollDay)
        let taxSnapshot = snapshotForDate(payoutDate, jobId: recurring.job_id)

        let taxEnabled = taxSnapshot?.effectiveTaxEnabled ?? false
        let net = computed.netPay(
          taxEnabled: taxEnabled,
          taxPercentage: taxSnapshot?.effectiveTaxPercentage ?? 0
        )

        results.append(
          VirtualShiftWithEarnings(
            date: virtualShift.date,
            earnings: CalendarEarningsData(
              net: net,
              gross: computed.gross,
              hasTaxEnabled: taxEnabled
            )
          ))
      }
    }

    return results
  }

  /// Clear the form after successful submission
  private func clearForm() {
    // Clear the saved draft since submission was successful
    clearDraft()

    // Clear date selections
    selectedDates.removeAll()
    selectedDays.removeAll()

    // Clear cached computation data
    cachedPreviewEarnings.removeAll()
    cachedConflictDatesForCalendar.removeAll()
    cachedProjectedRecurringDates.removeAll()
    cachedAnchorEarnings.removeAll()

    // Cancel any pending preview update before clearing times
    previewUpdateTask?.cancel()
    previewUpdateTask = nil

    // Clear times so user can start fresh
    startTime = nil
    endTime = nil

    // Reset recurring options to defaults (biweekly, indefinite)
    repeatInterval = 1
    endCondition = nil

    // NOTE: Do NOT reset the month context here!
    // The user should stay on the month where they just added shifts
    // so that when they're navigated to the Shifts tab, they see their new shifts.

    // Clear error state
    error = nil
  }

  /// Default start time (09:00)
  private static func defaultStartTime() -> Date {
    let calendar = Calendar.current
    var components = calendar.dateComponents([.year, .month, .day], from: Date())
    components.hour = 9
    components.minute = 0
    return calendar.date(from: components) ?? Date()
  }

  /// Default end time (17:00)
  private static func defaultEndTime() -> Date {
    let calendar = Calendar.current
    var components = calendar.dateComponents([.year, .month, .day], from: Date())
    components.hour = 17
    components.minute = 0
    return calendar.date(from: components) ?? Date()
  }

  // MARK: - Draft Persistence Methods

  /// Schedule a debounced draft save
  private func scheduleDraftSave() {
    // Cancel any pending save
    draftSaveTask?.cancel()

    // Schedule new save with debounce delay
    draftSaveTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: Self.draftSaveDebounceDelay)

        // Check if cancelled during sleep
        guard !Task.isCancelled else { return }

        await MainActor.run {
          self?.saveDraft()
        }
      } catch {
        // Task was cancelled - this is expected
      }
    }
  }

  /// Save the current form state as a draft
  private func saveDraft() {
    let draft = ShiftDraft(
      mode: mode,
      startTime: startTime.map { formatTimeAsHHmm($0) },
      endTime: endTimeString.isEmpty ? nil : endTimeString,
      jobId: selectedJobId,
      selectedDates: Array(selectedDates),
      selectedDays: selectedDays,
      repeatInterval: repeatInterval,
      endCondition: endCondition,
      lastModified: Date()
    )

    // Only save if there's meaningful content
    guard draft.hasContent else {
      clearDraft()
      return
    }

    if let data = try? JSONEncoder().encode(draft) {
      UserDefaults.standard.set(data, forKey: ShiftDraft.userDefaultsKey)
      logger.debug("Saved draft: mode=\(draft.mode.rawValue), dates=\(draft.selectedDates.count)")
    }
  }

  /// Load a saved draft if it exists and hasn't expired
  private func loadDraft() {
    guard let data = UserDefaults.standard.data(forKey: ShiftDraft.userDefaultsKey),
      let draft = try? JSONDecoder().decode(ShiftDraft.self, from: data),
      !draft.isExpired,
      draft.hasContent
    else {
      return
    }

    // Restore form state from draft
    mode = draft.mode
    selectedJobId = draft.jobId

    // Restore times
    if let startTimeString = draft.startTime {
      startTime = parseTimeFromHHmm(startTimeString)
    }
    if let endTimeString = draft.endTime {
      endTime = parseTimeFromHHmm(endTimeString)
    }

    // Restore mode-specific data
    switch mode {
    case .single:
      selectedDates = Set(draft.selectedDates)
    case .recurring:
      selectedDays = draft.selectedDays
      repeatInterval = draft.repeatInterval
      endCondition = draft.endCondition
    }

    logger.info(
      "Loaded draft: mode=\(draft.mode.rawValue), dates=\(draft.selectedDates.count), days=\(draft.selectedDays.count), jobSelected=\(draft.jobId != nil)"
    )
  }

  /// Clear the saved draft
  func clearDraft() {
    draftSaveTask?.cancel()
    draftSaveTask = nil
    UserDefaults.standard.removeObject(forKey: ShiftDraft.userDefaultsKey)
    logger.debug("Cleared draft")
  }

  /// Start fresh - clear all form data and the draft
  func startFresh() {
    clearDraft()
    clearSelectedDates()
    clearAnchors()
    startTime = nil
    endTime = nil
    repeatInterval = 1
    endCondition = nil
    error = nil

    // Haptic feedback
    let generator = UIImpactFeedbackGenerator(style: .medium)
    generator.impactOccurred()
  }

  /// Parse HH:mm string to Date (supports "24:00" as midnight)
  private func parseTimeFromHHmm(_ timeString: String) -> Date? {
    // Handle "24:00" which DateFormatter can't parse
    let is24 = timeString == "24:00"
    let parseable = is24 ? "00:00" : timeString

    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    guard let time = formatter.date(from: parseable) else { return nil }

    // Transfer hour and minute to today's date
    let calendar = Calendar.current
    var components = calendar.dateComponents([.year, .month, .day], from: Date())
    let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
    components.hour = timeComponents.hour
    components.minute = timeComponents.minute

    return calendar.date(from: components)
  }

  // MARK: - Performance Optimization Methods

  /// Schedule a debounced preview update after time input changes
  /// Uses adaptive delays: instant feedback when form is complete, debounced during typing
  private func schedulePreviewUpdate() {
    // Cancel any pending update
    previewUpdateTask?.cancel()

    // Use shorter delay when both times are set (user editing complete form = instant feedback)
    // Use longer delay when partially filled (user actively typing = debounce to reduce thrashing)
    let delay = hasValidTimes ? Self.completedFormDelay : Self.activeTypingDelay

    // Schedule new update with adaptive delay
    previewUpdateTask = Task { [weak self] in
      do {
        try await Task.sleep(nanoseconds: delay)

        // Check if cancelled during sleep
        guard !Task.isCancelled else { return }

        self?.scheduleConflictsAndPreviewsRecompute()
      } catch {
        // Task was cancelled - this is expected
      }
    }
  }

  private func scheduleCalendarDisplayRebuild() {
    displayComputationVersion &+= 1
    let computationVersion = displayComputationVersion
    let input = CalendarDisplayComputationInput(
      year: displayYear,
      month: displayMonthNumber,
      shifts: cachedShifts,
      recurringShifts: cachedRecurringShifts,
      snapshots: cachedSnapshots,
      jobs: activeJobs,
      settings: cachedSettings
    )

    Task { [weak self] in
      guard let self else { return }
      let displayData = await Self.computeCalendarDisplayDataOffMain(input)
      guard !Task.isCancelled else { return }
      guard self.displayComputationVersion == computationVersion else { return }

      self.cachedDisplayData = displayData
      logger.info(
        "Rebuilt calendar display data: \(displayData.existingShiftDates.count) dates, \(displayData.virtualShifts.count) virtual shifts"
      )
    }
  }

  private func scheduleConflictsAndPreviewsRecompute() {
    previewComputationVersion &+= 1
    let computationVersion = previewComputationVersion

    Task { [weak self] in
      await self?.computeConflictsAndPreviews(computationVersion: computationVersion)
    }
  }

  /// Update conflicts and preview earnings (called after time changes or initial load)
  private func updateConflictsAndPreviews() {
    scheduleConflictsAndPreviewsRecompute()
  }

  private func computeConflictsAndPreviews(computationVersion: UInt64) async {
    let input = ConflictsAndPreviewsComputationInput(
      mode: mode,
      selectedDates: Array(selectedDates),
      selectedDays: selectedDays,
      repeatInterval: repeatInterval,
      displayMonth: displayMonth,
      endCondition: endCondition,
      hasValidTimes: hasValidTimes,
      startTime: startTimeString,
      endTime: endTimeString,
      requiresExplicitJobSelection: requiresExplicitJobSelection,
      selectedJobId: selectedJobId,
      effectiveJobId: effectiveSelectedJobId,
      existingShifts: cachedShifts,
      existingRecurringShifts: cachedRecurringShifts,
      snapshots: cachedSnapshots,
      jobs: activeJobs,
      settings: cachedSettings
    )

    let result = await Self.computeConflictsAndPreviewsOffMain(input)
    guard !Task.isCancelled else { return }
    guard previewComputationVersion == computationVersion else { return }

    if let projectedDates = result.projectedRecurringDates {
      cachedProjectedRecurringDates = projectedDates
    }
    if let anchorEarnings = result.anchorEarnings {
      cachedAnchorEarnings = anchorEarnings
    }
    cachedConflictDatesForCalendar = result.conflictDates
    cachedPreviewEarnings = result.previewEarnings
  }

  /// Incrementally update preview earnings when a single date is added
  private func updatePreviewEarningsIncrementally(addedDate: String) {
    guard hasValidTimes else { return }

    if let earnings = computeEarningsForDate(addedDate) {
      cachedPreviewEarnings[addedDate] = earnings
    }
  }

  /// Incrementally update conflicts when a date is added
  private func updateConflictsIncrementally(addedDate: String) {
    guard hasValidTimes else { return }

    // Check if the added date conflicts with existing shifts
    let conflicts = ShiftConflictDetector.detectConflicts(
      dates: [addedDate],
      startTime: startTimeString,
      endTime: endTimeString,
      existingShifts: cachedShifts,
      existingRecurringShifts: cachedRecurringShifts
    )

    // Add any conflicts found
    cachedConflictDatesForCalendar.formUnion(conflicts)
  }

  /// Incrementally update conflicts when a date is removed
  private func updateConflictsIncrementally(removedDate: String) {
    // Simply remove the date from conflicts (it can't conflict if it's not selected)
    cachedConflictDatesForCalendar.remove(removedDate)
  }

  /// Update projected recurring dates when recurring settings change
  func updateProjectedRecurringDates() {
    guard !selectedDays.isEmpty else {
      cachedProjectedRecurringDates = []
      cachedAnchorEarnings = [:]
      return
    }

    // Only generate dates for calendar display (current month)
    cachedProjectedRecurringDates = RecurringShiftProjector.generateDatesForCalendarDisplay(
      selectedDays: selectedDays,
      repeatInterval: repeatInterval,
      displayMonth: displayMonth,
      endCondition: endCondition
    )

    // Compute earnings once per anchor
    if hasValidTimes {
      var anchorEarnings: [String: CalendarEarningsData] = [:]
      for (weekday, anchorISO) in selectedDays {
        if let earnings = computeEarningsForDate(anchorISO) {
          anchorEarnings[weekday] = earnings
        }
      }
      cachedAnchorEarnings = anchorEarnings

      // Update conflicts for the projected dates
      cachedConflictDatesForCalendar = ShiftConflictDetector.detectConflicts(
        dates: cachedProjectedRecurringDates,
        startTime: startTimeString,
        endTime: endTimeString,
        existingShifts: cachedShifts,
        existingRecurringShifts: cachedRecurringShifts
      )
    }
  }
}

extension AddShiftViewModel: AddShiftCalendarViewModeling {}
