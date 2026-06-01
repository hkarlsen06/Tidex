import Foundation

enum ReminderOffsetFormatter {
  static func localizedString(for minutes: Int) -> String {
    let hours = minutes / 60
    let remainingMinutes = minutes % 60

    if hours == 0 {
      return String(localized: .notificationReminderMinutesBefore(Int(remainingMinutes)))
    }

    if remainingMinutes == 0 {
      if hours == 24 {
        return String(localized: .notificationReminderOneDayBefore)
      }
      if hours == 48 {
        return String(localized: .notificationReminderTwoDaysBefore)
      }
      return String(localized: .notificationReminderHoursBefore(Int(hours)))
    }

    return
      "\(hours) \(String(localized: .commonHoursShort)) \(remainingMinutes) \(String(localized: .commonMinutesShort)) \(String(localized: .commonBefore))"
  }

  static func localizedShiftPickerPreview(hours: Int, minutes: Int) -> String {
    let totalMinutes = (hours * 60) + minutes
    guard totalMinutes >= 1 else {
      return String(localized: .notificationsTimePickerSelectTime)
    }

    if hours == 0 {
      return String(localized: .notificationReminderMinutesBeforeShift(Int(minutes)))
    }

    if minutes == 0 {
      if hours == 24 {
        return String(localized: .notificationReminderOneDayBeforeShift)
      }
      if hours == 48 {
        return String(localized: .notificationReminderTwoDaysBeforeShift)
      }
      return String(localized: .notificationReminderHoursBeforeShift(Int(hours)))
    }

    return
      "\(hours) \(String(localized: .commonHoursShort)) \(minutes) min \(String(localized: .commonBeforeShift))"
  }

  static func localizedEventPickerPreview(hours: Int, minutes: Int) -> String {
    let totalMinutes = (hours * 60) + minutes
    guard totalMinutes >= 1 else {
      return String(localized: .notificationsTimePickerSelectTime)
    }

    return localizedString(for: totalMinutes)
  }

  static func localizedAllDayEventDayLabel(daysBefore: Int) -> String {
    switch daysBefore {
    case 0:
      return String(localized: .eventsNotificationsSameDay)
    case 1:
      return String(localized: .eventsNotificationsOneDayBefore)
    case 2:
      return String(localized: .eventsNotificationsTwoDaysBefore)
    default:
      return localizedString(for: daysBefore * 1440)
    }
  }

  static func localizedAllDayEventReminder(minutesBefore: Int, anchorTime: Date?) -> String {
    guard minutesBefore >= 0, minutesBefore.isMultiple(of: 1440) else {
      return localizedString(for: minutesBefore)
    }

    let daysBefore = minutesBefore / 1440
    let dayLabel = localizedAllDayEventDayLabel(daysBefore: daysBefore)
    guard let anchorTime else { return dayLabel }
    return "\(dayLabel) • \(anchorTime.toHourMinuteString())"
  }
}
