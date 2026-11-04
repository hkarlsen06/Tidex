import ActivityKit
import Foundation
import UIKit
import os.log

private let clockSessionLogger = Logger(subsystem: "com.tidex.app", category: "ClockSession")  // swiftlint:disable:this explicit_type_interface line_length prefixed_toplevel_constant

struct TemporaryClockSession: Codable, Equatable, Identifiable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl file_types_order line_length
  let id: String  // swiftlint:disable:this explicit_acl
  let userId: String  // swiftlint:disable:this explicit_acl
  let jobId: String?  // swiftlint:disable:this explicit_acl
  let startedAt: Date  // swiftlint:disable:this explicit_acl
  let createdAt: Date  // swiftlint:disable:this explicit_acl
}

enum ClockSessionRules {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  private static func isValidClockTime(_ value: String) -> Bool {
    let parts = value.split(separator: ":")  // swiftlint:disable:this explicit_type_interface
    guard
      parts.count == 2,  // swiftlint:disable:this no_magic_numbers
      parts[1].count == 2,  // swiftlint:disable:this no_magic_numbers
      let hours = Int(parts[0]),
      let minutes = Int(parts[1]),
      (0...24).contains(hours),  // swiftlint:disable:this no_magic_numbers
      (0...59).contains(minutes),  // swiftlint:disable:this no_magic_numbers
      !(hours == 24 && minutes != 0)  // swiftlint:disable:this no_magic_numbers
    else {
      return false
    }

    return true
  }

  static func timeString(from date: Date) -> String {  // swiftlint:disable:this explicit_acl
    date.toHourMinuteString()
  }

  /// Shifts store only HH:mm start and end times, so a clocked shift must end within 24 hours.
  static let maxClockDuration: TimeInterval = 24 * 60 * 60  // swiftlint:disable:this explicit_acl no_magic_numbers

  static func exceedsMaxDuration(from start: Date, to end: Date) -> Bool {  // swiftlint:disable:this explicit_acl
    end.timeIntervalSince(start) >= maxClockDuration
  }

  static func hasExceededMaxDuration(  // swiftlint:disable:this explicit_acl
    _ session: TemporaryClockSession,
    at referenceDate: Date
  ) -> Bool {
    exceedsMaxDuration(from: session.startedAt, to: referenceDate)
  }

