import AppIntents
import Combine
import Foundation
import Observation
import SwiftUI
import os.log

let addShiftViewModelLogger: Logger = Logger(
  subsystem: "com.tidex.app", category: "AddShiftViewModel")

internal struct AddShiftPaySetupRequest: Identifiable, Equatable {
  internal enum Action: String, Equatable {
    case selectJob
    case showRecurringPreview
    case submitRecurring
    case submitSingle
  }

  internal let job: Job
  internal let action: Action

  internal var id: String {
    "\(job.id)-\(action.rawValue)"
  }
}

// MARK: - Calendar Display Data

/// Pre-computed display data for calendar cells to avoid redundant computation
internal struct CalendarDisplayData {
  /// Virtual shift with computed earnings
  internal struct VirtualShiftWithEarnings {
    internal let date: String
    internal let earnings: CalendarEarningsData
  }

  /// Set of dates that have existing shifts
  internal let existingShiftDates: Set<String>
  /// Earnings by date for existing shifts
  internal let existingShiftEarnings: [String: CalendarEarningsData]
  /// Start/end hour range by date for existing shifts
  internal let existingShiftHours: [String: HoursData]
  /// Virtual shifts with computed earnings (cached)
  internal let virtualShifts: [VirtualShiftWithEarnings]
  /// Year and month this data is for
  internal let year: Int
  internal let month: Int
  /// Timestamp for cache invalidation
  internal let timestamp: Date

  /// Check if cache is valid for the given month
  internal func isValid(for year: Int, month: Int) -> Bool {
    self.year == year && self.month == month
  }
}

/// ViewModel for the Add Shift screen
/// Manages state for single, event, and recurring add modes
@MainActor
@Observable
internal final class AddShiftViewModel {

  // MARK: - Dependencies

  let shiftsRepository: ShiftsRepository
  let eventsRepository: EventsRepository
  let recurringRepository: RecurringShiftsRepository
  let jobsRepository: JobsRepository
  let settingsRepository: SettingsRepository
  let snapshotsRepository: SnapshotsRepository
  let jobPaySetupStatusService: JobPaySetupStatusService
  let monthContext: SharedMonthContext
  private let addShiftCoordinator: AddShiftCoordinator
  let draftDefaults: UserDefaults
  @ObservationIgnored var eventRangeAnchorDate: Date?
  @ObservationIgnored var didEditEventCalendarSinceEnteringEvents: Bool = false
  @ObservationIgnored var isSyncingCalendarSelectionAcrossModes: Bool = false
  @ObservationIgnored var pendingDeepLinkMode: AddShiftMode?

  // MARK: - Mode State

  internal var mode: AddShiftMode = .single {
    didSet {
      guard oldValue != mode else {
        return
      }
      syncCalendarSelectionForModeTransition(from: oldValue, to: mode)
      if mode == .events {
        selectedDays.removeAll()
      }
      publishStateToCoordinator()
      scheduleDraftSave()
    }
  }

  // MARK: - Shared State

  // swiftlint:disable:next explicit_acl type_contents_order
  var startTime: Date? {
    didSet {
      // Debounce time changes - schedule recomputation
      schedulePreviewUpdate()
      publishStateToCoordinator()
      scheduleDraftSave()
    }
  }
  // swiftlint:disable:next explicit_acl type_contents_order
  var endTime: Date? {
    didSet {
      // Debounce time changes - schedule recomputation
      schedulePreviewUpdate()
      publishStateToCoordinator()
      scheduleDraftSave()
    }
  }
  internal var isLoading: Bool = false {
    didSet { publishStateToCoordinator() }
  }
  internal var error: String?

  // MARK: - Event Mode State

  internal var eventNote: String = "" {
    didSet {
      publishStateToCoordinator()
      scheduleDraftSave()
    }
  }

  internal var isEventAllDay: Bool = false {
    didSet {
      guard oldValue != isEventAllDay else {
        return
      }
      markEventCalendarSelectionEdited()
      if isEventAllDay {
        if eventStartDate != eventDate {
          eventStartDate = eventDate
        }
        if eventEndDate != eventDate {
          eventEndDate = eventDate
        }
        startTime = nil
        endTime = nil
        eventRangeAnchorDate = eventStartDate
        if !eventReminderTimes.isEmpty, eventReminderAnchorTime == nil {
          eventReminderAnchorTime = Self.defaultEventReminderAnchorTime()
        }
      } else {
        if eventDate != eventStartDate {
          eventDate = eventStartDate
        }
        if eventEndDate != eventStartDate {
          eventEndDate = eventStartDate
        }
        eventReminderAnchorTime = nil
        eventRangeAnchorDate = eventDate
      }
      publishStateToCoordinator()
      scheduleDraftSave()
    }
  }

