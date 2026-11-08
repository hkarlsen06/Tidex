import Combine
import Foundation
import Observation
import UIKit
import os.log  // swiftlint:disable:this sorted_imports

let dashboardViewModelLogger = Logger(subsystem: "com.tidex.app", category: "DashboardViewModel")  // swiftlint:disable:this explicit_type_interface line_length prefixed_toplevel_constant

// MARK: - Notification Names

extension Notification.Name {  // swiftlint:disable:this file_types_order
  /// Posted when dashboard clock button visibility changes in appearance settings.
  static let dashboardClockButtonsVisibilityDidChange = Notification.Name(  // swiftlint:disable:this explicit_acl explicit_type_interface line_length
    "com.tidex.dashboardClockButtonsVisibilityDidChange")  // swiftlint:disable:this multiline_arguments_brackets
}

// MARK: - Dashboard Error

enum DashboardError: Error, LocalizedError {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  case notAuthenticated  // swiftlint:disable:this sorted_enum_cases
  case dataLoadFailed(underlying: Error)  // swiftlint:disable:this sorted_enum_cases
  case noLocalData  // swiftlint:disable:this sorted_enum_cases

  var errorDescription: String? {  // swiftlint:disable:this explicit_acl
    switch self {
    case .notAuthenticated:
      return String(localized: .commonErrorNotAuthenticated)

    case .dataLoadFailed:
      return String(localized: .commonErrorLoadFailed)

    case .noLocalData:
      return String(localized: .commonErrorNoLocalData)
    }
  }
}

// MARK: - Dashboard View Model