  static func minuteAligned(_ date: Date) -> Date {  // swiftlint:disable:this explicit_acl
    var calendar = Calendar(identifier: .gregorian)  // swiftlint:disable:this explicit_type_interface
    calendar.timeZone = Date.localTimeZone
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)  // swiftlint:disable:this explicit_type_interface line_length
    return calendar.date(from: components) ?? date
  }

  /// The clock session from its start to `referenceDate`, priced like Home's featured card.
  static func shiftSoFar(  // swiftlint:disable:this explicit_acl
    _ session: TemporaryClockSession,
    snapshot: WageSnapshot?,
    at referenceDate: Date
  ) -> ShiftWithComputations {
    let alignedStart = minuteAligned(session.startedAt)  // swiftlint:disable:this explicit_type_interface
    let alignedReference = max(minuteAligned(referenceDate), alignedStart)  // swiftlint:disable:this explicit_type_interface line_length
    let shift = ShiftRow(  // swiftlint:disable:this explicit_type_interface
      id: session.id,
      user_id: session.userId,
      job_id: session.jobId,
      shift_date: alignedStart.toISODateString(),
      start_time: timeString(from: alignedStart),
      end_time: timeString(from: alignedReference),
      custom_supplements: nil
    )
    return ShiftWithComputations(
      shift: shift,
      computed: computedSoFar(shift, snapshot: snapshot),
      taxEnabled: snapshot?.effectiveTaxEnabled ?? false,
      taxPercentage: snapshot?.effectiveTaxPercentage ?? 0
    )
  }

  /// A running shift cut off at `referenceDate`.
  static func shiftSoFar(  // swiftlint:disable:this explicit_acl
    _ shift: ShiftWithComputations,
    snapshot: WageSnapshot?,
    at referenceDate: Date
  ) -> ShiftWithComputations {
    let reconstructedShift = ShiftRow(  // swiftlint:disable:this explicit_type_interface
      id: shift.id,
      user_id: shift.shift.user_id,
      job_id: shift.shift.job_id,
      shift_date: shift.shiftDate,
      start_time: shift.startTime,
      end_time: timeString(from: minuteAligned(referenceDate)),
      custom_supplements: shift.shift.custom_supplements
    )
    return ShiftWithComputations(
      shift: reconstructedShift,
      computed: computedSoFar(reconstructedShift, snapshot: snapshot),
      taxEnabled: shift.taxEnabled,
      taxPercentage: shift.taxPercentage,
      calculationContext: shift.calculationContext
    )
  }

  /// Equal HH:mm start and end would read as a 24-hour shift, so the first minute earns nothing.
  private static func computedSoFar(_ shift: ShiftRow, snapshot: WageSnapshot?) -> ShiftComputed {
    guard shift.start_time != shift.end_time else {
      return ShiftComputed(
        id: shift.id,
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
    return PayrollCalculator.computeShift(shift, snapshot: snapshot)
  }

  /// The end after adding `minutes`, or nil when the shift would reach `maxClockDuration`.
  static func extendedEnd(of shift: ShiftRow, byMinutes minutes: Int) -> Date? {  // swiftlint:disable:this explicit_acl
    let startTime: String = String(shift.start_time.prefix(5))  // swiftlint:disable:this no_magic_numbers
    let endTime: String = String(shift.end_time.prefix(5))  // swiftlint:disable:this no_magic_numbers
    guard
      let start = Date.fromDateAndTime(shift.shift_date, time: startTime),
      let end = Date.shiftEndDate(shiftDate: shift.shift_date, startTime: startTime, endTime: endTime)
    else {
      return nil
    }
    let extended: Date = end.addingTimeInterval(TimeInterval(minutes) * 60)  // swiftlint:disable:this no_magic_numbers
    return exceedsMaxDuration(from: start, to: extended) ? nil : extended
  }

  static func isShiftOngoing(_ shift: ShiftRow, at date: Date) -> Bool {  // swiftlint:disable:this explicit_acl
    let calendar = Calendar(identifier: .gregorian)  // swiftlint:disable:this explicit_type_interface
    let startTime = String(shift.start_time.prefix(5))  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers
    let endTime = String(shift.end_time.prefix(5))  // swiftlint:disable:this explicit_type_interface no_magic_numbers

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
final class TemporaryClockSessionStore {  // swiftlint:disable:this explicit_acl explicit_top_level_acl required_deinit
  static let shared = TemporaryClockSessionStore()  // swiftlint:disable:this explicit_acl explicit_type_interface

  private let defaults: UserDefaults
  private let sessionKeyPrefix = "dashboard.clock.temporary-session"  // swiftlint:disable:this explicit_type_interface
  private let decoder = JSONDecoder()  // swiftlint:disable:this explicit_type_interface
  private let encoder = JSONEncoder()  // swiftlint:disable:this explicit_type_interface

  init(defaults: UserDefaults = .standard) {  // swiftlint:disable:this explicit_acl
    self.defaults = defaults
  }

  func activeSession(for userId: String) -> TemporaryClockSession? {  // swiftlint:disable:this explicit_acl
    guard let data = defaults.data(forKey: key(for: userId)) else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return try? decoder.decode(TemporaryClockSession.self, from: data)
  }

  func save(_ session: TemporaryClockSession) {  // swiftlint:disable:this explicit_acl
    guard let data = try? encoder.encode(session) else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    defaults.set(data, forKey: key(for: session.userId))
  }

  func clear(for userId: String) {  // swiftlint:disable:this explicit_acl
    defaults.removeObject(forKey: key(for: userId))
  }

  private func key(for userId: String) -> String {
    "\(sessionKeyPrefix).\(userId)"
  }
}

@MainActor
final class ClockSessionReconciler {  // swiftlint:disable:this explicit_acl explicit_top_level_acl required_deinit
  static let shared = ClockSessionReconciler()  // swiftlint:disable:this explicit_acl explicit_type_interface

  private let clockSessionStore: TemporaryClockSessionStore
  private let shiftsRepository: ShiftsRepository
  private var isReconciling = false  // swiftlint:disable:this explicit_type_interface

  private func notifyShiftsDidChange(context: ShiftChangeContext = .fullReload) {  // swiftlint:disable:this line_length type_contents_order
    NotificationCenter.default.postShiftsDidChange(object: self, context: context)
  }

  init(  // swiftlint:disable:this explicit_acl
    clockSessionStore: TemporaryClockSessionStore? = nil,
    shiftsRepository: ShiftsRepository? = nil
  ) {
    self.clockSessionStore = clockSessionStore ?? TemporaryClockSessionStore.shared
    self.shiftsRepository = shiftsRepository ?? ShiftsRepository.shared
  }

  /// Reconcile temporary clock sessions against persisted ongoing shifts.
  /// Runs on app open/foreground so behavior is correct even when Dashboard is never shown.
  func reconcileIfNeeded(referenceDate: Date = Date()) async {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard !isReconciling else { return }  // swiftlint:disable:this conditional_returns_on_newline
    isReconciling = true
    defer { isReconciling = false }

    guard let session = await AuthSessionManager.shared.getSessionIfAvailable() else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    let userId = session.normalizedUserId  // swiftlint:disable:this explicit_type_interface

    guard let temporarySession = clockSessionStore.activeSession(for: userId) else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length

    if Self.hasExceededMaxDuration(temporarySession, at: referenceDate) {
      cancelTemporarySession(temporarySession)
      notifyShiftsDidChange(context: .affecting(date: temporarySession.startedAt))
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

    let sessionDate = temporarySession.startedAt.toISODateString()  // swiftlint:disable:this explicit_type_interface
    let sessionStartTime = Self.timeString(from: temporarySession.startedAt)  // swiftlint:disable:this explicit_type_interface line_length
    let ongoingStartTime = String(ongoingShift.start_time.prefix(5))  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers

    let shouldBackfillStartTime =  // swiftlint:disable:this explicit_type_interface
      sessionDate == ongoingShift.shift_date && sessionStartTime < ongoingStartTime

    if shouldBackfillStartTime {
      do {
        _ = try await shiftsRepository.updateShift(
          id: ongoingShift.id,
          startTime: sessionStartTime
        )
      } catch {
        clockSessionLogger.error(
          "Foreground clock handoff update failed: \(error.localizedDescription)")  // swiftlint:disable:this line_length multiline_arguments_brackets
        return
      }
    }

    cancelTemporarySession(temporarySession)

    notifyShiftsDidChange(context: .affecting(isoDate: sessionDate))
    ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?
      .checkAndStartLiveActivityIfNeeded()
  }

  private func cancelTemporarySession(_ session: TemporaryClockSession) {  // swiftlint:disable:this type_contents_order
    ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?.endLiveActivity(
      for: session.id)  // swiftlint:disable:this multiline_arguments_brackets
    clockSessionStore.clear(for: session.userId)
  }

  private func ensureTemporaryLiveActivity(for session: TemporaryClockSession) async {  // swiftlint:disable:this line_length type_contents_order
    let hasMatchingActivity = Activity<ShiftActivityAttributes>.activities.contains { activity in  // swiftlint:disable:this explicit_type_interface line_length
      guard activity.attributes.shiftId == session.id else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
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

  private static func isShiftOngoing(_ shift: ShiftRow, at date: Date) -> Bool {
    ClockSessionRules.isShiftOngoing(shift, at: date)
  }

  private static func timeString(from date: Date) -> String {
    ClockSessionRules.timeString(from: date)
  }

  private static func hasExceededMaxDuration(
    _ session: TemporaryClockSession, at referenceDate: Date
  )
    -> Bool
  {
    ClockSessionRules.hasExceededMaxDuration(session, at: referenceDate)
  }
}
