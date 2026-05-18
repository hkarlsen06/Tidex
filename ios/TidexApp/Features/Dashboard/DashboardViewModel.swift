import ActivityKit
import Combine
import Foundation
import Supabase
import UIKit
import os.log

private let logger = Logger(subsystem: "com.tidex.app", category: "DashboardViewModel")

// MARK: - Notification Names

extension Notification.Name {
  /// Posted when shifts are created/modified and dashboard should refresh
  static let shiftsDidChange = Notification.Name("com.tidex.shiftsDidChange")
  /// Posted when dashboard clock button visibility changes in appearance settings.
  static let dashboardClockButtonsVisibilityDidChange = Notification.Name(
    "com.tidex.dashboardClockButtonsVisibilityDidChange")
}

// MARK: - Dashboard Data

enum DashboardFeaturedItem: Equatable {
  case shift(ShiftWithComputations)
  case event(EventRow, coveredDateISO: String)

  var shift: ShiftWithComputations? {
    guard case .shift(let shift) = self else { return nil }
    return shift
  }
}

struct DashboardFeaturedSelection: Equatable {
  let item: DashboardFeaturedItem?
  let isToday: Bool
  let isBestShift: Bool
}

enum DashboardFeaturedItemSelector {
  static func select(
    shifts: [ShiftWithComputations],
    events: [EventRow],
    isViewingCurrentMonth: Bool,
    todayISO: String = todayISO(),
    now: Date = Date()
  ) -> DashboardFeaturedSelection {
    if isViewingCurrentMonth {
      return selectCurrentMonth(shifts: shifts, events: events, todayISO: todayISO, now: now)
    }

    guard let bestShift = findBestShift(in: shifts) else {
      return DashboardFeaturedSelection(item: nil, isToday: false, isBestShift: true)
    }

    return DashboardFeaturedSelection(
      item: .shift(bestShift),
      isToday: false,
      isBestShift: true
    )
  }

  private struct ShiftCandidate {
    let shift: ShiftWithComputations
    let startDate: Date
  }

  private struct EventCandidate {
    let event: EventRow
    let coveredDateISO: String
    let sortDate: Date
  }

  private static func selectCurrentMonth(
    shifts: [ShiftWithComputations],
    events: [EventRow],
    todayISO: String,
    now: Date
  ) -> DashboardFeaturedSelection {
    let nextShift = nextUpcomingShift(in: shifts, now: now)
    let nextEvent = nextUpcomingEvent(in: events, todayISO: todayISO, now: now)

    switch (nextShift, nextEvent) {
    case (.none, .none):
      return DashboardFeaturedSelection(item: nil, isToday: false, isBestShift: false)
    case (.some(let shiftCandidate), .none):
      return DashboardFeaturedSelection(
        item: .shift(shiftCandidate.shift),
        isToday: shiftCandidate.shift.shiftDate == todayISO,
        isBestShift: false
      )
    case (.none, .some(let eventCandidate)):
      return DashboardFeaturedSelection(
        item: .event(eventCandidate.event, coveredDateISO: eventCandidate.coveredDateISO),
        isToday: eventCandidate.coveredDateISO == todayISO,
        isBestShift: false
      )
    case (.some(let shiftCandidate), .some(let eventCandidate)):
      if shouldPrioritizeShift(shiftCandidate.shift, over: eventCandidate.event) {
        return DashboardFeaturedSelection(
          item: .shift(shiftCandidate.shift),
          isToday: shiftCandidate.shift.shiftDate == todayISO,
          isBestShift: false
        )
      }

      if shiftCandidate.startDate <= eventCandidate.sortDate {
        return DashboardFeaturedSelection(
          item: .shift(shiftCandidate.shift),
          isToday: shiftCandidate.shift.shiftDate == todayISO,
          isBestShift: false
        )
      }

      return DashboardFeaturedSelection(
        item: .event(eventCandidate.event, coveredDateISO: eventCandidate.coveredDateISO),
        isToday: eventCandidate.coveredDateISO == todayISO,
        isBestShift: false
      )
    }
  }

  private static func nextUpcomingShift(
    in shifts: [ShiftWithComputations],
    now: Date
  ) -> ShiftCandidate? {
    shifts
      .compactMap { shift -> ShiftCandidate? in
        guard
          let startDate = Date.fromDateAndTime(shift.shiftDate, time: shift.startTime),
          let endDate = shiftEndDate(for: shift)
        else {
          return nil
        }

        guard endDate > now else { return nil }
        return ShiftCandidate(shift: shift, startDate: startDate)
      }
      .min { lhs, rhs in
        if lhs.startDate == rhs.startDate {
          return lhs.shift.id < rhs.shift.id
        }
        return lhs.startDate < rhs.startDate
      }
  }

  private static func nextUpcomingEvent(
    in events: [EventRow],
    todayISO: String,
    now: Date
  ) -> EventCandidate? {
    events
      .compactMap { event -> EventCandidate? in
        guard let endDate = eventEndDate(for: event), endDate > now else { return nil }
        let coveredDateISO = coveredDateISO(for: event, todayISO: todayISO) ?? event.start_date
        guard let sortDate = eventSortDate(for: event, coveredDateISO: coveredDateISO) else {
          return nil
        }

        return EventCandidate(event: event, coveredDateISO: coveredDateISO, sortDate: sortDate)
      }
      .min { lhs, rhs in
        if lhs.sortDate == rhs.sortDate {
          return lhs.event.id < rhs.event.id
        }
        return lhs.sortDate < rhs.sortDate
      }
  }

  private static func shouldPrioritizeShift(_ shift: ShiftWithComputations, over event: EventRow)
    -> Bool
  {
    event.is_all_day && eventCovers(event, dateISO: shift.shiftDate)
  }

  private static func shiftEndDate(for shift: ShiftWithComputations) -> Date? {
    guard var endDate = Date.fromDateAndTime(shift.shiftDate, time: shift.endTime) else {
      return nil
    }

    if shift.endTime <= shift.startTime {
      endDate = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
    }

    return endDate
  }

  private static func eventSortDate(for event: EventRow, coveredDateISO: String) -> Date? {
    if event.is_all_day {
      return Date.fromISODateString(coveredDateISO)
    }

    guard let startTime = event.start_time else { return nil }
    return Date.fromDateAndTime(event.start_date, time: startTime)
  }

  private static func eventEndDate(for event: EventRow) -> Date? {
    if event.is_all_day {
      guard let endDate = Date.fromISODateString(event.end_date) else { return nil }
      return Calendar.current.date(byAdding: .day, value: 1, to: endDate)
    }

    guard let endTime = event.end_time else { return nil }
    return Date.fromDateAndTime(event.end_date, time: endTime)
  }

  private static func coveredDateISO(for event: EventRow, todayISO: String) -> String? {
    if eventCovers(event, dateISO: todayISO) {
      return todayISO
    }

    return event.start_date
  }

  private static func eventCovers(_ event: EventRow, dateISO: String) -> Bool {
    guard
      let date = Date.fromISODateString(dateISO),
      let startDate = Date.fromISODateString(event.start_date),
      let endDate = Date.fromISODateString(event.end_date)
    else {
      return false
    }

    return date >= startDate && date <= endDate
  }

  private static func findBestShift(in shifts: [ShiftWithComputations]) -> ShiftWithComputations? {
    shifts.max { a, b in a.grossPay < b.grossPay }
  }
}

/// Computed dashboard data ready for display
struct DashboardData: Equatable {
  // Month Context
  let displayedYear: Int
  let displayedMonth: Int

  // Payroll Card (Previous Month)
  let payrollDate: Date
  let payrollHasPassed: Bool  // true = previous payout, false = next payout
  let previousMonthGross: Double
  let previousMonthNet: Double?  // nil if tax not enabled
  let previousMonthTax: Double?
  let previousMonthTaxEnabled: Bool
  let previousMonthHasPayrollAdjustments: Bool

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
  let currentMonthGoal: Double?  // nil when no monthly goal is configured

  // Featured Home Card
  // For current month: next upcoming shift or calendar event
  // For other months: best shift (highest earnings) in that month
  let featuredItem: DashboardFeaturedItem?
  let featuredShift: ShiftWithComputations?
  let isFeaturedItemToday: Bool
  let featuredShiftIsBestShift: Bool  // true = showing best shift, false = showing next shift

  // Metadata
  let currentMonthName: String
  let previousMonthName: String

  // User Settings
  let currency: String  // User's selected currency (e.g., "kr", "$", "€")
  let currentMonthCurrencyAggregate: JobCurrencyAggregateResolution

  /// Whether there are future shifts (main display should be projected total)
  var hasFutureShifts: Bool {
    currentMonthPlannedCount > 0
  }

  /// Whether this dashboard payload represents the real current month.
  var isViewingCurrentMonth: Bool {
    let current = Date.currentYearMonth()
    return displayedYear == current.year && displayedMonth == current.month
  }
}

struct PayrollCardVariant: Identifiable, Equatable {
  let id: String
  let title: String
  let colorHex: String?
  let badges: [PayrollCardBadge]
  let currency: String
  let payoutDate: Date
  let gross: Double
  let net: Double?
  let tax: Double?
  let taxEnabled: Bool
  let hasPayrollAdjustments: Bool
  let jobBreakdowns: [PayrollCardJobBreakdown]
}

struct PayrollCardBadge: Identifiable, Equatable {
  let id: String
  let title: String
  let colorHex: String?
}

struct PayrollCardJobBreakdown: Identifiable, Equatable {
  let id: String
  let title: String
  let colorHex: String?
  let currency: String
  let basePay: Double
  let supplementPay: Double
  let supplementBreakdowns: [PayrollSupplementBreakdown]
  let postDeductions: Double
  let postDeductionParts: [BreakDeductionPart]
  let payoutDate: Date
  let gross: Double
  let net: Double?
  let tax: Double?
  let taxEnabled: Bool
  let adjustments: [PayrollAdjustment]
}

struct PayrollSupplementBreakdown: Identifiable, Equatable {
  let fromMin: Double
  let toMin: Double
  let rate: Double
  let hours: Double
  let amount: Double

  var id: String { "\(fromMin)-\(toMin)-\(rate)" }

  var segment: SupplementSegment {
    SupplementSegment(
      fromMin: fromMin,
      toMin: toMin,
      rate: rate,
      actualHours: hours
    )
  }
}

enum PayrollAdjustmentCreationError: Error {
  case missingUser
}

// MARK: - Temporary Clock Session

struct TemporaryClockSession: Codable, Equatable, Identifiable {
  let id: String
  let userId: String
  let jobId: String?
  let startedAt: Date
  let createdAt: Date
}