@MainActor
@Observable
final class DashboardViewModel: MonthNavigable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl line_length

  // MARK: - Dependencies (Local-First Repositories)

  let shiftsRepository: ShiftsRepository  // swiftlint:disable:this type_contents_order
  let eventsRepository: EventsRepository  // swiftlint:disable:this type_contents_order
  let jobsRepository: JobsRepository  // swiftlint:disable:this type_contents_order
  let settingsRepository: SettingsRepository  // swiftlint:disable:this type_contents_order
  let snapshotsRepository: SnapshotsRepository  // swiftlint:disable:this type_contents_order
  let jobPaySetupStatusService: JobPaySetupStatusService  // swiftlint:disable:this type_contents_order
  let payrollAdjustmentsRepository: PayrollAdjustmentsRepository  // swiftlint:disable:this type_contents_order
  let recurringShiftsRepository: RecurringShiftsRepository  // swiftlint:disable:this type_contents_order
  let monthlyPayrollReadService: MonthlyPayrollReadService  // swiftlint:disable:this type_contents_order
  let syncCoordinator: SyncCoordinator  // swiftlint:disable:this type_contents_order
  let monthContext: SharedMonthContext  // swiftlint:disable:this type_contents_order
  let clockSessionStore: TemporaryClockSessionStore  // swiftlint:disable:this type_contents_order
  nonisolated static let gregorianCalendar = Calendar(identifier: .gregorian)  // swiftlint:disable:this explicit_type_interface line_length type_contents_order

  // MARK: - Published State

  var dashboardData: DashboardData?  // swiftlint:disable:this explicit_acl type_contents_order
  var payrollCardSnapshot: DashboardPayrollCardSnapshot?  // swiftlint:disable:this explicit_acl line_length type_contents_order
  var isLoading = false  // swiftlint:disable:this explicit_acl explicit_type_interface line_length type_contents_order
  var error: Error?  // swiftlint:disable:this explicit_acl type_contents_order

  enum ActiveClockState: Equatable {  // swiftlint:disable:this explicit_acl
    case none  // swiftlint:disable:this discouraged_none_name
    case temporary(TemporaryClockSession)
    case persisted(ShiftRow)
    case computed(ShiftWithComputations)
  }

  enum ClockOutRoute: Equatable {  // swiftlint:disable:this explicit_acl
    case none  // swiftlint:disable:this discouraged_none_name
    case temporaryReview(TemporaryClockSession)
    case persistedEnded
  }

  enum ClockError: LocalizedError {  // swiftlint:disable:this explicit_acl
    case invalidRange
    case noActiveSession
    case maxDurationExceeded

    var errorDescription: String? {  // swiftlint:disable:this explicit_acl
      switch self {
      case .invalidRange:
        return String(localized: .dashboardClockErrorInvalidRange)

      case .noActiveSession:
        return String(localized: .dashboardClockErrorNoActiveSession)

      case .maxDurationExceeded:
        return String(localized: .dashboardClockErrorMaxDurationExceeded)
      }
    }
  }

  var activeClockState: ActiveClockState = .none  // swiftlint:disable:this explicit_acl line_length type_contents_order
  var isClockActionInProgress = false  // swiftlint:disable:this explicit_acl explicit_type_interface line_length type_contents_order
  var shouldShowDashboardClockButtons = true  // swiftlint:disable:this explicit_acl explicit_type_interface line_length type_contents_order

  var isClockInEnabled: Bool {  // swiftlint:disable:this explicit_acl type_contents_order
    if isClockActionInProgress || isUpdatingShift { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
    if case .none = activeClockState { return true }  // swiftlint:disable:this conditional_returns_on_newline
    return false
  }

  var isClockOutEnabled: Bool {  // swiftlint:disable:this explicit_acl type_contents_order
    if isClockActionInProgress || isUpdatingShift { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
    if case .none = activeClockState { return false }  // swiftlint:disable:this conditional_returns_on_newline
    return true
  }

  /// Currently displayed year - synced from SharedMonthContext
  var displayYear: Int { monthContext.displayYear }  // swiftlint:disable:this explicit_acl type_contents_order

  /// Currently displayed month 1-12 - synced from SharedMonthContext
  var displayMonth: Int { monthContext.displayMonth }  // swiftlint:disable:this explicit_acl type_contents_order

  /// Whether viewing the current (real) month
  var isCurrentMonth: Bool { monthContext.isCurrentMonth }  // swiftlint:disable:this explicit_acl type_contents_order

  /// Computed month name for immediate display (doesn't wait for API)
  var displayMonthName: String { monthContext.displayMonthName }  // swiftlint:disable:this explicit_acl line_length type_contents_order

  // MARK: - User Profile Data (for UserMenuButton)

  /// User's display name (derived from email or metadata)
  var userDisplayName: String = ""  // swiftlint:disable:this explicit_acl type_contents_order
  /// User's profile picture URL
  var userAvatarUrl: String?  // swiftlint:disable:this explicit_acl type_contents_order
  /// All non-deleted jobs used for dashboard workplace metadata.
  var displayJobs: [Job] = []  // swiftlint:disable:this explicit_acl type_contents_order

  var shouldShowJobIndicators: Bool {  // swiftlint:disable:this explicit_acl type_contents_order
    displayJobs.count > 1
  }

  func jobForShift(_ shift: ShiftWithComputations) -> Job? {  // swiftlint:disable:this explicit_acl type_contents_order
    let defaultJobId = displayJobs.first(where: \.is_default)?.id  // swiftlint:disable:this explicit_type_interface
    let effectiveJobId = shift.shift.job_id ?? defaultJobId  // swiftlint:disable:this explicit_type_interface
    guard let effectiveJobId else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    return displayJobs.first(where: { $0.id == effectiveJobId })
  }

  func jobForTemporarySession(_ session: TemporaryClockSession) -> Job? {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    let defaultJobId = displayJobs.first(where: \.is_default)?.id  // swiftlint:disable:this explicit_type_interface
    let effectiveJobId = session.jobId ?? defaultJobId  // swiftlint:disable:this explicit_type_interface
    guard let effectiveJobId else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    return displayJobs.first(where: { $0.id == effectiveJobId })
  }

  // MARK: - Private State

  var displayedMonthShifts: [ShiftWithComputations] = []  // swiftlint:disable:this type_contents_order
  var displayedMonthEvents: [EventRow] = []  // swiftlint:disable:this type_contents_order
  var previousMonthShifts: [ShiftWithComputations] = []  // swiftlint:disable:this type_contents_order
  // swiftlint:disable:next type_contents_order
  @ObservationIgnored var previousPayrollAdjustments: [PayrollAdjustment] = []
  @ObservationIgnored var payrollAdjustmentsByPayoutMonth:
    [PayrollReadMonth: [PayrollAdjustment]] = [:]  // swiftlint:disable:this type_contents_order
  @ObservationIgnored var settings: UserSettings?  // swiftlint:disable:this type_contents_order
  @ObservationIgnored var snapshots: [WageSnapshot] = []  // swiftlint:disable:this type_contents_order
  // swiftlint:disable:next type_contents_order
  @ObservationIgnored var recurringShifts: [RecurringShiftRow] = []
  // swiftlint:disable:next explicit_type_interface type_contents_order
  @ObservationIgnored var dashboardDependenciesLoaded = false
  @ObservationIgnored var cachedUserId: String?  // swiftlint:disable:this type_contents_order
  // swiftlint:disable:next explicit_type_interface type_contents_order
  @ObservationIgnored var isActiveTabVisible = true
  // swiftlint:disable:next explicit_type_interface type_contents_order
  @ObservationIgnored var localDataNeedsReload = false
  // swiftlint:disable:next explicit_type_interface type_contents_order
  @ObservationIgnored var displayedMonthLoadPending = false

  /// Subscription to SharedMonthContext changes
  @ObservationIgnored private var monthContextCancellable: AnyCancellable?
  // swiftlint:disable:previous type_contents_order

  /// Track the last observed month to detect changes
  @ObservationIgnored var lastObservedYear: Int = 0  // swiftlint:disable:this type_contents_order
  @ObservationIgnored var lastObservedMonth: Int = 0  // swiftlint:disable:this type_contents_order

  // MARK: - Month Cache

  /// Cache of computed shifts by month key (e.g., "2025-1")
  @ObservationIgnored var monthCache: [String: MonthCacheEntry] = [:]
  // swiftlint:disable:previous type_contents_order

  /// Maximum number of months to keep in cache (prevents unbounded memory growth)
  static let maxCacheSize = 12  // swiftlint:disable:this explicit_type_interface

  /// Background prefetch tasks keyed by month cache key and invalidation token
  /// (to avoid duplicate fetches and stale writes after invalidation).
  @ObservationIgnored var prefetchTasks: [String: Int] = [:]

  /// Per-month invalidation tokens used to discard stale background prefetch results.
  @ObservationIgnored var monthCacheInvalidationTokens: [String: Int] = [:]

  /// Tracks initial-sync transitions so the first post-sync local reload remains a full reset.
  @ObservationIgnored var hasObservedInitialSyncCompletion = false
  // swiftlint:disable:previous explicit_type_interface

  /// Memory warning observer
  @ObservationIgnored private var memoryWarningObserver: NSObjectProtocol?
  /// App lifecycle observer for foreground transitions
  @ObservationIgnored private var foregroundObserver: NSObjectProtocol?
  /// Observer for significant time changes (midnight, timezone, DST, etc.)
  @ObservationIgnored private var significantTimeObserver: NSObjectProtocol?

  // MARK: - Initialization

  init(  // swiftlint:disable:this explicit_acl function_body_length type_contents_order
    shiftsRepository: ShiftsRepository? = nil,
    eventsRepository: EventsRepository? = nil,
    jobsRepository: JobsRepository? = nil,
    settingsRepository: SettingsRepository? = nil,
    snapshotsRepository: SnapshotsRepository? = nil,
    jobPaySetupStatusService: JobPaySetupStatusService? = nil,
    payrollAdjustmentsRepository: PayrollAdjustmentsRepository? = nil,
    recurringShiftsRepository: RecurringShiftsRepository? = nil,
    monthlyPayrollReadService: MonthlyPayrollReadService? = nil,
    syncCoordinator: SyncCoordinator? = nil,
    monthContext: SharedMonthContext? = nil,
    clockSessionStore: TemporaryClockSessionStore? = nil
  ) {
    // Use provided repositories or default to shared instances
    // Using optional parameters avoids Swift 6 MainActor isolation errors
    self.shiftsRepository = shiftsRepository ?? ShiftsRepository.shared
    self.eventsRepository = eventsRepository ?? EventsRepository.shared
    self.jobsRepository = jobsRepository ?? JobsRepository.shared
    self.settingsRepository = settingsRepository ?? SettingsRepository.shared
    self.snapshotsRepository = snapshotsRepository ?? SnapshotsRepository.shared
    self.jobPaySetupStatusService = jobPaySetupStatusService ?? JobPaySetupStatusService.shared
    self.payrollAdjustmentsRepository =
      payrollAdjustmentsRepository ?? PayrollAdjustmentsRepository.shared
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
    self.clockSessionStore = clockSessionStore ?? TemporaryClockSessionStore.shared

    // Initialize tracking to current month context values
    self.lastObservedYear = self.monthContext.displayYear
    self.lastObservedMonth = self.monthContext.displayMonth
    self.hasObservedInitialSyncCompletion = AppCoordinator.shared.initialSyncComplete

    seedLayoutPreferencesFromLocalSettings()

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

    // Invalidate current-month cache when returning to foreground so time-based
    // fields (completed shifts, next shift selection, payroll status) refresh.
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willEnterForegroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.invalidateCurrentMonthCache(reason: "foreground")
      }
    }

    // Invalidate on significant wall-clock changes (e.g. midnight rollover).
    significantTimeObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.significantTimeChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.invalidateCurrentMonthCache(reason: "significant-time-change")
      }
    }
  }

  private func seedLayoutPreferencesFromLocalSettings() {  // swiftlint:disable:this type_contents_order
    guard
      let userId = AppCoordinator.shared.getCurrentUserId(),
      !userId.isEmpty,
      let localSettings = settingsRepository.getSettings(for: userId)
    else {
      return
    }

    cachedUserId = userId
    settings = localSettings
    shouldShowDashboardClockButtons = localSettings.effectiveShowDashboardClockButtons
  }

  /// Subscribe to SharedMonthContext changes to reload data when month changes
  private func setupMonthContextSubscription() {  // swiftlint:disable:this type_contents_order
    monthContextCancellable = monthContext.monthChanged
      .receive(on: DispatchQueue.main)
      .sink { [weak self] newMonth in
        guard let self else { return }  // swiftlint:disable:this conditional_returns_on_newline

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
          dashboardViewModelLogger.info("⏸️ Deferring dashboard month load while Home tab is hidden")
          return
        }

        // Trigger data reload for new month
        loadDashboardForDisplayedMonthNonBlocking()
      }
  }

  isolated deinit {  // swiftlint:disable:this type_contents_order
    // Cancel Combine subscriptions to prevent memory leaks
    monthContextCancellable?.cancel()

    // Cancel any active navigation task to prevent orphaned operations
    activeNavigationTask?.cancel()

    if let observer = memoryWarningObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    if let observer = foregroundObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    if let observer = significantTimeObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  // MARK: - Month Navigation

  /// Track active navigation task to cancel stale fetches
  @ObservationIgnored var activeNavigationTask: Task<Void, Never>?

  /// In-memory mirror of the UserDefaults-backed payroll-received override, lazily seeded
  /// per key on first read. Backing this with a tracked property (instead of reading
  /// UserDefaults directly) lets views that check it stay observed without a manual
  /// notification.
  var payrollReceivedOverrideKeys: Set<String> = []

  // MARK: - Shift Operations

  /// Whether a shift update is in progress
  var isUpdatingShift = false  // swiftlint:disable:this explicit_acl explicit_type_interface
  var isUpdatingRecurringShift = false  // swiftlint:disable:this explicit_type_interface
  var isUpdatingEvent = false  // swiftlint:disable:this explicit_type_interface
  var isDeletingEvent = false  // swiftlint:disable:this explicit_type_interface

// MARK: - Month Cache Entry

/// Cache entry for a single month's computed shifts
struct MonthCacheEntry {
  let year: Int
  let month: Int
  let shifts: [ShiftWithComputations]
  let events: [EventRow]
  let timestamp: Date
  /// Last access time for LRU eviction
  var lastAccessed: Date

  var key: String { "\(year)-\(month)" }

  /// Cache validity is managed via explicit invalidation events
  /// (sync/reload/edit, lifecycle time changes, memory pressure).
  /// Entries do not expire by fixed TTL.
  var isValid: Bool {
    true
  }

  init(
    year: Int,
    month: Int,
    shifts: [ShiftWithComputations],
    events: [EventRow],
    timestamp: Date
  ) {
    self.year = year
    self.month = month
    self.shifts = shifts
    self.events = events
    self.timestamp = timestamp
    self.lastAccessed = timestamp
  }
}
}
