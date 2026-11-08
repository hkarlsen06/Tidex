import Combine
import Foundation
import Observation
import UIKit
import os.log  // swiftlint:disable:this sorted_imports

extension DashboardViewModel {

  // MARK: - Clock Operations

  func refreshClockState() async {  // swiftlint:disable:this explicit_acl type_contents_order
    await refreshClockActiveState(referenceDate: Date())
    maybeTriggerCelebration()
  }

  func refreshAppearanceSettingsFromLocal() async {  // swiftlint:disable:this explicit_acl type_contents_order
    guard let userId = await ensureCachedUserId() else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    guard let latestSettings = settingsRepository.getSettings(for: userId) else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    settings = latestSettings
    shouldShowDashboardClockButtons = latestSettings.effectiveShowDashboardClockButtons
  }

  func applyDashboardClockButtonsVisibility(_ isVisible: Bool) {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    shouldShowDashboardClockButtons = isVisible
  }

  func temporaryFeaturedShift(  // swiftlint:disable:this explicit_acl type_contents_order
    from session: TemporaryClockSession,
    at referenceDate: Date = Date()
  ) -> ShiftWithComputations {
    let snapshot = snapshotsRepository.snapshotForDate(  // swiftlint:disable:this explicit_type_interface
      ClockSessionRules.minuteAligned(session.startedAt).toISODateString(),
      userId: session.userId,
      jobId: session.jobId
    )
    return ClockSessionRules.shiftSoFar(session, snapshot: snapshot, at: referenceDate)
  }

  func liveFeaturedShiftWhileOngoing(  // swiftlint:disable:this explicit_acl type_contents_order
    from shift: ShiftWithComputations,
    at referenceDate: Date = Date()
  ) -> ShiftWithComputations {
    let snapshot = (shift.shift.user_id ?? cachedUserId).flatMap { userId in  // swiftlint:disable:this explicit_type_interface line_length
      snapshotsRepository.snapshotForDate(shift.shiftDate, userId: userId, jobId: shift.shift.job_id)
    }
    return ClockSessionRules.shiftSoFar(shift, snapshot: snapshot, at: referenceDate)
  }

