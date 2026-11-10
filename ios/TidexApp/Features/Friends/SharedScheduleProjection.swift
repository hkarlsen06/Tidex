import Foundation

/// Whose clock a friend's schedule is read in.
enum SharedScheduleTimeDisplay: String {
  case viewer
  case schedule

  static let storageKey = "sharedScheduleTimeDisplay"
}

/// What a friend's schedule can offer about its clock.
enum SharedScheduleTimeControl: Equatable {
  /// The schedule's clock matches the viewer's, so there is nothing to choose.
  case none
  /// The schedule's zone differs from the viewer's, so either clock can be shown.
  case choice
  /// The schedule has no valid zone. Its times can only be shown as recorded.
  case unknownZone
}

enum SharedScheduleProjection {
  /// Two zones are at most 26 hours apart, so a shift's start date moves at most two days.
  static let boundaryDays = 2

  static func control(
    shifts: [ShiftWithComputations], scheduleZone: String?, viewerZone: TimeZone = .current,
    now: Date = .now
  ) -> SharedScheduleTimeControl {
    guard let zone = SharedShiftInterval.scheduleZone(scheduleZone) else { return .unknownZone }
    if zone.secondsFromGMT(for: now) != viewerZone.secondsFromGMT(for: now) { return .choice }
    let differs = shifts.contains { shift in
      interval(of: shift, scheduleZone: scheduleZone)?.differs(from: viewerZone) == true
    }
    return differs ? .choice : .none
  }

  /// Copies of `shifts` dated and clocked in the viewer's zone, for display only. A shift moves
  /// to the day it starts on for the viewer, and only the ones starting on `visibleDates` remain.
  /// The copies keep the recorded pay. Payroll and sharing use the recorded shift.
  static func viewerDated(
    _ shifts: [ShiftWithComputations], scheduleZone: String?, viewerZone: TimeZone = .current,
    visibleDates: ClosedRange<String>
  ) -> [ShiftWithComputations] {
    let posix = Locale(identifier: "en_US_POSIX")
    let dated = shifts.compactMap { shift -> ShiftWithComputations? in
      guard let interval = interval(of: shift, scheduleZone: scheduleZone) else {
        // A shift whose recorded time can't be read stays on its recorded day.
        return visibleDates.contains(shift.shiftDate) ? shift : nil
      }
      let date = interval.dateString(in: viewerZone)
      guard visibleDates.contains(date) else { return nil }
      let recorded = shift.shift
      return ShiftWithComputations(
        shift: ShiftRow(
          id: recorded.id, user_id: recorded.user_id, job_id: recorded.job_id, shift_date: date,
          start_time: interval.clock(interval.start, in: viewerZone, locale: posix),
          end_time: interval.clock(interval.end, in: viewerZone, locale: posix),
          note: recorded.note, custom_pause_windows: recorded.custom_pause_windows,
          custom_supplements: recorded.custom_supplements, created_at: recorded.created_at,
          updated_at: recorded.updated_at, recurring_id: recorded.recurring_id,
          recurring_anchor_weekday: recorded.recurring_anchor_weekday),
        computed: shift.computed, taxEnabled: shift.taxEnabled,
        taxPercentage: shift.taxPercentage, calculationContext: shift.calculationContext)
    }
    return dated.sorted { lhs, rhs in
      lhs.shiftDate == rhs.shiftDate
        ? lhs.startTime < rhs.startTime : lhs.shiftDate < rhs.shiftDate
    }
  }

  static func interval(of shift: ShiftWithComputations, scheduleZone: String?)
    -> SharedShiftInterval?
  {
    SharedShiftInterval(
      date: shift.shiftDate, startTime: shift.startTime, endTime: shift.endTime,
      timeZoneIdentifier: scheduleZone)
  }
}

/// Both readings of a shared shift whose schedule zone differs from the viewer's. The details
/// sheet leads with the one the schedule shows and puts the other beneath it.
struct SharedShiftTimeContext: Equatable {
  let interval: SharedShiftInterval
  let display: SharedScheduleTimeDisplay
  var viewerZone: TimeZone = .current

  private var shownZone: TimeZone { display == .viewer ? viewerZone : interval.timeZone }
  private var otherZone: TimeZone { display == .viewer ? interval.timeZone : viewerZone }

  func date(locale: Locale = .appLocale) -> String {
    var style = Date.FormatStyle().weekday(.wide).day().month(.wide).year().locale(locale)
    style.timeZone = shownZone
    style.calendar = Calendar(identifier: .gregorian)
    return interval.start.formatted(style).sentenceCased()
  }

  func timeRange(locale: Locale = .appLocale) -> String {
    interval.timeRange(in: shownZone, locale: locale)
  }

  /// The other clock's range, with its dates when they differ from the ones shown above it.
  func otherTimeRange(locale: Locale = .appLocale) -> String {
    interval.timeRange(in: otherZone, datedAgainst: shownZone, locale: locale)
  }
}
