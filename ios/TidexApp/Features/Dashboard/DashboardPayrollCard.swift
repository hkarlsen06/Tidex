import Combine
import Foundation
import Observation
import UIKit
import os.log  // swiftlint:disable:this sorted_imports

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
  var earningsPeriodStart: Date?
  var earningsPeriodEnd: Date?
  var payoutTaxSettings: PayoutTaxSettings?
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
    calendar: Calendar = .gregorianCurrent
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
    calendar: Calendar = .gregorianCurrent
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
    calendar: Calendar = .gregorianCurrent
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
    calendar: Calendar = .gregorianCurrent
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