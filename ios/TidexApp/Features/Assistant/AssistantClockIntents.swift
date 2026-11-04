import AppIntents
import Foundation

/// What the user is working right now, checked in the same order as Home's clock buttons.
enum ActiveWork {
  /// Clocked in without an end time. Clocking out goes through a review in the app.
  case clockedIn(TemporaryClockSession)
  case onShift(ShiftWithComputations)

  static func find(
    session: TemporaryClockSession?,
    shifts: [ShiftWithComputations],
    at now: Date
  ) -> Self? {
    if let session, !ClockSessionRules.hasExceededMaxDuration(session, at: now) {
      return .clockedIn(session)
    }
    return
      shifts
      .filter { ClockSessionRules.isShiftOngoing($0.shift, at: now) }
      .min { ($0.shiftDate, $0.startTime) < ($1.shiftDate, $1.startTime) }
      .map(Self.onShift)
  }

  @MainActor
  static func load(userId: String, now: Date) async throws
    -> (work: Self, context: PayrollReadContext)?
  {
    let loaded = try await AssistantShifts.computedShifts(access: .user(id: userId), now: now)
    let session = TemporaryClockSessionStore.shared.activeSession(for: userId)
    return find(session: session, shifts: loaded.shifts, at: now).map { ($0, loaded.context) }
  }

  @MainActor
  func earnedSoFar(userId: String, at now: Date, snapshots: SnapshotsRepository = .shared)
    -> ShiftWithComputations
  {
    switch self {
    case .clockedIn(let session):
      let snapshot = snapshots.snapshotForDate(
        ClockSessionRules.minuteAligned(session.startedAt).toISODateString(),
        userId: userId, jobId: session.jobId)
      return ClockSessionRules.shiftSoFar(session, snapshot: snapshot, at: now)

    case .onShift(let shift):
      let snapshot = snapshots.snapshotForDate(
        shift.shiftDate, userId: userId, jobId: shift.shift.job_id)
      return ClockSessionRules.shiftSoFar(shift, snapshot: snapshot, at: now)
    }
  }
}

struct EarnedSoFarIntent: AppIntent, LiveActivityIntent {
  static let title: LocalizedStringResource = "assistant.earnedSoFar.title"
  static let description = IntentDescription("assistant.earnedSoFar.description")
  static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let userId = try AssistantAccess.current.requireUserId()
    let now = Date()
    guard let active = try await ActiveWork.load(userId: userId, now: now) else {
      throw AssistantError.notWorking
    }
    let soFar = active.work.earnedSoFar(userId: userId, at: now)
    let jobs = active.context.jobs
    let currency =
      (soFar.shift.job_id.flatMap { id in jobs.first { $0.id == id } }
      ?? jobs.first(where: \.is_default))?.currency
      ?? active.context.settings?.currency ?? "kr"

    var text = String(
      localized: .assistantEarnedSoFarDialog(
        CurrencyConfig.format(soFar.grossPay, currency: currency)))
    if soFar.taxEnabled {
      text +=
        " "
        + String(
          localized: .assistantEarningsNet(CurrencyConfig.format(soFar.netPay, currency: currency)))
    }
    return .result(dialog: "\(text)")
  }
}

/// Clocks out through Home, so a clock session gets the same review as the Clock out button.
struct StopClockIntent: AppIntent {
  static let title: LocalizedStringResource = "assistant.stopClock.title"
  static let description = IntentDescription("assistant.stopClock.description")
  static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

  @MainActor
  func perform() async throws -> some IntentResult {
    let userId = try AssistantAccess.current.requireUserId()
    guard try await ActiveWork.load(userId: userId, now: Date()) != nil else {
      throw AssistantError.notWorking
    }
    try await continueInForeground(alwaysConfirm: false)
    AppCoordinator.shared.pendingDeepLink = .clockOut
    return .result()
  }
}

struct ExtendShiftIntent: AppIntent, LiveActivityIntent {
  static let title: LocalizedStringResource = "assistant.extendShift.title"
  static let description = IntentDescription("assistant.extendShift.description")
  static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

  @Parameter(
    title: "assistant.extendShift.minutes", description: "assistant.extendShift.minutes.description",
    default: 30, inclusiveRange: (1, 720))
  var minutes: Int

  init() {}

  init(minutes: Int) {
    self.minutes = minutes
  }

  @MainActor
  func perform() async throws -> some IntentResult & ProvidesDialog {
    let userId = try AssistantAccess.current.requireUserId()
    let shift: ShiftWithComputations
    switch try await ActiveWork.load(userId: userId, now: Date())?.work {
    case .onShift(let ongoing) where !ongoing.isVirtual:
      shift = ongoing

    case .onShift:
      throw AssistantError.recurringShift

    case .clockedIn:
      throw AssistantError.clockHasNoEnd

    case nil:
      throw AssistantError.notWorking
    }
    guard let end = ClockSessionRules.extendedEnd(of: shift.shift, byMinutes: minutes) else {
      throw AssistantError.shiftTooLong
    }
    let endTime = ClockSessionRules.timeString(from: end)

    try await requestConfirmation(
      actionName: .set,
      dialog: IntentDialog(
        .assistantExtendShiftConfirm(end.formatted(date: .omitted, time: .shortened))))

    guard try await ShiftsRepository.shared.updateShift(id: shift.id, endTime: endTime) != nil
    else {
      throw AssistantError.shiftNotFound
    }
    NotificationCenter.default.postShiftsDidChange(context: .affecting(isoDate: shift.shiftDate))
    // Also restarts the Live Activity with the new end, before the system suspends the app.
    await NativeWidgetStorage.refreshWidgetStorageNow(for: userId)
    return .result(
      dialog: IntentDialog(
        .assistantExtendShiftDone(end.formatted(date: .omitted, time: .shortened))))
  }
}
