import Combine
import Foundation
import Observation
import UIKit
import os.log  // swiftlint:disable:this sorted_imports

// MARK: - Dashboard Data

enum DashboardFeaturedItem: Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  case shift(ShiftWithComputations)  // swiftlint:disable:this sorted_enum_cases
  case event(EventRow, coveredDateISO: String)  // swiftlint:disable:this sorted_enum_cases

  var shift: ShiftWithComputations? {  // swiftlint:disable:this explicit_acl
    guard case .shift(let shift) = self else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    return shift
  }
}

struct DashboardFeaturedSelection: Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let item: DashboardFeaturedItem?  // swiftlint:disable:this explicit_acl
  let isToday: Bool  // swiftlint:disable:this explicit_acl
  let isBestShift: Bool  // swiftlint:disable:this explicit_acl
}

enum DashboardFeaturedItemSelector {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  static func select(  // swiftlint:disable:this explicit_acl type_contents_order
    shifts: [ShiftWithComputations],
    events: [EventRow],
    isViewingCurrentMonth: Bool,
    todayISO: String = todayISO(),
    now: Date = Date()
  ) -> DashboardFeaturedSelection {
    if isViewingCurrentMonth {
      return selectCurrentMonth(shifts: shifts, events: events, todayISO: todayISO, now: now)
    }

    guard let bestShift = findBestShift(in: shifts) else {
      return DashboardFeaturedSelection(item: nil, isToday: false, isBestShift: true)
    }

    return DashboardFeaturedSelection(
      item: .shift(bestShift),
      isToday: false,
      isBestShift: true
    )
  }

  private struct ShiftCandidate {
    let shift: ShiftWithComputations
    let startDate: Date
  }

  private struct EventCandidate {
    let event: EventRow
    let coveredDateISO: String
    let sortDate: Date
  }

  private static func selectCurrentMonth(
    shifts: [ShiftWithComputations],
    events: [EventRow],
    todayISO: String,
    now: Date
  ) -> DashboardFeaturedSelection {
    let nextShift = nextUpcomingShift(in: shifts, now: now)  // swiftlint:disable:this explicit_type_interface
    let nextEvent = nextUpcomingEvent(in: events, todayISO: todayISO, now: now)  // swiftlint:disable:this explicit_type_interface line_length

    switch (nextShift, nextEvent) {
    case (.none, .none):
      return DashboardFeaturedSelection(item: nil, isToday: false, isBestShift: false)

    case (.some(let shiftCandidate), .none):
      return DashboardFeaturedSelection(
        item: .shift(shiftCandidate.shift),
        isToday: shiftCandidate.shift.shiftDate == todayISO,
        isBestShift: false
      )

    case (.none, .some(let eventCandidate)):
      return DashboardFeaturedSelection(
        item: .event(eventCandidate.event, coveredDateISO: eventCandidate.coveredDateISO),
        isToday: eventCandidate.coveredDateISO == todayISO,
        isBestShift: false
      )

    case (.some(let shiftCandidate), .some(let eventCandidate)):  // swiftlint:disable:this pattern_matching_keywords
      if shouldPrioritizeShift(shiftCandidate.shift, over: eventCandidate.event) {
        return DashboardFeaturedSelection(
          item: .shift(shiftCandidate.shift),
          isToday: shiftCandidate.shift.shiftDate == todayISO,
          isBestShift: false
        )
      }

      if shiftCandidate.startDate <= eventCandidate.sortDate {
        return DashboardFeaturedSelection(
          item: .shift(shiftCandidate.shift),
          isToday: shiftCandidate.shift.shiftDate == todayISO,
          isBestShift: false
        )
      }

      return DashboardFeaturedSelection(
        item: .event(eventCandidate.event, coveredDateISO: eventCandidate.coveredDateISO),
        isToday: eventCandidate.coveredDateISO == todayISO,
        isBestShift: false
      )
    }
  }

  private static func nextUpcomingShift(
    in shifts: [ShiftWithComputations],
    now: Date
  ) -> ShiftCandidate? {
    shifts
      .compactMap { shift -> ShiftCandidate? in
        guard
          let startDate = Date.fromDateAndTime(shift.shiftDate, time: shift.startTime),
          let endDate = shiftEndDate(for: shift)
        else {
          return nil
        }

        guard endDate > now else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
        return ShiftCandidate(shift: shift, startDate: startDate)
      }
      .min { lhs, rhs in
        if lhs.startDate == rhs.startDate {
          return lhs.shift.id < rhs.shift.id
        }
        return lhs.startDate < rhs.startDate
      }
  }

  private static func nextUpcomingEvent(
    in events: [EventRow],
    todayISO: String,
    now: Date
  ) -> EventCandidate? {
    events
      .compactMap { event -> EventCandidate? in
        guard let endDate = eventEndDate(for: event), endDate > now else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length
        let coveredDateISO = coveredDateISO(for: event, todayISO: todayISO) ?? event.start_date  // swiftlint:disable:this explicit_type_interface line_length
        guard let sortDate = eventSortDate(for: event, coveredDateISO: coveredDateISO) else {
          return nil
        }

        return EventCandidate(event: event, coveredDateISO: coveredDateISO, sortDate: sortDate)
      }
      .min { lhs, rhs in
        if lhs.sortDate == rhs.sortDate {
          return lhs.event.id < rhs.event.id
        }
        return lhs.sortDate < rhs.sortDate
      }
  }

  private static func shouldPrioritizeShift(_ shift: ShiftWithComputations, over event: EventRow)
    -> Bool
  {
    event.is_all_day && eventCovers(event, dateISO: shift.shiftDate)
  }

  private static func shiftEndDate(for shift: ShiftWithComputations) -> Date? {
    guard var endDate = Date.fromDateAndTime(shift.shiftDate, time: shift.endTime) else {
      return nil
    }

    if shift.endTime <= shift.startTime {
      endDate = Calendar.gregorianCurrent.date(byAdding: .day, value: 1, to: endDate) ?? endDate
    }

    return endDate
  }

  private static func eventSortDate(for event: EventRow, coveredDateISO: String) -> Date? {
    if event.is_all_day {
      return Date.fromISODateString(coveredDateISO)
    }

    guard let startTime = event.start_time else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    return Date.fromDateAndTime(event.start_date, time: startTime)
  }

  private static func eventEndDate(for event: EventRow) -> Date? {
    if event.is_all_day {
      guard let endDate = Date.fromISODateString(event.end_date) else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length
      return Calendar.gregorianCurrent.date(byAdding: .day, value: 1, to: endDate)
    }

    guard let endTime = event.end_time else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    return Date.fromDateAndTime(event.end_date, time: endTime)
  }

  private static func coveredDateISO(for event: EventRow, todayISO: String) -> String? {
    if eventCovers(event, dateISO: todayISO) {
      return todayISO
    }

    return event.start_date
  }

  private static func eventCovers(_ event: EventRow, dateISO: String) -> Bool {
    guard
      let date = Date.fromISODateString(dateISO),
      let startDate = Date.fromISODateString(event.start_date),
      let endDate = Date.fromISODateString(event.end_date)
    else {
      return false
    }

    return date >= startDate && date <= endDate
  }

  private static func findBestShift(in shifts: [ShiftWithComputations]) -> ShiftWithComputations? {
    shifts.max { a, b in a.grossPay < b.grossPay }  // swiftlint:disable:this identifier_name
  }
}