  internal var eventDate: Date = Calendar.gregorianCurrent.startOfDay(for: Date()) {
    didSet {
      guard oldValue != eventDate else {
        return
      }
      if !isEventAllDay {
        if eventStartDate != eventDate {
          eventStartDate = eventDate
        }
        if eventEndDate != eventDate {
          eventEndDate = eventDate
        }
        eventRangeAnchorDate = eventDate
      }
      publishStateToCoordinator()
      scheduleDraftSave()
    }
  }

  internal var eventStartDate: Date = Calendar.gregorianCurrent.startOfDay(for: Date()) {
    didSet {
      guard oldValue != eventStartDate else {
        return
      }
      if !isEventAllDay {
        if eventDate != eventStartDate {
          eventDate = eventStartDate
        }
        eventRangeAnchorDate = eventStartDate
      }
      publishStateToCoordinator()
      scheduleDraftSave()
    }
  }

  internal var eventEndDate: Date = Calendar.gregorianCurrent.startOfDay(for: Date()) {
    didSet {
      guard oldValue != eventEndDate else {
        return
      }
      publishStateToCoordinator()
      scheduleDraftSave()
    }
  }

  internal var eventReminderTimes: [Int] = [] {
    didSet {
      let normalized: [Int] = LocalEvent.normalizedReminderMinutes(eventReminderTimes)
      guard oldValue != normalized else {
        return
      }
      if eventReminderTimes != normalized {
        eventReminderTimes = normalized
        return
      }
      if isEventAllDay, !normalized.isEmpty, eventReminderAnchorTime == nil {
        eventReminderAnchorTime = Self.defaultEventReminderAnchorTime()
      }
      publishStateToCoordinator()
      scheduleDraftSave()
    }
  }

  internal var eventReminderAnchorTime: Date? {
    didSet {
      guard oldValue != eventReminderAnchorTime else {
        return
      }
      publishStateToCoordinator()
      scheduleDraftSave()
    }
  }

  /// Active (non-archived, non-deleted) jobs for the current user.
  internal var activeJobs: [Job] = []
  /// Active job IDs that have the required baseline wage snapshot.
  internal var configuredJobIds: Set<String> = []

  /// Number of distinct start/end time pairs the user has used across all shifts.
  internal var distinctShiftTimePairCount: Int = 0

  /// Selected job for new shift creation.
  /// Defaults to the user's standard workplace when no valid selection exists.
  internal var selectedJobId: String? {
    didSet {
      guard oldValue != selectedJobId else {
        return
      }
      publishStateToCoordinator()
      scheduleDraftSave()
      scheduleConflictsAndPreviewsRecompute()
    }
  }

  // MARK: - Time Input Debouncing

  /// Debounce timer for time input changes
  @ObservationIgnored var previewUpdateTask: Task<Void, Never>?

  /// Guards against applying stale async preview/conflict computations.
  var previewComputationVersion: UInt64 = 0

  /// Guards against applying stale async calendar display computations.
  var displayComputationVersion: UInt64 = 0

  /// Debounce delay when user is actively typing (partial input)
  static let activeTypingDelay: UInt64 = 150_000_000  // 150ms

  /// Minimal delay when form is complete (instant feedback)
  static let completedFormDelay: UInt64 = 50_000_000  // 50ms

  static let defaultStartHour: Int = 9
  static let defaultEndHour: Int = 17

  struct CalendarDisplayComputationInput {
    let year: Int
    let month: Int
    let shifts: [ShiftRow]
    let recurringShifts: [RecurringShiftRow]
    let snapshots: [WageSnapshot]
    let jobs: [Job]
    let settings: UserSettings?
  }

  struct ConflictsAndPreviewsComputationInput {
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
    let configuredJobIds: Set<String>
    let settings: UserSettings?
  }

