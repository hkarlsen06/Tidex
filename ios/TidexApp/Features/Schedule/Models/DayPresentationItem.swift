import Foundation

struct EventPresentation: Identifiable, Equatable {
  let event: EventRow
  let coveredDateISO: String

  var id: String { event.id }
  var anchorDateISO: String { event.start_date }
  var isAllDay: Bool { event.is_all_day }
  var sortTime: String { event.start_time ?? "99:99" }
}

enum DayPresentationItem: Identifiable, Equatable {
  case shift(ShiftWithComputations)
  case event(EventPresentation)

  var id: String {
    switch self {
    case .shift(let shift):
      return shift.id

    case .event(let event):
      return event.id
    }
  }

  var anchorDateISO: String {
    switch self {
    case .shift(let shift):
      return shift.shiftDate

    case .event(let event):
      return event.anchorDateISO
    }
  }

  var coveredDateISO: String {
    switch self {
    case .shift(let shift):
      return shift.shiftDate

    case .event(let event):
      return event.coveredDateISO
    }
  }

  var isAllDayEvent: Bool {
    if case .event(let event) = self {
      return event.isAllDay
    }
    return false
  }

  var startSortKey: String {
    switch self {
    case .shift(let shift):
      return shift.startTime

    case .event(let event):
      return event.sortTime
    }
  }
}

enum ShiftsListPlaceholderPolicy {
  static func shouldShowTodayPlaceholder(
    isCurrentMonth: Bool,
    filteredShifts: [ShiftWithComputations],
    eventCoverageByDate: [String: [EventPresentation]],
    todayISO: String
  ) -> Bool {
    guard isCurrentMonth else { return false }
    guard !filteredShifts.contains(where: { $0.shiftDate == todayISO }) else { return false }
    return eventCoverageByDate[todayISO]?.isEmpty != false
  }
}
