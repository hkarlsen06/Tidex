import Foundation

/// A shift's day and its HH:mm times as stored. An end at or before the start is on the next
/// day, as on the Add Shift screen.
struct ShiftSchedule: Equatable {
  private static let minutesPerDay = 24 * 60

  let shiftDate: String
  let startTime: String
  let endTime: String

  init(shiftDate: String, startTime: String, endTime: String) {
    self.shiftDate = shiftDate
    self.startTime = startTime
    self.endTime = Self.storedEndTime(endTime, start: startTime)
  }

  /// Takes the day from `day` and the clock times from `start` and `end`.
  init(day: Date, start: Date, end: Date) {
    self.init(
      shiftDate: day.toISODateString(),
      startTime: start.toHourMinuteString(),
      endTime: end.toHourMinuteString())
  }

  init(_ shift: ShiftRow) {
    self.init(
      shiftDate: shift.shift_date,
      startTime: String(shift.start_time.prefix(5)),
      endTime: String(shift.end_time.prefix(5)))
  }

  /// A shift that ends at midnight is stored as ending at 24:00, so it stays on its own day.
  static func storedEndTime(_ end: String, start: String) -> String {
    end == "00:00" && start != "00:00" ? "24:00" : end
  }

  var interval: DateInterval? {
    guard
      let start = Date.fromDateAndTime(shiftDate, time: startTime),
      let end = Date.shiftEndDate(shiftDate: shiftDate, startTime: startTime, endTime: endTime)
    else {
      return nil
    }
    return DateInterval(start: start, end: end)
  }

  /// Changes what is given. A new start without a new end keeps the shift's length.
  func moved(to day: Date?, start newStart: Date?, end newEnd: Date?) -> Self {
    let startTime = newStart?.toHourMinuteString() ?? self.startTime
    let endTime: String
    if let newEnd {
      endTime = newEnd.toHourMinuteString()
    } else if newStart != nil {
      endTime = Self.time(fromMinutes: Self.minutes(startTime) + lengthInMinutes)
    } else {
      endTime = self.endTime
    }
    return Self(
      shiftDate: day?.toISODateString() ?? shiftDate, startTime: startTime, endTime: endTime)
  }

  private var lengthInMinutes: Int {
    let length = (Self.minutes(endTime) - Self.minutes(startTime)) % Self.minutesPerDay
    return length <= 0 ? length + Self.minutesPerDay : length
  }

  private static func minutes(_ time: String) -> Int {
    let parts = time.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2 else { return 0 }
    return parts[0] * 60 + parts[1]
  }

  private static func time(fromMinutes minutes: Int) -> String {
    let wrapped = minutes % minutesPerDay
    return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
  }
}