  func clockIn(jobId: String? = nil, at now: Date = Date()) async {  // swiftlint:disable:this explicit_acl function_body_length line_length type_contents_order
    guard !isClockActionInProgress else {
      return
    }
    await refreshClockActiveState(referenceDate: now)

    guard case .none = activeClockState else {
      // Self-heal: if an active local clock state exists but its Live Activity is missing,
      // reconciling can recreate the temporary activity.
      await ClockSessionReconciler.shared.reconcileIfNeeded(referenceDate: now)
      return
    }

    guard let userId = await ensureCachedUserId() else {
      dashboardViewModelLogger.error("❌ Clock in aborted: unable to resolve user ID")
      return
    }
    let resolvedJobId = jobId ?? defaultJobId(for: userId)  // swiftlint:disable:this explicit_type_interface
    do {
      _ = try jobPaySetupStatusService.requireConfiguredActiveJob(
        userId: userId,
        requestedJobId: resolvedJobId
      )
    } catch {
      dashboardViewModelLogger.info("Clock in requires pay setup before starting a temporary session")
      return
    }

    let alignedStart = ClockSessionRules.minuteAligned(now)  // swiftlint:disable:this explicit_type_interface
    let session = TemporaryClockSession(  // swiftlint:disable:this explicit_type_interface
      id: UUID().lowercasedString,
      userId: userId,
      jobId: resolvedJobId,
      startedAt: alignedStart,
      createdAt: now
    )
    clockSessionStore.save(session)
    activeClockState = .temporary(session)

    let currency = settings?.currency ?? "kr"  // swiftlint:disable:this explicit_type_interface
    guard let appDelegate = (UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared
    else {
      dashboardViewModelLogger.error("❌ Clock in aborted: AppDelegate unavailable")
      return
    }

    await appDelegate.startTemporaryLiveActivity(
      shiftId: session.id,
      startedAt: session.startedAt,
      currencySymbol: currency
    )
  }

  func routeClockOut(at now: Date = Date()) async -> ClockOutRoute {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard !isClockActionInProgress else { return .none }  // swiftlint:disable:this conditional_returns_on_newline
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

  func commitTemporaryClockOut(start: Date, end: Date, jobId: String? = nil) async throws {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard end > start else { throw ClockError.invalidRange }
    guard !isClockActionInProgress else { return }  // swiftlint:disable:this conditional_returns_on_newline

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

    if hasExceededMaxDuration(session, at: Date())
      || ClockSessionRules.exceedsMaxDuration(from: start, to: end)
    {
      throw ClockError.maxDurationExceeded
    }

    isClockActionInProgress = true
    defer { isClockActionInProgress = false }

    let resolvedJobId = jobId ?? session.jobId ?? defaultJobId(for: session.userId)  // swiftlint:disable:this explicit_type_interface line_length
    let shiftDate = Calendar.gregorianCurrent.startOfDay(for: start)  // swiftlint:disable:this explicit_type_interface
    _ = try await shiftsRepository.createShift(
      shiftId: session.id,
      userId: session.userId,
      jobId: resolvedJobId,
      shiftDate: shiftDate,
      startTime: Self.timeString(from: start),
      endTime: Self.timeString(from: end),
      customSupplements: nil,
      creationMethod: "clock"
    )

    cancelTemporarySession(session)

    await reloadFromLocal()
    notifyShiftsDidChange(context: .affecting(date: shiftDate))
    await refreshClockActiveState(referenceDate: Date())
  }

  func discardTemporaryClockSession() async {  // swiftlint:disable:this explicit_acl type_contents_order
    guard !isClockActionInProgress else { return }  // swiftlint:disable:this conditional_returns_on_newline

    await refreshClockActiveState(referenceDate: Date())
    guard case .temporary(let session) = activeClockState else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length

    cancelTemporarySession(session)
    notifyShiftsDidChange(context: .affecting(date: session.startedAt))
    await refreshClockActiveState(referenceDate: Date())
  }

  func clockSelectableJobs() async -> [Job] {  // swiftlint:disable:this explicit_acl type_contents_order
    if !displayJobs.isEmpty {
      return sortClockJobs(displayJobs)
    }

    guard let userId = await ensureCachedUserId() else { return [] }  // swiftlint:disable:this conditional_returns_on_newline line_length
    displayJobs = jobsRepository.getNonDeletedJobs(for: userId)
    return sortClockJobs(displayJobs)
  }

  func clockSelectableJobsSnapshot() -> [Job] {  // swiftlint:disable:this explicit_acl type_contents_order
    sortClockJobs(displayJobs)
  }

  func clockJobRequiringPaySetup(jobId: String?) async -> Job? {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard let userId = await ensureCachedUserId() else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length
    if displayJobs.isEmpty {
      displayJobs = jobsRepository.getNonDeletedJobs(for: userId)
    }

    let activeJobs = sortClockJobs(displayJobs)  // swiftlint:disable:this explicit_type_interface
    let resolvedJob: Job?
    if let jobId {
      resolvedJob = activeJobs.first { $0.id == jobId }
    } else {
      resolvedJob = activeJobs.first(where: \.is_default) ?? activeJobs.first
    }

    guard let resolvedJob else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    return jobPaySetupStatusService.isJobConfigured(userId: userId, jobId: resolvedJob.id)
      ? nil
      : resolvedJob
  }

  func completeClockPaySetup(for job: Job, input: JobPaySetupInput) async -> Bool {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard let userId = await ensureCachedUserId() else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length

    do {
      _ = try await jobsRepository.completePaySetup(
        userId: userId,
        jobId: job.id,
        currency: input.currency,
        payrollDay: input.payrollDay,
        halfTaxMonth: input.halfTaxMonth,
        monthlyGoal: job.monthly_goal,
        baselineSnapshot: input.baselineSnapshot
      )
      displayJobs = jobsRepository.getNonDeletedJobs(for: userId)
      await reloadFromLocal()
      notifyShiftsDidChange(context: .fullReload)
      Haptics.play(.success)
      return true
    } catch {
      dashboardViewModelLogger.error("❌ Failed to complete clock pay setup: \(error.localizedDescription)")
      return false
    }
  }

  func preloadClockSelectableJobs() async {  // swiftlint:disable:this explicit_acl type_contents_order
    _ = await clockSelectableJobs()
  }

  func preferredClockJobId(for session: TemporaryClockSession) -> String? {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    let selectableJobs = sortClockJobs(displayJobs)  // swiftlint:disable:this explicit_type_interface
    let defaultJobId = selectableJobs.first(where: \.is_default)?.id  // swiftlint:disable:this explicit_type_interface
    return session.jobId ?? defaultJobId ?? selectableJobs.first?.id
  }

  private func sortClockJobs(_ jobs: [Job]) -> [Job] {  // swiftlint:disable:this type_contents_order
    let selectableJobs = jobs.filter { $0.archived_at == nil && $0.deleted_at == nil }  // swiftlint:disable:this explicit_type_interface line_length
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

  func refreshClockActiveState(referenceDate: Date) async {  // swiftlint:disable:this type_contents_order
    await ClockSessionReconciler.shared.reconcileIfNeeded(referenceDate: referenceDate)

    guard let userId = await ensureCachedUserId() else {
      activeClockState = .none
      return
    }

    if let session = clockSessionStore.activeSession(for: userId) {
      if hasExceededMaxDuration(session, at: referenceDate) {
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

  private func cancelTemporarySession(_ session: TemporaryClockSession) {  // swiftlint:disable:this type_contents_order
    ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?.endLiveActivity(
      for: session.id)  // swiftlint:disable:this multiline_arguments_brackets
    clockSessionStore.clear(for: session.userId)
  }

  private func hasExceededMaxDuration(_ session: TemporaryClockSession, at referenceDate: Date)  // swiftlint:disable:this line_length type_contents_order
    -> Bool
  {
    ClockSessionRules.hasExceededMaxDuration(session, at: referenceDate)
  }

  private func findPersistedOngoingShift(for userId: String, at referenceDate: Date) async  // swiftlint:disable:this line_length type_contents_order
    -> ShiftRow?
  {
    let calendar = Calendar.gregorianCurrent  // swiftlint:disable:this explicit_type_interface
    let startDate = calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate  // swiftlint:disable:this explicit_type_interface line_length
    let endDate = calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate  // swiftlint:disable:this explicit_type_interface line_length
    let shifts = await shiftsRepository.getShiftsOffMain(  // swiftlint:disable:this explicit_type_interface
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
  private func findComputedOngoingShift(at referenceDate: Date) -> ShiftWithComputations? {  // swiftlint:disable:this line_length type_contents_order
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
}