  struct ConflictsAndPreviewsComputationResult {
    let projectedRecurringDates: [String]?
    let anchorEarnings: [String: CalendarEarningsData]?
    let conflictDates: Set<String>
    let previewEarnings: [String: CalendarEarningsData]
  }

  struct EarningsComputationContext {
    let requiresExplicitJobSelection: Bool
    let selectedJobId: String?
    let effectiveJobId: String?
    let snapshots: [WageSnapshot]
    let jobs: [Job]
    let configuredJobIds: Set<String>
    let settings: UserSettings?
  }

  // MARK: - Draft Persistence

  /// Debounce timer for draft saving
  @ObservationIgnored var draftSaveTask: Task<Void, Never>?

  /// Debounce delay for draft saving (500ms)
  static let draftSaveDebounceDelay: UInt64 = 500_000_000

  /// Display month as Date - computed from SharedMonthContext
  /// Setter updates the SharedMonthContext to sync with other tabs
  var displayMonth: Date {
    get {
      var components = DateComponents()
      components.year = monthContext.displayYear
      components.month = monthContext.displayMonth
      components.day = 1
      return Calendar.gregorianCurrent.date(from: components) ?? Date()
    }
    set {
      let calendar = Calendar.gregorianCurrent
      let components = calendar.dateComponents([.year, .month], from: newValue)
      if let year = components.year, let month = components.month {
        // Update tracking immediately to prevent the subscription from double-triggering
        lastObservedYear = year
        lastObservedMonth = month

        // Update shared context (this will trigger other tabs); displayMonth's getter reads
        // monthContext's observed properties directly, so views tracking it refresh
        // automatically without a manual notification.
        monthContext.navigateTo(year: year, month: month)
      }
    }
  }

  /// Subscription to SharedMonthContext changes
  @ObservationIgnored private var monthContextCancellable: AnyCancellable?

  /// Subscription to tab bar add action trigger
  @ObservationIgnored private var addActionCancellable: AnyCancellable?

  /// Track the last observed month to detect changes
  @ObservationIgnored private var lastObservedYear: Int = 0
  @ObservationIgnored private var lastObservedMonth: Int = 0

  /// Direction of last navigation (for animations). Read live so it changes in the same
  /// update as the month; a copy made in the month subscription lands a run loop late.
  var navigationDirection: MonthNavigationDirection? { monthContext.navigationDirection }

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
  var currency: String = "kr"

  // MARK: - Single Mode State

  var selectedDates: Set<String> = [] {  // ISO dates (YYYY-MM-DD)
    didSet {
      publishStateToCoordinator()
      scheduleDraftSave()
    }
  }

  // MARK: - Recurring Mode State

  var repeatInterval: Int = 1 {  // 0 = weekly, 1 = biweekly, etc. Default: biweekly
    didSet {
      scheduleDraftSave()
      // Update projected dates immediately when interval changes
      updateProjectedRecurringDates()
    }
  }
  var selectedDays: [String: String] = [:] {  // weekday "0"-"6" -> anchor ISO date
    didSet {
      publishStateToCoordinator()
      scheduleDraftSave()
    }
  }
  // swiftlint:disable:next explicit_acl type_contents_order
  var endCondition: EndCondition? {  // Default: indefinite
    didSet {
      scheduleDraftSave()
      // Update projected dates immediately when end condition changes
      updateProjectedRecurringDates()
    }
  }
  var showPreviewSheet = false
  var showSubmitJobChooser = false
  var paySetupRequest: AddShiftPaySetupRequest?

  // MARK: - Cached Data

  @ObservationIgnored var cachedShifts: [ShiftRow] = []
  @ObservationIgnored var cachedRecurringShifts: [RecurringShiftRow] = []
  @ObservationIgnored var cachedSnapshots: [WageSnapshot] = []
  @ObservationIgnored var cachedSettings: UserSettings?

  // MARK: - Performance Optimized Caches

  /// Cached calendar display data - computed once per month, not per view update
  var cachedDisplayData: CalendarDisplayData?

  /// Cached conflict dates - only recomputed when dates or times change
  var cachedConflictDatesForCalendar: Set<String> = []

  /// Cached preview earnings - only recomputed when selection or times change
  var cachedPreviewEarnings: [String: CalendarEarningsData] = [:]

  /// Cached projected recurring dates for calendar display (current month only)
  var cachedProjectedRecurringDates: [String] = []

