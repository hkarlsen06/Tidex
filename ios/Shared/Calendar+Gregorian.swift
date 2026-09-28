import Foundation

extension Calendar {
  /// The Gregorian calendar, but otherwise following the user: current timezone, current
  /// locale, and the locale's week layout (first weekday, minimum days in first week).
  ///
  /// Pay periods, shift dates, month labels, and calendar grids are always Gregorian in this
  /// app. Reading them with `Calendar.current` or `Calendar.autoupdatingCurrent` on a device
  /// set to a non-Gregorian calendar (Buddhist, Islamic, etc.) misreads the year, mislabels
  /// months, and can land on a date hundreds of years away. Use this instead of
  /// `Calendar.current`/`Calendar.autoupdatingCurrent` everywhere in the app, its shared code,
  /// and its extensions, unless a call site genuinely needs the user's own calendar system.
  ///
  /// A computed property, not a cached value, so timezone and locale changes still apply.
  static var gregorianCurrent: Calendar {
    let current = Calendar.current
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = current.timeZone
    calendar.locale = current.locale
    calendar.firstWeekday = current.firstWeekday
    calendar.minimumDaysInFirstWeek = current.minimumDaysInFirstWeek
    return calendar
  }
}

extension Date.FormatStyle {
  /// Formats with the given calendar system instead of the user's, e.g. `.calendar(.gregorian)`.
  func calendar(_ identifier: Calendar.Identifier) -> Self {
    var style = self
    style.calendar = Calendar(identifier: identifier)
    return style
  }
}
