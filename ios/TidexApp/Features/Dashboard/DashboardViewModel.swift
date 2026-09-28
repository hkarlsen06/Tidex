import Combine
import Foundation
import Supabase
import UIKit
import os.log  // swiftlint:disable:this sorted_imports

private let logger = Logger(subsystem: "com.tidex.app", category: "DashboardViewModel")  // swiftlint:disable:this explicit_type_interface line_length prefixed_toplevel_constant

// MARK: - Notification Names

extension Notification.Name {  // swiftlint:disable:this file_types_order
  /// Posted when dashboard clock button visibility changes in appearance settings.
  static let dashboardClockButtonsVisibilityDidChange = Notification.Name(  // swiftlint:disable:this explicit_acl explicit_type_interface line_length
    "com.tidex.dashboardClockButtonsVisibilityDidChange")  // swiftlint:disable:this multiline_arguments_brackets
}

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
      endDate = Calendar.current.date(byAdding: .day, value: 1, to: endDate) ?? endDate
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
      return Calendar.current.date(byAdding: .day, value: 1, to: endDate)
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

/// Computed dashboard data ready for display
struct DashboardData: Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  // Month Context
  let displayedYear: Int  // swiftlint:disable:this explicit_acl
  let displayedMonth: Int  // swiftlint:disable:this explicit_acl

  // Payroll Card (Previous Month)
  let payrollDate: Date  // swiftlint:disable:this explicit_acl
  let payrollHasPassed: Bool  // true = previous payout, false = next payout // swiftlint:disable:this explicit_acl
  let previousMonthGross: Double  // swiftlint:disable:this explicit_acl
  let previousMonthNet: Double?  // nil if tax not enabled // swiftlint:disable:this explicit_acl
  let previousMonthTax: Double?  // swiftlint:disable:this explicit_acl
  let previousMonthTaxEnabled: Bool  // swiftlint:disable:this explicit_acl
  let previousMonthHasPayrollAdjustments: Bool  // swiftlint:disable:this explicit_acl

  // Total Card (Current Month)
  let currentMonthGross: Double  // All shifts (projected total) // swiftlint:disable:this explicit_acl
  let currentMonthNet: Double?  // All shifts net (projected) // swiftlint:disable:this explicit_acl
  let currentMonthCompletedGross: Double  // Only completed shifts (earned to date) // swiftlint:disable:this explicit_acl line_length
  let currentMonthCompletedNet: Double?  // Only completed shifts net // swiftlint:disable:this explicit_acl
  let currentMonthShiftCount: Int  // Total shift count // swiftlint:disable:this explicit_acl
  let currentMonthCompletedCount: Int  // Completed shifts count // swiftlint:disable:this explicit_acl
  let currentMonthPlannedCount: Int  // Future shifts // swiftlint:disable:this explicit_acl
  let percentageChangeVsPrevious: Double?  // swiftlint:disable:this explicit_acl
  let currentMonthTaxEnabled: Bool  // swiftlint:disable:this explicit_acl

  // Featured Home Card
  // For current month: next upcoming shift or calendar event
  // For other months: best shift (highest earnings) in that month
  let featuredItem: DashboardFeaturedItem?  // swiftlint:disable:this explicit_acl
  let featuredShift: ShiftWithComputations?  // swiftlint:disable:this explicit_acl
  let isFeaturedItemToday: Bool  // swiftlint:disable:this explicit_acl
  let featuredShiftIsBestShift: Bool  // true = showing best shift, false = showing next shift // swiftlint:disable:this explicit_acl line_length

  // Metadata
  let currentMonthName: String  // swiftlint:disable:this explicit_acl
  let previousMonthName: String  // swiftlint:disable:this explicit_acl

  // User Settings
  let currency: String  // User's selected currency (e.g., "kr", "$", "€") // swiftlint:disable:this explicit_acl
  let currentMonthCurrencyAggregate: JobCurrencyAggregateResolution  // swiftlint:disable:this explicit_acl

  /// Whether there are future shifts (main display should be projected total)
  var hasFutureShifts: Bool {  // swiftlint:disable:this explicit_acl
    currentMonthPlannedCount > 0
  }

  /// Whether this dashboard payload represents the real current month.
  var isViewingCurrentMonth: Bool {  // swiftlint:disable:this explicit_acl
    let current = Date.currentYearMonth()  // swiftlint:disable:this explicit_type_interface
    return displayedYear == current.year && displayedMonth == current.month
  }
}

struct PayrollCardVariant: Identifiable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let id: String  // swiftlint:disable:this explicit_acl
  let title: String  // swiftlint:disable:this explicit_acl
  let colorHex: String?  // swiftlint:disable:this explicit_acl
  var usesDefaultTitle: Bool = false  // swiftlint:disable:this explicit_acl
  let badges: [PayrollCardBadge]  // swiftlint:disable:this explicit_acl
  let currency: String  // swiftlint:disable:this explicit_acl
  let payoutDate: Date  // swiftlint:disable:this explicit_acl
  let gross: Double  // swiftlint:disable:this explicit_acl
  let net: Double?  // swiftlint:disable:this explicit_acl
  let tax: Double?  // swiftlint:disable:this explicit_acl
  let taxEnabled: Bool  // swiftlint:disable:this explicit_acl
  let hasPayrollAdjustments: Bool  // swiftlint:disable:this explicit_acl
  let jobBreakdowns: [PayrollCardJobBreakdown]  // swiftlint:disable:this explicit_acl
}

extension PayrollCardVariant {  // swiftlint:disable:this file_types_order no_grouping_extension
  func resolvingDefaultTitle(_ defaultTitle: String) -> PayrollCardVariant {  // swiftlint:disable:this explicit_acl
    guard usesDefaultTitle else { return self }  // swiftlint:disable:this conditional_returns_on_newline

    return PayrollCardVariant(
      id: id,
      title: defaultTitle,
      colorHex: colorHex,
      usesDefaultTitle: true,
      badges: badges,
      currency: currency,
      payoutDate: payoutDate,
      gross: gross,
      net: net,
      tax: tax,
      taxEnabled: taxEnabled,
      hasPayrollAdjustments: hasPayrollAdjustments,
      jobBreakdowns: jobBreakdowns
    )
  }
}

struct PayrollCardBadge: Identifiable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let id: String  // swiftlint:disable:this explicit_acl
  let title: String  // swiftlint:disable:this explicit_acl
  let colorHex: String?  // swiftlint:disable:this explicit_acl
}

struct PayrollCardJobBreakdown: Identifiable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let id: String  // swiftlint:disable:this explicit_acl
  let title: String  // swiftlint:disable:this explicit_acl
  let colorHex: String?  // swiftlint:disable:this explicit_acl
  let currency: String  // swiftlint:disable:this explicit_acl
  let basePay: Double  // swiftlint:disable:this explicit_acl
  let supplementPay: Double  // swiftlint:disable:this explicit_acl
  let supplementBreakdowns: [PayrollSupplementBreakdown]  // swiftlint:disable:this explicit_acl
  let postDeductions: Double  // swiftlint:disable:this explicit_acl
  let postDeductionParts: [BreakDeductionPart]  // swiftlint:disable:this explicit_acl
  let payoutDate: Date  // swiftlint:disable:this explicit_acl
  let gross: Double  // swiftlint:disable:this explicit_acl
  let net: Double?  // swiftlint:disable:this explicit_acl
  let tax: Double?  // swiftlint:disable:this explicit_acl
  let taxEnabled: Bool  // swiftlint:disable:this explicit_acl
  let adjustments: [PayrollAdjustment]  // swiftlint:disable:this explicit_acl
  var earningsPeriodStart: Date? = nil
  var earningsPeriodEnd: Date?
  var payoutTaxSettings: PayoutTaxSettings? = nil
}

struct DashboardPayrollCardSnapshot: Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let displayedYear: Int  // swiftlint:disable:this explicit_acl
  let displayedMonth: Int  // swiftlint:disable:this explicit_acl
  let variants: [PayrollCardVariant]  // swiftlint:disable:this explicit_acl
  let previousPayoutVariants: [PayrollCardVariant]  // swiftlint:disable:this explicit_acl
}

struct DashboardPayrollSelection: Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  /// Month of the nominal payday. Used for adjustment lookups and half tax.
  let payoutYear: Int  // swiftlint:disable:this explicit_acl
  let payoutMonth: Int  // swiftlint:disable:this explicit_acl
  let payoutDate: Date  // swiftlint:disable:this explicit_acl
  let jobIds: [String]  // swiftlint:disable:this explicit_acl
  /// The pay period each selected job is paid for on `payoutDate`.
  let windowsByJobId: [String: PayWindow]  // swiftlint:disable:this explicit_acl
}