enum ClockSessionRules {
  private static func isValidClockTime(_ value: String) -> Bool {
    let parts = value.split(separator: ":")
    guard
      parts.count == 2,
      parts[1].count == 2,
      let hours = Int(parts[0]),
      let minutes = Int(parts[1]),
      (0...24).contains(hours),
      (0...59).contains(minutes),
      !(hours == 24 && minutes != 0)
    else {
      return false
    }

    return true
  }

  static func timeString(from date: Date) -> String {
    date.toHourMinuteString()
  }

  static func hasExceededEndOfDayLimit(
    _ session: TemporaryClockSession,
    at referenceDate: Date
  ) -> Bool {
    let calendar = Calendar.current
    let startOfDay = calendar.startOfDay(for: session.startedAt)
    guard let cutoff = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: startOfDay)
    else {
      return false
    }
    return referenceDate > cutoff
  }

  static func isShiftOngoing(_ shift: ShiftRow, at date: Date) -> Bool {
    let calendar = Calendar(identifier: .gregorian)
    let startTime = String(shift.start_time.prefix(5))
    let endTime = String(shift.end_time.prefix(5))

    guard
      isValidClockTime(startTime),
      isValidClockTime(endTime),
      let startDate = Date.fromDateAndTime(shift.shift_date, time: startTime),
      var endDate = Date.fromDateAndTime(shift.shift_date, time: endTime)
    else {
      return false
    }

    if endDate <= startDate {
      endDate = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
    }

    return date >= startDate && date < endDate
  }
}

@MainActor
final class TemporaryClockSessionStore {
  static let shared = TemporaryClockSessionStore()

  private let defaults: UserDefaults
  private let sessionKeyPrefix = "dashboard.clock.temporary-session"
  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func activeSession(for userId: String) -> TemporaryClockSession? {
    guard let data = defaults.data(forKey: key(for: userId)) else { return nil }
    return try? decoder.decode(TemporaryClockSession.self, from: data)
  }

  func save(_ session: TemporaryClockSession) {
    guard let data = try? encoder.encode(session) else { return }
    defaults.set(data, forKey: key(for: session.userId))
  }

  func clear(for userId: String) {
    defaults.removeObject(forKey: key(for: userId))
  }

  private func key(for userId: String) -> String {
    "\(sessionKeyPrefix).\(userId)"
  }
}

@MainActor
final class ClockSessionReconciler {
  static let shared = ClockSessionReconciler()

  private let clockSessionStore: TemporaryClockSessionStore
  private let shiftsRepository: ShiftsRepository
  private var isReconciling = false

  private func notifyShiftsDidChange() {
    NotificationCenter.default.post(name: .shiftsDidChange, object: self)
  }

  init(
    clockSessionStore: TemporaryClockSessionStore? = nil,
    shiftsRepository: ShiftsRepository? = nil
  ) {
    self.clockSessionStore = clockSessionStore ?? TemporaryClockSessionStore.shared
    self.shiftsRepository = shiftsRepository ?? ShiftsRepository.shared
  }

  /// Reconcile temporary clock sessions against persisted ongoing shifts.
  /// Runs on app open/foreground so behavior is correct even when Dashboard is never shown.
  func reconcileIfNeeded(referenceDate: Date = Date()) async {
    guard !isReconciling else { return }
    isReconciling = true
    defer { isReconciling = false }

    guard let session = await AuthSessionManager.shared.getSessionIfAvailable() else { return }
    let userId = session.normalizedUserId

    guard let temporarySession = clockSessionStore.activeSession(for: userId) else { return }

    if Self.hasExceededEndOfDayLimit(temporarySession, at: referenceDate) {
      cancelTemporarySession(temporarySession)
      notifyShiftsDidChange()
      ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?
        .checkAndStartLiveActivityIfNeeded()
      return
    }

    guard
      let ongoingShift = await findPersistedOngoingShift(for: userId, at: referenceDate)
    else {
      await ensureTemporaryLiveActivity(for: temporarySession)
      return
    }

    let sessionDate = temporarySession.startedAt.toISODateString()
    let sessionStartTime = Self.timeString(from: temporarySession.startedAt)
    let ongoingStartTime = String(ongoingShift.start_time.prefix(5))

    let shouldBackfillStartTime =
      sessionDate == ongoingShift.shift_date && sessionStartTime < ongoingStartTime

    if shouldBackfillStartTime {
      do {
        _ = try await shiftsRepository.updateShift(
          id: ongoingShift.id,
          startTime: sessionStartTime
        )
      } catch {
        logger.error(
          "❌ Foreground clock handoff update failed: \(error.localizedDescription)")
        return
      }
    }

    cancelTemporarySession(temporarySession)

    notifyShiftsDidChange()
    ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?
      .checkAndStartLiveActivityIfNeeded()
  }

  private func cancelTemporarySession(_ session: TemporaryClockSession) {
    ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?.endLiveActivity(
      for: session.id)
    clockSessionStore.clear(for: session.userId)
  }