  /// Cached earnings per anchor weekday - computed once per anchor, shared by all projected dates
  var cachedAnchorEarnings: [String: CalendarEarningsData] = [:]

  // MARK: - Preview Cache (computed only when preview sheet is shown)

  /// Cached projected dates for preview sheet - computed once when preview is shown
  var cachedProjectedDates: [String] = []
  /// Cached conflict dates for preview sheet
  var cachedConflictDates: Set<String> = []

  /// Prevents reloading the saved draft over live add-state on later tab appearances.
  @ObservationIgnored var hasLoadedInitialData = false

  // MARK: - Navigation Callback

  /// Called when shifts are successfully created.
  var onShiftsCreated: (() -> Void)?

  // MARK: - Initialization

  init(
    shiftsRepository: ShiftsRepository? = nil,
    eventsRepository: EventsRepository? = nil,
    recurringRepository: RecurringShiftsRepository? = nil,
    jobsRepository: JobsRepository? = nil,
    settingsRepository: SettingsRepository? = nil,
    snapshotsRepository: SnapshotsRepository? = nil,
    jobPaySetupStatusService: JobPaySetupStatusService? = nil,
    monthContext: SharedMonthContext? = nil,
    addShiftCoordinator: AddShiftCoordinator? = nil,
    draftDefaults: UserDefaults = .standard
  ) {
    self.shiftsRepository = shiftsRepository ?? ShiftsRepository.shared
    self.eventsRepository = eventsRepository ?? EventsRepository.shared
    self.recurringRepository = recurringRepository ?? RecurringShiftsRepository.shared
    self.jobsRepository = jobsRepository ?? JobsRepository.shared
    self.settingsRepository = settingsRepository ?? SettingsRepository.shared
    self.snapshotsRepository = snapshotsRepository ?? SnapshotsRepository.shared
    self.jobPaySetupStatusService = jobPaySetupStatusService ?? JobPaySetupStatusService.shared
    self.monthContext = monthContext ?? SharedMonthContext.shared
    self.addShiftCoordinator = addShiftCoordinator ?? AddShiftCoordinator.shared
    self.draftDefaults = draftDefaults

    // Initialize tracking to current month context values
    self.lastObservedYear = self.monthContext.displayYear
    self.lastObservedMonth = self.monthContext.displayMonth

    // Subscribe to month context changes
    setupMonthContextSubscription()

    // Subscribe to tab bar add action trigger
    setupAddActionSubscription()
  }

  isolated deinit {
    monthContextCancellable?.cancel()
    addActionCancellable?.cancel()
    previewUpdateTask?.cancel()
    draftSaveTask?.cancel()
  }

  /// Subscribe to SharedMonthContext changes to reload data when month changes
  private func setupMonthContextSubscription() {
    // No main-queue hop: SharedMonthContext sends on the main actor, and handling the change
    // right away gives the calendar its new month and that month's shift times in one update.
    // A hop draws one frame of the new month without times, which then pop in mid-slide.
    monthContextCancellable = monthContext.monthChanged
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

        // Reload shifts and publish the new month's cell data together.
        reloadShiftsForDisplayedMonth()
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

    case .events:
      Task {
        await submitEvent()
      }
    }
  }

  /// Publish current state to the coordinator (call after state changes)
  func publishStateToCoordinator() {
    let canSubmit: Bool
    switch mode {
    case .single:
      canSubmit = canSubmitSingle

    case .recurring:
      canSubmit = canSubmitRecurring

    case .events:
      canSubmit = canSubmitEvent
    }
    addShiftCoordinator.updateCanSubmit(canSubmit)
    addShiftCoordinator.updateMode(mode)
    addShiftCoordinator.updateIsLoading(isLoading)
    addShiftCoordinator.updateJobSelection(
      selectedJobId: mode == .events ? nil : effectiveSelectedJobId,
      requiresJobSelection: mode == .events ? false : requiresExplicitJobSelection
    )
    addShiftCoordinator.updateSubmitBlockers(submitBlockers)
  }

  var paymentFormContext: PayrollAdjustmentFormContext?
  var paymentDataOwnerId: String?
  var paymentOwnerId: String?
  var paymentSaved = false
}

extension AddShiftViewModel: AddShiftCalendarViewModeling {}
