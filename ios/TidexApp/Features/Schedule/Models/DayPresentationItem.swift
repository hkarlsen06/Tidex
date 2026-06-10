import Foundation

internal enum DayPresentationItem: Identifiable, Equatable {
  case event(EventPresentation)
  case shift(ShiftWithComputations)

  internal var id: String {
    switch self {
    case .event(let event):
      return event.id

    case .shift(let shift):
      return shift.id
    }
  }

  internal var anchorDateISO: String {
    switch self {
    case .event(let event):
      return event.anchorDateISO

    case .shift(let shift):
      return shift.shiftDate
    }
  }

  internal var coveredDateISO: String {
    switch self {
    case .event(let event):
      return event.coveredDateISO

    case .shift(let shift):
      return shift.shiftDate
    }
  }

  internal var isAllDayEvent: Bool {
    if case .event(let event) = self {
      return event.isAllDay
    }
    return false
  }

  internal var startSortKey: String {
    switch self {
    case .event(let event):
      return event.sortTime

    case .shift(let shift):
      return shift.startTime
    }
  }
}

internal enum ShiftsListPlaceholderPolicy {
  internal static func shouldShowTodayPlaceholder(
    isCurrentMonth: Bool,
    filteredShifts: [ShiftWithComputations],
    eventCoverageByDate: [String: [EventPresentation]],
    todayISO: String
  ) -> Bool {
    guard isCurrentMonth else {
      return false
    }
    guard !filteredShifts.contains(where: { $0.shiftDate == todayISO }) else {
      return false
    }
    return eventCoverageByDate[todayISO]?.isEmpty != false
  }
}

internal struct EventPresentation: Identifiable, Equatable {
  private static let allDaySortTime: String = "99:99"

  internal let event: EventRow
  internal let coveredDateISO: String

  internal var id: String { event.id }
  internal var anchorDateISO: String { event.start_date }
  internal var isAllDay: Bool { event.is_all_day }
  internal var sortTime: String { event.start_time ?? Self.allDaySortTime }
}