  private func ensureTemporaryLiveActivity(for session: TemporaryClockSession) async {
    let hasMatchingActivity = Activity<ShiftActivityAttributes>.activities.contains { activity in
      guard activity.attributes.shiftId == session.id else { return false }
      switch activity.activityState {
      case .ended, .dismissed:
        return false
      default:
        return true
      }
    }
    guard !hasMatchingActivity else {
      return
    }

    guard let appDelegate = (UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared
    else { return }
    await appDelegate.startTemporaryLiveActivity(
      shiftId: session.id,
      startedAt: session.startedAt
    )
  }

  private func findPersistedOngoingShift(for userId: String, at referenceDate: Date) async
    -> ShiftRow?
  {
    let calendar = Calendar.current
    let startDate = calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
    let endDate = calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
    let shifts = await shiftsRepository.getShiftsOffMain(
      for: userId,
      startDate: startDate,
      endDate: endDate
    )

    return
      shifts
      .sorted { lhs, rhs in
        if lhs.shift_date == rhs.shift_date {
          return lhs.start_time < rhs.start_time
        }
        return lhs.shift_date < rhs.shift_date
      }
      .first(where: { Self.isShiftOngoing($0, at: referenceDate) })
  }

  private static func isShiftOngoing(_ shift: ShiftRow, at date: Date) -> Bool {
    ClockSessionRules.isShiftOngoing(shift, at: date)
  }

  private static func timeString(from date: Date) -> String {
    ClockSessionRules.timeString(from: date)
  }

  private static func hasExceededEndOfDayLimit(
    _ session: TemporaryClockSession, at referenceDate: Date
  )
    -> Bool
  {
    ClockSessionRules.hasExceededEndOfDayLimit(session, at: referenceDate)
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

// MARK: - Dashboard View Model

@MainActor
final class DashboardViewModel: ObservableObject, MonthNavigable {

  // MARK: - Dependencies (Local-First Repositories)

  private let shiftsRepository: ShiftsRepository
  private let eventsRepository: EventsRepository
  private let jobsRepository: JobsRepository
  private let settingsRepository: SettingsRepository
  private let snapshotsRepository: SnapshotsRepository
  private let payrollAdjustmentsRepository: PayrollAdjustmentsRepository
  private let recurringShiftsRepository: RecurringShiftsRepository
  private let monthlyPayrollReadService: MonthlyPayrollReadService
  private let syncCoordinator: SyncCoordinator
  private let monthContext: SharedMonthContext
  private let clockSessionStore: TemporaryClockSessionStore
  nonisolated private static let gregorianCalendar = Calendar(identifier: .gregorian)

  private struct DashboardDataBuildInput {
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

  private func notifyShiftsDidChange() {
    NotificationCenter.default.post(name: .shiftsDidChange, object: self)
  }

  // MARK: - Published State

  @Published private(set) var dashboardData: DashboardData?
  @Published private(set) var isLoading = false
  @Published private(set) var error: Error?

  enum ActiveClockState: Equatable {
    case none
    case temporary(TemporaryClockSession)
    case persisted(ShiftRow)
    case computed(ShiftWithComputations)
  }

  enum ClockOutRoute: Equatable {
    case none
    case temporaryReview(TemporaryClockSession)
    case persistedEnded
  }

  enum ClockError: LocalizedError {
    case invalidRange
    case noActiveSession
    case endOfDayLimitExceeded

    var errorDescription: String? {
      switch self {
      case .invalidRange:
        return "End time must be after start time."
      case .noActiveSession:
        return "No active clock session was found."
      case .endOfDayLimitExceeded:
        return "This clock session can only be saved before midnight on the start day."
      }
    }
  }

  @Published private(set) var activeClockState: ActiveClockState = .none
  @Published private(set) var isClockActionInProgress = false
  @Published private(set) var shouldShowDashboardClockButtons = true

  var isClockInEnabled: Bool {
    if isClockActionInProgress || isUpdatingShift { return false }
    if case .none = activeClockState { return true }
    return false
  }

  var isClockOutEnabled: Bool {
    if isClockActionInProgress || isUpdatingShift { return false }
    if case .none = activeClockState { return false }
    return true
  }

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

  /// Baseline monthly goal from settings (global fallback goal).
  var baselineMonthlyGoal: Int? {
    settings?.monthly_goal.flatMap { $0 > 0 ? $0 : nil }
  }

  /// Month-specific override for the currently displayed month, if present.
  var displayedMonthOverrideGoal: Int? {
    let monthKey = UserSettings.monthKey(year: displayYear, month: displayMonth)
    return settings?.monthly_goals_by_month?[monthKey].flatMap { $0 > 0 ? $0 : nil }
  }

  func payrollCardVariants(fallback: DashboardData, defaultTitle: String) -> [PayrollCardVariant] {
    guard let userId = resolveUserIdForPayrollVariants() else {
      return [
        PayrollCardVariant(
          id: "default",
          title: defaultTitle,
          colorHex: nil,
          badges: [],
          currency: fallback.currency,
          payoutDate: fallback.payrollDate,
          gross: fallback.previousMonthGross,
          net: fallback.previousMonthNet,
          tax: fallback.previousMonthTax,
          taxEnabled: fallback.previousMonthTaxEnabled,
          hasPayrollAdjustments: fallback.previousMonthHasPayrollAdjustments,
          jobBreakdowns: []
        )
      ]
    }

    let jobs = jobsRepository.getNonDeletedJobs(for: userId)
    guard !jobs.isEmpty else {
      return [
        PayrollCardVariant(
          id: "default",
          title: defaultTitle,
          colorHex: nil,
          badges: [],
          currency: fallback.currency,
          payoutDate: fallback.payrollDate,
          gross: fallback.previousMonthGross,
          net: fallback.previousMonthNet,
          tax: fallback.previousMonthTax,
          taxEnabled: fallback.previousMonthTaxEnabled,
          hasPayrollAdjustments: fallback.previousMonthHasPayrollAdjustments,
          jobBreakdowns: []
        )
      ]
    }

    let calendar = Calendar.current
    let now = Date()
    let displayYM = (year: displayYear, month: displayMonth)
    let previousYM = Date.previousYearMonth(from: displayYM)
    let fallbackPayrollDay = settings?.effectivePayrollDay ?? 15
    let halfTaxMonth = settings?.half_tax_month
    let defaultJobId = jobs.first(where: { $0.is_default })?.id

    let sortedJobs = jobs.sorted { lhs, rhs in
      let lhsDay = lhs.payroll_day ?? fallbackPayrollDay
      let rhsDay = rhs.payroll_day ?? fallbackPayrollDay
      let lhsNext = nextUpcomingPayoutDate(from: now, payrollDay: lhsDay, calendar: calendar)
      let rhsNext = nextUpcomingPayoutDate(from: now, payrollDay: rhsDay, calendar: calendar)

      if lhsNext == rhsNext {
        if lhs.sort_order == rhs.sort_order {
          return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
        return lhs.sort_order < rhs.sort_order
      }

      return lhsNext < rhsNext
    }

    let jobVariants = sortedJobs.map { job in
      let payrollDay = job.payroll_day ?? fallbackPayrollDay
      let payoutDate = PayrollDateAdjuster.adjustPayrollDate(
        payrollDay: payrollDay,
        month: displayYM.month,
        year: displayYM.year
      )

      let jobShifts = previousMonthShifts.filter { shift in
        guard let shiftJobId = shift.shift.job_id else {
          return job.id == defaultJobId
        }
        return shiftJobId == job.id
      }

      let totals = PayrollEngine.summarizeShiftTotals(
        shifts: jobShifts,
        halfTaxMonth: halfTaxMonth,
        earningsMonth: previousYM.month,
        now: now
      )
      let jobAdjustments = previousPayrollAdjustments.filter { adjustment in
        guard let adjustmentJobId = adjustment.job_id else {
          return job.id == defaultJobId
        }
        return adjustmentJobId == job.id
      }
      let fallbackTaxSettings = payrollTaxSettings(
        from: jobShifts,
        fallbackDate: payoutDate.toISODateString(),
        jobId: job.id
      )
      let adjustmentTotals = PayrollAdjustmentCalculator.totals(
        adjustments: jobAdjustments,
        taxSettings: { adjustment in
          payrollTaxSettings(
            for: adjustment,
            fallback: fallbackTaxSettings,
            jobId: job.id,
            defaultJobId: defaultJobId
          )
        },
        halfTaxMonth: halfTaxMonth,
        payoutMonth: displayYM.month
      )
      let taxEnabled = jobShifts.contains { $0.taxEnabled } || adjustmentTotals.taxEnabled
      let shiftBasePay = jobShifts.reduce(0) { total, shift in
        total + displayedBasePay(for: shift)
      }
      let shiftSupplementPay = jobShifts.reduce(0) { total, shift in
        total + displayedSupplementPay(for: shift)
      }
      let supplementBreakdowns = payrollSupplementBreakdowns(for: jobShifts)
      let shiftPostDeductions = jobShifts.reduce(0) { total, shift in
        total + breakDeductionAmount(for: shift)
      }
      let postDeductionParts = payrollBreakDeductionParts(for: jobShifts)
      let gross = totals.gross + adjustmentTotals.gross
      let net = totals.net + adjustmentTotals.net
      let tax = taxEnabled ? gross - net : nil

      return PayrollCardVariant(
        id: job.id,
        title: job.name,
        colorHex: job.color,
        badges: [
          PayrollCardBadge(
            id: job.id,
            title: job.name,
            colorHex: job.color
          )
        ],
        currency: job.currency,
        payoutDate: payoutDate,
        gross: gross,
        net: taxEnabled ? net : nil,
        tax: tax,
        taxEnabled: taxEnabled,
        hasPayrollAdjustments: !jobAdjustments.isEmpty,
        jobBreakdowns: [
          PayrollCardJobBreakdown(
            id: job.id,
            title: job.name,
            colorHex: job.color,
            currency: job.currency,
            basePay: shiftBasePay,
            supplementPay: shiftSupplementPay,
            supplementBreakdowns: supplementBreakdowns,
            postDeductions: shiftPostDeductions,
            postDeductionParts: postDeductionParts,
            payoutDate: payoutDate,
            gross: gross,
            net: taxEnabled ? net : nil,
            tax: tax,
            taxEnabled: taxEnabled,
            adjustments: jobAdjustments
          )
        ]
      )
    }

    let payableJobVariants = jobVariants.filter { $0.gross != 0 }
    let detailBreakdowns = payableJobVariants.flatMap(\.jobBreakdowns)

    guard let nextPayoutDate = payableJobVariants.first?.payoutDate else {
      return [
        PayrollCardVariant(
          id: "default",
          title: defaultTitle,
          colorHex: nil,
          badges: [],
          currency: fallback.currency,
          payoutDate: fallback.payrollDate,
          gross: fallback.previousMonthGross,
          net: fallback.previousMonthNet,
          tax: fallback.previousMonthTax,
          taxEnabled: fallback.previousMonthTaxEnabled,
          hasPayrollAdjustments: fallback.previousMonthHasPayrollAdjustments,
          jobBreakdowns: []
        )
      ]
    }

    let nextPayoutJobs = payableJobVariants.filter {
      calendar.isDate($0.payoutDate, inSameDayAs: nextPayoutDate)
    }

    guard nextPayoutJobs.count > 1 else {
      guard let nextPayoutJob = nextPayoutJobs.first else { return [] }
      return [
        PayrollCardVariant(
          id: nextPayoutJob.id,
          title: jobs.count > 1 ? nextPayoutJob.title : defaultTitle,
          colorHex: jobs.count > 1 ? nextPayoutJob.colorHex : nil,
          badges: jobs.count > 1 ? nextPayoutJob.badges : [],
          currency: nextPayoutJob.currency,
          payoutDate: nextPayoutJob.payoutDate,
          gross: nextPayoutJob.gross,
          net: nextPayoutJob.net,
          tax: nextPayoutJob.tax,
          taxEnabled: nextPayoutJob.taxEnabled,
          hasPayrollAdjustments: nextPayoutJob.hasPayrollAdjustments,
          jobBreakdowns: detailBreakdowns
        )
      ]
    }

    let taxEnabled = nextPayoutJobs.contains { $0.taxEnabled }
    let gross = nextPayoutJobs.reduce(0) { $0 + $1.gross }
    let net = nextPayoutJobs.reduce(0) { $0 + ($1.net ?? $1.gross) }
    let tax = taxEnabled ? gross - net : nil

    return [
      PayrollCardVariant(
        id: "payout-\(nextPayoutDate.timeIntervalSince1970)",
        title: defaultTitle,
        colorHex: nil,
        badges: nextPayoutJobs.flatMap(\.badges),
        currency: nextPayoutJobs.first?.currency ?? fallback.currency,
        payoutDate: nextPayoutDate,
        gross: gross,
        net: taxEnabled ? net : nil,
        tax: tax,
        taxEnabled: taxEnabled,
        hasPayrollAdjustments: nextPayoutJobs.contains { $0.hasPayrollAdjustments },
        jobBreakdowns: detailBreakdowns
      )
    ]
  }

  func createPayrollAdjustment(_ draft: PayrollAdjustmentDraft) async throws -> PayrollAdjustment {
    guard let userId = resolveUserIdForPayrollVariants() else {
      throw PayrollAdjustmentCreationError.missingUser
    }

    let adjustment = try await payrollAdjustmentsRepository.createAdjustment(
      userId: userId,
      jobId: draft.jobId,
      amount: draft.amount,
      currency: draft.currency,
      category: draft.category,
      taxTreatment: draft.taxTreatment,
      description: draft.description,
      note: draft.note,
      earnedFromDate: draft.earnedFromDate,
      earnedToDate: draft.earnedToDate,
      payoutDate: draft.payoutDate
    )

    previousPayrollAdjustments.append(adjustment)
    await loadDashboardFromLocal(showLoadingState: false)
    return adjustment
  }

  func updatePayrollAdjustment(_ id: String, _ draft: PayrollAdjustmentDraft) async throws
    -> PayrollAdjustment
  {
    guard let userId = resolveUserIdForPayrollVariants() else {
      throw PayrollAdjustmentCreationError.missingUser
    }

    let adjustment = try await payrollAdjustmentsRepository.updateAdjustment(
      id: id,
      userId: userId,
      jobId: draft.jobId,
      amount: draft.amount,
      currency: draft.currency,
      category: draft.category,
      taxTreatment: draft.taxTreatment,
      description: draft.description,
      note: draft.note,
      earnedFromDate: draft.earnedFromDate,
      earnedToDate: draft.earnedToDate,
      payoutDate: draft.payoutDate
    )

    previousPayrollAdjustments.removeAll { $0.id == id }
    previousPayrollAdjustments.append(adjustment)
    await loadDashboardFromLocal(showLoadingState: false)
    return adjustment
  }

  func deletePayrollAdjustment(id: String) async throws {
    guard let userId = resolveUserIdForPayrollVariants() else {
      throw PayrollAdjustmentCreationError.missingUser
    }

    try await payrollAdjustmentsRepository.deleteAdjustment(id: id, userId: userId)
    previousPayrollAdjustments.removeAll { $0.id == id }
    await loadDashboardFromLocal(showLoadingState: false)
  }

  /// Resolve a stable user ID for payroll card variants while reload is in-flight.
  /// This prevents a transient fallback to single-card UI during `cachedUserId` resets.
  private func resolveUserIdForPayrollVariants() -> String? {
    if let cachedUserId, !cachedUserId.isEmpty {
      return cachedUserId
    }

    if let settingsUserId = settings?.user_id, !settingsUserId.isEmpty {
      return settingsUserId
    }

    if let coordinatorUserId = AppCoordinator.shared.getCurrentUserId(), !coordinatorUserId.isEmpty
    {
      return coordinatorUserId
    }

    return nil
  }

  private func displayedBasePay(for shift: ShiftWithComputations) -> Double {
    breakDeductionAmount(for: shift) > 0
      ? BreakDeductionBreakdown.basePay(for: shift.computed.originalWagePeriods)
      : shift.computed.basePay
  }

  private func displayedSupplementPay(for shift: ShiftWithComputations) -> Double {
    breakDeductionAmount(for: shift) > 0
      ? BreakDeductionBreakdown.supplementPay(for: shift.computed.originalWagePeriods)
      : shift.computed.supplementPay
  }

  private func breakDeductionAmount(for shift: ShiftWithComputations) -> Double {
    guard shift.computed.breakAudit.deductedHours > 0 else { return 0 }
    return BreakDeductionBreakdown.make(
      originalPeriods: shift.computed.originalWagePeriods,
      adjustedPeriods: shift.computed.wagePeriods
    )?.totalAmount ?? 0
  }

  private func payrollBreakDeductionParts(for shifts: [ShiftWithComputations])
    -> [BreakDeductionPart]
  {
    let parts = shifts.flatMap { shift -> [BreakDeductionPart] in
      guard shift.computed.breakAudit.deductedHours > 0 else { return [] }
      return BreakDeductionBreakdown.make(
        originalPeriods: shift.computed.originalWagePeriods,
        adjustedPeriods: shift.computed.wagePeriods
      )?.parts ?? []
    }

    var grouped: [String: BreakDeductionPart] = [:]

    for part in parts {
      let key: String
      switch part.kind {
      case .base:
        key = "base"
      case .supplement:
        key = "supplement-\(part.supplementSegment?.id ?? "\(part.rate ?? 0)")"
      }

      if let existing = grouped[key] {
        let hours = existing.hours + part.hours
        let amount = existing.amount + part.amount
        grouped[key] = BreakDeductionPart(
          id: key,
          kind: existing.kind,
          supplementSegment: existing.supplementSegment.map {
            SupplementSegment(
              fromMin: $0.fromMin,
              toMin: $0.toMin,
              rate: $0.rate,
              actualHours: hours
            )
          },
          hours: hours,
          rate: hours > 0 ? amount / hours : existing.rate,
          amount: amount
        )
      } else {
        grouped[key] = BreakDeductionPart(
          id: key,
          kind: part.kind,
          supplementSegment: part.supplementSegment,
          hours: part.hours,
          rate: part.rate,
          amount: part.amount
        )
      }
    }

    return grouped.values.sorted { lhs, rhs in
      if lhs.kind != rhs.kind {
        return lhs.kind == .base
      }
      return lhs.id < rhs.id
    }
  }

  private func payrollSupplementBreakdowns(for shifts: [ShiftWithComputations])
    -> [PayrollSupplementBreakdown]
  {
    let segments = shifts.flatMap { shift -> [SupplementSegment] in
      let original = shift.computed.originalWagePeriods
      let adjusted =
        shift.computed.breakAudit.deductedHours > 0
        ? original : shift.computed.wagePeriods
      var segments: [SupplementSegment] = []
      var i = 0

      while i < original.count {
        let period = original[i]
        guard period.supplementRate > 0 else {
          i += 1
          continue
        }

        let groupStart = period.fromMin
        var groupEnd = period.toMin
        let rate = period.supplementRate
        var j = i + 1

        while j < original.count && original[j].supplementRate == rate {
          groupEnd = original[j].toMin
          j += 1
        }

        var actualHours: Double = 0
        for adjustedPeriod in adjusted where adjustedPeriod.supplementRate == rate {
          let overlapStart = max(adjustedPeriod.fromMin, groupStart)
          let overlapEnd = min(adjustedPeriod.toMin, groupEnd)
          if overlapEnd > overlapStart {
            actualHours += (overlapEnd - overlapStart) / 60.0
          }
        }

        if actualHours > 0 {
          segments.append(
            SupplementSegment(
              fromMin: groupStart,
              toMin: groupEnd,
              rate: rate,
              actualHours: actualHours
            ))
        }

        i = j
      }

      return segments
    }

    let grouped = segments.reduce(
      into: [String: (fromMin: Double, toMin: Double, rate: Double, hours: Double)]()
    ) { result, segment in
      let key = segment.id
      result[key, default: (segment.fromMin, segment.toMin, segment.rate, 0)].hours +=
        segment.actualHours
    }

    return grouped.values.map { segment in
      PayrollSupplementBreakdown(
        fromMin: segment.fromMin,
        toMin: segment.toMin,
        rate: segment.rate,
        hours: segment.hours,
        amount: segment.hours * segment.rate
      )
    }
    .sorted { lhs, rhs in
      if lhs.fromMin == rhs.fromMin {
        if lhs.toMin == rhs.toMin {
          return lhs.rate < rhs.rate
        }
        return lhs.toMin < rhs.toMin
      }
      return lhs.fromMin < rhs.fromMin
    }
  }

  // MARK: - User Profile Data (for UserMenuButton)

  /// User's display name (derived from email or metadata)
  @Published private(set) var userDisplayName: String = ""
  /// User's profile picture URL
  @Published private(set) var userAvatarUrl: String?
  /// All non-deleted jobs used for dashboard workplace metadata.
  @Published private(set) var displayJobs: [Job] = []

  var shouldShowJobIndicators: Bool {
    displayJobs.count > 1
  }

  func jobForShift(_ shift: ShiftWithComputations) -> Job? {
    let defaultJobId = displayJobs.first(where: { $0.is_default })?.id
    let effectiveJobId = shift.shift.job_id ?? defaultJobId
    guard let effectiveJobId else { return nil }
    return displayJobs.first(where: { $0.id == effectiveJobId })
  }

  func jobForTemporarySession(_ session: TemporaryClockSession) -> Job? {
    let defaultJobId = displayJobs.first(where: { $0.is_default })?.id
    let effectiveJobId = session.jobId ?? defaultJobId
    guard let effectiveJobId else { return nil }
    return displayJobs.first(where: { $0.id == effectiveJobId })
  }

  // MARK: - Private State

  private var displayedMonthShifts: [ShiftWithComputations] = []
  private var displayedMonthEvents: [EventRow] = []
  private var previousMonthShifts: [ShiftWithComputations] = []
  private var previousPayrollAdjustments: [PayrollAdjustment] = []
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
  /// App lifecycle observer for foreground transitions
  private var foregroundObserver: NSObjectProtocol?
  /// Observer for significant time changes (midnight, timezone, DST, etc.)
  private var significantTimeObserver: NSObjectProtocol?

  // MARK: - Initialization

  init(
    shiftsRepository: ShiftsRepository? = nil,
    eventsRepository: EventsRepository? = nil,
    jobsRepository: JobsRepository? = nil,
    settingsRepository: SettingsRepository? = nil,
    snapshotsRepository: SnapshotsRepository? = nil,
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
    self.payrollAdjustmentsRepository =
      payrollAdjustmentsRepository ?? PayrollAdjustmentsRepository.shared
    self.recurringShiftsRepository = recurringShiftsRepository ?? RecurringShiftsRepository.shared
    self.monthlyPayrollReadService =
      monthlyPayrollReadService
      ?? MonthlyPayrollReadService(
        shiftsRepository: self.shiftsRepository,
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
    if let observer = foregroundObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    if let observer = significantTimeObserver {
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

  /// Invalidate cache entries for the real current month.
  /// Keeps historical months hot while ensuring time-dependent current-month
  /// dashboard values are recomputed on next access.
  private func invalidateCurrentMonthCache(reason: String) {
    let current = Date.currentYearMonth()
    let key = "\(current.year)-\(current.month)"
    guard monthCache.removeValue(forKey: key) != nil else { return }

    // Also allow background prefetch for this key again after invalidation.
    prefetchTasks.remove(key)
    logger.info("♻️ Invalidated current-month cache (\(reason)): \(key)")

    // If the user is viewing the invalidated month, trigger a background
    // reload so the dashboard reflects updated time-based fields immediately.
    if displayYear == current.year && displayMonth == current.month {
      loadDashboardForDisplayedMonthNonBlocking()
    }
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
      self.displayedMonthEvents = displayCache.events
      self.previousMonthShifts = previousCache.shifts
      if let userId = cachedUserId {
        self.previousPayrollAdjustments = fetchPayrollAdjustmentsForPayoutMonth(
          userId: userId,
          year: targetYear,
          month: targetMonth
        )
      }

      // Update last accessed time for LRU tracking
      displayCache.lastAccessed = Date()
      previousCache.lastAccessed = Date()
      monthCache[displayKey] = displayCache
      monthCache[previousKey] = previousCache

      if let currentSettings = settings {
        let capturedDisplay = displayCache.shifts
        let capturedDisplayEvents = displayCache.events
        let capturedPrevious = previousCache.shifts
        let capturedCurrency = currentSettings.currency ?? "kr"
        let capturedJobs = displayJobs
        let capturedAdjustments = previousPayrollAdjustments
        let capturedSnapshots = snapshots

        Task.detached(priority: .userInitiated) {
          [
            displayYM = (year: targetYear, month: targetMonth), previousYM, currentSettings,
            capturedCurrency, capturedJobs, capturedDisplay, capturedDisplayEvents,
            capturedPrevious, capturedAdjustments, capturedSnapshots
          ] in
          let data = Self.buildDashboardDataOffMain(
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
            ))
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

    // Cache miss - fetch in background while keeping the currently rendered
    // dashboard content visible (matches Shifts tab behavior).
    // This avoids a brief full-screen skeleton flash on first month change
    // after cold start or after cache expiry.
    logger.info("🔄 Cache miss for \(displayKey), fetching in background...")

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
    displayJobs = []

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

  private func loadDashboardDependencies(
    for userId: String,
    forceReload: Bool = false
  ) {
    guard forceReload || settings == nil || snapshots.isEmpty || recurringShifts.isEmpty else {
      return
    }

    let context = monthlyPayrollReadService.loadContext(for: userId)
    settings = context.settings
    snapshots = context.snapshots
    recurringShifts = context.recurringShifts
    displayJobs = context.jobs
    shouldShowDashboardClockButtons = settings?.effectiveShowDashboardClockButtons ?? true
  }

  private func fetchShiftRows(
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

  private func fetchMonthShiftRows(
    for userId: String,
    displayYM: (year: Int, month: Int),
    previousYM: (year: Int, month: Int)
  ) async -> (display: [ShiftRow], previous: [ShiftRow]) {
    let months = [
      PayrollReadMonth(year: displayYM.year, month: displayYM.month),
      PayrollReadMonth(year: previousYM.year, month: previousYM.month),
    ]
    let rowsByMonth = await monthlyPayrollReadService.loadShiftRows(
      for: userId,
      months: months
    )
    let displayRows =
      rowsByMonth[PayrollReadMonth(year: displayYM.year, month: displayYM.month)] ?? []
    let previousRows =
      rowsByMonth[PayrollReadMonth(year: previousYM.year, month: previousYM.month)] ?? []
    return (displayRows, previousRows)
  }

  private func fetchMonthEvents(
    for userId: String,
    displayYM: (year: Int, month: Int),
    previousYM: (year: Int, month: Int)
  ) async -> (display: [EventRow], previous: [EventRow]) {
    let displayStartDate = Date.firstDayOfMonthDate(year: displayYM.year, month: displayYM.month)
    let displayEndDate = Date.lastDayOfMonthDate(year: displayYM.year, month: displayYM.month)
    let previousStartDate = Date.firstDayOfMonthDate(year: previousYM.year, month: previousYM.month)
    let previousEndDate = Date.lastDayOfMonthDate(year: previousYM.year, month: previousYM.month)

    async let displayEvents = eventsRepository.getEventsOffMain(
      for: userId,
      startDate: displayStartDate,
      endDate: displayEndDate
    )
    async let previousEvents = eventsRepository.getEventsOffMain(
      for: userId,
      startDate: previousStartDate,
      endDate: previousEndDate
    )

    return await (displayEvents, previousEvents)
  }

  private func fetchPayrollAdjustmentsForPayoutMonth(
    userId: String,
    year: Int,
    month: Int
  ) -> [PayrollAdjustment] {
    let start = Date.firstDayOfMonthDate(year: year, month: month)
    let end =
      Calendar(identifier: .gregorian).date(byAdding: .month, value: 1, to: start)
      ?? Date.lastDayOfMonthDate(year: year, month: month)

    return payrollAdjustmentsRepository.getAdjustments(
      for: userId,
      payoutStart: start,
      payoutEnd: end
    )
  }

  private func payrollTaxSettings(
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

  private func payrollTaxSettings(
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

  nonisolated private static func payrollTaxSettings(
    from shifts: [ShiftWithComputations],
    fallbackDate: String,
    snapshots: [WageSnapshot],
    jobs: [Job],
    jobId: String?
  ) -> PayoutTaxSettings {
    if let firstTaxedShift = shifts.first(where: { $0.taxEnabled }) {
      return PayoutTaxSettings(
        enabled: true,
        percentage: firstTaxedShift.taxPercentage
      )
    }

    let scopedSnapshots = payrollSnapshotsForJob(jobId: jobId, snapshots: snapshots, jobs: jobs)
    let snapshot = SnapshotsService.snapshotForDate(fallbackDate, from: scopedSnapshots)
    return PayoutTaxSettings(
      enabled: snapshot?.effectiveTaxEnabled ?? false,
      percentage: snapshot?.effectiveTaxPercentage ?? 0
    )
  }

  nonisolated private static func payrollTaxSettings(
    for adjustment: PayrollAdjustment,
    fallback: PayoutTaxSettings,
    snapshots: [WageSnapshot],
    jobs: [Job],
    jobId: String?,
    defaultJobId: String?
  ) -> PayoutTaxSettings {
    let effectiveJobId = jobId ?? adjustment.job_id ?? defaultJobId
    let scopedSnapshots = payrollSnapshotsForJob(
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

  nonisolated private static func payrollSnapshotsForJob(
    jobId: String?,
    snapshots: [WageSnapshot],
    jobs: [Job]
  ) -> [WageSnapshot] {
    let snapshotsByJobId = Dictionary(grouping: snapshots, by: { $0.job_id })
    let legacyNilJobSnapshots = snapshotsByJobId[nil] ?? []

    guard let jobId else {
      return legacyNilJobSnapshots.isEmpty ? snapshots : legacyNilJobSnapshots
    }

    if let scoped = snapshotsByJobId[jobId], !scoped.isEmpty {
      return scoped
    }

    let defaultJobId = jobs.first(where: { $0.is_default })?.id
    if let defaultJobId, let defaultScoped = snapshotsByJobId[defaultJobId], !defaultScoped.isEmpty
    {
      return defaultScoped
    }

    return legacyNilJobSnapshots.isEmpty ? snapshots : legacyNilJobSnapshots
  }

  /// Prepare for reload by setting loading state synchronously
  /// Call this BEFORE starting a Task to reload, to prevent empty state flash
  /// This ensures the loading indicator shows immediately when sync completes
  func prepareForReload() {
    isLoading = true
  }

  /// Returns whether payroll has been manually marked as received for the displayed month.
  func isPayrollReceivedOverrideForDisplayedMonth(userId: String? = nil) -> Bool {
    guard let key = payrollReceivedOverrideKeyForDisplayedMonth(userId: userId) else {
      return false
    }
    return UserDefaults.standard.bool(forKey: key)
  }

  /// Marks payroll as received for the displayed month.
  /// This is idempotent and only stores `true`.
  func markPayrollReceivedForDisplayedMonth(userId: String? = nil) {
    guard let key = payrollReceivedOverrideKeyForDisplayedMonth(userId: userId) else { return }
    UserDefaults.standard.set(true, forKey: key)
    objectWillChange.send()
  }

  /// Clears the manual payroll-received override for the displayed month.
  func clearPayrollReceivedOverrideForDisplayedMonth(userId: String? = nil) {
    guard let key = payrollReceivedOverrideKeyForDisplayedMonth(userId: userId) else { return }
    UserDefaults.standard.removeObject(forKey: key)
    objectWillChange.send()
  }

  /// Save month-specific goal override for the currently displayed month.
  func saveMonthlyGoalForDisplayedMonth(_ goal: Int?) async throws {
    if cachedUserId == nil {
      cachedUserId = try await getCurrentUserId()
    }

    guard let userId = cachedUserId else {
      throw DashboardError.notAuthenticated
    }

    guard
      let updatedSettings = try await settingsRepository.saveMonthlyGoalForMonth(
        userId: userId,
        year: displayYear,
        month: displayMonth,
        goal: goal
      )
    else {
      throw DashboardError.noLocalData
    }

    settings = updatedSettings
    dashboardData = buildDashboardData()
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
    displayJobs = []
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

      displayJobs = jobsRepository.getNonDeletedJobs(for: userId)

      // Load settings from repositories
      if settings == nil {
        loadDashboardDependencies(for: userId)
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

          // Retry loading through the shared monthly payroll read path
          loadDashboardDependencies(for: userId, forceReload: true)
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

      loadDashboardDependencies(for: userId)
      logger.info("📋 Loaded snapshots: \(self.snapshots.count)")
      logger.info("📋 Loaded recurring: \(self.recurringShifts.count)")

      // Calculate date ranges for displayed month
      let displayYM = (year: displayYear, month: displayMonth)
      let previousYM = Date.previousYearMonth(from: displayYM)

      // Load shifts through the repository/DAL path (after settings retry to avoid stale empty reads)
      let fetchedShiftRows = await fetchMonthShiftRows(
        for: userId,
        displayYM: displayYM,
        previousYM: previousYM
      )
      let fetchedEvents = await fetchMonthEvents(
        for: userId,
        displayYM: displayYM,
        previousYM: previousYM
      )
      let displayShifts = fetchedShiftRows.display
      logger.info(
        "📋 Loaded shifts for \(displayYM.year)-\(displayYM.month): \(displayShifts.count)")
      let fetchedPreviousShifts = fetchedShiftRows.previous
      let displayEvents = fetchedEvents.display
      let previousEvents = fetchedEvents.previous
      let fetchedPayrollAdjustments = fetchPayrollAdjustmentsForPayoutMonth(
        userId: userId,
        year: displayYM.year,
        month: displayYM.month
      )

      let capturedRecurring = recurringShifts
      let capturedSnapshots = snapshots
      let capturedCurrency = currentSettings.currency ?? "kr"
      let capturedJobs = displayJobs
      let capturedPayrollAdjustments = fetchedPayrollAdjustments

      let result = await Task.detached(priority: .userInitiated) {
        let displayComputed = PayrollEngine.computeShiftsForMonth(
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

        let previousComputed = PayrollEngine.computeShiftsForMonth(
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

        let dashboardData = Self.buildDashboardDataOffMain(
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
          ))

        return (
          display: displayComputed,
          displayEvents: displayEvents,
          previous: previousComputed,
          previousEvents: previousEvents,
          dashboardData: dashboardData
        )
      }.value

      self.displayedMonthShifts = result.display
      self.displayedMonthEvents = result.displayEvents
      self.previousMonthShifts = result.previous
      self.previousPayrollAdjustments = fetchedPayrollAdjustments

      // Cache the computed results
      let displayKey = "\(displayYM.year)-\(displayYM.month)"
      let previousKey = "\(previousYM.year)-\(previousYM.month)"
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

      // Evict old cache entries if over limit
      evictCacheIfNeeded()

      // Build dashboard data and clear loading state
      // Always clear isLoading on success since we have data to show
      self.dashboardData = result.dashboardData
      self.maybeTriggerCelebration()
      await refreshClockActiveState(referenceDate: Date())
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

      displayJobs = jobsRepository.getNonDeletedJobs(for: userId)

      // Load settings and cached payroll inputs through repositories if needed
      if settings == nil || snapshots.isEmpty || recurringShifts.isEmpty {
        loadDashboardDependencies(for: userId)
        updateUserAvatarFromSettings()
      }

      // Calculate date ranges for displayed month
      let displayYM = (year: displayYear, month: displayMonth)
      let previousYM = Date.previousYearMonth(from: displayYM)

      // Load shifts through the repository/DAL path
      let fetchedShiftRows = await fetchMonthShiftRows(
        for: userId,
        displayYM: displayYM,
        previousYM: previousYM
      )
      let fetchedEvents = await fetchMonthEvents(
        for: userId,
        displayYM: displayYM,
        previousYM: previousYM
      )
      let displayShifts = fetchedShiftRows.display
      let fetchedPreviousShifts = fetchedShiftRows.previous
      let displayEvents = fetchedEvents.display
      let previousEvents = fetchedEvents.previous
      let fetchedPayrollAdjustments = fetchPayrollAdjustmentsForPayoutMonth(
        userId: userId,
        year: displayYM.year,
        month: displayYM.month
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
      let capturedJobs = displayJobs
      let capturedPayrollAdjustments = fetchedPayrollAdjustments

      let result = await Task.detached(priority: .userInitiated) {
        let displayComputed = PayrollEngine.computeShiftsForMonth(
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

        let previousComputed = PayrollEngine.computeShiftsForMonth(
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

        let dashboardData = Self.buildDashboardDataOffMain(
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
          ))

        return (
          display: displayComputed,
          displayEvents: displayEvents,
          previous: previousComputed,
          previousEvents: previousEvents,
          dashboardData: dashboardData
        )
      }.value

      self.displayedMonthShifts = result.display
      self.displayedMonthEvents = result.displayEvents
      self.previousMonthShifts = result.previous
      self.previousPayrollAdjustments = fetchedPayrollAdjustments

      // Cache the computed results
      let displayKey = "\(displayYM.year)-\(displayYM.month)"
      let previousKey = "\(previousYM.year)-\(previousYM.month)"
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

      // Evict old cache entries if over limit
      evictCacheIfNeeded()

      // Build dashboard data and clear loading state
      self.dashboardData = result.dashboardData
      self.maybeTriggerCelebration()
      await refreshClockActiveState(referenceDate: Date())
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

      // Read from the repository/DAL path off the main actor
      async let fetchedShifts = shiftsRepository.getShiftsOffMain(
        for: userId,
        startDate: startDate,
        endDate: endDate
      )
      async let fetchedEvents = eventsRepository.getEventsOffMain(
        for: userId,
        startDate: startDate,
        endDate: endDate
      )

      // Compute shifts with payroll
      guard let settings = self.settings else {
        prefetchTasks.remove(key)
        return
      }

      let monthShifts = await fetchedShifts
      let monthEvents = await fetchedEvents
      let capturedRecurring = recurringShifts
      let capturedSnapshots = snapshots
      let capturedJobs = displayJobs

      let computedShifts = await Task.detached(priority: .utility) {
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

      // Store in cache
      let entry = MonthCacheEntry(
        year: year,
        month: month,
        shifts: computedShifts,
        events: monthEvents,
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
    let session: Session
    do {
      // Use AuthSessionManager to prevent concurrent refresh race conditions
      session = try await AuthSessionManager.shared.getSession()
    } catch {
      guard AuthSessionManager.shared.isTransientSessionResolutionError(error) else {
        throw error
      }

      if let offlineUserId = AuthSessionManager.shared.offlineUserIdFallback() {
        // Preserve usable dashboard header state during cold offline launches.
        if self.userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          self.userDisplayName = "User"
        }
        logger.info("Using offline user id fallback")
        return offlineUserId
      }

      throw error
    }
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
    let resolvedUserId = cachedUserId ?? resolveUserIdForPayrollVariants()
    guard let userId = resolvedUserId, !userId.isEmpty else { return }
    cachedUserId = userId
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
    let previousAdjustments = previousPayrollAdjustments

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
    let fallbackTaxSettings = payrollTaxSettings(
      from: previousMonthShifts,
      fallbackDate: payrollDate.toISODateString(),
      jobId: nil
    )
    let adjustmentTotals = PayrollAdjustmentCalculator.totals(
      adjustments: previousAdjustments,
      taxSettings: { adjustment in
        payrollTaxSettings(
          for: adjustment,
          fallback: fallbackTaxSettings,
          jobId: adjustment.job_id,
          defaultJobId: displayJobs.first(where: { $0.is_default })?.id
        )
      },
      halfTaxMonth: halfTaxMonth,
      payoutMonth: displayYM.month
    )
    let prevTaxEnabled =
      previousMonthShifts.contains { $0.taxEnabled } || adjustmentTotals.taxEnabled
    let previousGross = prevTotals.gross + adjustmentTotals.gross
    let previousNet = prevTotals.net + adjustmentTotals.net
    let prevTax: Double? = prevTaxEnabled ? previousGross - previousNet : nil

    let fallbackCurrency = settings?.currency ?? "kr"
    let currentMonthAggregate = JobCurrencyAggregateResolver.resolve(
      shifts: displayedMonthShifts,
      jobs: displayJobs,
      fallbackCurrency: fallbackCurrency,
      referenceDate: now
    )
    let primaryMonthShifts = JobCurrencyAggregateResolver.shifts(
      matching: currentMonthAggregate.primary,
      in: displayedMonthShifts,
      jobs: displayJobs,
      fallbackCurrency: fallbackCurrency
    )

    // Displayed month totals (primary currency bucket only).
    let displayTotals = PayrollEngine.summarizeShiftTotals(
      shifts: primaryMonthShifts,
      halfTaxMonth: halfTaxMonth,
      earningsMonth: displayYM.month,
      now: now
    )
    let displayTaxEnabled = currentMonthAggregate.primary.hasTaxEnabled
    let monthlyGoal = settings?.effectiveMonthlyGoal(year: displayYM.year, month: displayYM.month)
      .flatMap { $0 > 0 ? Double($0) : nil }

    let completedShiftsCount = currentMonthAggregate.primary.completedShiftCount
    let plannedShiftsCount = currentMonthAggregate.primary.plannedShiftCount

    // Percentage change vs previous month (same currency scope as the primary bucket)
    let previousComparisonGross: Double
    if currentMonthAggregate.hasMixedCurrency {
      let previousPrimaryShifts = JobCurrencyAggregateResolver.shifts(
        matching: currentMonthAggregate.primary,
        in: previousMonthShifts,
        jobs: displayJobs,
        fallbackCurrency: fallbackCurrency
      )
      let previousPrimaryAdjustments = Self.payrollAdjustments(
        previousAdjustments,
        matching: currentMonthAggregate.primary,
        jobs: displayJobs,
        fallbackCurrency: fallbackCurrency
      )
      let previousPrimaryAdjustmentTotals = PayrollAdjustmentCalculator.totals(
        adjustments: previousPrimaryAdjustments,
        taxSettings: { adjustment in
          payrollTaxSettings(
            for: adjustment,
            fallback: fallbackTaxSettings,
            jobId: adjustment.job_id,
            defaultJobId: displayJobs.first(where: { $0.is_default })?.id
          )
        },
        halfTaxMonth: halfTaxMonth,
        payoutMonth: displayYM.month
      )
      previousComparisonGross =
        PayrollEngine.summarizeShiftTotals(
          shifts: previousPrimaryShifts,
          halfTaxMonth: halfTaxMonth,
          earningsMonth: previousYM.month,
          now: now
        ).gross + previousPrimaryAdjustmentTotals.gross
    } else {
      previousComparisonGross = previousGross
    }

    let percentChange: Double? =
      previousComparisonGross > 0
      ? ((displayTotals.gross - previousComparisonGross) / previousComparisonGross) * 100
      : nil

    // Featured shift logic:
    // - Current month: show next upcoming shift
    // - Other months: show best shift (highest earnings)
    let current = Date.currentYearMonth()
    let isViewingCurrentMonth = displayYM.year == current.year && displayYM.month == current.month

    let featuredSelection = DashboardFeaturedItemSelector.select(
      shifts: displayedMonthShifts,
      events: displayedMonthEvents,
      isViewingCurrentMonth: isViewingCurrentMonth,
      todayISO: today,
      now: now
    )

    // Month names for display
    let displayMonthName = monthName(year: displayYM.year, month: displayYM.month)
    let previousMonthName = monthName(year: previousYM.year, month: previousYM.month)

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
      currentMonthGoal: monthlyGoal,
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
  nonisolated private static func buildDashboardDataOffMain(
    _ input: DashboardDataBuildInput
  ) -> DashboardData {
    let displayedMonthShifts = input.displayedMonthShifts
    let displayedMonthEvents = input.displayedMonthEvents
    let previousMonthShifts = input.previousMonthShifts
    let previousPayrollAdjustments = input.previousPayrollAdjustments
    let snapshots = input.snapshots
    let settings = input.settings
    let displayYM = input.displayYM
    let previousYM = input.previousYM
    let currency = input.currency
    let jobs = input.jobs

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
    let fallbackTaxSettings = payrollTaxSettings(
      from: previousMonthShifts,
      fallbackDate: payrollDate.toISODateString(),
      snapshots: snapshots,
      jobs: jobs,
      jobId: nil
    )
    let adjustmentTotals = PayrollAdjustmentCalculator.totals(
      adjustments: previousPayrollAdjustments,
      taxSettings: { adjustment in
        payrollTaxSettings(
          for: adjustment,
          fallback: fallbackTaxSettings,
          snapshots: snapshots,
          jobs: jobs,
          jobId: adjustment.job_id,
          defaultJobId: jobs.first(where: { $0.is_default })?.id
        )
      },
      halfTaxMonth: halfTaxMonth,
      payoutMonth: displayYM.month
    )
    let prevTaxEnabled =
      previousMonthShifts.contains { $0.taxEnabled } || adjustmentTotals.taxEnabled
    let previousGross = prevTotals.gross + adjustmentTotals.gross
    let previousNet = prevTotals.net + adjustmentTotals.net
    let prevTax: Double? = prevTaxEnabled ? previousGross - previousNet : nil

    let currentMonthAggregate = JobCurrencyAggregateResolver.resolve(
      shifts: displayedMonthShifts,
      jobs: jobs,
      fallbackCurrency: currency,
      referenceDate: now
    )
    let primaryMonthShifts = JobCurrencyAggregateResolver.shifts(
      matching: currentMonthAggregate.primary,
      in: displayedMonthShifts,
      jobs: jobs,
      fallbackCurrency: currency
    )

    let displayTotals = PayrollEngine.summarizeShiftTotals(
      shifts: primaryMonthShifts,
      halfTaxMonth: halfTaxMonth,
      earningsMonth: displayYM.month,
      now: now
    )
    let displayTaxEnabled = currentMonthAggregate.primary.hasTaxEnabled
    let monthlyGoal = settings.effectiveMonthlyGoal(year: displayYM.year, month: displayYM.month)
      .flatMap { $0 > 0 ? Double($0) : nil }

    let completedShiftsCount = currentMonthAggregate.primary.completedShiftCount
    let plannedShiftsCount = currentMonthAggregate.primary.plannedShiftCount

    let previousComparisonGross: Double
    if currentMonthAggregate.hasMixedCurrency {
      let previousPrimaryShifts = JobCurrencyAggregateResolver.shifts(
        matching: currentMonthAggregate.primary,
        in: previousMonthShifts,
        jobs: jobs,
        fallbackCurrency: currency
      )
      let previousPrimaryAdjustments = payrollAdjustments(
        previousPayrollAdjustments,
        matching: currentMonthAggregate.primary,
        jobs: jobs,
        fallbackCurrency: currency
      )
      let previousPrimaryAdjustmentTotals = PayrollAdjustmentCalculator.totals(
        adjustments: previousPrimaryAdjustments,
        taxSettings: { adjustment in
          payrollTaxSettings(
            for: adjustment,
            fallback: fallbackTaxSettings,
            snapshots: snapshots,
            jobs: jobs,
            jobId: adjustment.job_id,
            defaultJobId: jobs.first(where: { $0.is_default })?.id
          )
        },
        halfTaxMonth: halfTaxMonth,
        payoutMonth: displayYM.month
      )
      previousComparisonGross =
        PayrollEngine.summarizeShiftTotals(
          shifts: previousPrimaryShifts,
          halfTaxMonth: halfTaxMonth,
          earningsMonth: previousYM.month,
          now: now
        ).gross + previousPrimaryAdjustmentTotals.gross
    } else {
      previousComparisonGross = previousGross
    }

    let percentChange: Double? =
      previousComparisonGross > 0
      ? ((displayTotals.gross - previousComparisonGross) / previousComparisonGross) * 100
      : nil

    let current = Date.currentYearMonth()
    let isViewingCurrentMonth = displayYM.year == current.year && displayYM.month == current.month

    let featuredSelection = DashboardFeaturedItemSelector.select(
      shifts: displayedMonthShifts,
      events: displayedMonthEvents,
      isViewingCurrentMonth: isViewingCurrentMonth,
      todayISO: today,
      now: now
    )

    let displayMonthName = monthNameStatic(year: displayYM.year, month: displayYM.month)
    let previousMonthName = monthNameStatic(year: previousYM.year, month: previousYM.month)

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
      currentMonthGoal: monthlyGoal,
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

  nonisolated private static func monthNameStatic(year: Int, month: Int) -> String {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = 1
    guard let date = gregorianCalendar.date(from: components) else { return "" }
    return FormatterCache.monthNameFormatter(locale: .appLocale).string(from: date)
  }

  nonisolated private static func payrollAdjustments(
    _ adjustments: [PayrollAdjustment],
    matching entry: JobCurrencyAggregateEntry,
    jobs: [Job],
    fallbackCurrency: String
  ) -> [PayrollAdjustment] {
    let activeJobs = jobs.filter { $0.deleted_at == nil && $0.archived_at == nil }
    let defaultJobId =
      activeJobs.first(where: { $0.is_default })?.id
      ?? activeJobs.first?.id
      ?? jobs.first(where: { $0.is_default })?.id
      ?? jobs.first?.id
    let jobsById = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) })

    return adjustments.filter { adjustment in
      let effectiveJobId = adjustment.job_id ?? defaultJobId
      let jobCurrency =
        effectiveJobId.flatMap { jobId in
          jobsById[jobId]?.currency
        } ?? fallbackCurrency

      return effectiveJobId == entry.jobId && jobCurrency == entry.currency
    }
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
  private var isUpdatingEvent = false
  private var isDeletingEvent = false

  // MARK: - Clock Operations

  func refreshClockState() async {
    await refreshClockActiveState(referenceDate: Date())
    maybeTriggerCelebration()
  }

  func refreshAppearanceSettingsFromLocal() async {
    guard let userId = await ensureCachedUserId() else { return }
    guard let latestSettings = settingsRepository.getSettings(for: userId) else { return }
    settings = latestSettings
    shouldShowDashboardClockButtons = latestSettings.effectiveShowDashboardClockButtons
  }

  func applyDashboardClockButtonsVisibility(_ isVisible: Bool) {
    shouldShowDashboardClockButtons = isVisible
  }

  func temporaryFeaturedShift(
    from session: TemporaryClockSession,
    at referenceDate: Date = Date()
  ) -> ShiftWithComputations {
    let alignedStart = Self.minuteAligned(session.startedAt)
    let alignedReference = max(Self.minuteAligned(referenceDate), alignedStart)
    let shiftDate = alignedStart.toISODateString()
    let startTime = Self.timeString(from: alignedStart)
    let endTime = Self.timeString(from: alignedReference)
    let shift = ShiftRow(
      id: session.id,
      user_id: session.userId,
      job_id: session.jobId,
      shift_date: shiftDate,
      start_time: startTime,
      end_time: endTime,
      custom_supplements: nil
    )

    let snapshot = snapshotsRepository.snapshotForDate(
      shiftDate,
      userId: session.userId,
      jobId: session.jobId
    )

    let computed: ShiftComputed
    if startTime == endTime {
      // HH:mm precision can produce equal start/end in the first minute; keep preview at zero
      // until at least one minute has elapsed to avoid accidental cross-midnight interpretation.
      computed = Self.zeroShiftComputed(id: session.id)
    } else {
      computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)
    }

    return ShiftWithComputations(
      shift: shift,
      computed: computed,
      taxEnabled: snapshot?.effectiveTaxEnabled ?? false,
      taxPercentage: snapshot?.effectiveTaxPercentage ?? 0
    )
  }

  func liveFeaturedShiftWhileOngoing(
    from shift: ShiftWithComputations,
    at referenceDate: Date = Date()
  ) -> ShiftWithComputations {
    let alignedReference = Self.minuteAligned(referenceDate)
    let endTime = Self.timeString(from: alignedReference)
    let reconstructedShift = ShiftRow(
      id: shift.id,
      user_id: shift.shift.user_id,
      job_id: shift.shift.job_id,
      shift_date: shift.shiftDate,
      start_time: shift.startTime,
      end_time: endTime,
      custom_supplements: shift.shift.custom_supplements
    )

    let snapshot: WageSnapshot?
    if let snapshotUserId = shift.shift.user_id ?? cachedUserId {
      snapshot = snapshotsRepository.snapshotForDate(
        shift.shiftDate,
        userId: snapshotUserId,
        jobId: shift.shift.job_id
      )
    } else {
      snapshot = nil
    }

    let computed: ShiftComputed
    if shift.startTime == endTime {
      computed = Self.zeroShiftComputed(id: shift.id)
    } else {
      computed = PayrollCalculator.computeShift(reconstructedShift, snapshot: snapshot)
    }

    return ShiftWithComputations(
      shift: reconstructedShift,
      computed: computed,
      taxEnabled: snapshot?.effectiveTaxEnabled ?? shift.taxEnabled,
      taxPercentage: snapshot?.effectiveTaxPercentage ?? shift.taxPercentage
    )
  }

  func clockIn(jobId: String? = nil, at now: Date = Date()) async {
    print("[Clock] Clock in requested")
    guard !isClockActionInProgress else {
      print("[Clock] Clock in skipped: action already in progress")
      return
    }
    await refreshClockActiveState(referenceDate: now)

    guard case .none = activeClockState else {
      let stateDescription: String = {
        switch activeClockState {
        case .none:
          return "none"
        case .temporary(let session):
          return "temporary(\(session.id))"
        case .persisted(let shift):
          return "persisted(\(shift.id))"
        case .computed(let shift):
          return "computed(\(shift.id))"
        }
      }()
      print("[Clock] Clock in skipped: active state is \(stateDescription)")
      // Self-heal: if an active local clock state exists but its Live Activity is missing,
      // reconciling can recreate the temporary activity.
      await ClockSessionReconciler.shared.reconcileIfNeeded(referenceDate: now)
      return
    }

    guard let userId = await ensureCachedUserId() else {
      logger.error("❌ Clock in aborted: unable to resolve user ID")
      print("[Clock] Clock in aborted: unable to resolve user ID")
      return
    }
    let resolvedJobId = jobId ?? defaultJobId(for: userId)

    let alignedStart = Self.minuteAligned(now)
    let session = TemporaryClockSession(
      id: UUID().lowercasedString,
      userId: userId,
      jobId: resolvedJobId,
      startedAt: alignedStart,
      createdAt: now
    )
    clockSessionStore.save(session)
    activeClockState = .temporary(session)

    let currency = settings?.currency ?? "kr"
    guard let appDelegate = (UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared
    else {
      logger.error("❌ Clock in aborted: AppDelegate unavailable")
      print("[Clock] Clock in aborted: AppDelegate unavailable")
      return
    }

    await appDelegate.startTemporaryLiveActivity(
      shiftId: session.id,
      startedAt: session.startedAt,
      currencySymbol: currency
    )
  }

  func routeClockOut(at now: Date = Date()) async -> ClockOutRoute {
    guard !isClockActionInProgress else { return .none }
    await refreshClockActiveState(referenceDate: now)

    switch activeClockState {
    case .none:
      return .none
    case .temporary(let session):
      return .temporaryReview(session)
    case .persisted(let ongoingShift):
      isClockActionInProgress = true
      defer { isClockActionInProgress = false }
      await endShiftNow(ongoingShift, at: now)
      await refreshClockActiveState(referenceDate: Date())
      return .persistedEnded
    case .computed(let ongoingShift):
      isClockActionInProgress = true
      defer { isClockActionInProgress = false }
      await endShiftNow(ongoingShift, at: now)
      await refreshClockActiveState(referenceDate: Date())
      return .persistedEnded
    }
  }

  func commitTemporaryClockOut(start: Date, end: Date, jobId: String? = nil) async throws {
    guard end > start else { throw ClockError.invalidRange }
    guard !isClockActionInProgress else { return }

    let session: TemporaryClockSession
    if case .temporary(let activeSession) = activeClockState {
      session = activeSession
    } else {
      guard
        let userId = await ensureCachedUserId(),
        let storedSession = clockSessionStore.activeSession(for: userId)
      else {
        throw ClockError.noActiveSession
      }
      activeClockState = .temporary(storedSession)
      session = storedSession
    }

    if hasExceededEndOfDayLimit(session, at: Date())
      || hasExceededEndOfDayLimit(session, at: end)
    {
      throw ClockError.endOfDayLimitExceeded
    }

    isClockActionInProgress = true
    defer { isClockActionInProgress = false }

    let resolvedJobId = jobId ?? session.jobId ?? defaultJobId(for: session.userId)
    let shiftDate = Calendar.current.startOfDay(for: start)
    _ = try await shiftsRepository.createShift(
      shiftId: session.id,
      userId: session.userId,
      jobId: resolvedJobId,
      shiftDate: shiftDate,
      startTime: Self.timeString(from: start),
      endTime: Self.timeString(from: end),
      customSupplements: nil
    )

    cancelTemporarySession(session)

    await reloadFromLocal()
    notifyShiftsDidChange()
    await refreshClockActiveState(referenceDate: Date())
  }

  func discardTemporaryClockSession() async {
    guard !isClockActionInProgress else { return }

    await refreshClockActiveState(referenceDate: Date())
    guard case .temporary(let session) = activeClockState else { return }

    cancelTemporarySession(session)
    notifyShiftsDidChange()
    await refreshClockActiveState(referenceDate: Date())
  }

  func clockSelectableJobs() async -> [Job] {
    if !displayJobs.isEmpty {
      return sortClockJobs(displayJobs)
    }

    guard let userId = await ensureCachedUserId() else { return [] }
    displayJobs = jobsRepository.getNonDeletedJobs(for: userId)
    return sortClockJobs(displayJobs)
  }

  func clockSelectableJobsSnapshot() -> [Job] {
    sortClockJobs(displayJobs)
  }

  func preloadClockSelectableJobs() async {
    _ = await clockSelectableJobs()
  }

  func preferredClockJobId(for session: TemporaryClockSession) -> String? {
    let selectableJobs = sortClockJobs(displayJobs)
    let defaultJobId = selectableJobs.first(where: { $0.is_default })?.id
    return session.jobId ?? defaultJobId ?? selectableJobs.first?.id
  }

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

  func getDisplayedShift(id: String) -> ShiftWithComputations? {
    displayedMonthShifts.first(where: { $0.id == id })
  }

  // MARK: - Event Operations

  func updateEvent(_ editResult: EventEditResult) async throws {
    guard !isUpdatingEvent else { return }

    isUpdatingEvent = true
    defer { isUpdatingEvent = false }

    guard
      let startDate = Date.fromISODateString(editResult.startDate),
      let endDate = Date.fromISODateString(editResult.endDate)
    else {
      throw ShiftsError.invalidEventDateRange
    }

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
      throw ShiftsError.eventNotFound
    }

    await reloadFromLocal()
    notifyShiftsDidChange()
  }

  func deleteEvent(_ event: EventRow) async throws {
    guard !isDeletingEvent else { return }

    isDeletingEvent = true
    defer { isDeletingEvent = false }

    try await eventsRepository.deleteEvent(id: event.id)
    await reloadFromLocal()
    notifyShiftsDidChange()
  }

  /// End an active shift immediately using the current local device time.
  /// Uses the existing update pipeline so sync/reload behavior stays consistent.
  /// - Parameters:
  ///   - shift: The shift to end now
  ///   - now: Optional reference time for testing
  func endShiftNow(_ shift: ShiftWithComputations, at now: Date = Date()) async {
    guard !isUpdatingShift else { return }

    ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?.endLiveActivity(
      for: shift.id)

    let editResult = ShiftEditResult(
      shiftId: shift.id,
      shiftDate: shift.shiftDate,
      startTime: String(shift.startTime.prefix(5)),
      endTime: Self.timeString(from: now),
      isVirtualShiftConversion: shift.isVirtual,
      recurringId: shift.shift.recurring_id,
      originalDate: shift.shiftDate,
      customSupplements: nil
    )

    await updateShift(editResult)
  }

  /// End a persisted (non-virtual) shift immediately.
  /// This is used by dashboard clock actions when an ongoing normal shift exists.
  func endShiftNow(_ shift: ShiftRow, at now: Date = Date()) async {
    guard !isUpdatingShift else { return }

    ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?.endLiveActivity(
      for: shift.id)

    let editResult = ShiftEditResult(
      shiftId: shift.id,
      shiftDate: shift.shift_date,
      startTime: String(shift.start_time.prefix(5)),
      endTime: Self.timeString(from: now),
      isVirtualShiftConversion: false,
      recurringId: nil,
      originalDate: shift.shift_date,
      customSupplements: nil
    )

    await updateShift(editResult)
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

      let currentShift = displayedMonthShifts.first(where: { $0.id == editResult.shiftId })?.shift
      let hasTimeOrDateChanges =
        editResult.shiftDate != currentShift?.shift_date
        || editResult.startTime != currentShift.map { String($0.start_time.prefix(5)) }
        || editResult.endTime != currentShift.map { String($0.end_time.prefix(5)) }
      let resolvedNote = editResult.noteWasEdited ? editResult.note : currentShift?.note

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
          logger.info("✅ Updated recurring note for \(editResult.originalDate)")
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
          logger.info("✅ Added exclusion for \(editResult.originalDate)")

          let sourceJobId =
            displayedMonthShifts.first(where: { $0.id == editResult.shiftId })?.shift.job_id
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
          logger.info("✅ Created new shift on \(editResult.shiftDate)")

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

  func updateShiftPause(_ editResult: ShiftPauseEditResult) async {
    guard !isUpdatingShift else { return }

    isUpdatingShift = true
    defer { isUpdatingShift = false }

    logger.info("⏸️ Updating shift pause windows")

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
          logger.error("Recurring shift not found for pause update: \(recurringId)")
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
      notifyShiftsDidChange()
    } catch {
      logger.error("❌ Failed to update shift pause windows: \(error.localizedDescription)")
    }
  }

  private func ensureCachedUserId() async -> String? {
    if let cachedUserId, !cachedUserId.isEmpty {
      return cachedUserId
    }

    // Use session-derived user ID for clock actions to avoid stale settings/coordinator
    // values during reload/account-context transitions.
    cachedUserId = try? await getCurrentUserId()
    return cachedUserId
  }

  private func defaultJobId(for userId: String) -> String? {
    if displayJobs.isEmpty {
      displayJobs = jobsRepository.getNonDeletedJobs(for: userId)
    }
    let activeJobs = displayJobs.filter { $0.archived_at == nil && $0.deleted_at == nil }
    return activeJobs.first(where: { $0.is_default })?.id ?? activeJobs.first?.id
  }

  private func sortClockJobs(_ jobs: [Job]) -> [Job] {
    let selectableJobs = jobs.filter { $0.archived_at == nil && $0.deleted_at == nil }
    return selectableJobs.sorted { lhs, rhs in
      if lhs.is_default != rhs.is_default {
        return lhs.is_default && !rhs.is_default
      }
      if lhs.sort_order != rhs.sort_order {
        return lhs.sort_order < rhs.sort_order
      }
      return lhs.name.localizedCompare(rhs.name) == .orderedAscending
    }
  }

  private func refreshClockActiveState(referenceDate: Date) async {
    await ClockSessionReconciler.shared.reconcileIfNeeded(referenceDate: referenceDate)

    guard let userId = await ensureCachedUserId() else {
      activeClockState = .none
      return
    }

    if let session = clockSessionStore.activeSession(for: userId) {
      if hasExceededEndOfDayLimit(session, at: referenceDate) {
        cancelTemporarySession(session)
      } else {
        activeClockState = .temporary(session)
        return
      }
    }

    if let ongoingShift = await findPersistedOngoingShift(for: userId, at: referenceDate) {
      activeClockState = .persisted(ongoingShift)
      return
    }

    if let ongoingShift = findComputedOngoingShift(at: referenceDate) {
      activeClockState = .computed(ongoingShift)
      return
    }

    activeClockState = .none
  }

  private func cancelTemporarySession(_ session: TemporaryClockSession) {
    ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?.endLiveActivity(
      for: session.id)
    clockSessionStore.clear(for: session.userId)
  }

  private func hasExceededEndOfDayLimit(_ session: TemporaryClockSession, at referenceDate: Date)
    -> Bool
  {
    ClockSessionRules.hasExceededEndOfDayLimit(session, at: referenceDate)
  }

  private func findPersistedOngoingShift(for userId: String, at referenceDate: Date) async
    -> ShiftRow?
  {
    let calendar = Calendar.current
    let startDate = calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
    let endDate = calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
    let shifts = await shiftsRepository.getShiftsOffMain(
      for: userId,
      startDate: startDate,
      endDate: endDate
    )

    return
      shifts
      .sorted { lhs, rhs in
        if lhs.shift_date == rhs.shift_date {
          return lhs.start_time < rhs.start_time
        }
        return lhs.shift_date < rhs.shift_date
      }
      .first(where: { Self.isShiftOngoing($0, at: referenceDate) })
  }

  /// Fallback for ongoing recurring/virtual shifts that are visible in dashboard data
  /// but not persisted in the local shifts table yet.
  private func findComputedOngoingShift(at referenceDate: Date) -> ShiftWithComputations? {
    var best: ShiftWithComputations?

    for shift in displayedMonthShifts where Self.isShiftOngoing(shift.shift, at: referenceDate) {
      guard let currentBest = best else {
        best = shift
        continue
      }

      if shift.shiftDate < currentBest.shiftDate
        || (shift.shiftDate == currentBest.shiftDate && shift.startTime < currentBest.startTime)
      {
        best = shift
      }
    }

    return best
  }

  // MARK: - Payroll Override Helpers

  private func payrollReceivedOverrideKeyForDisplayedMonth(userId: String? = nil) -> String? {
    let resolvedUserId = userId ?? cachedUserId
    guard let resolvedUserId, !resolvedUserId.isEmpty else { return nil }
    return "dashboard.payroll.received.\(resolvedUserId).\(displayYearMonthKey)"
  }

  private var displayYearMonthKey: String {
    String(format: "%04d-%02d", displayYear, displayMonth)
  }

  // MARK: - Helper Methods

  private static func timeString(from date: Date) -> String {
    ClockSessionRules.timeString(from: date)
  }

  private static func minuteAligned(_ date: Date) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = Date.localTimeZone
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    return calendar.date(from: components) ?? date
  }

  private static func isShiftOngoing(_ shift: ShiftRow, at date: Date) -> Bool {
    ClockSessionRules.isShiftOngoing(shift, at: date)
  }

  private static func zeroShiftComputed(id: String) -> ShiftComputed {
    ShiftComputed(
      id: id,
      durationHours: 0,
      paidHours: 0,
      basePay: 0,
      supplementPay: 0,
      gross: 0,
      wagePeriods: [],
      originalWagePeriods: [],
      breakAudit: BreakAudit(method: .none, thresholdHours: 0, deductedHours: 0, notes: [])
    )
  }

  /// Calculate the adjusted payroll date for a given month
  /// Adjusts backwards if the date falls on a weekend, Monday, or Norwegian public holiday
  private func calculatePayrollDate(year: Int, month: Int, day: Int) -> Date {
    return PayrollDateAdjuster.adjustPayrollDate(payrollDay: day, month: month, year: year)
  }

  private func nextUpcomingPayoutDate(from date: Date, payrollDay: Int, calendar: Calendar) -> Date
  {
    let startOfToday = calendar.startOfDay(for: date)
    let currentComponents = calendar.dateComponents([.year, .month], from: startOfToday)
    let currentYear = currentComponents.year ?? displayYear
    let currentMonth = currentComponents.month ?? displayMonth

    let currentMonthPayout = PayrollDateAdjuster.adjustPayrollDate(
      payrollDay: payrollDay,
      month: currentMonth,
      year: currentYear
    )

    if currentMonthPayout >= startOfToday {
      return currentMonthPayout
    }

    let nextMonthDate = calendar.date(byAdding: .month, value: 1, to: startOfToday) ?? startOfToday
    let nextMonthComponents = calendar.dateComponents([.year, .month], from: nextMonthDate)
    let nextYear = nextMonthComponents.year ?? currentYear
    let nextMonth = nextMonthComponents.month ?? currentMonth

    return PayrollDateAdjuster.adjustPayrollDate(
      payrollDay: payrollDay,
      month: nextMonth,
      year: nextYear
    )
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