enum DashboardPayrollSelector {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  static func select(  // swiftlint:disable:this explicit_acl type_contents_order
    displayYM: (year: Int, month: Int),
    jobs: [Job],
    fallbackPayrollDay: Int,
    isViewingCurrentMonth: Bool,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> DashboardPayrollSelection? {
    selections(
      displayYM: displayYM,
      jobs: jobs,
      fallbackPayrollDay: fallbackPayrollDay,
      isViewingCurrentMonth: isViewingCurrentMonth,
      now: now,
      calendar: calendar
    ).first
  }

  static func selections(  // swiftlint:disable:this explicit_acl type_contents_order
    displayYM: (year: Int, month: Int),
    jobs: [Job],
    fallbackPayrollDay: Int,
    isViewingCurrentMonth: Bool,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [DashboardPayrollSelection] {
    guard !jobs.isEmpty else { return [] }  // swiftlint:disable:this conditional_returns_on_newline

    if isViewingCurrentMonth {
      let startOfToday = calendar.startOfDay(for: now)  // swiftlint:disable:this explicit_type_interface
      let currentCandidates = payoutCandidates(  // swiftlint:disable:this explicit_type_interface
        for: displayYM,
        jobs: jobs,
        fallbackPayrollDay: fallbackPayrollDay
      ).filter { $0.payoutDate >= startOfToday }

      if !currentCandidates.isEmpty {
        return makeSelections(
          payoutYM: displayYM,
          candidates: currentCandidates,
          calendar: calendar
        )
      }

      let nextYM = Date.nextYearMonth(from: displayYM)  // swiftlint:disable:this explicit_type_interface
      return makeSelections(
        payoutYM: nextYM,
        candidates: payoutCandidates(
          for: nextYM,
          jobs: jobs,
          fallbackPayrollDay: fallbackPayrollDay
        ),
        calendar: calendar
      )
    }

    return makeSelections(
      payoutYM: displayYM,
      candidates: payoutCandidates(
        for: displayYM,
        jobs: jobs,
        fallbackPayrollDay: fallbackPayrollDay
      ),
      calendar: calendar
    )
  }

  static func previousPassedSelections(  // swiftlint:disable:this explicit_acl type_contents_order
    displayYM: (year: Int, month: Int),
    jobs: [Job],
    fallbackPayrollDay: Int,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [DashboardPayrollSelection] {
    let startOfToday = calendar.startOfDay(for: now)  // swiftlint:disable:this explicit_type_interface
    return Array(
      makeSelections(
        payoutYM: displayYM,
        candidates: payoutCandidates(
          for: displayYM,
          jobs: jobs,
          fallbackPayrollDay: fallbackPayrollDay
        ).filter { $0.payoutDate < startOfToday },
        calendar: calendar
      ).reversed()
    )
  }

  /// The earliest previous payday among the selected jobs. Progress toward the
  /// selected payout starts here.
  static func previousPayoutStartDate(  // swiftlint:disable:this explicit_acl type_contents_order
    for selection: DashboardPayrollSelection,
    jobs: [Job],
    fallbackPayrollDay: Int
  ) -> Date? {
    jobs
      .compactMap { job -> Date? in
        guard let window = selection.windowsByJobId[job.id] else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length
        return PayoutSchedule(job: job, fallbackPayrollDay: fallbackPayrollDay)
          .previousWindow(before: window)?
          .adjustedPayoutDate
      }
      .min()
  }

  private static func makeSelections(  // swiftlint:disable:this type_contents_order
    payoutYM: (year: Int, month: Int),
    candidates: [PayoutCandidate],
    calendar: Calendar
  ) -> [DashboardPayrollSelection] {
    var remaining = candidates  // swiftlint:disable:this explicit_type_interface
    var selections: [DashboardPayrollSelection] = []

    while let candidate = earliestCandidate(in: remaining) {
      let selectedDate = candidate.payoutDate  // swiftlint:disable:this explicit_type_interface
      let sameDay = remaining.filter { calendar.isDate($0.payoutDate, inSameDayAs: selectedDate) }  // swiftlint:disable:this explicit_type_interface line_length

      selections.append(
        DashboardPayrollSelection(
          payoutYear: payoutYM.year,
          payoutMonth: payoutYM.month,
          payoutDate: selectedDate,
          jobIds: sameDay.map(\.job.id),
          windowsByJobId: Dictionary(
            sameDay.map { ($0.job.id, $0.window) }, uniquingKeysWith: { first, _ in first })
        ))  // swiftlint:disable:this multiline_arguments_brackets

      remaining.removeAll { calendar.isDate($0.payoutDate, inSameDayAs: selectedDate) }
    }

    return selections
  }

  private struct PayoutCandidate {
    let job: Job
    let window: PayWindow
    let payoutDate: Date
  }

  /// One candidate per payday in the month. Two-weekly jobs can have two or three.
  private static func payoutCandidates(
    for payoutYM: (year: Int, month: Int),
    jobs: [Job],
    fallbackPayrollDay: Int
  ) -> [PayoutCandidate] {
    jobs.flatMap { job in
      PayoutSchedule(job: job, fallbackPayrollDay: fallbackPayrollDay)
        .windows(paidInYear: payoutYM.year, month: payoutYM.month)
        .map { PayoutCandidate(job: job, window: $0, payoutDate: $0.adjustedPayoutDate) }
    }
  }

  private static func earliestCandidate(in candidates: [PayoutCandidate]) -> PayoutCandidate? {
    candidates.min { lhs, rhs in
      if lhs.payoutDate == rhs.payoutDate {
        if lhs.job.sort_order == rhs.job.sort_order {
          return lhs.job.name.localizedCompare(rhs.job.name) == .orderedAscending
        }
        return lhs.job.sort_order < rhs.job.sort_order
      }
      return lhs.payoutDate < rhs.payoutDate
    }
  }
}

enum DashboardPayrollVariantPicker {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  static func firstPayableVariants(  // swiftlint:disable:this explicit_acl
    in candidateGroups: [[PayrollCardVariant]]
  ) -> [PayrollCardVariant]? {  // swiftlint:disable:this discouraged_optional_collection
    candidateGroups.lazy
      .map { $0.filter(\.isPayableForDashboardPayroll) }
      .first { !$0.isEmpty }
  }
}

extension PayrollCardVariant {  // swiftlint:disable:this file_types_order no_grouping_extension
  var isPayableForDashboardPayroll: Bool {  // swiftlint:disable:this explicit_acl
    gross != 0
  }
}

enum DashboardPayrollAdjustmentFilter {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  /// An adjustment belongs to the payout in its month. When a job has several paydays that
  /// month (`jobPayoutDatesInMonth`), it goes to the first payday on or after its date, or the
  /// last payday if it comes after all of them.
  static func matches(  // swiftlint:disable:this explicit_acl
    _ adjustment: PayrollAdjustment,
    payoutDate: Date,
    jobPayoutDatesInMonth: [Date] = [],
    calendar: Calendar = .current
  ) -> Bool {
    guard let adjustmentDate = Date.fromISODateString(adjustment.payout_date) else {
      return adjustment.payout_date.prefix(7) == payoutDate.toISODateString().prefix(7)  // swiftlint:disable:this line_length no_magic_numbers
    }

    let adjustmentComponents = calendar.dateComponents([.year, .month], from: adjustmentDate)  // swiftlint:disable:this explicit_type_interface line_length
    let payoutComponents = calendar.dateComponents([.year, .month], from: payoutDate)  // swiftlint:disable:this explicit_type_interface line_length
    guard
      adjustmentComponents.year == payoutComponents.year
        && adjustmentComponents.month == payoutComponents.month
    else {
      return false
    }

    let paydays = jobPayoutDatesInMonth.sorted()  // swiftlint:disable:this explicit_type_interface
    guard paydays.count > 1 else { return true }  // swiftlint:disable:this conditional_returns_on_newline
    let adjustmentDay = calendar.startOfDay(for: adjustmentDate)  // swiftlint:disable:this explicit_type_interface
    let target = paydays.first { calendar.startOfDay(for: $0) >= adjustmentDay } ?? paydays.last  // swiftlint:disable:this explicit_type_interface line_length
    return target.map { calendar.isDate($0, inSameDayAs: payoutDate) } ?? true
  }
}

struct PayrollSupplementBreakdown: Identifiable, Equatable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl line_length
  let fromMin: Double  // swiftlint:disable:this explicit_acl
  let toMin: Double  // swiftlint:disable:this explicit_acl
  let rate: Double  // swiftlint:disable:this explicit_acl
  let hours: Double  // swiftlint:disable:this explicit_acl
  let amount: Double  // swiftlint:disable:this explicit_acl

  var isOvertime: Bool = false

  var id: String { "\(fromMin)-\(toMin)-\(rate)-\(isOvertime)" }  // swiftlint:disable:this explicit_acl

  var segment: SupplementSegment {  // swiftlint:disable:this explicit_acl
    SupplementSegment(
      fromMin: fromMin,
      toMin: toMin,
      rate: rate,
      actualHours: hours,
      isOvertime: isOvertime
    )
  }
}

enum PayrollAdjustmentCreationError: Error {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  case missingUser
}

// MARK: - Dashboard Error

enum DashboardError: Error, LocalizedError {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  case notAuthenticated  // swiftlint:disable:this sorted_enum_cases
  case dataLoadFailed(underlying: Error)  // swiftlint:disable:this sorted_enum_cases
  case noLocalData  // swiftlint:disable:this sorted_enum_cases

  var errorDescription: String? {  // swiftlint:disable:this explicit_acl
    switch self {
    case .notAuthenticated:
      return String(localized: .commonErrorNotAuthenticated)

    case .dataLoadFailed:
      return String(localized: .commonErrorLoadFailed)

    case .noLocalData:
      return String(localized: .commonErrorNoLocalData)
    }
  }
}

// MARK: - Month Cache Entry

/// Cache entry for a single month's computed shifts
private struct MonthCacheEntry {
  let year: Int
  let month: Int
  let shifts: [ShiftWithComputations]
  let events: [EventRow]
  let timestamp: Date
  /// Last access time for LRU eviction
  var lastAccessed: Date

  var key: String { "\(year)-\(month)" }

  /// Cache validity is managed via explicit invalidation events
  /// (sync/reload/edit, lifecycle time changes, memory pressure).
  /// Entries do not expire by fixed TTL.
  var isValid: Bool {
    true
  }

  init(
    year: Int,
    month: Int,
    shifts: [ShiftWithComputations],
    events: [EventRow],
    timestamp: Date
  ) {
    self.year = year
    self.month = month
    self.shifts = shifts
    self.events = events
    self.timestamp = timestamp
    self.lastAccessed = timestamp
  }
}

// MARK: - Dashboard View Model

@MainActor
final class DashboardViewModel: ObservableObject, MonthNavigable {  // swiftlint:disable:this explicit_acl explicit_top_level_acl line_length type_body_length

  // MARK: - Dependencies (Local-First Repositories)

  private let shiftsRepository: ShiftsRepository  // swiftlint:disable:this type_contents_order
  private let eventsRepository: EventsRepository  // swiftlint:disable:this type_contents_order
  private let jobsRepository: JobsRepository  // swiftlint:disable:this type_contents_order
  private let settingsRepository: SettingsRepository  // swiftlint:disable:this type_contents_order
  private let snapshotsRepository: SnapshotsRepository  // swiftlint:disable:this type_contents_order
  private let jobPaySetupStatusService: JobPaySetupStatusService  // swiftlint:disable:this type_contents_order
  private let payrollAdjustmentsRepository: PayrollAdjustmentsRepository  // swiftlint:disable:this type_contents_order
  private let recurringShiftsRepository: RecurringShiftsRepository  // swiftlint:disable:this type_contents_order
  private let monthlyPayrollReadService: MonthlyPayrollReadService  // swiftlint:disable:this type_contents_order
  private let syncCoordinator: SyncCoordinator  // swiftlint:disable:this type_contents_order
  private let monthContext: SharedMonthContext  // swiftlint:disable:this type_contents_order
  private let clockSessionStore: TemporaryClockSessionStore  // swiftlint:disable:this type_contents_order
  nonisolated private static let gregorianCalendar = Calendar(identifier: .gregorian)  // swiftlint:disable:this explicit_type_interface line_length type_contents_order

  private struct DashboardDataBuildInput {
    let displayedMonthShifts: [ShiftWithComputations]
    let displayedMonthEvents: [EventRow]
    let previousMonthShifts: [ShiftWithComputations]
    let previousPayrollAdjustments: [PayrollAdjustment]
    let snapshots: [WageSnapshot]
    let settings: UserSettings
    let displayYM: (year: Int, month: Int)
    let previousYM: (year: Int, month: Int)
    let currency: String
    let jobs: [Job]
  }

  private struct PayrollCardVariantBuildInput {
    let displayedMonthShifts: [ShiftWithComputations]
    let previousMonthShifts: [ShiftWithComputations]
    /// Two months before the displayed month. Needed for periods such as the 16th to the 15th
    /// paid the month after.
    var earlierMonthShifts: [ShiftWithComputations] = []
    let payrollAdjustmentsByPayoutMonth: [PayrollReadMonth: [PayrollAdjustment]]
    let previousPayrollAdjustments: [PayrollAdjustment]
    let snapshots: [WageSnapshot]
    let settings: UserSettings?
    let jobs: [Job]
    let displayYM: (year: Int, month: Int)
    let fallbackCurrency: String
    let fallbackPayrollDate: Date
    let fallbackPreviousGross: Double
    let fallbackPreviousNet: Double?
    let fallbackPreviousTax: Double?
    let fallbackPreviousTaxEnabled: Bool
    let fallbackPreviousHasPayrollAdjustments: Bool
    let now: Date
  }

  private enum PayrollCardVariantSelectionMode {
    case primary
    case previousPassedCurrentMonth
  }

  private func notifyShiftsDidChange(context: ShiftChangeContext = .fullReload) {  // swiftlint:disable:this line_length type_contents_order
    NotificationCenter.default.postShiftsDidChange(object: self, context: context)
  }

  private func shiftChangeContext(  // swiftlint:disable:this type_contents_order
    for editResult: ShiftEditResult,
    existingShift: ShiftRow?
  ) -> ShiftChangeContext {
    var dates = [editResult.shiftDate, editResult.originalDate]  // swiftlint:disable:this explicit_type_interface

    if let existingShift {
      dates.append(existingShift.shift_date)
    }

    return .affecting(isoDates: dates)
  }

  private func eventChangeContext(  // swiftlint:disable:this type_contents_order
    for editResult: EventEditResult,
    existingEvent: EventRow?
  ) -> ShiftChangeContext {
    var context = ShiftChangeContext.affecting(  // swiftlint:disable:this explicit_type_interface
      isoDateRangeStart: editResult.startDate,
      end: editResult.endDate
    )

    if let existingEvent {
      context = context.merging(
        .affecting(
          isoDateRangeStart: existingEvent.start_date,
          end: existingEvent.end_date
        ))  // swiftlint:disable:this multiline_arguments_brackets
    }

    return context
  }

  private func applyDashboardData(_ data: DashboardData) {  // swiftlint:disable:this type_contents_order
    guard dashboardData != data else { return }  // swiftlint:disable:this conditional_returns_on_newline
    dashboardData = data
  }

  private func applyDashboardData(  // swiftlint:disable:this type_contents_order
    _ data: DashboardData,
    payrollCardSnapshot snapshot: DashboardPayrollCardSnapshot
  ) {
    if payrollCardSnapshot != snapshot {
      payrollCardSnapshot = snapshot
    }
    applyDashboardData(data)
  }

  // MARK: - Published State

  @Published private(set) var dashboardData: DashboardData?  // swiftlint:disable:this explicit_acl type_contents_order
  @Published private(set) var payrollCardSnapshot: DashboardPayrollCardSnapshot?  // swiftlint:disable:this explicit_acl line_length type_contents_order
  @Published private(set) var isLoading = false  // swiftlint:disable:this explicit_acl explicit_type_interface line_length type_contents_order
  @Published private(set) var error: Error?  // swiftlint:disable:this explicit_acl type_contents_order

  enum ActiveClockState: Equatable {  // swiftlint:disable:this explicit_acl
    case none  // swiftlint:disable:this discouraged_none_name
    case temporary(TemporaryClockSession)
    case persisted(ShiftRow)
    case computed(ShiftWithComputations)
  }

  enum ClockOutRoute: Equatable {  // swiftlint:disable:this explicit_acl
    case none  // swiftlint:disable:this discouraged_none_name
    case temporaryReview(TemporaryClockSession)
    case persistedEnded
  }

  enum ClockError: LocalizedError {  // swiftlint:disable:this explicit_acl
    case invalidRange
    case noActiveSession
    case maxDurationExceeded

    var errorDescription: String? {  // swiftlint:disable:this explicit_acl
      switch self {
      case .invalidRange:
        return String(localized: .dashboardClockErrorInvalidRange)

      case .noActiveSession:
        return String(localized: .dashboardClockErrorNoActiveSession)

      case .maxDurationExceeded:
        return String(localized: .dashboardClockErrorMaxDurationExceeded)
      }
    }
  }

  @Published private(set) var activeClockState: ActiveClockState = .none  // swiftlint:disable:this explicit_acl line_length type_contents_order
  @Published private(set) var isClockActionInProgress = false  // swiftlint:disable:this explicit_acl explicit_type_interface line_length type_contents_order
  @Published private(set) var shouldShowDashboardClockButtons = true  // swiftlint:disable:this explicit_acl explicit_type_interface line_length type_contents_order

  var isClockInEnabled: Bool {  // swiftlint:disable:this explicit_acl type_contents_order
    if isClockActionInProgress || isUpdatingShift { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
    if case .none = activeClockState { return true }  // swiftlint:disable:this conditional_returns_on_newline
    return false
  }

  var isClockOutEnabled: Bool {  // swiftlint:disable:this explicit_acl type_contents_order
    if isClockActionInProgress || isUpdatingShift { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
    if case .none = activeClockState { return false }  // swiftlint:disable:this conditional_returns_on_newline
    return true
  }

  /// Direction of last navigation (for animations) - synced from SharedMonthContext
  @Published private(set) var navigationDirection: MonthNavigationDirection?  // swiftlint:disable:this explicit_acl line_length type_contents_order

  /// Currently displayed year - synced from SharedMonthContext
  var displayYear: Int { monthContext.displayYear }  // swiftlint:disable:this explicit_acl type_contents_order

  /// Currently displayed month 1-12 - synced from SharedMonthContext
  var displayMonth: Int { monthContext.displayMonth }  // swiftlint:disable:this explicit_acl type_contents_order

  /// Whether viewing the current (real) month
  var isCurrentMonth: Bool { monthContext.isCurrentMonth }  // swiftlint:disable:this explicit_acl type_contents_order

  /// Computed month name for immediate display (doesn't wait for API)
  var displayMonthName: String { monthContext.displayMonthName }  // swiftlint:disable:this explicit_acl line_length type_contents_order

  func isCurrentMonthAdvancedNextPayoutDate(  // swiftlint:disable:this explicit_acl type_contents_order
    _ payoutDate: Date,
    now: Date = Date()
  ) -> Bool {
    let current = now.yearMonth()  // swiftlint:disable:this explicit_type_interface
    let jobs = currentPayrollSelectionJobs()  // swiftlint:disable:this explicit_type_interface
    guard !jobs.isEmpty else { return false }  // swiftlint:disable:this conditional_returns_on_newline

    let fallbackPayrollDay = settings?.effectivePayrollDay ?? 15  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers
    guard
      let currentSelection = DashboardPayrollSelector.select(
        displayYM: current,
        jobs: sortedPayrollSelectionJobs(jobs, displayYM: current),
        fallbackPayrollDay: fallbackPayrollDay,
        isViewingCurrentMonth: true,
        now: now
      )
    else {
      return false
    }

    guard
      currentSelection.payoutYear != current.year
        || currentSelection.payoutMonth != current.month
    else {
      return false
    }

    return Calendar.current.isDate(currentSelection.payoutDate, inSameDayAs: payoutDate)
  }

  func currentPayrollProgressStartDate(  // swiftlint:disable:this explicit_acl type_contents_order
    for payoutDate: Date,
    now: Date = Date()
  ) -> Date? {
    let current = now.yearMonth()  // swiftlint:disable:this explicit_type_interface
    let jobs = currentPayrollSelectionJobs()  // swiftlint:disable:this explicit_type_interface
    guard !jobs.isEmpty else { return nil }  // swiftlint:disable:this conditional_returns_on_newline

    let fallbackPayrollDay = settings?.effectivePayrollDay ?? 15  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers
    let sortedJobs = sortedPayrollSelectionJobs(jobs, displayYM: current)  // swiftlint:disable:this explicit_type_interface line_length
    let selections = DashboardPayrollSelector.selections(  // swiftlint:disable:this explicit_type_interface
      displayYM: current,
      jobs: sortedJobs,
      fallbackPayrollDay: fallbackPayrollDay,
      isViewingCurrentMonth: true,
      now: now
    )

    guard
      let selection = selections.first(where: {
        Calendar.current.isDate($0.payoutDate, inSameDayAs: payoutDate)  // swiftlint:disable:this anonymous_argument_in_multiline_closure line_length
      })
    else {
      return nil
    }

    return DashboardPayrollSelector.previousPayoutStartDate(
      for: selection,
      jobs: sortedJobs,
      fallbackPayrollDay: fallbackPayrollDay
    )
  }

  func payrollCardVariants(  // swiftlint:disable:this explicit_acl type_contents_order
    fallback: DashboardData,
    defaultTitle: String
  ) -> [PayrollCardVariant] {
    let matchingSnapshot = payrollCardSnapshot.flatMap { snapshot in  // swiftlint:disable:this explicit_type_interface
      snapshot.displayedYear == fallback.displayedYear
        && snapshot.displayedMonth == fallback.displayedMonth
        ? snapshot
        : nil
    }
    let variants =  // swiftlint:disable:this explicit_type_interface
      matchingSnapshot?.variants
      ?? Self.fallbackPayrollCardVariants(fallback: fallback)
    return variants.map { $0.resolvingDefaultTitle(defaultTitle) }
  }

  func previousPayrollCardVariants(  // swiftlint:disable:this explicit_acl type_contents_order
    fallback: DashboardData,
    defaultTitle: String
  ) -> [PayrollCardVariant] {
    guard
      let snapshot = payrollCardSnapshot,
      snapshot.displayedYear == fallback.displayedYear,
      snapshot.displayedMonth == fallback.displayedMonth
    else {
      return []
    }

    return snapshot.previousPayoutVariants.map { $0.resolvingDefaultTitle(defaultTitle) }
  }

  nonisolated private static func fallbackPayrollCardVariants(  // swiftlint:disable:this type_contents_order
    fallback: DashboardData
  ) -> [PayrollCardVariant] {
    [
      PayrollCardVariant(
        id: "default",
        title: "",
        colorHex: nil,
        usesDefaultTitle: true,
        badges: [],
        currency: fallback.currency,
        payoutDate: fallback.payrollDate,
        gross: fallback.previousMonthGross,
        net: fallback.previousMonthNet,
        tax: fallback.previousMonthTax,
        taxEnabled: fallback.previousMonthTaxEnabled,
        hasPayrollAdjustments: fallback.previousMonthHasPayrollAdjustments,
        jobBreakdowns: []
      )
    ]
  }

  nonisolated private static func buildPayrollCardVariants(  // swiftlint:disable:this cyclomatic_complexity function_body_length line_length type_contents_order
    _ input: PayrollCardVariantBuildInput,
    defaultTitle: String = "",
    selectionMode: PayrollCardVariantSelectionMode = .primary
  ) -> [PayrollCardVariant] {
    let displayedMonthShifts = input.displayedMonthShifts  // swiftlint:disable:this explicit_type_interface
    let previousMonthShifts = input.previousMonthShifts  // swiftlint:disable:this explicit_type_interface
    // Pay periods can reach two months back, so search all three loaded months.
    let payoutShiftPool = displayedMonthShifts + previousMonthShifts + input.earlierMonthShifts  // swiftlint:disable:this explicit_type_interface line_length
    let payrollAdjustmentsByPayoutMonth = input.payrollAdjustmentsByPayoutMonth  // swiftlint:disable:this explicit_type_interface line_length
    let previousPayrollAdjustments = input.previousPayrollAdjustments  // swiftlint:disable:this explicit_type_interface
    let snapshots = input.snapshots  // swiftlint:disable:this explicit_type_interface
    let settings = input.settings  // swiftlint:disable:this explicit_type_interface
    let jobs = input.jobs  // swiftlint:disable:this explicit_type_interface
    let displayYM = input.displayYM  // swiftlint:disable:this explicit_type_interface
    let fallbackCurrency = input.fallbackCurrency  // swiftlint:disable:this explicit_type_interface
    let fallbackPayrollDate = input.fallbackPayrollDate  // swiftlint:disable:this explicit_type_interface
    let fallbackPreviousGross = input.fallbackPreviousGross  // swiftlint:disable:this explicit_type_interface
    let fallbackPreviousNet = input.fallbackPreviousNet  // swiftlint:disable:this explicit_type_interface
    let fallbackPreviousTax = input.fallbackPreviousTax  // swiftlint:disable:this explicit_type_interface
    let fallbackPreviousTaxEnabled = input.fallbackPreviousTaxEnabled  // swiftlint:disable:this explicit_type_interface
    let fallbackPreviousHasPayrollAdjustments = input.fallbackPreviousHasPayrollAdjustments  // swiftlint:disable:this explicit_type_interface line_length
    let now = input.now  // swiftlint:disable:this explicit_type_interface

    func fallbackVariant() -> [PayrollCardVariant] {
      [
        PayrollCardVariant(
          id: "default",
          title: defaultTitle,
          colorHex: nil,
          usesDefaultTitle: true,
          badges: [],
          currency: fallbackCurrency,
          payoutDate: fallbackPayrollDate,
          gross: fallbackPreviousGross,
          net: fallbackPreviousNet,
          tax: fallbackPreviousTax,
          taxEnabled: fallbackPreviousTaxEnabled,
          hasPayrollAdjustments: fallbackPreviousHasPayrollAdjustments,
          jobBreakdowns: []
        )
      ]
    }

    guard let settings, !jobs.isEmpty else {
      return selectionMode == .primary ? fallbackVariant() : []
    }

    let fallbackPayrollDay = settings.effectivePayrollDay  // swiftlint:disable:this explicit_type_interface
    let halfTaxMonth = settings.half_tax_month  // swiftlint:disable:this explicit_type_interface
    let defaultJobId = jobs.first(where: \.is_default)?.id  // swiftlint:disable:this explicit_type_interface
    let sortedJobs = sortedPayrollSelectionJobs(  // swiftlint:disable:this explicit_type_interface
      jobs,
      displayYM: displayYM,
      fallbackPayrollDay: fallbackPayrollDay
    )

    let current = now.yearMonth()  // swiftlint:disable:this explicit_type_interface
    let isViewingCurrentMonth =  // swiftlint:disable:this explicit_type_interface
      displayYM.year == current.year && displayYM.month == current.month
    let candidateSelections: [DashboardPayrollSelection] = {
      switch selectionMode {
      case .primary:
        return DashboardPayrollSelector.selections(
          displayYM: displayYM,
          jobs: sortedJobs,
          fallbackPayrollDay: fallbackPayrollDay,
          isViewingCurrentMonth: isViewingCurrentMonth,
          now: now
        )

      case .previousPassedCurrentMonth:
        guard isViewingCurrentMonth else { return [] }  // swiftlint:disable:this conditional_returns_on_newline
        return DashboardPayrollSelector.previousPassedSelections(
          displayYM: displayYM,
          jobs: sortedJobs,
          fallbackPayrollDay: fallbackPayrollDay,
          now: now
        )
      }
    }()

    let candidateJobVariantGroups = candidateSelections.map { selection in  // swiftlint:disable:this closure_body_length explicit_type_interface line_length
      let selectedJobIds = Set(selection.jobIds)  // swiftlint:disable:this explicit_type_interface
      let selectedJobs = sortedJobs.filter { selectedJobIds.contains($0.id) }  // swiftlint:disable:this explicit_type_interface line_length
      let payoutYM = (year: selection.payoutYear, month: selection.payoutMonth)  // swiftlint:disable:this explicit_type_interface line_length
      let selectedPayoutAdjustments = payrollAdjustments(  // swiftlint:disable:this explicit_type_interface
        forPayoutYM: (year: selection.payoutYear, month: selection.payoutMonth),
        renderedDisplayYM: displayYM,
        payrollAdjustmentsByPayoutMonth: payrollAdjustmentsByPayoutMonth,
        previousPayrollAdjustments: previousPayrollAdjustments
      )
      let payoutDate = selection.payoutDate  // swiftlint:disable:this explicit_type_interface

      return selectedJobs.compactMap { job -> PayrollCardVariant? in  // swiftlint:disable:this closure_body_length
        guard let window = selection.windowsByJobId[job.id] else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length
        let schedule = PayoutSchedule(job: job, fallbackPayrollDay: fallbackPayrollDay)  // swiftlint:disable:this explicit_type_interface line_length
        let jobShifts = payoutShiftPool.filter { shift in  // swiftlint:disable:this explicit_type_interface
          guard window.contains(shift.shiftDate) else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
          guard let shiftJobId = shift.shift.job_id else {
            return job.id == defaultJobId
          }
          return shiftJobId == job.id
        }

        let totals = PayrollEngine.summarizeShiftTotals(  // swiftlint:disable:this explicit_type_interface
          shifts: jobShifts,
          halfTaxMonth: job.half_tax_month,
          earningsMonth: Date.previousYearMonth(from: payoutYM).month,
          now: now
        )
        let jobPaydaysInMonth = schedule  // swiftlint:disable:this explicit_type_interface
          .windows(paidInYear: payoutYM.year, month: payoutYM.month)
          .map(\.adjustedPayoutDate)
        let jobAdjustments = selectedPayoutAdjustments.filter { adjustment in  // swiftlint:disable:this explicit_type_interface line_length
          guard
            DashboardPayrollAdjustmentFilter.matches(
              adjustment, payoutDate: payoutDate, jobPayoutDatesInMonth: jobPaydaysInMonth)
          else {
            return false
          }
          guard let adjustmentJobId = adjustment.job_id else {
            return job.id == defaultJobId
          }
          return adjustmentJobId == job.id
        }
        let fallbackTaxSettings = payrollTaxSettings(  // swiftlint:disable:this explicit_type_interface
          from: jobShifts,
          fallbackDate: window.payoutDate,
          snapshots: snapshots,
          jobs: jobs,
          jobId: job.id
        )
        let adjustmentTotals = PayrollAdjustmentCalculator.totals(  // swiftlint:disable:this explicit_type_interface
          adjustments: jobAdjustments,
          taxSettings: { adjustment in
            payrollTaxSettings(
              for: adjustment,
              fallback: fallbackTaxSettings,
              snapshots: snapshots,
              jobs: jobs,
              jobId: job.id,
              defaultJobId: defaultJobId
            )
          },
          halfTaxMonth: halfTaxMonth,
          payoutMonth: selection.payoutMonth,
          jobs: jobs
        )
        let taxEnabled: Bool =
          jobShifts.contains(where: \.taxEnabled) || adjustmentTotals.taxEnabled
        let shiftBasePay = jobShifts.reduce(0) { total, shift in  // swiftlint:disable:this explicit_type_interface
          total + displayedBasePay(for: shift)
        }
        let shiftSupplementPay: Double = jobShifts.reduce(0) { total, shift in
          total + displayedSupplementPay(for: shift)
        }
        let supplementBreakdowns: [PayrollSupplementBreakdown] = payrollSupplementBreakdowns(
          for: jobShifts
        )
        let shiftPostDeductions = jobShifts.reduce(0) { total, shift in  // swiftlint:disable:this explicit_type_interface line_length
          total + breakDeductionAmount(for: shift)
        }
        let postDeductionParts = payrollBreakDeductionParts(for: jobShifts)  // swiftlint:disable:this explicit_type_interface line_length
        let gross = totals.gross + adjustmentTotals.gross  // swiftlint:disable:this explicit_type_interface
        let net = totals.net + adjustmentTotals.net  // swiftlint:disable:this explicit_type_interface
        let tax = taxEnabled ? gross - net : nil  // swiftlint:disable:this explicit_type_interface

        return PayrollCardVariant(
          id: job.id,
          title: job.name,
          colorHex: job.color,
          badges: [
            PayrollCardBadge(
              id: job.id,
              title: job.name,
              colorHex: job.color
            )
          ],
          currency: job.currency,
          payoutDate: payoutDate,
          gross: gross,
          net: taxEnabled ? net : nil,
          tax: tax,
          taxEnabled: taxEnabled,
          hasPayrollAdjustments: !jobAdjustments.isEmpty,
          jobBreakdowns: [
            PayrollCardJobBreakdown(
              id: job.id,
              title: job.name,
              colorHex: job.color,
              currency: job.currency,
              basePay: shiftBasePay,
              supplementPay: shiftSupplementPay,
              supplementBreakdowns: supplementBreakdowns,
              postDeductions: shiftPostDeductions,
              postDeductionParts: postDeductionParts,
              payoutDate: payoutDate,
              gross: gross,
              net: taxEnabled ? net : nil,
              tax: tax,
              taxEnabled: taxEnabled,
              adjustments: jobAdjustments,
              earningsPeriodStart: Date.fromISODateString(window.start),
              earningsPeriodEnd: Date.fromISODateString(window.end),
              payoutTaxSettings: fallbackTaxSettings.adjusted(
                payoutMonth: selection.payoutMonth, halfTaxMonth: job.half_tax_month)
            )
          ]
        )
      }
    }

    let selectedPayoutJobs =  // swiftlint:disable:this explicit_type_interface
      DashboardPayrollVariantPicker.firstPayableVariants(in: candidateJobVariantGroups)
      ?? candidateJobVariantGroups.first { !$0.isEmpty }

    guard let selectedPayoutJobs, let payoutDate = selectedPayoutJobs.first?.payoutDate else {
      return selectionMode == .primary ? fallbackVariant() : []
    }

    guard selectedPayoutJobs.count > 1 else {
      guard let selectedPayoutJob = selectedPayoutJobs.first else { return [] }  // swiftlint:disable:this conditional_returns_on_newline line_length
      let usesDefaultTitle = jobs.count <= 1  // swiftlint:disable:this explicit_type_interface
      return [
        PayrollCardVariant(
          id: selectedPayoutJob.id,
          title: usesDefaultTitle ? defaultTitle : selectedPayoutJob.title,
          colorHex: usesDefaultTitle ? nil : selectedPayoutJob.colorHex,
          usesDefaultTitle: usesDefaultTitle,
          badges: usesDefaultTitle ? [] : selectedPayoutJob.badges,
          currency: selectedPayoutJob.currency,
          payoutDate: selectedPayoutJob.payoutDate,
          gross: selectedPayoutJob.gross,
          net: selectedPayoutJob.net,
          tax: selectedPayoutJob.tax,
          taxEnabled: selectedPayoutJob.taxEnabled,
          hasPayrollAdjustments: selectedPayoutJob.hasPayrollAdjustments,
          jobBreakdowns: selectedPayoutJob.jobBreakdowns
        )
      ]
    }

    let taxEnabled = selectedPayoutJobs.contains(where: \.taxEnabled)  // swiftlint:disable:this explicit_type_interface
    let gross = selectedPayoutJobs.reduce(0) { $0 + $1.gross }  // swiftlint:disable:this explicit_type_interface
    let net = selectedPayoutJobs.reduce(0) { $0 + ($1.net ?? $1.gross) }  // swiftlint:disable:this explicit_type_interface
    let tax = taxEnabled ? gross - net : nil  // swiftlint:disable:this explicit_type_interface

    return [
      PayrollCardVariant(
        id: "payout-\(payoutDate.timeIntervalSince1970)",
        title: defaultTitle,
        colorHex: nil,
        usesDefaultTitle: true,
        badges: selectedPayoutJobs.flatMap(\.badges),
        currency: selectedPayoutJobs.first?.currency ?? fallbackCurrency,
        payoutDate: payoutDate,
        gross: gross,
        net: taxEnabled ? net : nil,
        tax: tax,
        taxEnabled: taxEnabled,
        hasPayrollAdjustments: selectedPayoutJobs.contains(where: \.hasPayrollAdjustments),
        jobBreakdowns: selectedPayoutJobs.flatMap(\.jobBreakdowns)
      )
    ]
  }

  nonisolated private static func buildPayrollCardSnapshot(  // swiftlint:disable:this type_contents_order
    _ input: PayrollCardVariantBuildInput
  ) -> DashboardPayrollCardSnapshot {
    DashboardPayrollCardSnapshot(
      displayedYear: input.displayYM.year,
      displayedMonth: input.displayYM.month,
      variants: buildPayrollCardVariants(input),
      previousPayoutVariants: buildPayrollCardVariants(
        input,
        defaultTitle: String(localized: .dashboardPreviousPayout),
        selectionMode: .previousPassedCurrentMonth
      )
    )
  }

  func createPayrollAdjustment(  // swiftlint:disable:this explicit_acl type_contents_order
    _ draft: PayrollAdjustmentDraft
  ) async throws -> PayrollAdjustment {
    guard let userId = resolveUserIdForPayrollVariants() else {
      throw PayrollAdjustmentCreationError.missingUser
    }

    let adjustment = try await payrollAdjustmentsRepository.createAdjustment(  // swiftlint:disable:this explicit_type_interface line_length
      userId: userId,
      jobId: draft.jobId,
      amount: draft.amount,
      currency: draft.currency,
      category: draft.category,
      taxTreatment: draft.taxTreatment,
      description: draft.description,
      note: draft.note,
      earnedFromDate: draft.earnedFromDate,
      earnedToDate: draft.earnedToDate,
      payoutDate: draft.payoutDate
    )

    await loadDashboardFromLocal(showLoadingState: false)
    return adjustment
  }

  func updatePayrollAdjustment(_ id: String, _ draft: PayrollAdjustmentDraft) async throws  // swiftlint:disable:this explicit_acl line_length type_contents_order
    -> PayrollAdjustment
  {
    guard let userId = resolveUserIdForPayrollVariants() else {
      throw PayrollAdjustmentCreationError.missingUser
    }

    let adjustment = try await payrollAdjustmentsRepository.updateAdjustment(  // swiftlint:disable:this explicit_type_interface line_length
      id: id,
      userId: userId,
      jobId: draft.jobId,
      amount: draft.amount,
      currency: draft.currency,
      category: draft.category,
      taxTreatment: draft.taxTreatment,
      description: draft.description,
      note: draft.note,
      earnedFromDate: draft.earnedFromDate,
      earnedToDate: draft.earnedToDate,
      payoutDate: draft.payoutDate
    )

    await loadDashboardFromLocal(showLoadingState: false)
    return adjustment
  }

  func deletePayrollAdjustment(id: String) async throws {  // swiftlint:disable:this explicit_acl type_contents_order
    guard let userId = resolveUserIdForPayrollVariants() else {
      throw PayrollAdjustmentCreationError.missingUser
    }

    try await payrollAdjustmentsRepository.deleteAdjustment(id: id, userId: userId)
    await loadDashboardFromLocal(showLoadingState: false)
  }

  /// Resolve a stable user ID for payroll card variants while reload is in-flight.
  /// This prevents a transient fallback to single-card UI during `cachedUserId` resets.
  private func resolveUserIdForPayrollVariants() -> String? {  // swiftlint:disable:this type_contents_order
    if let cachedUserId, !cachedUserId.isEmpty {
      return cachedUserId
    }

    if let settingsUserId = settings?.user_id, !settingsUserId.isEmpty {
      return settingsUserId
    }

    if let coordinatorUserId = AppCoordinator.shared.getCurrentUserId(), !coordinatorUserId.isEmpty
    {
      return coordinatorUserId
    }

    return nil
  }

  private func currentPayrollSelectionJobs() -> [Job] {  // swiftlint:disable:this type_contents_order
    if !displayJobs.isEmpty {
      return displayJobs
    }

    guard let userId = resolveUserIdForPayrollVariants() else { return [] }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return jobsRepository.getNonDeletedJobs(for: userId)
  }

  private func sortedPayrollSelectionJobs(  // swiftlint:disable:this type_contents_order
    _ jobs: [Job],
    displayYM: (year: Int, month: Int)
  ) -> [Job] {
    let fallbackPayrollDay = settings?.effectivePayrollDay ?? 15  // swiftlint:disable:this explicit_type_interface line_length no_magic_numbers

    return Self.sortedPayrollSelectionJobs(
      jobs,
      displayYM: displayYM,
      fallbackPayrollDay: fallbackPayrollDay
    )
  }

  nonisolated private static func sortedPayrollSelectionJobs(  // swiftlint:disable:this type_contents_order
    _ jobs: [Job],
    displayYM: (year: Int, month: Int),
    fallbackPayrollDay: Int
  ) -> [Job] {
    jobs.sorted { lhs, rhs in
      let lhsPayout = PayrollDateAdjuster.adjustPayrollDate(  // swiftlint:disable:this explicit_type_interface
        payrollDay: lhs.payroll_day ?? fallbackPayrollDay,
        month: displayYM.month,
        year: displayYM.year
      )
      let rhsPayout = PayrollDateAdjuster.adjustPayrollDate(  // swiftlint:disable:this explicit_type_interface
        payrollDay: rhs.payroll_day ?? fallbackPayrollDay,
        month: displayYM.month,
        year: displayYM.year
      )

      if lhsPayout == rhsPayout {
        if lhs.sort_order == rhs.sort_order {
          return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
        return lhs.sort_order < rhs.sort_order
      }

      return lhsPayout < rhsPayout
    }
  }

  nonisolated private static func payrollAdjustments(  // swiftlint:disable:this type_contents_order
    forPayoutYM payoutYM: (year: Int, month: Int),
    renderedDisplayYM displayYM: (year: Int, month: Int),
    payrollAdjustmentsByPayoutMonth: [PayrollReadMonth: [PayrollAdjustment]],
    previousPayrollAdjustments: [PayrollAdjustment]
  ) -> [PayrollAdjustment] {
    let key = PayrollReadMonth(year: payoutYM.year, month: payoutYM.month)  // swiftlint:disable:this explicit_type_interface line_length
    if let adjustments = payrollAdjustmentsByPayoutMonth[key] {
      return adjustments
    }

    if payoutYM.year == displayYM.year, payoutYM.month == displayYM.month {
      return previousPayrollAdjustments
    }

    return []
  }

  nonisolated private static func displayedBasePay(  // swiftlint:disable:this type_contents_order
    for shift: ShiftWithComputations
  ) -> Double {
    breakDeductionAmount(for: shift) > 0
      ? BreakDeductionBreakdown.basePay(for: shift.computed.preBreakWagePeriods)
      : shift.computed.basePay
  }

  nonisolated private static func displayedSupplementPay(  // swiftlint:disable:this type_contents_order
    for shift: ShiftWithComputations
  ) -> Double {
    breakDeductionAmount(for: shift) > 0
      ? BreakDeductionBreakdown.supplementPay(for: shift.computed.preBreakWagePeriods)
      : shift.computed.supplementPay
  }

  nonisolated private static func breakDeductionAmount(  // swiftlint:disable:this type_contents_order
    for shift: ShiftWithComputations
  ) -> Double {
    guard shift.computed.breakAudit.deductedHours > 0 else {
      return 0
    }
    return BreakDeductionBreakdown.make(
      originalPeriods: shift.computed.preBreakWagePeriods,
      adjustedPeriods: shift.computed.wagePeriods
    )?.totalAmount ?? 0
  }

  nonisolated private static func payrollBreakDeductionParts(for shifts: [ShiftWithComputations])  // swiftlint:disable:this function_body_length line_length type_contents_order
    -> [BreakDeductionPart]
  {
    let parts = shifts.flatMap { shift -> [BreakDeductionPart] in  // swiftlint:disable:this explicit_type_interface
      guard shift.computed.breakAudit.deductedHours > 0 else { return [] }  // swiftlint:disable:this conditional_returns_on_newline line_length
      return BreakDeductionBreakdown.make(
        originalPeriods: shift.computed.preBreakWagePeriods,
        adjustedPeriods: shift.computed.wagePeriods
      )?.parts ?? []
    }

    var grouped: [String: BreakDeductionPart] = [:]

    for part in parts {
      let key: String
      switch part.kind {
      case .base:
        key = "base"

      case .supplement:
        key = "supplement-\(part.supplementSegment?.id ?? "\(part.rate ?? 0)")"
      }

      if let existing = grouped[key] {
        let hours = existing.hours + part.hours  // swiftlint:disable:this explicit_type_interface
        let amount = existing.amount + part.amount  // swiftlint:disable:this explicit_type_interface
        grouped[key] = BreakDeductionPart(
          id: key,
          kind: existing.kind,
          supplementSegment: existing.supplementSegment.map {
            SupplementSegment(
              fromMin: $0.fromMin,  // swiftlint:disable:this anonymous_argument_in_multiline_closure
              toMin: $0.toMin,  // swiftlint:disable:this anonymous_argument_in_multiline_closure
              rate: $0.rate,  // swiftlint:disable:this anonymous_argument_in_multiline_closure
              actualHours: hours
            )
          },
          hours: hours,
          rate: hours > 0 ? amount / hours : existing.rate,
          amount: amount
        )
      } else {
        grouped[key] = BreakDeductionPart(
          id: key,
          kind: part.kind,
          supplementSegment: part.supplementSegment,
          hours: part.hours,
          rate: part.rate,
          amount: part.amount
        )
      }
    }

    return grouped.values.sorted { lhs, rhs in
      if lhs.kind != rhs.kind {
        return lhs.kind == .base
      }
      return lhs.id < rhs.id
    }
  }

  nonisolated private static func payrollSupplementBreakdowns(for shifts: [ShiftWithComputations])
    -> [PayrollSupplementBreakdown]
  {
    let segments = shifts.flatMap { shift -> [SupplementSegment] in
      let periods =
        shift.computed.breakAudit.deductedHours > 0
        ? shift.computed.preBreakWagePeriods : shift.computed.classifiedWagePeriods
      return SupplementSegment.grouped(from: periods)
    }

    let grouped = segments.reduce(  // swiftlint:disable:this explicit_type_interface
      into: [
        String: (fromMin: Double, toMin: Double, rate: Double, hours: Double, isOvertime: Bool)
      ]()
    ) { result, segment in
      let key = segment.id  // swiftlint:disable:this explicit_type_interface
      result[key, default: (segment.fromMin, segment.toMin, segment.rate, 0, segment.isOvertime)]
        .hours +=
        segment.actualHours
    }

    return grouped.values.map { segment in
      PayrollSupplementBreakdown(
        fromMin: segment.fromMin,
        toMin: segment.toMin,
        rate: segment.rate,
        hours: segment.hours,
        amount: segment.hours * segment.rate,
        isOvertime: segment.isOvertime
      )
    }
    .sorted { lhs, rhs in
      if lhs.fromMin == rhs.fromMin {
        if lhs.toMin == rhs.toMin {
          return lhs.rate < rhs.rate
        }
        return lhs.toMin < rhs.toMin
      }
      return lhs.fromMin < rhs.fromMin
    }
  }

  // MARK: - User Profile Data (for UserMenuButton)

  /// User's display name (derived from email or metadata)
  @Published private(set) var userDisplayName: String = ""  // swiftlint:disable:this explicit_acl type_contents_order
  /// User's profile picture URL
  @Published private(set) var userAvatarUrl: String?  // swiftlint:disable:this explicit_acl type_contents_order
  /// All non-deleted jobs used for dashboard workplace metadata.
  @Published private(set) var displayJobs: [Job] = []  // swiftlint:disable:this explicit_acl type_contents_order

  var shouldShowJobIndicators: Bool {  // swiftlint:disable:this explicit_acl type_contents_order
    displayJobs.count > 1
  }

  func jobForShift(_ shift: ShiftWithComputations) -> Job? {  // swiftlint:disable:this explicit_acl type_contents_order
    let defaultJobId = displayJobs.first(where: \.is_default)?.id  // swiftlint:disable:this explicit_type_interface
    let effectiveJobId = shift.shift.job_id ?? defaultJobId  // swiftlint:disable:this explicit_type_interface
    guard let effectiveJobId else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    return displayJobs.first(where: { $0.id == effectiveJobId })
  }

  func jobForTemporarySession(_ session: TemporaryClockSession) -> Job? {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    let defaultJobId = displayJobs.first(where: \.is_default)?.id  // swiftlint:disable:this explicit_type_interface
    let effectiveJobId = session.jobId ?? defaultJobId  // swiftlint:disable:this explicit_type_interface
    guard let effectiveJobId else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    return displayJobs.first(where: { $0.id == effectiveJobId })
  }

  // MARK: - Private State

  private var displayedMonthShifts: [ShiftWithComputations] = []  // swiftlint:disable:this type_contents_order
  private var displayedMonthEvents: [EventRow] = []  // swiftlint:disable:this type_contents_order
  private var previousMonthShifts: [ShiftWithComputations] = []  // swiftlint:disable:this type_contents_order
  private var previousPayrollAdjustments: [PayrollAdjustment] = []  // swiftlint:disable:this type_contents_order
  private var payrollAdjustmentsByPayoutMonth: [PayrollReadMonth: [PayrollAdjustment]] = [:]  // swiftlint:disable:this line_length type_contents_order
  private var settings: UserSettings?  // swiftlint:disable:this type_contents_order
  private var snapshots: [WageSnapshot] = []  // swiftlint:disable:this type_contents_order
  private var recurringShifts: [RecurringShiftRow] = []  // swiftlint:disable:this type_contents_order
  private var dashboardDependenciesLoaded = false  // swiftlint:disable:this explicit_type_interface type_contents_order
  private var cachedUserId: String?  // swiftlint:disable:this type_contents_order
  private var isActiveTabVisible = true  // swiftlint:disable:this explicit_type_interface type_contents_order
  private var localDataNeedsReload = false  // swiftlint:disable:this explicit_type_interface type_contents_order
  private var displayedMonthLoadPending = false  // swiftlint:disable:this explicit_type_interface type_contents_order

  /// Subscription to SharedMonthContext changes
  private var monthContextCancellable: AnyCancellable?  // swiftlint:disable:this type_contents_order

  /// Track the last observed month to detect changes
  private var lastObservedYear: Int = 0  // swiftlint:disable:this type_contents_order
  private var lastObservedMonth: Int = 0  // swiftlint:disable:this type_contents_order

  // MARK: - Month Cache

  /// Cache of computed shifts by month key (e.g., "2025-1")
  private var monthCache: [String: MonthCacheEntry] = [:]  // swiftlint:disable:this type_contents_order

  /// Maximum number of months to keep in cache (prevents unbounded memory growth)
  private static let maxCacheSize = 12  // swiftlint:disable:this explicit_type_interface

  /// Background prefetch tasks keyed by month cache key and invalidation token
  /// (to avoid duplicate fetches and stale writes after invalidation).
  private var prefetchTasks: [String: Int] = [:]

  /// Per-month invalidation tokens used to discard stale background prefetch results.
  private var monthCacheInvalidationTokens: [String: Int] = [:]

  /// Tracks initial-sync transitions so the first post-sync local reload remains a full reset.
  private var hasObservedInitialSyncCompletion = false  // swiftlint:disable:this explicit_type_interface

  /// Memory warning observer
  private var memoryWarningObserver: NSObjectProtocol?
  /// App lifecycle observer for foreground transitions
  private var foregroundObserver: NSObjectProtocol?
  /// Observer for significant time changes (midnight, timezone, DST, etc.)
  private var significantTimeObserver: NSObjectProtocol?

  // MARK: - Initialization

  init(  // swiftlint:disable:this explicit_acl function_body_length type_contents_order
    shiftsRepository: ShiftsRepository? = nil,
    eventsRepository: EventsRepository? = nil,
    jobsRepository: JobsRepository? = nil,
    settingsRepository: SettingsRepository? = nil,
    snapshotsRepository: SnapshotsRepository? = nil,
    jobPaySetupStatusService: JobPaySetupStatusService? = nil,
    payrollAdjustmentsRepository: PayrollAdjustmentsRepository? = nil,
    recurringShiftsRepository: RecurringShiftsRepository? = nil,
    monthlyPayrollReadService: MonthlyPayrollReadService? = nil,
    syncCoordinator: SyncCoordinator? = nil,
    monthContext: SharedMonthContext? = nil,
    clockSessionStore: TemporaryClockSessionStore? = nil
  ) {
    // Use provided repositories or default to shared instances
    // Using optional parameters avoids Swift 6 MainActor isolation errors
    self.shiftsRepository = shiftsRepository ?? ShiftsRepository.shared
    self.eventsRepository = eventsRepository ?? EventsRepository.shared
    self.jobsRepository = jobsRepository ?? JobsRepository.shared
    self.settingsRepository = settingsRepository ?? SettingsRepository.shared
    self.snapshotsRepository = snapshotsRepository ?? SnapshotsRepository.shared
    self.jobPaySetupStatusService = jobPaySetupStatusService ?? JobPaySetupStatusService.shared
    self.payrollAdjustmentsRepository =
      payrollAdjustmentsRepository ?? PayrollAdjustmentsRepository.shared
    self.recurringShiftsRepository = recurringShiftsRepository ?? RecurringShiftsRepository.shared
    self.monthlyPayrollReadService =
      monthlyPayrollReadService
      ?? MonthlyPayrollReadService(
        shiftsRepository: self.shiftsRepository,
        eventsRepository: self.eventsRepository,
        settingsRepository: self.settingsRepository,
        snapshotsRepository: self.snapshotsRepository,
        recurringShiftsRepository: self.recurringShiftsRepository,
        jobsRepository: self.jobsRepository
      )
    self.syncCoordinator = syncCoordinator ?? SyncCoordinator.shared
    self.monthContext = monthContext ?? SharedMonthContext.shared
    self.clockSessionStore = clockSessionStore ?? TemporaryClockSessionStore.shared

    // Initialize tracking to current month context values
    self.lastObservedYear = self.monthContext.displayYear
    self.lastObservedMonth = self.monthContext.displayMonth
    self.hasObservedInitialSyncCompletion = AppCoordinator.shared.initialSyncComplete

    seedLayoutPreferencesFromLocalSettings()

    // Subscribe to month context changes
    setupMonthContextSubscription()

    // Listen for memory warnings to clear cache
    memoryWarningObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didReceiveMemoryWarningNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.handleMemoryWarning()
      }
    }

    // Invalidate current-month cache when returning to foreground so time-based
    // fields (completed shifts, next shift selection, payroll status) refresh.
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willEnterForegroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.invalidateCurrentMonthCache(reason: "foreground")
      }
    }

    // Invalidate on significant wall-clock changes (e.g. midnight rollover).
    significantTimeObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.significantTimeChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.invalidateCurrentMonthCache(reason: "significant-time-change")
      }
    }
  }

  private func seedLayoutPreferencesFromLocalSettings() {  // swiftlint:disable:this type_contents_order
    guard
      let userId = AppCoordinator.shared.getCurrentUserId(),
      !userId.isEmpty,
      let localSettings = settingsRepository.getSettings(for: userId)
    else {
      return
    }

    cachedUserId = userId
    settings = localSettings
    shouldShowDashboardClockButtons = localSettings.effectiveShowDashboardClockButtons
  }

  /// Subscribe to SharedMonthContext changes to reload data when month changes
  private func setupMonthContextSubscription() {  // swiftlint:disable:this type_contents_order
    monthContextCancellable = monthContext.monthChanged
      .receive(on: DispatchQueue.main)
      .sink { [weak self] newMonth in
        guard let self else { return }  // swiftlint:disable:this conditional_returns_on_newline

        // Only reload if month actually changed
        guard newMonth.year != lastObservedYear || newMonth.month != lastObservedMonth
        else {
          return
        }

        // Update tracking
        lastObservedYear = newMonth.year
        lastObservedMonth = newMonth.month

        // Sync navigation direction from context
        navigationDirection = monthContext.navigationDirection

        guard isActiveTabVisible else {
          displayedMonthLoadPending = true
          logger.info("⏸️ Deferring dashboard month load while Home tab is hidden")
          return
        }

        // Trigger data reload for new month
        loadDashboardForDisplayedMonthNonBlocking()
      }
  }

  deinit {  // swiftlint:disable:this type_contents_order
    // Cancel Combine subscriptions to prevent memory leaks
    monthContextCancellable?.cancel()

    // Cancel any active navigation task to prevent orphaned operations
    activeNavigationTask?.cancel()

    if let observer = memoryWarningObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    if let observer = foregroundObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    if let observer = significantTimeObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  // MARK: - Memory Management

  /// Handle memory warning by clearing the cache
  private func handleMemoryWarning() {  // swiftlint:disable:this type_contents_order
    logger.warning(
      "⚠️ Memory warning received - clearing month cache (\(self.monthCache.count) entries)")  // swiftlint:disable:this line_length multiline_arguments_brackets
    clearAllMonthCache(reason: "memory-warning")
  }

  /// Invalidate cache entries for the real current month.
  /// Keeps historical months hot while ensuring time-dependent current-month
  /// dashboard values are recomputed on next access.
  private func invalidateCurrentMonthCache(reason: String) {  // swiftlint:disable:this type_contents_order
    let current = Date.currentYearMonth()  // swiftlint:disable:this explicit_type_interface
    let key = monthCacheKey(year: current.year, month: current.month)  // swiftlint:disable:this explicit_type_interface
    let removedCount = invalidateMonthCacheEntries(for: [key], reason: reason)  // swiftlint:disable:this explicit_type_interface line_length
    guard removedCount > 0 else { return }  // swiftlint:disable:this conditional_returns_on_newline

    logger.info("♻️ Invalidated current-month cache (\(reason)): \(key)")

    // If the user is viewing the invalidated month, trigger a background
    // reload so the dashboard reflects updated time-based fields immediately.
    if displayYear == current.year, displayMonth == current.month {
      loadDashboardForDisplayedMonthNonBlocking()
    }
  }

  private func monthCacheKey(year: Int, month: Int) -> String {  // swiftlint:disable:this type_contents_order
    "\(year)-\(month)"
  }

  private func monthCacheKey(_ yearMonth: (year: Int, month: Int)) -> String {  // swiftlint:disable:this line_length type_contents_order
    monthCacheKey(year: yearMonth.year, month: yearMonth.month)
  }

  private func movingWindowCacheKeys(around displayYM: (year: Int, month: Int)) -> Set<String> {  // swiftlint:disable:this line_length type_contents_order
    let previousYM = Date.previousYearMonth(from: displayYM)  // swiftlint:disable:this explicit_type_interface
    let nextYM = nextYearMonth(from: displayYM)  // swiftlint:disable:this explicit_type_interface
    let previousPreviousYM = Date.previousYearMonth(from: previousYM)  // swiftlint:disable:this explicit_type_interface
    let nextPreviousYM = Date.previousYearMonth(from: nextYM)  // swiftlint:disable:this explicit_type_interface

    return Set([
      monthCacheKey(displayYM),
      monthCacheKey(previousYM),
      monthCacheKey(nextYM),
      monthCacheKey(previousPreviousYM),
      monthCacheKey(nextPreviousYM),
    ])
  }

  @discardableResult
  private func invalidateMonthCacheEntries(for keys: Set<String>, reason: String) -> Int {  // swiftlint:disable:this line_length type_contents_order
    guard !keys.isEmpty else { return 0 }  // swiftlint:disable:this conditional_returns_on_newline

    incrementMonthCacheInvalidationTokens(for: keys)

    var removedCount = 0  // swiftlint:disable:this explicit_type_interface
    for key in keys {
      if monthCache.removeValue(forKey: key) != nil {
        removedCount += 1
      }
      prefetchTasks.removeValue(forKey: key)
    }

    if removedCount > 0 {
      logger.info("♻️ Invalidated \(removedCount) dashboard cache entries (\(reason))")
    }

    return removedCount
  }

  private func invalidateMovingWindowCache(reason: String) {  // swiftlint:disable:this type_contents_order
    let keys = movingWindowCacheKeys(around: (year: displayYear, month: displayMonth))  // swiftlint:disable:this explicit_type_interface line_length
    let removedCount = invalidateMonthCacheEntries(for: keys, reason: reason)  // swiftlint:disable:this explicit_type_interface line_length
    logger.info(
      "♻️ Local dashboard reload invalidated \(removedCount)/\(keys.count) moving-window cache entries"
    )
  }

  private func clearAllMonthCache(reason: String) {  // swiftlint:disable:this type_contents_order
    let keys = Set(monthCache.keys).union(Set(prefetchTasks.keys))  // swiftlint:disable:this explicit_type_interface
    incrementMonthCacheInvalidationTokens(for: keys)

    let removedCount = monthCache.count  // swiftlint:disable:this explicit_type_interface
    let prefetchCount = prefetchTasks.count  // swiftlint:disable:this explicit_type_interface
    monthCache.removeAll()
    prefetchTasks.removeAll()

    if removedCount > 0 || prefetchCount > 0 {
      logger.info(
        "♻️ Cleared dashboard month cache (\(reason)): \(removedCount) entries, \(prefetchCount) prefetches"
      )
    }
  }

  private func incrementMonthCacheInvalidationTokens(for keys: Set<String>) {  // swiftlint:disable:this line_length type_contents_order
    for key in keys {
      monthCacheInvalidationTokens[key, default: 0] += 1
    }
  }

  private func monthCacheInvalidationToken(for key: String) -> Int {  // swiftlint:disable:this type_contents_order
    monthCacheInvalidationTokens[key] ?? 0
  }

  private func isPrefetchCurrent(for key: String, token: Int) -> Bool {  // swiftlint:disable:this type_contents_order
    prefetchTasks[key] == token && monthCacheInvalidationToken(for: key) == token
  }

  private func finishPrefetch(for key: String, token: Int) {  // swiftlint:disable:this type_contents_order
    guard prefetchTasks[key] == token else { return }  // swiftlint:disable:this conditional_returns_on_newline
    prefetchTasks.removeValue(forKey: key)
  }

  /// Evict least recently used cache entries if over limit
  private func evictCacheIfNeeded() {  // swiftlint:disable:this type_contents_order
    guard monthCache.count > Self.maxCacheSize else { return }  // swiftlint:disable:this conditional_returns_on_newline

    // Sort by last accessed time (oldest first)
    let sortedKeys = monthCache.keys.sorted { key1, key2 in  // swiftlint:disable:this explicit_type_interface
      guard let entry1 = monthCache[key1], let entry2 = monthCache[key2] else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
      return entry1.lastAccessed < entry2.lastAccessed
    }

    // Remove oldest entries until we're under the limit
    let entriesToRemove = monthCache.count - Self.maxCacheSize  // swiftlint:disable:this explicit_type_interface
    for i in 0..<entriesToRemove {  // swiftlint:disable:this identifier_name
      let key = sortedKeys[i]  // swiftlint:disable:this explicit_type_interface
      monthCache.removeValue(forKey: key)
      logger.info("🗑️ Evicted cache entry: \(key)")
    }
  }

  // MARK: - Month Navigation

  /// Track active navigation task to cancel stale fetches
  private var activeNavigationTask: Task<Void, Never>?

  /// Navigate to the previous month (non-blocking)
  /// Delegates to SharedMonthContext - data reload happens via subscription
  func goToPreviousMonth() {  // swiftlint:disable:this explicit_acl type_contents_order
    monthContext.goToPreviousMonth()
  }

  /// Navigate to the next month (non-blocking)
  /// Delegates to SharedMonthContext - data reload happens via subscription
  func goToNextMonth() {  // swiftlint:disable:this explicit_acl type_contents_order
    monthContext.goToNextMonth()
  }

  /// Non-blocking month data loader
  /// Uses cache for instant display, fetches in background if needed
  private func loadDashboardForDisplayedMonthNonBlocking() {  // swiftlint:disable:this cyclomatic_complexity function_body_length line_length type_contents_order
    guard isActiveTabVisible else {
      displayedMonthLoadPending = true
      logger.info("⏸️ Deferring dashboard month load while Home tab is hidden")
      return
    }

    let targetYear = displayYear  // swiftlint:disable:this explicit_type_interface
    let targetMonth = displayMonth  // swiftlint:disable:this explicit_type_interface
    let displayKey = "\(targetYear)-\(targetMonth)"  // swiftlint:disable:this explicit_type_interface
    let previousYM = Date.previousYearMonth(from: (year: targetYear, month: targetMonth))  // swiftlint:disable:this explicit_type_interface line_length
    let previousKey = "\(previousYM.year)-\(previousYM.month)"  // swiftlint:disable:this explicit_type_interface
    let earlierKey = monthCacheKey(Date.previousYearMonth(from: previousYM))  // swiftlint:disable:this explicit_type_interface line_length

    // Check if we have valid cache for the displayed month and the two before it
    if var displayCache = monthCache[displayKey], displayCache.isValid,
      var previousCache = monthCache[previousKey], previousCache.isValid,
      let earlierCache = monthCache[earlierKey], earlierCache.isValid
    {
      // Use cached data - instant navigation!
      logger.info("📦 Using cached data for \(displayKey)")
      self.displayedMonthShifts = displayCache.shifts
      self.displayedMonthEvents = displayCache.events
      self.previousMonthShifts = previousCache.shifts
      if let userId = cachedUserId {
        let adjustmentMonths = payrollPayoutMonthsToLoad(  // swiftlint:disable:this explicit_type_interface
          displayYM: (year: targetYear, month: targetMonth)
        )
        self.payrollAdjustmentsByPayoutMonth = fetchPayrollAdjustmentsForPayoutMonths(
          userId: userId,
          months: adjustmentMonths
        )
        self.previousPayrollAdjustments =
          payrollAdjustmentsByPayoutMonth[
            PayrollReadMonth(year: targetYear, month: targetMonth)
          ] ?? []
      }

      // Update last accessed time for LRU tracking
      displayCache.lastAccessed = Date()
      previousCache.lastAccessed = Date()
      monthCache[displayKey] = displayCache
      monthCache[previousKey] = previousCache

      if let currentSettings = settings {
        let capturedDisplay = displayCache.shifts  // swiftlint:disable:this explicit_type_interface
        let capturedDisplayEvents = displayCache.events  // swiftlint:disable:this explicit_type_interface
        let capturedPrevious = previousCache.shifts  // swiftlint:disable:this explicit_type_interface
        let capturedEarlier = earlierCache.shifts  // swiftlint:disable:this explicit_type_interface
        let capturedCurrency = currentSettings.currency ?? "kr"  // swiftlint:disable:this explicit_type_interface
        let capturedJobs = displayJobs  // swiftlint:disable:this explicit_type_interface
        let capturedAdjustments = previousPayrollAdjustments  // swiftlint:disable:this explicit_type_interface
        let capturedAdjustmentsByPayoutMonth = payrollAdjustmentsByPayoutMonth  // swiftlint:disable:this explicit_type_interface line_length
        let capturedSnapshots = snapshots  // swiftlint:disable:this explicit_type_interface

        Task.detached(priority: .userInitiated) {  // swiftlint:disable:this closure_body_length
          [
            displayYM = (year: targetYear, month: targetMonth), previousYM, currentSettings,
            capturedCurrency, capturedJobs, capturedDisplay, capturedDisplayEvents,
            capturedPrevious, capturedEarlier, capturedAdjustments,
            capturedAdjustmentsByPayoutMonth, capturedSnapshots
          ] in
          let data = Self.buildDashboardDataOffMain(  // swiftlint:disable:this explicit_type_interface
            .init(
              displayedMonthShifts: capturedDisplay,
              displayedMonthEvents: capturedDisplayEvents,
              previousMonthShifts: capturedPrevious,
              previousPayrollAdjustments: capturedAdjustments,
              snapshots: capturedSnapshots,
              settings: currentSettings,
              displayYM: displayYM,
              previousYM: previousYM,
              currency: capturedCurrency,
              jobs: capturedJobs
            ))  // swiftlint:disable:this multiline_arguments_brackets
          let payrollCardSnapshot = Self.buildPayrollCardSnapshot(  // swiftlint:disable:this explicit_type_interface
            .init(
              displayedMonthShifts: capturedDisplay,
              previousMonthShifts: capturedPrevious,
              earlierMonthShifts: capturedEarlier,
              payrollAdjustmentsByPayoutMonth: capturedAdjustmentsByPayoutMonth,
              previousPayrollAdjustments: capturedAdjustments,
              snapshots: capturedSnapshots,
              settings: currentSettings,
              jobs: capturedJobs,
              displayYM: displayYM,
              fallbackCurrency: data.currency,
              fallbackPayrollDate: data.payrollDate,
              fallbackPreviousGross: data.previousMonthGross,
              fallbackPreviousNet: data.previousMonthNet,
              fallbackPreviousTax: data.previousMonthTax,
              fallbackPreviousTaxEnabled: data.previousMonthTaxEnabled,
              fallbackPreviousHasPayrollAdjustments: data.previousMonthHasPayrollAdjustments,
              now: Date()
            ))  // swiftlint:disable:this multiline_arguments_brackets
          await MainActor.run {
            guard self.displayYear == targetYear, self.displayMonth == targetMonth else {
              logger.info("⏭️ Skipping stale cached dashboard payload for \(displayKey)")
              return
            }
            self.applyDashboardData(data, payrollCardSnapshot: payrollCardSnapshot)
            self.maybeTriggerCelebration()
          }
        }
      } else {
        self.applyDashboardData(buildDashboardData())
        self.maybeTriggerCelebration()
      }

      // Still prefetch neighbors in background
      prefetchNeighboringMonths()
      return
    }

    // Cache miss - fetch in background while keeping the currently rendered
    // dashboard content visible (matches Shifts tab behavior).
    // This avoids a brief full-screen skeleton flash on first month change
    // after cold start or after cache expiry.
    logger.info("🔄 Cache miss for \(displayKey), fetching in background...")

    self.isLoading = true

    // Cancel any previous navigation task
    activeNavigationTask?.cancel()

    // Start background fetch
    activeNavigationTask = Task { [weak self] in
      guard let self else { return }  // swiftlint:disable:this conditional_returns_on_newline

      do {
        // Check cancellation at the start
        try Task.checkCancellation()

        // Check if this task is still relevant (user hasn't navigated away)
        guard displayYear == targetYear,
          displayMonth == targetMonth
        else {
          logger.info("⏭️ Skipping stale fetch for \(displayKey)")
          return
        }

        await loadDashboardForDisplayedMonth(
          showLoadingState: false,
          expectedDisplayYM: (year: targetYear, month: targetMonth)
        )

        // Check cancellation after async operation
        try Task.checkCancellation()

        // Check again after fetch - user may have navigated during the async operation
        guard displayYear == targetYear,
          displayMonth == targetMonth
        else {
          logger.info("⏭️ Skipping prefetch - user navigated during fetch")
          return
        }

        // Prefetch neighbors after successful load
        prefetchNeighboringMonths()
      } catch is CancellationError {
        logger.info("⏭️ Navigation task was cancelled for \(displayKey)")
      } catch {
        logger.error("Navigation task failed for \(displayKey): \(error.localizedDescription)")
      }
    }
  }

  // MARK: - Public Methods

  func setActiveTabVisible(_ isVisible: Bool) {  // swiftlint:disable:this explicit_acl type_contents_order
    guard isActiveTabVisible != isVisible else { return }  // swiftlint:disable:this conditional_returns_on_newline

    isActiveTabVisible = isVisible

    if !isVisible {
      activeNavigationTask?.cancel()
      incrementMonthCacheInvalidationTokens(for: Set(prefetchTasks.keys))
      prefetchTasks.removeAll()
      isLoading = false
      return
    }

    let dashboardMatchesDisplayed =  // swiftlint:disable:this explicit_type_interface
      dashboardData?.displayedYear == displayYear && dashboardData?.displayedMonth == displayMonth
    if localDataNeedsReload || displayedMonthLoadPending || !dashboardMatchesDisplayed {
      Task {
        await reloadFromLocalIfStale()
      }
    }
  }

  func markLocalDataStale() {  // swiftlint:disable:this explicit_acl type_contents_order
    localDataNeedsReload = true
    displayedMonthLoadPending = true
    dashboardDependenciesLoaded = false
    invalidateSharedPayrollReadCache()
  }

  func handleExternalShiftsDidChange(_ context: ShiftChangeContext) async {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    invalidateSharedPayrollReadCache()

    guard context.canUseTargetedInvalidation else {
      markLocalDataStale()
      guard isActiveTabVisible else { return }  // swiftlint:disable:this conditional_returns_on_newline
      await reloadFromLocal(showLoadingState: dashboardData == nil)
      return
    }

    let affectedKeys = Set(  // swiftlint:disable:this explicit_type_interface
      context.affectedMonths.map { monthCacheKey(year: $0.year, month: $0.month) }
    )
    invalidateMonthCacheEntries(for: affectedKeys, reason: "shift-change")

    guard
      HomeScheduleAffectedMonthResolver.dashboardDisplayedMonthDepends(
        on: context.affectedMonths,
        displayYear: displayYear,
        displayMonth: displayMonth
      )
    else {
      return
    }

    displayedMonthLoadPending = true
    guard isActiveTabVisible else { return }  // swiftlint:disable:this conditional_returns_on_newline

    displayedMonthLoadPending = false
    loadDashboardForDisplayedMonthNonBlocking()
  }

  /// Reloads data that was deferred while Home was hidden.
  /// Uses cached month data when only the displayed month changed.
  func reloadFromLocalIfStale() async {  // swiftlint:disable:this explicit_acl type_contents_order
    guard isActiveTabVisible else {
      displayedMonthLoadPending = true
      return
    }

    if localDataNeedsReload {
      await reloadFromLocal(showLoadingState: dashboardData == nil)
      return
    }

    if dashboardData == nil {
      await loadDashboard()
      return
    }

    let dashboardMatchesDisplayed =  // swiftlint:disable:this explicit_type_interface
      dashboardData?.displayedYear == displayYear && dashboardData?.displayedMonth == displayMonth
    guard displayedMonthLoadPending || !dashboardMatchesDisplayed else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    displayedMonthLoadPending = false
    loadDashboardForDisplayedMonthNonBlocking()
  }

  /// Load all dashboard data for current month (initial load)
  /// Reads from local repositories only - sync is triggered by AppCoordinator
  /// Also prefetches neighboring months for instant navigation
  func loadDashboard() async {  // swiftlint:disable:this explicit_acl type_contents_order
    guard isActiveTabVisible else {
      displayedMonthLoadPending = true
      return
    }

    // Sync tracking with current month context values
    lastObservedYear = monthContext.displayYear
    lastObservedMonth = monthContext.displayMonth
    navigationDirection = nil

    // Clear cache on full reload (including cachedUserId for impersonation support)
    clearAllMonthCache(reason: "full-load")
    if dashboardData == nil {
      payrollCardSnapshot = nil
    }
    cachedUserId = nil
    resetDashboardDependencies(preservingDisplayJobs: dashboardData != nil)
    previousPayrollAdjustments = []
    payrollAdjustmentsByPayoutMonth.removeAll()

    await loadDashboardFromLocal()
    localDataNeedsReload = false
    displayedMonthLoadPending = false

    // Prefetch neighboring months in the background
    prefetchNeighboringMonths()
  }

  /// Refresh dashboard data via sync then local reload
  /// Called by pull-to-refresh - triggers network sync, then reloads from local
  func refresh() async {  // swiftlint:disable:this explicit_acl type_contents_order
    // SwiftUI .refreshable can cancel the parent task when the view hierarchy changes.
    // Run refresh work in an unstructured task so sync can complete reliably.
    let refreshTask = Task { @MainActor [weak self] in  // swiftlint:disable:this explicit_type_interface
      guard let self else { return }  // swiftlint:disable:this conditional_returns_on_newline
      await performRefresh()
    }

    _ = await refreshTask.result
  }

  /// Performs pull-to-refresh sync and local reload.
  private func performRefresh() async {  // swiftlint:disable:this type_contents_order
    logger.info("🔄 Pull-to-refresh: triggering sync then local reload")

    // Store current data as fallback in case of failure
    let previousDashboardData = dashboardData  // swiftlint:disable:this explicit_type_interface

    do {
      // Get user ID
      if cachedUserId == nil {
        guard let userId = try await getCurrentUserId() else {
          throw DashboardError.notAuthenticated
        }
        cachedUserId = userId
      }

      guard let userId = cachedUserId else {
        throw DashboardError.notAuthenticated
      }

      // Trigger sync to pull/push changes
      let syncResult = await syncCoordinator.sync(reason: .manualRefresh, userId: userId)  // swiftlint:disable:this explicit_type_interface line_length

      if !syncResult.success, let errorMessage = syncResult.error {
        logger.warning("⚠️ Sync had issues: \(errorMessage)")
        // Continue anyway - we still want to show local data
      }

      // Clear in-memory caches so we pick up synced data
      clearAllMonthCache(reason: "manual-refresh")
      invalidateSharedPayrollReadCache(for: userId)
      resetDashboardDependencies(preservingDisplayJobs: dashboardData != nil)

      // Reload from local repositories
      await loadDashboardFromLocal()

      // Prefetch neighboring months in the background
      prefetchNeighboringMonths()

      logger.info("✅ Pull-to-refresh complete (synced \(syncResult.totalRowsProcessed) rows)")

    } catch {
      logger.error("❌ Pull-to-refresh failed: \(error.localizedDescription)")

      // Restore previous data so UI doesn't break
      if let previousDashboardData {
        applyDashboardData(previousDashboardData)
      } else {
        self.dashboardData = nil
      }

      // Don't show error state - just log it and keep showing previous data
      // The user can try again, but they'll still see their data
      logger.info("📦 Restored previous data after refresh failure")
    }
  }

  private func loadDashboardDependencies(  // swiftlint:disable:this type_contents_order
    for userId: String,
    forceReload: Bool = false
  ) async {
    guard forceReload || !dashboardDependenciesLoaded else {
      return
    }

    let context = await monthlyPayrollReadService.loadContextOffMain(for: userId)  // swiftlint:disable:this explicit_type_interface line_length
    applyDashboardDependencies(context)
  }

  private func applyDashboardDependencies(  // swiftlint:disable:this type_contents_order
    _ context: PayrollReadContext
  ) {
    settings = context.settings
    snapshots = context.snapshots
    recurringShifts = context.recurringShifts
    displayJobs = context.jobs
    shouldShowDashboardClockButtons = settings?.effectiveShowDashboardClockButtons ?? true
    dashboardDependenciesLoaded = true
  }

  /// Invalidates dependency reads. Preserve displayed jobs while existing dashboard data remains
  /// visible so workplace badges do not flicker during local reloads.
  private func resetDashboardDependencies(preservingDisplayJobs: Bool = false) {  // swiftlint:disable:this line_length type_contents_order
    settings = nil
    snapshots = []
    recurringShifts = []
    if !preservingDisplayJobs {
      displayJobs = []
    }
    dashboardDependenciesLoaded = false
  }

  private func invalidateSharedPayrollReadCache(for userId: String? = nil) {  // swiftlint:disable:this line_length type_contents_order
    monthlyPayrollReadService.invalidateSharedCache(for: userId ?? cachedUserId)
  }

  private func dashboardDependenciesDiffer(from context: PayrollReadContext) -> Bool {  // swiftlint:disable:this line_length type_contents_order
    guard dashboardDependenciesLoaded else { return true }  // swiftlint:disable:this conditional_returns_on_newline

    return settings != context.settings
      || snapshots != context.snapshots
      || recurringShifts != context.recurringShifts
      || displayJobs != context.jobs
  }

  private func consumeInitialSyncCompletionTransition() -> Bool {  // swiftlint:disable:this type_contents_order
    let initialSyncComplete = AppCoordinator.shared.initialSyncComplete  // swiftlint:disable:this explicit_type_interface line_length
    defer {
      hasObservedInitialSyncCompletion = initialSyncComplete
    }

    return initialSyncComplete && !hasObservedInitialSyncCompletion
  }

  private func fullCacheInvalidationReasonForLocalReload(  // swiftlint:disable:this type_contents_order
    previousUserId: String?,
    currentUserId: String?,
    initialSyncJustCompleted: Bool,
    dependenciesChanged: Bool
  ) -> String? {
    guard let currentUserId, !currentUserId.isEmpty else {
      return "local-reload-user-unavailable"
    }

    guard let previousUserId, !previousUserId.isEmpty else {
      return "local-reload-user-uncached"
    }

    guard previousUserId == currentUserId else {
      return "local-reload-user-changed"
    }

    if initialSyncJustCompleted {
      return "initial-sync-complete"
    }

    if dependenciesChanged {
      return "local-reload-dependencies-changed"
    }

    return nil
  }

  private func fetchShiftRows(  // swiftlint:disable:this type_contents_order
    for userId: String,
    year: Int,
    month: Int
  ) async -> [ShiftRow] {
    await monthlyPayrollReadService.loadShiftRows(
      for: userId,
      year: year,
      month: month
    )
  }

  private func fetchMonthRawWindows(  // swiftlint:disable:this type_contents_order
    for userId: String,
    displayYM: (year: Int, month: Int),
    previousYM: (year: Int, month: Int)
  ) async -> (  // swiftlint:disable:this large_tuple
    display: PayrollRawWindowData, previous: PayrollRawWindowData, earlier: PayrollRawWindowData
  ) {
    let displayWindow = PayrollReadWindow.month(year: displayYM.year, month: displayYM.month)  // swiftlint:disable:this explicit_type_interface line_length
    let previousWindow = PayrollReadWindow.month(year: previousYM.year, month: previousYM.month)  // swiftlint:disable:this explicit_type_interface line_length
    let earlierYM = Date.previousYearMonth(from: previousYM)  // swiftlint:disable:this explicit_type_interface
    let earlierWindow = PayrollReadWindow.month(year: earlierYM.year, month: earlierYM.month)  // swiftlint:disable:this explicit_type_interface line_length

    async let displayData = monthlyPayrollReadService.loadRawWindow(  // swiftlint:disable:this explicit_type_interface
      for: userId,
      window: displayWindow
    )
    async let previousData = monthlyPayrollReadService.loadRawWindow(  // swiftlint:disable:this explicit_type_interface
      for: userId,
      window: previousWindow
    )
    async let earlierData = monthlyPayrollReadService.loadRawWindow(  // swiftlint:disable:this explicit_type_interface
      for: userId,
      window: earlierWindow
    )

    return await (displayData, previousData, earlierData)
  }

  private func fetchPayrollAdjustmentsForPayoutMonth(  // swiftlint:disable:this type_contents_order
    userId: String,
    year: Int,
    month: Int
  ) -> [PayrollAdjustment] {
    let start = Date.firstDayOfMonthDate(year: year, month: month)  // swiftlint:disable:this explicit_type_interface
    let end =  // swiftlint:disable:this explicit_type_interface
      Calendar(identifier: .gregorian).date(byAdding: .month, value: 1, to: start)
      ?? Date.lastDayOfMonthDate(year: year, month: month)

    return payrollAdjustmentsRepository.getAdjustments(
      for: userId,
      payoutStart: start,
      payoutEnd: end
    )
  }

  private func fetchPayrollAdjustmentsForPayoutMonths(  // swiftlint:disable:this type_contents_order
    userId: String,
    months: Set<PayrollReadMonth>
  ) -> [PayrollReadMonth: [PayrollAdjustment]] {
    months.reduce(into: [PayrollReadMonth: [PayrollAdjustment]]()) { result, month in
      result[month] = fetchPayrollAdjustmentsForPayoutMonth(
        userId: userId,
        year: month.year,
        month: month.month
      )
    }
  }

  private func payrollPayoutMonthsToLoad(  // swiftlint:disable:this type_contents_order
    displayYM: (year: Int, month: Int)
  ) -> Set<PayrollReadMonth> {
    var months: Set<PayrollReadMonth> = [
      PayrollReadMonth(year: displayYM.year, month: displayYM.month)
    ]

    let current = Date.currentYearMonth()  // swiftlint:disable:this explicit_type_interface
    if displayYM.year == current.year, displayYM.month == current.month {
      let nextYM = nextYearMonth(from: displayYM)  // swiftlint:disable:this explicit_type_interface
      months.insert(PayrollReadMonth(year: nextYM.year, month: nextYM.month))
    }

    return months
  }

  private func payrollTaxSettings(  // swiftlint:disable:this type_contents_order
    from shifts: [ShiftWithComputations],
    fallbackDate: String,
    jobId: String?
  ) -> PayoutTaxSettings {
    Self.payrollTaxSettings(
      from: shifts,
      fallbackDate: fallbackDate,
      snapshots: snapshots,
      jobs: displayJobs,
      jobId: jobId
    )
  }

  private func payrollTaxSettings(  // swiftlint:disable:this type_contents_order
    for adjustment: PayrollAdjustment,
    fallback: PayoutTaxSettings,
    jobId: String?,
    defaultJobId: String?
  ) -> PayoutTaxSettings {
    Self.payrollTaxSettings(
      for: adjustment,
      fallback: fallback,
      snapshots: snapshots,
      jobs: displayJobs,
      jobId: jobId,
      defaultJobId: defaultJobId
    )
  }

  nonisolated private static func payrollTaxSettings(  // swiftlint:disable:this type_contents_order
    from shifts: [ShiftWithComputations],
    fallbackDate: String,
    snapshots: [WageSnapshot],
    jobs: [Job],
    jobId: String?
  ) -> PayoutTaxSettings {
    if let firstTaxedShift = shifts.first(where: \.taxEnabled) {
      return PayoutTaxSettings(
        enabled: true,
        percentage: firstTaxedShift.taxPercentage
      )
    }

    let scopedSnapshots = payrollSnapshotsForJob(jobId: jobId, snapshots: snapshots, jobs: jobs)  // swiftlint:disable:this explicit_type_interface line_length
    let snapshot = SnapshotsService.snapshotForDate(fallbackDate, from: scopedSnapshots)  // swiftlint:disable:this explicit_type_interface line_length
    return PayoutTaxSettings(
      enabled: snapshot?.effectiveTaxEnabled ?? false,
      percentage: snapshot?.effectiveTaxPercentage ?? 0
    )
  }

  nonisolated private static func payrollTaxSettings(  // swiftlint:disable:this function_parameter_count line_length type_contents_order
    for adjustment: PayrollAdjustment,
    fallback: PayoutTaxSettings,
    snapshots: [WageSnapshot],
    jobs: [Job],
    jobId: String?,
    defaultJobId: String?
  ) -> PayoutTaxSettings {
    let effectiveJobId = jobId ?? adjustment.job_id ?? defaultJobId  // swiftlint:disable:this explicit_type_interface
    let scopedSnapshots = payrollSnapshotsForJob(  // swiftlint:disable:this explicit_type_interface
      jobId: effectiveJobId,
      snapshots: snapshots,
      jobs: jobs
    )
    guard
      let snapshot = SnapshotsService.snapshotForDate(adjustment.payout_date, from: scopedSnapshots)
    else {
      return fallback
    }
    return PayoutTaxSettings(
      enabled: snapshot.effectiveTaxEnabled,
      percentage: snapshot.effectiveTaxPercentage
    )
  }

  nonisolated private static func payrollSnapshotsForJob(  // swiftlint:disable:this type_contents_order
    jobId: String?,
    snapshots: [WageSnapshot],
    jobs: [Job]
  ) -> [WageSnapshot] {
    let snapshotsByJobId = Dictionary(grouping: snapshots, by: { $0.job_id })  // swiftlint:disable:this explicit_type_interface line_length
    let legacyNilJobSnapshots = snapshotsByJobId[nil] ?? []  // swiftlint:disable:this explicit_type_interface

    guard let jobId else {
      return legacyNilJobSnapshots.isEmpty ? snapshots : legacyNilJobSnapshots
    }

    if let scoped = snapshotsByJobId[jobId], !scoped.isEmpty {
      return scoped
    }

    let defaultJobId = jobs.first(where: \.is_default)?.id  // swiftlint:disable:this explicit_type_interface
    if let defaultJobId, let defaultScoped = snapshotsByJobId[defaultJobId], !defaultScoped.isEmpty
    {
      return defaultScoped
    }

    return legacyNilJobSnapshots.isEmpty ? snapshots : legacyNilJobSnapshots
  }

  /// Prepare for reload by setting loading state synchronously
  /// Call this BEFORE starting a Task to reload, to prevent empty state flash
  /// This ensures the loading indicator shows immediately when sync completes
  func prepareForReload() {  // swiftlint:disable:this explicit_acl type_contents_order
    isLoading = true
  }

  /// Returns whether payroll has been manually marked as received for the displayed month.
  func isPayrollReceivedOverrideForDisplayedMonth(userId: String? = nil) -> Bool {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard let key = payrollReceivedOverrideKeyForDisplayedMonth(userId: userId) else {
      return false
    }
    return UserDefaults.standard.bool(forKey: key)
  }

  /// Marks payroll as received for the displayed month.
  /// This is idempotent and only stores `true`.
  func markPayrollReceivedForDisplayedMonth(userId: String? = nil) {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard let key = payrollReceivedOverrideKeyForDisplayedMonth(userId: userId) else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    UserDefaults.standard.set(true, forKey: key)
    objectWillChange.send()
  }

  /// Clears the manual payroll-received override for the displayed month.
  func clearPayrollReceivedOverrideForDisplayedMonth(userId: String? = nil) {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard let key = payrollReceivedOverrideKeyForDisplayedMonth(userId: userId) else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    UserDefaults.standard.removeObject(forKey: key)
    objectWillChange.send()
  }

  /// Reload dashboard from local data without triggering sync
  /// Called when shifts change locally (e.g., after adding a shift) or after initial sync completes
  /// - Parameter showLoadingState: Whether to show loading indicator (false for seamless updates after sync)
  func reloadFromLocal(  // swiftlint:disable:this explicit_acl function_body_length type_contents_order
    showLoadingState: Bool = true
  ) async {
    guard isActiveTabVisible else {
      markLocalDataStale()
      return
    }

    logger.info("🔄 Reloading dashboard from local data")

    // Set loading state if not already set (e.g., by prepareForReload)
    if showLoadingState, !isLoading {
      isLoading = true
    }

    let previousUserId = cachedUserId  // swiftlint:disable:this explicit_type_interface
    let currentUserId = try? await getCurrentUserId()  // swiftlint:disable:this explicit_type_interface
    invalidateSharedPayrollReadCache(for: currentUserId)
    let initialSyncJustCompleted = consumeInitialSyncCompletionTransition()  // swiftlint:disable:this explicit_type_interface line_length
    let refreshedContext: PayrollReadContext?
    if let currentUserId {
      refreshedContext = await monthlyPayrollReadService.loadContextOffMain(for: currentUserId)
    } else {
      refreshedContext = nil
    }
    let dependenciesChanged = refreshedContext.map(dashboardDependenciesDiffer(from:)) ?? true  // swiftlint:disable:this explicit_type_interface line_length

    if let fullInvalidationReason = fullCacheInvalidationReasonForLocalReload(
      previousUserId: previousUserId,
      currentUserId: currentUserId,
      initialSyncJustCompleted: initialSyncJustCompleted,
      dependenciesChanged: dependenciesChanged
    ) {
      clearAllMonthCache(reason: fullInvalidationReason)
    } else {
      invalidateMovingWindowCache(reason: "local-reload")
    }

    cachedUserId = currentUserId  // Refreshed from session for impersonation correctness.
    if let refreshedContext {
      applyDashboardDependencies(refreshedContext)
    } else {
      resetDashboardDependencies()
    }

    // Reload from local repositories (pass false since we already set loading state)
    await loadDashboardFromLocal(showLoadingState: false)
    localDataNeedsReload = false
    displayedMonthLoadPending = false

    // Prefetch neighboring months after launch animations settle
    Task {
      try? await Task.sleep(nanoseconds: 1_200_000_000)  // swiftlint:disable:this no_magic_numbers
      prefetchNeighboringMonths()
    }

    logger.info("✅ Dashboard reloaded from local")
  }

  /// Load dashboard data from local repositories
  /// This is the core local-first read path - no network calls
  /// - Parameter showLoadingState: Whether to show/update loading indicator (false for seamless background updates)
  private func loadDashboardFromLocal(showLoadingState: Bool = true) async {  // swiftlint:disable:this cyclomatic_complexity function_body_length line_length type_contents_order
    if showLoadingState {
      isLoading = true
    }
    error = nil

    do {
      // Get or cache user ID
      if cachedUserId == nil {
        guard let userId = try await getCurrentUserId() else {
          throw DashboardError.notAuthenticated
        }
        cachedUserId = userId
      }

      guard let userId = cachedUserId else {
        throw DashboardError.notAuthenticated
      }

      // Load settings from repositories
      await loadDashboardDependencies(for: userId)
      logger.info("📋 Loaded settings: \(self.settings != nil ? "found" : "nil")")

      // Check if we have any data to show
      // Note: Empty shifts is OK, but missing settings means we can't compute payroll
      if self.settings == nil {
        // No settings yet - retry multiple times with delays
        // This handles the race condition where sync completes but data isn't readable yet
        for attempt in 1...5 {  // swiftlint:disable:this no_magic_numbers
          logger.info("📭 No local settings yet - retry \(attempt)/5 in 400ms (userId: \(userId))")

          do {
            try await Task.sleep(nanoseconds: 400_000_000)  // 400ms // swiftlint:disable:this no_magic_numbers
          } catch {
            // Sleep was cancelled - exit retry loop
            logger.info("⏭️ Retry sleep cancelled")
            break
          }

          // Retry loading through the shared monthly payroll read path
          await loadDashboardDependencies(for: userId, forceReload: true)
          if settings != nil {
            logger.info("📋 Settings found on retry \(attempt)")
            break
          }
        }
      }

      guard let currentSettings = self.settings else {
        // Still no settings after all retries - this is a real error
        logger.error("❌ No settings after retries - cannot load dashboard")
        self.error = DashboardError.noLocalData
        self.isLoading = false
        return
      }

      updateUserAvatarFromSettings()

      await loadDashboardDependencies(for: userId)
      logger.info("📋 Loaded snapshots: \(self.snapshots.count)")
      logger.info("📋 Loaded recurring: \(self.recurringShifts.count)")

      // Calculate date ranges for displayed month
      let displayYM = (year: displayYear, month: displayMonth)  // swiftlint:disable:this explicit_type_interface
      let previousYM = Date.previousYearMonth(from: displayYM)  // swiftlint:disable:this explicit_type_interface

      // Load shifts through the repository/DAL path (after settings retry to avoid stale empty reads)
      let fetchedRawWindows = await fetchMonthRawWindows(  // swiftlint:disable:this explicit_type_interface
        for: userId,
        displayYM: displayYM,
        previousYM: previousYM
      )
      let displayShifts = fetchedRawWindows.display.shifts  // swiftlint:disable:this explicit_type_interface
      logger.info(
        "📋 Loaded shifts for \(displayYM.year)-\(displayYM.month): \(displayShifts.count)")  // swiftlint:disable:this line_length multiline_arguments_brackets
      let fetchedPreviousShifts = fetchedRawWindows.previous.shifts  // swiftlint:disable:this explicit_type_interface
      let fetchedEarlierShifts = fetchedRawWindows.earlier.shifts  // swiftlint:disable:this explicit_type_interface
      let earlierYM = Date.previousYearMonth(from: previousYM)  // swiftlint:disable:this explicit_type_interface
      let displayEvents = fetchedRawWindows.display.events  // swiftlint:disable:this explicit_type_interface
      let previousEvents = fetchedRawWindows.previous.events  // swiftlint:disable:this explicit_type_interface
      let fetchedPayrollAdjustmentsByMonth = fetchPayrollAdjustmentsForPayoutMonths(  // swiftlint:disable:this explicit_type_interface line_length
        userId: userId,
        months: payrollPayoutMonthsToLoad(displayYM: displayYM)
      )
      let fetchedPayrollAdjustments =  // swiftlint:disable:this explicit_type_interface
        fetchedPayrollAdjustmentsByMonth[
          PayrollReadMonth(year: displayYM.year, month: displayYM.month)
        ] ?? []

      let capturedRecurring = recurringShifts  // swiftlint:disable:this explicit_type_interface
      let capturedSnapshots = snapshots  // swiftlint:disable:this explicit_type_interface
      let capturedCurrency = currentSettings.currency ?? "kr"  // swiftlint:disable:this explicit_type_interface
      let capturedJobs = displayJobs  // swiftlint:disable:this explicit_type_interface
      let capturedPayrollAdjustments = fetchedPayrollAdjustments  // swiftlint:disable:this explicit_type_interface
      let capturedPayrollAdjustmentsByPayoutMonth = fetchedPayrollAdjustmentsByMonth  // swiftlint:disable:this explicit_type_interface line_length

      let result = await Task.detached(priority: .userInitiated) {  // swiftlint:disable:this closure_body_length explicit_type_interface line_length
        let displayComputed = PayrollEngine.computeShiftsForMonth(  // swiftlint:disable:this explicit_type_interface
          .init(
            year: displayYM.year,
            month: displayYM.month,
            shifts: displayShifts,
            recurring: capturedRecurring,
            snapshots: capturedSnapshots,
            settings: currentSettings,
            jobs: capturedJobs
          )
        )

        let previousComputed = PayrollEngine.computeShiftsForMonth(  // swiftlint:disable:this explicit_type_interface
          .init(
            year: previousYM.year,
            month: previousYM.month,
            shifts: fetchedPreviousShifts,
            recurring: capturedRecurring,
            snapshots: capturedSnapshots,
            settings: currentSettings,
            jobs: capturedJobs
          )
        )

        let earlierComputed = PayrollEngine.computeShiftsForMonth(  // swiftlint:disable:this explicit_type_interface
          .init(
            year: earlierYM.year,
            month: earlierYM.month,
            shifts: fetchedEarlierShifts,
            recurring: capturedRecurring,
            snapshots: capturedSnapshots,
            settings: currentSettings,
            jobs: capturedJobs
          )
        )

        let dashboardData = Self.buildDashboardDataOffMain(  // swiftlint:disable:this explicit_type_interface
          .init(
            displayedMonthShifts: displayComputed,
            displayedMonthEvents: displayEvents,
            previousMonthShifts: previousComputed,
            previousPayrollAdjustments: capturedPayrollAdjustments,
            snapshots: capturedSnapshots,
            settings: currentSettings,
            displayYM: displayYM,
            previousYM: previousYM,
            currency: capturedCurrency,
            jobs: capturedJobs
          ))  // swiftlint:disable:this multiline_arguments_brackets

        let payrollCardSnapshot = Self.buildPayrollCardSnapshot(  // swiftlint:disable:this explicit_type_interface
          .init(
            displayedMonthShifts: displayComputed,
            previousMonthShifts: previousComputed,
            earlierMonthShifts: earlierComputed,
            payrollAdjustmentsByPayoutMonth: capturedPayrollAdjustmentsByPayoutMonth,
            previousPayrollAdjustments: capturedPayrollAdjustments,
            snapshots: capturedSnapshots,
            settings: currentSettings,
            jobs: capturedJobs,
            displayYM: displayYM,
            fallbackCurrency: dashboardData.currency,
            fallbackPayrollDate: dashboardData.payrollDate,
            fallbackPreviousGross: dashboardData.previousMonthGross,
            fallbackPreviousNet: dashboardData.previousMonthNet,
            fallbackPreviousTax: dashboardData.previousMonthTax,
            fallbackPreviousTaxEnabled: dashboardData.previousMonthTaxEnabled,
            fallbackPreviousHasPayrollAdjustments: dashboardData.previousMonthHasPayrollAdjustments,
            now: Date()
          ))  // swiftlint:disable:this multiline_arguments_brackets

        return (
          display: displayComputed,
          displayEvents: displayEvents,
          previous: previousComputed,
          previousEvents: previousEvents,
          earlier: earlierComputed,
          dashboardData: dashboardData,
          payrollCardSnapshot: payrollCardSnapshot
        )
      }.value

      self.displayedMonthShifts = result.display
      self.displayedMonthEvents = result.displayEvents
      self.previousMonthShifts = result.previous
      self.previousPayrollAdjustments = fetchedPayrollAdjustments
      self.payrollAdjustmentsByPayoutMonth = fetchedPayrollAdjustmentsByMonth

      // Cache the computed results
      let displayKey = "\(displayYM.year)-\(displayYM.month)"  // swiftlint:disable:this explicit_type_interface
      let previousKey = "\(previousYM.year)-\(previousYM.month)"  // swiftlint:disable:this explicit_type_interface
      monthCache[displayKey] = MonthCacheEntry(
        year: displayYM.year,
        month: displayYM.month,
        shifts: result.display,
        events: result.displayEvents,
        timestamp: Date()
      )
      monthCache[previousKey] = MonthCacheEntry(
        year: previousYM.year,
        month: previousYM.month,
        shifts: result.previous,
        events: result.previousEvents,
        timestamp: Date()
      )
      monthCache[monthCacheKey(year: earlierYM.year, month: earlierYM.month)] = MonthCacheEntry(
        year: earlierYM.year,
        month: earlierYM.month,
        shifts: result.earlier,
        events: fetchedRawWindows.earlier.events,
        timestamp: Date()
      )

      // Evict old cache entries if over limit
      evictCacheIfNeeded()

      // Build dashboard data and clear loading state
      // Always clear isLoading on success since we have data to show
      applyDashboardData(result.dashboardData, payrollCardSnapshot: result.payrollCardSnapshot)
      self.maybeTriggerCelebration()
      await refreshClockActiveState(referenceDate: Date())
      self.isLoading = false

      logger.info("📊 Loaded dashboard from local: \(displayShifts.count) shifts for \(displayKey)")

    } catch is CancellationError {
      logger.info("⏭️ Load cancelled (user navigated away)")
      // Don't clear isLoading on cancellation - another load should be in progress
    } catch let urlError as URLError where urlError.code == .cancelled {
      logger.info("⏭️ Request cancelled (user navigated away)")
      // Don't clear isLoading on cancellation - another load should be in progress
    } catch {
      logger.error("❌ Dashboard local load failed: \(error.localizedDescription)")
      self.error = DashboardError.dataLoadFailed(underlying: error)
      // Always clear loading state on completion
      self.isLoading = false
    }
  }

  /// Load dashboard data for the currently displayed month from local repositories
  /// - Parameter showLoadingState: Whether to show loading indicator (false for background navigation loads)
  private func loadDashboardForDisplayedMonth(  // swiftlint:disable:this cyclomatic_complexity function_body_length line_length type_contents_order
    showLoadingState: Bool = true,
    expectedDisplayYM: (year: Int, month: Int)? = nil
  ) async {
    if showLoadingState {
      isLoading = true
    }
    error = nil

    do {
      // Get or cache user ID
      if cachedUserId == nil {
        guard let userId = try await getCurrentUserId() else {
          throw DashboardError.notAuthenticated
        }
        cachedUserId = userId
      }

      guard let userId = cachedUserId else {
        throw DashboardError.notAuthenticated
      }

      // Load settings and cached payroll inputs through repositories if needed
      await loadDashboardDependencies(for: userId)
      updateUserAvatarFromSettings()

      // Calculate date ranges for displayed month
      let displayYM = (year: displayYear, month: displayMonth)  // swiftlint:disable:this explicit_type_interface
      if let expectedDisplayYM,
        displayYM.year != expectedDisplayYM.year || displayYM.month != expectedDisplayYM.month
      {
        logger.info("⏭️ Skipping stale dashboard load before fetch")
        return
      }
      let previousYM = Date.previousYearMonth(from: displayYM)  // swiftlint:disable:this explicit_type_interface

      // Load shifts through the repository/DAL path
      let fetchedRawWindows = await fetchMonthRawWindows(  // swiftlint:disable:this explicit_type_interface
        for: userId,
        displayYM: displayYM,
        previousYM: previousYM
      )
      let displayShifts = fetchedRawWindows.display.shifts  // swiftlint:disable:this explicit_type_interface
      let fetchedPreviousShifts = fetchedRawWindows.previous.shifts  // swiftlint:disable:this explicit_type_interface
      let fetchedEarlierShifts = fetchedRawWindows.earlier.shifts  // swiftlint:disable:this explicit_type_interface
      let earlierYM = Date.previousYearMonth(from: previousYM)  // swiftlint:disable:this explicit_type_interface
      let displayEvents = fetchedRawWindows.display.events  // swiftlint:disable:this explicit_type_interface
      let previousEvents = fetchedRawWindows.previous.events  // swiftlint:disable:this explicit_type_interface
      let fetchedPayrollAdjustmentsByMonth = fetchPayrollAdjustmentsForPayoutMonths(  // swiftlint:disable:this explicit_type_interface line_length
        userId: userId,
        months: payrollPayoutMonthsToLoad(displayYM: displayYM)
      )
      let fetchedPayrollAdjustments =  // swiftlint:disable:this explicit_type_interface
        fetchedPayrollAdjustmentsByMonth[
          PayrollReadMonth(year: displayYM.year, month: displayYM.month)
        ] ?? []

      // Ensure settings are available before computing payroll
      guard let currentSettings = self.settings else {
        // No settings yet - sync may not have completed
        logger.info("📭 No local settings yet - waiting for sync")
        self.isLoading = false
        return
      }

      let capturedRecurring = recurringShifts  // swiftlint:disable:this explicit_type_interface
      let capturedSnapshots = snapshots  // swiftlint:disable:this explicit_type_interface
      let capturedCurrency = currentSettings.currency ?? "kr"  // swiftlint:disable:this explicit_type_interface
      let capturedJobs = displayJobs  // swiftlint:disable:this explicit_type_interface
      let capturedPayrollAdjustments = fetchedPayrollAdjustments  // swiftlint:disable:this explicit_type_interface
      let capturedPayrollAdjustmentsByPayoutMonth = fetchedPayrollAdjustmentsByMonth  // swiftlint:disable:this explicit_type_interface line_length

      let result = await Task.detached(priority: .userInitiated) {  // swiftlint:disable:this closure_body_length explicit_type_interface line_length
        let displayComputed = PayrollEngine.computeShiftsForMonth(  // swiftlint:disable:this explicit_type_interface
          .init(
            year: displayYM.year,
            month: displayYM.month,
            shifts: displayShifts,
            recurring: capturedRecurring,
            snapshots: capturedSnapshots,
            settings: currentSettings,
            jobs: capturedJobs
          )
        )

        let previousComputed = PayrollEngine.computeShiftsForMonth(  // swiftlint:disable:this explicit_type_interface
          .init(
            year: previousYM.year,
            month: previousYM.month,
            shifts: fetchedPreviousShifts,
            recurring: capturedRecurring,
            snapshots: capturedSnapshots,
            settings: currentSettings,
            jobs: capturedJobs
          )
        )

        let earlierComputed = PayrollEngine.computeShiftsForMonth(  // swiftlint:disable:this explicit_type_interface
          .init(
            year: earlierYM.year,
            month: earlierYM.month,
            shifts: fetchedEarlierShifts,
            recurring: capturedRecurring,
            snapshots: capturedSnapshots,
            settings: currentSettings,
            jobs: capturedJobs
          )
        )

        let dashboardData = Self.buildDashboardDataOffMain(  // swiftlint:disable:this explicit_type_interface
          .init(
            displayedMonthShifts: displayComputed,
            displayedMonthEvents: displayEvents,
            previousMonthShifts: previousComputed,
            previousPayrollAdjustments: capturedPayrollAdjustments,
            snapshots: capturedSnapshots,
            settings: currentSettings,
            displayYM: displayYM,
            previousYM: previousYM,
            currency: capturedCurrency,
            jobs: capturedJobs
          ))  // swiftlint:disable:this multiline_arguments_brackets

        let payrollCardSnapshot = Self.buildPayrollCardSnapshot(  // swiftlint:disable:this explicit_type_interface
          .init(
            displayedMonthShifts: displayComputed,
            previousMonthShifts: previousComputed,
            earlierMonthShifts: earlierComputed,
            payrollAdjustmentsByPayoutMonth: capturedPayrollAdjustmentsByPayoutMonth,
            previousPayrollAdjustments: capturedPayrollAdjustments,
            snapshots: capturedSnapshots,
            settings: currentSettings,
            jobs: capturedJobs,
            displayYM: displayYM,
            fallbackCurrency: dashboardData.currency,
            fallbackPayrollDate: dashboardData.payrollDate,
            fallbackPreviousGross: dashboardData.previousMonthGross,
            fallbackPreviousNet: dashboardData.previousMonthNet,
            fallbackPreviousTax: dashboardData.previousMonthTax,
            fallbackPreviousTaxEnabled: dashboardData.previousMonthTaxEnabled,
            fallbackPreviousHasPayrollAdjustments: dashboardData.previousMonthHasPayrollAdjustments,
            now: Date()
          ))  // swiftlint:disable:this multiline_arguments_brackets

        return (
          display: displayComputed,
          displayEvents: displayEvents,
          previous: previousComputed,
          previousEvents: previousEvents,
          earlier: earlierComputed,
          dashboardData: dashboardData,
          payrollCardSnapshot: payrollCardSnapshot
        )
      }.value

      // Cache the computed results
      let displayKey = "\(displayYM.year)-\(displayYM.month)"  // swiftlint:disable:this explicit_type_interface
      let previousKey = "\(previousYM.year)-\(previousYM.month)"  // swiftlint:disable:this explicit_type_interface
      monthCache[displayKey] = MonthCacheEntry(
        year: displayYM.year,
        month: displayYM.month,
        shifts: result.display,
        events: result.displayEvents,
        timestamp: Date()
      )
      monthCache[previousKey] = MonthCacheEntry(
        year: previousYM.year,
        month: previousYM.month,
        shifts: result.previous,
        events: result.previousEvents,
        timestamp: Date()
      )
      monthCache[monthCacheKey(year: earlierYM.year, month: earlierYM.month)] = MonthCacheEntry(
        year: earlierYM.year,
        month: earlierYM.month,
        shifts: result.earlier,
        events: fetchedRawWindows.earlier.events,
        timestamp: Date()
      )

      // Evict old cache entries if over limit
      evictCacheIfNeeded()

      if let expectedDisplayYM,
        displayYear != expectedDisplayYM.year || displayMonth != expectedDisplayYM.month
      {
        logger.info("⏭️ Skipping stale dashboard payload after fetch")
        return
      }

      self.displayedMonthShifts = result.display
      self.displayedMonthEvents = result.displayEvents
      self.previousMonthShifts = result.previous
      self.previousPayrollAdjustments = fetchedPayrollAdjustments
      self.payrollAdjustmentsByPayoutMonth = fetchedPayrollAdjustmentsByMonth

      // Build dashboard data and clear loading state
      applyDashboardData(result.dashboardData, payrollCardSnapshot: result.payrollCardSnapshot)
      self.maybeTriggerCelebration()
      await refreshClockActiveState(referenceDate: Date())
      self.isLoading = false

    } catch is CancellationError {
      // Task was cancelled due to rapid navigation - this is expected, not an error
      // Don't reset isLoading here - the new navigation task will handle its own state
      logger.info("⏭️ Load cancelled (user navigated away)")
    } catch {
      logger.error("❌ Dashboard load failed: \(error.localizedDescription)")
      self.error = DashboardError.dataLoadFailed(underlying: error)
      self.isLoading = false
    }
  }

  /// Prefetch neighboring months in the background
  /// This enables instant navigation when the user swipes
  private func prefetchNeighboringMonths() {  // swiftlint:disable:this type_contents_order
    guard isActiveTabVisible else { return }  // swiftlint:disable:this conditional_returns_on_newline

    let displayYM = (year: displayYear, month: displayMonth)  // swiftlint:disable:this explicit_type_interface

    // Calculate previous and next months
    let previousYM = Date.previousYearMonth(from: displayYM)  // swiftlint:disable:this explicit_type_interface
    let nextYM = nextYearMonth(from: displayYM)  // swiftlint:disable:this explicit_type_interface

    // Also get the months needed for the payroll card of each neighbor.
    // Pay periods can reach two months back, so the previous month needs three months before it.
    let prevPrevYM = Date.previousYearMonth(from: previousYM)  // swiftlint:disable:this explicit_type_interface
    let prevPrevPrevYM = Date.previousYearMonth(from: prevPrevYM)  // swiftlint:disable:this explicit_type_interface
    let nextPrevYM = Date.previousYearMonth(from: nextYM)  // swiftlint:disable:this explicit_type_interface

    // Prefetch all needed months
    prefetchMonthInBackground(year: previousYM.year, month: previousYM.month)
    prefetchMonthInBackground(year: nextYM.year, month: nextYM.month)
    prefetchMonthInBackground(year: prevPrevYM.year, month: prevPrevYM.month)
    prefetchMonthInBackground(year: prevPrevPrevYM.year, month: prevPrevPrevYM.month)
    prefetchMonthInBackground(year: nextPrevYM.year, month: nextPrevYM.month)
  }

  /// Prefetch a single month's data in the background from local repository
  private func prefetchMonthInBackground(year: Int, month: Int) {  // swiftlint:disable:this function_body_length line_length type_contents_order
    let key = monthCacheKey(year: year, month: month)  // swiftlint:disable:this explicit_type_interface

    // Skip if already cached and valid
    if let cached = monthCache[key], cached.isValid {
      return
    }

    // Skip if already prefetching
    let token = monthCacheInvalidationToken(for: key)  // swiftlint:disable:this explicit_type_interface
    if prefetchTasks[key] == token {
      return
    }

    prefetchTasks[key] = token

    // Local reads are fast, but we run in a Task to not block UI
    Task {  // swiftlint:disable:this closure_body_length
      defer {
        self.finishPrefetch(for: key, token: token)
      }

      guard let userId = cachedUserId else {
        return
      }

      // Compute shifts with payroll
      guard let settings = self.settings else {
        return
      }

      let fetchedWindow = await monthlyPayrollReadService.loadRawWindow(  // swiftlint:disable:this explicit_type_interface line_length
        for: userId,
        window: .month(year: year, month: month)
      )

      guard self.isPrefetchCurrent(for: key, token: token) else {
        return
      }

      let monthShifts = fetchedWindow.shifts  // swiftlint:disable:this explicit_type_interface
      let monthEvents = fetchedWindow.events  // swiftlint:disable:this explicit_type_interface
      let capturedRecurring = recurringShifts  // swiftlint:disable:this explicit_type_interface
      let capturedSnapshots = snapshots  // swiftlint:disable:this explicit_type_interface
      let capturedJobs = displayJobs  // swiftlint:disable:this explicit_type_interface

      let computedShifts = await Task.detached(priority: .utility) {  // swiftlint:disable:this explicit_type_interface
        PayrollEngine.computeShiftsForMonth(
          .init(
            year: year,
            month: month,
            shifts: monthShifts,
            recurring: capturedRecurring,
            snapshots: capturedSnapshots,
            settings: settings,
            jobs: capturedJobs
          )
        )
      }.value

      guard self.isPrefetchCurrent(for: key, token: token) else {
        return
      }

      // Store in cache
      let entry = MonthCacheEntry(  // swiftlint:disable:this explicit_type_interface
        year: year,
        month: month,
        shifts: computedShifts,
        events: monthEvents,
        timestamp: Date()
      )
      self.monthCache[key] = entry

      // Evict old cache entries if over limit
      self.evictCacheIfNeeded()

      logger.info("📦 Prefetched \(key) with \(computedShifts.count) shifts from local")
    }
  }

  /// Get next year/month (handles year rollover)
  private func nextYearMonth(from current: (year: Int, month: Int)) -> (year: Int, month: Int) {  // swiftlint:disable:this line_length type_contents_order
    if current.month == 12 {  // swiftlint:disable:this no_magic_numbers
      return (year: current.year + 1, month: 1)
    }
    return (year: current.year, month: current.month + 1)
  }

  // MARK: - Private Methods

  /// Get current authenticated user ID and update user profile data
  private func getCurrentUserId() async throws -> String? {  // swiftlint:disable:this type_contents_order
    let session: Session
    do {
      // Use AuthSessionManager to prevent concurrent refresh race conditions
      session = try await AuthSessionManager.shared.getSession()
    } catch {
      guard AuthSessionManager.shared.isTransientSessionResolutionError(error) else {
        throw error
      }

      if let offlineUserId = AuthSessionManager.shared.offlineUserIdFallback() {
        // Preserve usable dashboard header state during cold offline launches.
        if self.userDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          self.userDisplayName = "User"
        }
        logger.info("Using offline user id fallback")
        return offlineUserId
      }

      throw error
    }
    let user = session.user  // swiftlint:disable:this explicit_type_interface

    // Extract display name from user metadata or fall back to email
    let displayName: String
    if let fullName = user.userMetadata["full_name"]?.value as? String, !fullName.isEmpty {
      displayName = fullName
    } else if let name = user.userMetadata["name"]?.value as? String, !name.isEmpty {
      displayName = name
    } else if let email = user.email {
      // Use the part before @ for email
      displayName = email.components(separatedBy: "@").first ?? email
    } else if let phone = user.phone {
      displayName = phone
    } else {
      displayName = "User"
    }

    // Update published properties
    self.userDisplayName = displayName

    return user.normalizedId
  }

  /// Update user avatar URL from settings (called after settings are loaded)
  private func updateUserAvatarFromSettings() {  // swiftlint:disable:this type_contents_order
    self.userAvatarUrl = settings?.profile_picture_url
  }

  /// Trigger shift completion celebration for current month (if applicable)
  private func maybeTriggerCelebration() {  // swiftlint:disable:this type_contents_order
    let resolvedUserId = cachedUserId ?? resolveUserIdForPayrollVariants()  // swiftlint:disable:this explicit_type_interface line_length
    guard let userId = resolvedUserId, !userId.isEmpty else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    cachedUserId = userId
    guard let dashboardData, let settings else { return }  // swiftlint:disable:this conditional_returns_on_newline

    let current = Date.currentYearMonth()  // swiftlint:disable:this explicit_type_interface
    guard displayYear == current.year, displayMonth == current.month else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    guard dashboardData.displayedYear == current.year,
      dashboardData.displayedMonth == current.month
    else {
      return
    }

    let display = CelebrationDetector.displayValue(dashboardData: dashboardData)  // swiftlint:disable:this explicit_type_interface line_length
    let currency = settings.currency ?? dashboardData.currency  // swiftlint:disable:this explicit_type_interface
    let currentMonthShifts = displayedMonthShifts.filter { shift in  // swiftlint:disable:this explicit_type_interface
      guard let date = Date.fromISODateString(shift.shiftDate) else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length
      let components = Calendar.current.dateComponents([.year, .month], from: date)  // swiftlint:disable:this explicit_type_interface line_length
      return components.year == current.year && components.month == current.month
    }

    ShiftCompletionCelebrationManager.shared.checkForCelebration(
      userId: userId,
      month: current,
      shifts: currentMonthShifts,
      displayValue: display.value,
      displayTaxEnabled: display.taxEnabled,
      currency: currency,
      includeVirtual: true
    )
  }

  /// Build the final dashboard data from computed shifts
  /// Uses PayrollEngine.summarizeShiftTotals for correct half-tax and conflict exclusion
  private func buildDashboardData() -> DashboardData {  // swiftlint:disable:this function_body_length line_length type_contents_order
    let today = todayISO()  // swiftlint:disable:this explicit_type_interface
    let now = Date()  // swiftlint:disable:this explicit_type_interface
    let payrollDay = settings?.effectivePayrollDay ?? 1  // swiftlint:disable:this explicit_type_interface
    let halfTaxMonth = settings?.half_tax_month  // swiftlint:disable:this explicit_type_interface
    let displayYM = (year: displayYear, month: displayMonth)  // swiftlint:disable:this explicit_type_interface
    let previousYM = Date.previousYearMonth(from: displayYM)  // swiftlint:disable:this explicit_type_interface
    let previousAdjustments = previousPayrollAdjustments  // swiftlint:disable:this explicit_type_interface

    // Calculate payroll date for displayed month
    let payrollDate = calculatePayrollDate(  // swiftlint:disable:this explicit_type_interface
      year: displayYM.year, month: displayYM.month, day: payrollDay)  // swiftlint:disable:this line_length multiline_arguments_brackets
    let payrollHasPassed = now > payrollDate  // swiftlint:disable:this explicit_type_interface

    // Previous month totals using PayrollEngine (for payroll card)
    // This correctly applies half-tax and conflict exclusion
    let prevTotals = PayrollEngine.summarizeShiftTotals(  // swiftlint:disable:this explicit_type_interface
      shifts: previousMonthShifts,
      halfTaxMonth: halfTaxMonth,
      earningsMonth: previousYM.month,
      now: now
    )
    let fallbackTaxSettings = payrollTaxSettings(  // swiftlint:disable:this explicit_type_interface
      from: previousMonthShifts,
      fallbackDate: payrollDate.toISODateString(),
      jobId: nil
    )
    let adjustmentTotals = PayrollAdjustmentCalculator.totals(  // swiftlint:disable:this explicit_type_interface
      adjustments: previousAdjustments,
      taxSettings: { adjustment in
        payrollTaxSettings(
          for: adjustment,
          fallback: fallbackTaxSettings,
          jobId: adjustment.job_id,
          defaultJobId: displayJobs.first(where: \.is_default)?.id
        )
      },
      halfTaxMonth: halfTaxMonth,
      payoutMonth: displayYM.month,
      jobs: displayJobs
    )
    let prevTaxEnabled =  // swiftlint:disable:this explicit_type_interface
      previousMonthShifts.contains(where: \.taxEnabled) || adjustmentTotals.taxEnabled
    let previousGross = prevTotals.gross + adjustmentTotals.gross  // swiftlint:disable:this explicit_type_interface
    let previousNet = prevTotals.net + adjustmentTotals.net  // swiftlint:disable:this explicit_type_interface
    let prevTax: Double? = prevTaxEnabled ? previousGross - previousNet : nil

    let fallbackCurrency = settings?.currency ?? "kr"  // swiftlint:disable:this explicit_type_interface
    let currentMonthAggregate = JobCurrencyAggregateResolver.resolve(  // swiftlint:disable:this explicit_type_interface
      shifts: displayedMonthShifts,
      jobs: displayJobs,
      fallbackCurrency: fallbackCurrency,
      referenceDate: now
    )
    let primaryMonthShifts = JobCurrencyAggregateResolver.shifts(  // swiftlint:disable:this explicit_type_interface
      matching: currentMonthAggregate.primary,
      in: displayedMonthShifts,
      jobs: displayJobs,
      fallbackCurrency: fallbackCurrency
    )

    // Displayed month totals (primary currency bucket only).
    let displayTotals = PayrollEngine.summarizeShiftTotals(  // swiftlint:disable:this explicit_type_interface
      shifts: primaryMonthShifts,
      halfTaxMonth: halfTaxMonth,
      earningsMonth: displayYM.month,
      now: now
    )
    let displayTaxEnabled = currentMonthAggregate.primary.hasTaxEnabled  // swiftlint:disable:this explicit_type_interface line_length
    let completedShiftsCount = currentMonthAggregate.primary.completedShiftCount  // swiftlint:disable:this explicit_type_interface line_length
    let plannedShiftsCount = currentMonthAggregate.primary.plannedShiftCount  // swiftlint:disable:this explicit_type_interface line_length

    // Same computation as Stats: gross shift pay in the primary currency, without payroll adjustments.
    let percentChange = MonthlyEarningsChange.percent(  // swiftlint:disable:this explicit_type_interface
      monthShifts: displayedMonthShifts,
      previousMonthShifts: previousMonthShifts,
      jobs: displayJobs,
      fallbackCurrency: fallbackCurrency,
      halfTaxMonth: halfTaxMonth,
      currentMonth: displayYM.month,
      previousMonth: previousYM.month,
      now: now
    )

    // Featured shift logic:
    // - Current month: show next upcoming shift
    // - Other months: show best shift (highest earnings)
    let current = Date.currentYearMonth()  // swiftlint:disable:this explicit_type_interface
    let isViewingCurrentMonth = displayYM.year == current.year && displayYM.month == current.month  // swiftlint:disable:this explicit_type_interface line_length

    let featuredSelection = DashboardFeaturedItemSelector.select(  // swiftlint:disable:this explicit_type_interface
      shifts: displayedMonthShifts,
      events: displayedMonthEvents,
      isViewingCurrentMonth: isViewingCurrentMonth,
      todayISO: today,
      now: now
    )

    // Month names for display
    let displayMonthName = monthName(year: displayYM.year, month: displayYM.month)  // swiftlint:disable:this explicit_type_interface line_length
    let previousMonthName = monthName(year: previousYM.year, month: previousYM.month)  // swiftlint:disable:this explicit_type_interface line_length

    return DashboardData(
      displayedYear: displayYM.year,
      displayedMonth: displayYM.month,
      payrollDate: payrollDate,
      payrollHasPassed: payrollHasPassed,
      previousMonthGross: previousGross,
      previousMonthNet: prevTaxEnabled ? previousNet : nil,
      previousMonthTax: prevTax,
      previousMonthTaxEnabled: prevTaxEnabled,
      previousMonthHasPayrollAdjustments: !previousAdjustments.isEmpty,
      currentMonthGross: displayTotals.gross,
      currentMonthNet: displayTaxEnabled ? displayTotals.net : nil,
      currentMonthCompletedGross: displayTotals.completedGross,
      currentMonthCompletedNet: displayTaxEnabled ? displayTotals.completedNet : nil,
      currentMonthShiftCount: currentMonthAggregate.primary.shiftCount,
      currentMonthCompletedCount: completedShiftsCount,
      currentMonthPlannedCount: plannedShiftsCount,
      percentageChangeVsPrevious: percentChange,
      currentMonthTaxEnabled: displayTaxEnabled,
      featuredItem: featuredSelection.item,
      featuredShift: featuredSelection.item?.shift,
      isFeaturedItemToday: featuredSelection.isToday,
      featuredShiftIsBestShift: featuredSelection.isBestShift,
      currentMonthName: displayMonthName,
      previousMonthName: previousMonthName,
      currency: currentMonthAggregate.primary.currency,
      currentMonthCurrencyAggregate: currentMonthAggregate
    )
  }

  /// Build dashboard data off the main actor to avoid blocking animations.
  nonisolated private static func buildDashboardDataOffMain(  // swiftlint:disable:this function_body_length line_length type_contents_order
    _ input: DashboardDataBuildInput
  ) -> DashboardData {
    let displayedMonthShifts = input.displayedMonthShifts  // swiftlint:disable:this explicit_type_interface
    let displayedMonthEvents = input.displayedMonthEvents  // swiftlint:disable:this explicit_type_interface
    let previousMonthShifts = input.previousMonthShifts  // swiftlint:disable:this explicit_type_interface
    let previousPayrollAdjustments = input.previousPayrollAdjustments  // swiftlint:disable:this explicit_type_interface
    let snapshots = input.snapshots  // swiftlint:disable:this explicit_type_interface
    let settings = input.settings  // swiftlint:disable:this explicit_type_interface
    let displayYM = input.displayYM  // swiftlint:disable:this explicit_type_interface
    let previousYM = input.previousYM  // swiftlint:disable:this explicit_type_interface
    let currency = input.currency  // swiftlint:disable:this explicit_type_interface
    let jobs = input.jobs  // swiftlint:disable:this explicit_type_interface

    let today = todayISO()  // swiftlint:disable:this explicit_type_interface
    let now = Date()  // swiftlint:disable:this explicit_type_interface
    let payrollDay = settings.effectivePayrollDay  // swiftlint:disable:this explicit_type_interface
    let halfTaxMonth = settings.half_tax_month  // swiftlint:disable:this explicit_type_interface

    let payrollDate = PayrollDateAdjuster.adjustPayrollDate(  // swiftlint:disable:this explicit_type_interface
      payrollDay: payrollDay,
      month: displayYM.month,
      year: displayYM.year
    )
    let payrollHasPassed = now > payrollDate  // swiftlint:disable:this explicit_type_interface

    let prevTotals = PayrollEngine.summarizeShiftTotals(  // swiftlint:disable:this explicit_type_interface
      shifts: previousMonthShifts,
      halfTaxMonth: halfTaxMonth,
      earningsMonth: previousYM.month,
      now: now
    )
    let fallbackTaxSettings = payrollTaxSettings(  // swiftlint:disable:this explicit_type_interface
      from: previousMonthShifts,
      fallbackDate: payrollDate.toISODateString(),
      snapshots: snapshots,
      jobs: jobs,
      jobId: nil
    )
    let adjustmentTotals = PayrollAdjustmentCalculator.totals(  // swiftlint:disable:this explicit_type_interface
      adjustments: previousPayrollAdjustments,
      taxSettings: { adjustment in
        payrollTaxSettings(
          for: adjustment,
          fallback: fallbackTaxSettings,
          snapshots: snapshots,
          jobs: jobs,
          jobId: adjustment.job_id,
          defaultJobId: jobs.first(where: \.is_default)?.id
        )
      },
      halfTaxMonth: halfTaxMonth,
      payoutMonth: displayYM.month,
      jobs: jobs
    )
    let prevTaxEnabled =  // swiftlint:disable:this explicit_type_interface
      previousMonthShifts.contains(where: \.taxEnabled) || adjustmentTotals.taxEnabled
    let previousGross = prevTotals.gross + adjustmentTotals.gross  // swiftlint:disable:this explicit_type_interface
    let previousNet = prevTotals.net + adjustmentTotals.net  // swiftlint:disable:this explicit_type_interface
    let prevTax: Double? = prevTaxEnabled ? previousGross - previousNet : nil

    let currentMonthAggregate = JobCurrencyAggregateResolver.resolve(  // swiftlint:disable:this explicit_type_interface
      shifts: displayedMonthShifts,
      jobs: jobs,
      fallbackCurrency: currency,
      referenceDate: now
    )
    let primaryMonthShifts = JobCurrencyAggregateResolver.shifts(  // swiftlint:disable:this explicit_type_interface
      matching: currentMonthAggregate.primary,
      in: displayedMonthShifts,
      jobs: jobs,
      fallbackCurrency: currency
    )

    let displayTotals = PayrollEngine.summarizeShiftTotals(  // swiftlint:disable:this explicit_type_interface
      shifts: primaryMonthShifts,
      halfTaxMonth: halfTaxMonth,
      earningsMonth: displayYM.month,
      now: now
    )
    let displayTaxEnabled = currentMonthAggregate.primary.hasTaxEnabled  // swiftlint:disable:this explicit_type_interface line_length
    let completedShiftsCount = currentMonthAggregate.primary.completedShiftCount  // swiftlint:disable:this explicit_type_interface line_length
    let plannedShiftsCount = currentMonthAggregate.primary.plannedShiftCount  // swiftlint:disable:this explicit_type_interface line_length

    // Same computation as Stats: gross shift pay in the primary currency, without payroll adjustments.
    let percentChange = MonthlyEarningsChange.percent(  // swiftlint:disable:this explicit_type_interface
      monthShifts: displayedMonthShifts,
      previousMonthShifts: previousMonthShifts,
      jobs: jobs,
      fallbackCurrency: currency,
      halfTaxMonth: halfTaxMonth,
      currentMonth: displayYM.month,
      previousMonth: previousYM.month,
      now: now
    )

    let current = Date.currentYearMonth()  // swiftlint:disable:this explicit_type_interface
    let isViewingCurrentMonth = displayYM.year == current.year && displayYM.month == current.month  // swiftlint:disable:this explicit_type_interface line_length

    let featuredSelection = DashboardFeaturedItemSelector.select(  // swiftlint:disable:this explicit_type_interface
      shifts: displayedMonthShifts,
      events: displayedMonthEvents,
      isViewingCurrentMonth: isViewingCurrentMonth,
      todayISO: today,
      now: now
    )

    let displayMonthName = monthNameStatic(year: displayYM.year, month: displayYM.month)  // swiftlint:disable:this explicit_type_interface line_length
    let previousMonthName = monthNameStatic(year: previousYM.year, month: previousYM.month)  // swiftlint:disable:this explicit_type_interface line_length

    return DashboardData(
      displayedYear: displayYM.year,
      displayedMonth: displayYM.month,
      payrollDate: payrollDate,
      payrollHasPassed: payrollHasPassed,
      previousMonthGross: previousGross,
      previousMonthNet: prevTaxEnabled ? previousNet : nil,
      previousMonthTax: prevTax,
      previousMonthTaxEnabled: prevTaxEnabled,
      previousMonthHasPayrollAdjustments: !previousPayrollAdjustments.isEmpty,
      currentMonthGross: displayTotals.gross,
      currentMonthNet: displayTaxEnabled ? displayTotals.net : nil,
      currentMonthCompletedGross: displayTotals.completedGross,
      currentMonthCompletedNet: displayTaxEnabled ? displayTotals.completedNet : nil,
      currentMonthShiftCount: currentMonthAggregate.primary.shiftCount,
      currentMonthCompletedCount: completedShiftsCount,
      currentMonthPlannedCount: plannedShiftsCount,
      percentageChangeVsPrevious: percentChange,
      currentMonthTaxEnabled: displayTaxEnabled,
      featuredItem: featuredSelection.item,
      featuredShift: featuredSelection.item?.shift,
      isFeaturedItemToday: featuredSelection.isToday,
      featuredShiftIsBestShift: featuredSelection.isBestShift,
      currentMonthName: displayMonthName,
      previousMonthName: previousMonthName,
      currency: currentMonthAggregate.primary.currency,
      currentMonthCurrencyAggregate: currentMonthAggregate
    )
  }

  nonisolated private static func monthNameStatic(year: Int, month: Int) -> String {  // swiftlint:disable:this line_length type_contents_order
    var components = DateComponents()  // swiftlint:disable:this explicit_type_interface
    components.year = year
    components.month = month
    components.day = 1
    guard let date = gregorianCalendar.date(from: components) else { return "" }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return FormatterCache.monthNameFormatter(locale: .appLocale).string(from: date)
  }

  nonisolated private static func findBestShiftStatic(in shifts: [ShiftWithComputations])  // swiftlint:disable:this line_length type_contents_order
    -> ShiftWithComputations?
  {
    guard !shifts.isEmpty else { return nil }  // swiftlint:disable:this conditional_returns_on_newline

    let maxGross = shifts.map(\.grossPay).max() ?? 0  // swiftlint:disable:this explicit_type_interface
    guard maxGross > 0 else { return shifts.first }  // swiftlint:disable:this conditional_returns_on_newline

    let bestShifts =  // swiftlint:disable:this explicit_type_interface
      shifts
      .filter { $0.grossPay == maxGross }
      .sorted { $0.shiftDate < $1.shiftDate }

    return bestShifts.first
  }

  // MARK: - Shift Operations

  /// Whether a shift update is in progress
  @Published private(set) var isUpdatingShift = false  // swiftlint:disable:this explicit_acl explicit_type_interface
  private var isUpdatingRecurringShift = false  // swiftlint:disable:this explicit_type_interface
  private var isUpdatingEvent = false  // swiftlint:disable:this explicit_type_interface
  private var isDeletingEvent = false  // swiftlint:disable:this explicit_type_interface

  // MARK: - Clock Operations

  func refreshClockState() async {  // swiftlint:disable:this explicit_acl type_contents_order
    await refreshClockActiveState(referenceDate: Date())
    maybeTriggerCelebration()
  }

  func refreshAppearanceSettingsFromLocal() async {  // swiftlint:disable:this explicit_acl type_contents_order
    guard let userId = await ensureCachedUserId() else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    guard let latestSettings = settingsRepository.getSettings(for: userId) else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length
    settings = latestSettings
    shouldShowDashboardClockButtons = latestSettings.effectiveShowDashboardClockButtons
  }

  func applyDashboardClockButtonsVisibility(_ isVisible: Bool) {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    shouldShowDashboardClockButtons = isVisible
  }

  func temporaryFeaturedShift(  // swiftlint:disable:this explicit_acl type_contents_order
    from session: TemporaryClockSession,
    at referenceDate: Date = Date()
  ) -> ShiftWithComputations {
    let alignedStart = Self.minuteAligned(session.startedAt)  // swiftlint:disable:this explicit_type_interface
    let alignedReference = max(Self.minuteAligned(referenceDate), alignedStart)  // swiftlint:disable:this explicit_type_interface line_length
    let shiftDate = alignedStart.toISODateString()  // swiftlint:disable:this explicit_type_interface
    let startTime = Self.timeString(from: alignedStart)  // swiftlint:disable:this explicit_type_interface
    let endTime = Self.timeString(from: alignedReference)  // swiftlint:disable:this explicit_type_interface
    let shift = ShiftRow(  // swiftlint:disable:this explicit_type_interface
      id: session.id,
      user_id: session.userId,
      job_id: session.jobId,
      shift_date: shiftDate,
      start_time: startTime,
      end_time: endTime,
      custom_supplements: nil
    )

    let snapshot = snapshotsRepository.snapshotForDate(  // swiftlint:disable:this explicit_type_interface
      shiftDate,
      userId: session.userId,
      jobId: session.jobId
    )

    let computed: ShiftComputed
    if startTime == endTime {
      // HH:mm precision can produce equal start/end in the first minute; keep preview at zero
      // until at least one minute has elapsed to avoid accidental cross-midnight interpretation.
      computed = Self.zeroShiftComputed(id: session.id)
    } else {
      computed = PayrollCalculator.computeShift(shift, snapshot: snapshot)
    }

    return ShiftWithComputations(
      shift: shift,
      computed: computed,
      taxEnabled: snapshot?.effectiveTaxEnabled ?? false,
      taxPercentage: snapshot?.effectiveTaxPercentage ?? 0
    )
  }

  func liveFeaturedShiftWhileOngoing(  // swiftlint:disable:this explicit_acl type_contents_order
    from shift: ShiftWithComputations,
    at referenceDate: Date = Date()
  ) -> ShiftWithComputations {
    let alignedReference = Self.minuteAligned(referenceDate)  // swiftlint:disable:this explicit_type_interface
    let endTime = Self.timeString(from: alignedReference)  // swiftlint:disable:this explicit_type_interface
    let reconstructedShift = ShiftRow(  // swiftlint:disable:this explicit_type_interface
      id: shift.id,
      user_id: shift.shift.user_id,
      job_id: shift.shift.job_id,
      shift_date: shift.shiftDate,
      start_time: shift.startTime,
      end_time: endTime,
      custom_supplements: shift.shift.custom_supplements
    )

    let snapshot: WageSnapshot?
    if let snapshotUserId = shift.shift.user_id ?? cachedUserId {
      snapshot = snapshotsRepository.snapshotForDate(
        shift.shiftDate,
        userId: snapshotUserId,
        jobId: shift.shift.job_id
      )
    } else {
      snapshot = nil
    }

    let computed: ShiftComputed
    if shift.startTime == endTime {
      computed = Self.zeroShiftComputed(id: shift.id)
    } else {
      computed = PayrollCalculator.computeShift(reconstructedShift, snapshot: snapshot)
    }

    return ShiftWithComputations(
      shift: reconstructedShift,
      computed: computed,
      taxEnabled: shift.taxEnabled,
      taxPercentage: shift.taxPercentage,
      calculationContext: shift.calculationContext
    )
  }

  func clockIn(jobId: String? = nil, at now: Date = Date()) async {  // swiftlint:disable:this explicit_acl function_body_length line_length type_contents_order
    guard !isClockActionInProgress else {
      return
    }
    await refreshClockActiveState(referenceDate: now)

    guard case .none = activeClockState else {
      // Self-heal: if an active local clock state exists but its Live Activity is missing,
      // reconciling can recreate the temporary activity.
      await ClockSessionReconciler.shared.reconcileIfNeeded(referenceDate: now)
      return
    }

    guard let userId = await ensureCachedUserId() else {
      logger.error("❌ Clock in aborted: unable to resolve user ID")
      return
    }
    let resolvedJobId = jobId ?? defaultJobId(for: userId)  // swiftlint:disable:this explicit_type_interface
    do {
      _ = try jobPaySetupStatusService.requireConfiguredActiveJob(
        userId: userId,
        requestedJobId: resolvedJobId
      )
    } catch {
      logger.info("Clock in requires pay setup before starting a temporary session")
      return
    }

    let alignedStart = Self.minuteAligned(now)  // swiftlint:disable:this explicit_type_interface
    let session = TemporaryClockSession(  // swiftlint:disable:this explicit_type_interface
      id: UUID().lowercasedString,
      userId: userId,
      jobId: resolvedJobId,
      startedAt: alignedStart,
      createdAt: now
    )
    clockSessionStore.save(session)
    activeClockState = .temporary(session)

    let currency = settings?.currency ?? "kr"  // swiftlint:disable:this explicit_type_interface
    guard let appDelegate = (UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared
    else {
      logger.error("❌ Clock in aborted: AppDelegate unavailable")
      return
    }

    await appDelegate.startTemporaryLiveActivity(
      shiftId: session.id,
      startedAt: session.startedAt,
      currencySymbol: currency
    )
  }

  func routeClockOut(at now: Date = Date()) async -> ClockOutRoute {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard !isClockActionInProgress else { return .none }  // swiftlint:disable:this conditional_returns_on_newline
    await refreshClockActiveState(referenceDate: now)

    switch activeClockState {
    case .none:
      return .none

    case .temporary(let session):
      return .temporaryReview(session)

    case .persisted(let ongoingShift):
      isClockActionInProgress = true
      defer { isClockActionInProgress = false }
      await endShiftNow(ongoingShift, at: now)
      await refreshClockActiveState(referenceDate: Date())
      return .persistedEnded

    case .computed(let ongoingShift):
      isClockActionInProgress = true
      defer { isClockActionInProgress = false }
      await endShiftNow(ongoingShift, at: now)
      await refreshClockActiveState(referenceDate: Date())
      return .persistedEnded
    }
  }

  func commitTemporaryClockOut(start: Date, end: Date, jobId: String? = nil) async throws {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard end > start else { throw ClockError.invalidRange }
    guard !isClockActionInProgress else { return }  // swiftlint:disable:this conditional_returns_on_newline

    let session: TemporaryClockSession
    if case .temporary(let activeSession) = activeClockState {
      session = activeSession
    } else {
      guard
        let userId = await ensureCachedUserId(),
        let storedSession = clockSessionStore.activeSession(for: userId)
      else {
        throw ClockError.noActiveSession
      }
      activeClockState = .temporary(storedSession)
      session = storedSession
    }

    if hasExceededMaxDuration(session, at: Date())
      || ClockSessionRules.exceedsMaxDuration(from: start, to: end)
    {
      throw ClockError.maxDurationExceeded
    }

    isClockActionInProgress = true
    defer { isClockActionInProgress = false }

    let resolvedJobId = jobId ?? session.jobId ?? defaultJobId(for: session.userId)  // swiftlint:disable:this explicit_type_interface line_length
    let shiftDate = Calendar.current.startOfDay(for: start)  // swiftlint:disable:this explicit_type_interface
    _ = try await shiftsRepository.createShift(
      shiftId: session.id,
      userId: session.userId,
      jobId: resolvedJobId,
      shiftDate: shiftDate,
      startTime: Self.timeString(from: start),
      endTime: Self.timeString(from: end),
      customSupplements: nil
    )

    cancelTemporarySession(session)

    await reloadFromLocal()
    notifyShiftsDidChange(context: .affecting(date: shiftDate))
    await refreshClockActiveState(referenceDate: Date())
  }

  func discardTemporaryClockSession() async {  // swiftlint:disable:this explicit_acl type_contents_order
    guard !isClockActionInProgress else { return }  // swiftlint:disable:this conditional_returns_on_newline

    await refreshClockActiveState(referenceDate: Date())
    guard case .temporary(let session) = activeClockState else { return }  // swiftlint:disable:this conditional_returns_on_newline line_length

    cancelTemporarySession(session)
    notifyShiftsDidChange(context: .affecting(date: session.startedAt))
    await refreshClockActiveState(referenceDate: Date())
  }

  func clockSelectableJobs() async -> [Job] {  // swiftlint:disable:this explicit_acl type_contents_order
    if !displayJobs.isEmpty {
      return sortClockJobs(displayJobs)
    }

    guard let userId = await ensureCachedUserId() else { return [] }  // swiftlint:disable:this conditional_returns_on_newline line_length
    displayJobs = jobsRepository.getNonDeletedJobs(for: userId)
    return sortClockJobs(displayJobs)
  }

  func clockSelectableJobsSnapshot() -> [Job] {  // swiftlint:disable:this explicit_acl type_contents_order
    sortClockJobs(displayJobs)
  }

  func clockJobRequiringPaySetup(jobId: String?) async -> Job? {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard let userId = await ensureCachedUserId() else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length
    if displayJobs.isEmpty {
      displayJobs = jobsRepository.getNonDeletedJobs(for: userId)
    }

    let activeJobs = sortClockJobs(displayJobs)  // swiftlint:disable:this explicit_type_interface
    let resolvedJob: Job?
    if let jobId {
      resolvedJob = activeJobs.first { $0.id == jobId }
    } else {
      resolvedJob = activeJobs.first(where: \.is_default) ?? activeJobs.first
    }

    guard let resolvedJob else { return nil }  // swiftlint:disable:this conditional_returns_on_newline
    return jobPaySetupStatusService.isJobConfigured(userId: userId, jobId: resolvedJob.id)
      ? nil
      : resolvedJob
  }

  func completeClockPaySetup(for job: Job, input: JobPaySetupInput) async -> Bool {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard let userId = await ensureCachedUserId() else { return false }  // swiftlint:disable:this conditional_returns_on_newline line_length

    do {
      _ = try await jobsRepository.completePaySetup(
        userId: userId,
        jobId: job.id,
        currency: input.currency,
        payrollDay: input.payrollDay,
        halfTaxMonth: input.halfTaxMonth,
        monthlyGoal: job.monthly_goal,
        baselineSnapshot: input.baselineSnapshot
      )
      displayJobs = jobsRepository.getNonDeletedJobs(for: userId)
      await reloadFromLocal()
      notifyShiftsDidChange(context: .fullReload)
      Haptics.play(.success)
      return true
    } catch {
      logger.error("❌ Failed to complete clock pay setup: \(error.localizedDescription)")
      return false
    }
  }

  func preloadClockSelectableJobs() async {  // swiftlint:disable:this explicit_acl type_contents_order
    _ = await clockSelectableJobs()
  }

  func preferredClockJobId(for session: TemporaryClockSession) -> String? {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    let selectableJobs = sortClockJobs(displayJobs)  // swiftlint:disable:this explicit_type_interface
    let defaultJobId = selectableJobs.first(where: \.is_default)?.id  // swiftlint:disable:this explicit_type_interface
    return session.jobId ?? defaultJobId ?? selectableJobs.first?.id
  }

  /// Get tariff supplement rules for a specific shift date
  /// Used by ShiftDetailsSheet to show applicable tariff rules
  /// - Parameter shiftDate: ISO date string (YYYY-MM-DD)
  /// - Returns: Array of supplement rules from the applicable snapshot
  func getTariffRules(for shiftDate: String) -> [SupplementRule] {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard let snapshot = SnapshotsService.snapshotForDate(shiftDate, from: snapshots) else {
      return []
    }
    return snapshot.effectiveSupplements
  }

  /// Get a recurring shift by ID
  /// - Parameter id: The recurring shift ID
  /// - Returns: The recurring shift if found
  func getRecurringShift(id: String) -> RecurringShiftRow? {  // swiftlint:disable:this explicit_acl type_contents_order
    recurringShiftsRepository.getRecurringShift(id: id)
  }

  func stopRecurringShiftAfterDate(recurringId: String, occurrenceDate: String) async throws {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard !isUpdatingRecurringShift else { throw ShiftSaveError.alreadyInProgress }

    isUpdatingRecurringShift = true
    defer { isUpdatingRecurringShift = false }

    _ = try await recurringShiftsRepository.updateRecurringShift(
      id: recurringId,
      endCondition: .endDate(date: occurrenceDate)
    )

    resetDashboardDependencies(preservingDisplayJobs: true)
    await reloadFromLocal()
    notifyShiftsDidChange(context: .fullReload)
  }

  func getDisplayedShift(id: String) -> ShiftWithComputations? {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    displayedMonthShifts.first(where: { $0.id == id })
  }

  // MARK: - Event Operations

  func updateEvent(_ editResult: EventEditResult) async throws {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard !isUpdatingEvent else { return }  // swiftlint:disable:this conditional_returns_on_newline

    isUpdatingEvent = true
    defer { isUpdatingEvent = false }
    let existingEvent = displayedMonthEvents.first(where: { $0.id == editResult.eventId })  // swiftlint:disable:this explicit_type_interface line_length

    guard
      let startDate = Date.fromISODateString(editResult.startDate),
      let endDate = Date.fromISODateString(editResult.endDate)
    else {
      throw ShiftsError.invalidEventDateRange
    }

    guard
      try await eventsRepository.updateEvent(
        id: editResult.eventId,
        startDate: startDate,
        endDate: endDate,
        isAllDay: editResult.isAllDay,
        startTime: editResult.startTime,
        endTime: editResult.endTime,
        note: editResult.note,
        notificationMinutesArray: editResult.notificationMinutesArray,
        notificationAnchorTime: editResult.notificationAnchorTime
      ) != nil
    else {
      throw ShiftsError.eventNotFound
    }

    await reloadFromLocal()
    notifyShiftsDidChange(
      context: eventChangeContext(
        for: editResult,
        existingEvent: existingEvent
      ))  // swiftlint:disable:this multiline_arguments_brackets
  }

  func deleteEvent(_ event: EventRow) async throws {  // swiftlint:disable:this explicit_acl type_contents_order
    guard !isDeletingEvent else { return }  // swiftlint:disable:this conditional_returns_on_newline

    isDeletingEvent = true
    defer { isDeletingEvent = false }

    try await eventsRepository.deleteEvent(id: event.id)
    await reloadFromLocal()
    notifyShiftsDidChange(
      context: .affecting(
        isoDateRangeStart: event.start_date,
        end: event.end_date
      ))  // swiftlint:disable:this multiline_arguments_brackets
  }

  /// End an active shift immediately using the current local device time.
  /// Uses the existing update pipeline so sync/reload behavior stays consistent.
  /// - Parameters:
  ///   - shift: The shift to end now
  ///   - now: Optional reference time for testing
  func endShiftNow(_ shift: ShiftWithComputations, at now: Date = Date()) async {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard !isUpdatingShift else { return }  // swiftlint:disable:this conditional_returns_on_newline

    ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?.endLiveActivity(
      for: shift.id)  // swiftlint:disable:this multiline_arguments_brackets

    let editResult = ShiftEditResult(  // swiftlint:disable:this explicit_type_interface
      shiftId: shift.id,
      shiftDate: shift.shiftDate,
      startTime: String(shift.startTime.prefix(5)),  // swiftlint:disable:this no_magic_numbers
      endTime: Self.timeString(from: now),
      isVirtualShiftConversion: shift.isVirtual,
      recurringId: shift.shift.recurring_id,
      originalDate: shift.shiftDate,
      customSupplements: nil
    )

    do {
      try await updateShift(editResult)
    } catch {
      logger.error("❌ Failed to end active shift: \(error.localizedDescription)")
    }
  }

  /// End a persisted (non-virtual) shift immediately.
  /// This is used by dashboard clock actions when an ongoing normal shift exists.
  func endShiftNow(_ shift: ShiftRow, at now: Date = Date()) async {  // swiftlint:disable:this explicit_acl line_length type_contents_order
    guard !isUpdatingShift else { return }  // swiftlint:disable:this conditional_returns_on_newline

    ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?.endLiveActivity(
      for: shift.id)  // swiftlint:disable:this multiline_arguments_brackets

    let editResult = ShiftEditResult(  // swiftlint:disable:this explicit_type_interface
      shiftId: shift.id,
      shiftDate: shift.shift_date,
      startTime: String(shift.start_time.prefix(5)),  // swiftlint:disable:this no_magic_numbers
      endTime: Self.timeString(from: now),
      isVirtualShiftConversion: false,
      recurringId: nil,
      originalDate: shift.shift_date,
      customSupplements: nil
    )

    do {
      try await updateShift(editResult)
    } catch {
      logger.error("❌ Failed to end persisted shift: \(error.localizedDescription)")
    }
  }

  /// Update a shift with new date/time values
  /// - Parameter editResult: The result from the shift edit form
  func updateShift(_ editResult: ShiftEditResult) async throws {  // swiftlint:disable:this cyclomatic_complexity explicit_acl function_body_length line_length type_contents_order
    // Prevent duplicate taps
    guard !isUpdatingShift else { throw ShiftSaveError.alreadyInProgress }

    isUpdatingShift = true
    defer { isUpdatingShift = false }
    logger.info("📝 Updating shift \(editResult.shiftId)")

    do {
      // Parse the new date
      guard let newDate = Date.fromISODateString(editResult.shiftDate) else {
        logger.error("Invalid date format: \(editResult.shiftDate)")
        throw ShiftSaveError.invalidDate
      }

      let currentShift = displayedMonthShifts.first(where: { $0.id == editResult.shiftId })?.shift  // swiftlint:disable:this explicit_type_interface line_length
      let hasTimeOrDateChanges =  // swiftlint:disable:this explicit_type_interface
        editResult.shiftDate != currentShift?.shift_date
        || editResult.startTime != currentShift.map { String($0.start_time.prefix(5)) }  // swiftlint:disable:this line_length no_magic_numbers
        || editResult.endTime != currentShift.map { String($0.end_time.prefix(5)) }  // swiftlint:disable:this line_length no_magic_numbers
      let resolvedNote = editResult.noteWasEdited ? editResult.note : currentShift?.note  // swiftlint:disable:this explicit_type_interface line_length

      if editResult.isVirtualShiftConversion {
        // Virtual shift conversion:
        // 1. Add exclusion to the recurring shift for the original date
        // 2. Create a new regular shift with the edited values
        logger.info("🔄 Converting virtual shift to regular shift")

        // Get user ID
        guard let recurringId = editResult.recurringId,
          let userId = cachedUserId
        else {
          logger.error("Missing recurringId or userId for virtual shift conversion")
          throw ShiftSaveError.missingRecurringInfo
        }

        let recurringShift =  // swiftlint:disable:this explicit_type_interface
          recurringShifts.first(where: { $0.id == recurringId })
          ?? recurringShiftsRepository.getRecurringShift(id: recurringId)

        if !hasTimeOrDateChanges, editResult.customSupplements == nil, editResult.noteWasEdited {
          var updatedNotes = recurringShift?.date_specific_notes ?? [:]  // swiftlint:disable:this explicit_type_interface line_length
          if let resolvedNote {
            updatedNotes[editResult.originalDate] = resolvedNote
          } else {
            updatedNotes.removeValue(forKey: editResult.originalDate)
          }

          _ = try await recurringShiftsRepository.updateDateSpecificNotes(
            id: recurringId,
            dateSpecificNotes: updatedNotes
          )
          logger.info("✅ Updated recurring note for \(editResult.originalDate)")
        } else {
          if var updatedNotes = recurringShift?.date_specific_notes {
            updatedNotes.removeValue(forKey: editResult.originalDate)
            _ = try await recurringShiftsRepository.updateDateSpecificNotes(
              id: recurringId,
              dateSpecificNotes: updatedNotes
            )
          }

          // Step 1: Add exclusion for the original date
          try await RecurringShiftsRepository.shared.addExclusion(
            id: recurringId,
            date: editResult.originalDate
          )
          logger.info("✅ Added exclusion for \(editResult.originalDate)")

          let sourceJobId =  // swiftlint:disable:this explicit_type_interface
            displayedMonthShifts.first(where: { $0.id == editResult.shiftId })?.shift.job_id
            ?? recurringShifts.first(where: { $0.id == recurringId })?.job_id

          // Step 2: Create a new regular shift with the edited values
          _ = try await shiftsRepository.createShift(
            userId: userId,
            jobId: sourceJobId,
            shiftDate: newDate,
            startTime: editResult.startTime,
            endTime: editResult.endTime,
            note: resolvedNote,
            customSupplements: editResult.customSupplements
          )
          logger.info("✅ Created new shift on \(editResult.shiftDate)")

          if var updatedNotes = recurringShift?.date_specific_notes {
            updatedNotes.removeValue(forKey: editResult.originalDate)
            _ = try await recurringShiftsRepository.updateDateSpecificNotes(
              id: recurringId,
              dateSpecificNotes: updatedNotes
            )
          }
        }

      } else {
        // Regular shift update - just update the existing shift
        _ = try await shiftsRepository.updateShift(
          id: editResult.shiftId,
          shiftDate: newDate,
          startTime: editResult.startTime,
          endTime: editResult.endTime,
          note: editResult.note,
          noteWasEdited: editResult.noteWasEdited,
          customSupplements: editResult.customSupplements
        )
        logger.info("✅ Updated shift \(editResult.shiftId)")
      }

      // Reload to show the changes
      await reloadFromLocal()

      // Post notification for other views
      notifyShiftsDidChange(
        context: shiftChangeContext(
          for: editResult,
          existingShift: currentShift
        ))  // swiftlint:disable:this multiline_arguments_brackets

    } catch {
      logger.error("❌ Failed to update shift: \(error.localizedDescription)")
      throw error
    }
  }

  func updateShiftPause(_ editResult: ShiftPauseEditResult) async {  // swiftlint:disable:this cyclomatic_complexity explicit_acl function_body_length line_length type_contents_order
    guard !isUpdatingShift else { return }  // swiftlint:disable:this conditional_returns_on_newline

    isUpdatingShift = true
    defer { isUpdatingShift = false }

    logger.info("⏸️ Updating shift pause windows")
    let changeContext: ShiftChangeContext

    switch editResult.target {
    case .standalone(let shiftId):
      if let shift = displayedMonthShifts.first(where: { $0.id == shiftId }) {
        changeContext = .affecting(isoDate: shift.shiftDate)
      } else {
        changeContext = .fullReload
      }

    case .recurringOccurrence(_, let date):
      changeContext = .affecting(isoDate: date)
    }

    do {
      switch editResult.target {
      case .standalone(let shiftId):
        _ = try await shiftsRepository.updateCustomPauseWindows(
          id: shiftId,
          customPauseWindows: editResult.customPauseWindows
        )

      case .recurringOccurrence(let recurringId, let date):  // swiftlint:disable:this pattern_matching_keywords
        guard
          let recurringShift = recurringShifts.first(where: { $0.id == recurringId })
            ?? recurringShiftsRepository.getRecurringShift(id: recurringId)
        else {
          logger.error("Recurring shift not found for pause update: \(recurringId)")
          return
        }

        var updatedPauseWindows = recurringShift.date_specific_pause_windows ?? [:]  // swiftlint:disable:this explicit_type_interface line_length
        if let normalized = PauseWindowSupport.normalize(editResult.customPauseWindows) {
          updatedPauseWindows[date] = normalized
        } else {
          updatedPauseWindows.removeValue(forKey: date)
        }

        _ = try await recurringShiftsRepository.updateDateSpecificPauseWindows(
          id: recurringId,
          dateSpecificPauseWindows: PauseWindowSupport.normalize(updatedPauseWindows)
        )
      }

      await reloadFromLocal()
      notifyShiftsDidChange(context: changeContext)
    } catch {
      logger.error("❌ Failed to update shift pause windows: \(error.localizedDescription)")
    }
  }

  private func ensureCachedUserId() async -> String? {  // swiftlint:disable:this type_contents_order
    if let cachedUserId, !cachedUserId.isEmpty {
      return cachedUserId
    }

    // Use session-derived user ID for clock actions to avoid stale settings/coordinator
    // values during reload/account-context transitions.
    cachedUserId = try? await getCurrentUserId()
    return cachedUserId
  }

  private func defaultJobId(for userId: String) -> String? {  // swiftlint:disable:this type_contents_order
    if displayJobs.isEmpty {
      displayJobs = jobsRepository.getNonDeletedJobs(for: userId)
    }
    let activeJobs = displayJobs.filter { $0.archived_at == nil && $0.deleted_at == nil }  // swiftlint:disable:this explicit_type_interface line_length
    return activeJobs.first(where: \.is_default)?.id ?? activeJobs.first?.id
  }

  private func sortClockJobs(_ jobs: [Job]) -> [Job] {  // swiftlint:disable:this type_contents_order
    let selectableJobs = jobs.filter { $0.archived_at == nil && $0.deleted_at == nil }  // swiftlint:disable:this explicit_type_interface line_length
    return selectableJobs.sorted { lhs, rhs in
      if lhs.is_default != rhs.is_default {
        return lhs.is_default && !rhs.is_default
      }
      if lhs.sort_order != rhs.sort_order {
        return lhs.sort_order < rhs.sort_order
      }
      return lhs.name.localizedCompare(rhs.name) == .orderedAscending
    }
  }

  private func refreshClockActiveState(referenceDate: Date) async {  // swiftlint:disable:this type_contents_order
    await ClockSessionReconciler.shared.reconcileIfNeeded(referenceDate: referenceDate)

    guard let userId = await ensureCachedUserId() else {
      activeClockState = .none
      return
    }

    if let session = clockSessionStore.activeSession(for: userId) {
      if hasExceededMaxDuration(session, at: referenceDate) {
        cancelTemporarySession(session)
      } else {
        activeClockState = .temporary(session)
        return
      }
    }

    if let ongoingShift = await findPersistedOngoingShift(for: userId, at: referenceDate) {
      activeClockState = .persisted(ongoingShift)
      return
    }

    if let ongoingShift = findComputedOngoingShift(at: referenceDate) {
      activeClockState = .computed(ongoingShift)
      return
    }

    activeClockState = .none
  }

  private func cancelTemporarySession(_ session: TemporaryClockSession) {  // swiftlint:disable:this type_contents_order
    ((UIApplication.shared.delegate as? AppDelegate) ?? AppDelegate.shared)?.endLiveActivity(
      for: session.id)  // swiftlint:disable:this multiline_arguments_brackets
    clockSessionStore.clear(for: session.userId)
  }

  private func hasExceededMaxDuration(_ session: TemporaryClockSession, at referenceDate: Date)  // swiftlint:disable:this line_length type_contents_order
    -> Bool
  {
    ClockSessionRules.hasExceededMaxDuration(session, at: referenceDate)
  }

  private func findPersistedOngoingShift(for userId: String, at referenceDate: Date) async  // swiftlint:disable:this line_length type_contents_order
    -> ShiftRow?
  {
    let calendar = Calendar.current  // swiftlint:disable:this explicit_type_interface
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

  /// Fallback for ongoing recurring/virtual shifts that are visible in dashboard data
  /// but not persisted in the local shifts table yet.
  private func findComputedOngoingShift(at referenceDate: Date) -> ShiftWithComputations? {  // swiftlint:disable:this line_length type_contents_order
    var best: ShiftWithComputations?

    for shift in displayedMonthShifts where Self.isShiftOngoing(shift.shift, at: referenceDate) {
      guard let currentBest = best else {
        best = shift
        continue
      }

      if shift.shiftDate < currentBest.shiftDate
        || (shift.shiftDate == currentBest.shiftDate && shift.startTime < currentBest.startTime)
      {
        best = shift
      }
    }

    return best
  }

  // MARK: - Payroll Override Helpers

  private func payrollReceivedOverrideKeyForDisplayedMonth(userId: String? = nil) -> String? {  // swiftlint:disable:this line_length type_contents_order
    let resolvedUserId = userId ?? cachedUserId  // swiftlint:disable:this explicit_type_interface
    guard let resolvedUserId, !resolvedUserId.isEmpty else { return nil }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return "dashboard.payroll.received.\(resolvedUserId).\(displayYearMonthKey)"
  }

  private var displayYearMonthKey: String {
    String(format: "%04d-%02d", displayYear, displayMonth)
  }

  // MARK: - Helper Methods

  private static func timeString(from date: Date) -> String {
    ClockSessionRules.timeString(from: date)
  }

  private static func minuteAligned(_ date: Date) -> Date {
    var calendar = Calendar(identifier: .gregorian)  // swiftlint:disable:this explicit_type_interface
    calendar.timeZone = Date.localTimeZone
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)  // swiftlint:disable:this explicit_type_interface line_length
    return calendar.date(from: components) ?? date
  }

  private static func isShiftOngoing(_ shift: ShiftRow, at date: Date) -> Bool {
    ClockSessionRules.isShiftOngoing(shift, at: date)
  }

  private static func zeroShiftComputed(id: String) -> ShiftComputed {
    ShiftComputed(
      id: id,
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

  /// Calculate the adjusted payroll date for a given month
  /// Adjusts backwards if the date falls on a weekend, Monday, or Norwegian public holiday
  private func calculatePayrollDate(year: Int, month: Int, day: Int) -> Date {
    return PayrollDateAdjuster.adjustPayrollDate(payrollDay: day, month: month, year: year)
  }

  private func monthName(year: Int, month: Int) -> String {
    var components = DateComponents()  // swiftlint:disable:this explicit_type_interface
    components.year = year
    components.month = month
    components.day = 1
    guard let date = Self.gregorianCalendar.date(from: components) else { return "" }  // swiftlint:disable:this conditional_returns_on_newline line_length
    return FormatterCache.monthNameFormatter(locale: .appLocale).string(from: date)
  }

  /// Find the best (highest earnings) shift in a collection
  /// Returns the first shift chronologically if multiple have the same max earnings
  private func findBestShift(in shifts: [ShiftWithComputations]) -> ShiftWithComputations? {
    guard !shifts.isEmpty else { return nil }  // swiftlint:disable:this conditional_returns_on_newline

    // Find max gross earnings
    let maxGross = shifts.map(\.grossPay).max() ?? 0  // swiftlint:disable:this explicit_type_interface
    guard maxGross > 0 else { return shifts.first }  // swiftlint:disable:this conditional_returns_on_newline

    // Get all shifts with max earnings, sorted chronologically
    let bestShifts =  // swiftlint:disable:this explicit_type_interface
      shifts
      .filter { $0.grossPay == maxGross }
      .sorted { $0.shiftDate < $1.shiftDate }

    return bestShifts.first
  }
}  // swiftlint:disable:this file_length
