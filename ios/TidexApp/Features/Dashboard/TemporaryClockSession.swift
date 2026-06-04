import ActivityKit
import Foundation
import UIKit
import os.log

private let clockSessionLogger = Logger(subsystem: "com.tidex.app", category: "ClockSession")

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

  private func notifyShiftsDidChange(context: ShiftChangeContext = .fullReload) {
    NotificationCenter.default.postShiftsDidChange(object: self, context: context)
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
        clockSessionLogger.error(
          "Foreground clock handoff update failed: \(error.localizedDescription)")
        return
      }
    }

    cancelTemporarySession(temporarySession)

    notifyShiftsDidChange(context: .affecting(isoDate: sessionDate))
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
