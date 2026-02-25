import Foundation
import SwiftUI
import UIKit

/// Local-only Add tab simulator for pre-auth onboarding.
/// Mirrors single-shift interactions without persisting or requiring auth.
@MainActor
final class PreAuthAddShiftSimulatorViewModel: ObservableObject, AddShiftCalendarViewModeling {
  @Published var startTime: Date? = nil {
    didSet { updateConflictsAndPreviews() }
  }

  @Published var endTime: Date? = nil {
    didSet { updateConflictsAndPreviews() }
  }

  @Published var selectedDates: Set<String> = [] {
    didSet { updateConflictsAndPreviews() }
  }

  @Published private(set) var conflictDates: Set<String> = []
  @Published private(set) var previewEarnings: [String: CalendarEarningsData] = [:]
  @Published private(set) var existingShiftHours: [String: HoursData] = [:]
  @Published private(set) var baselineToolbarTotals: CalendarHeaderTotals?
  @Published private(set) var toolbarTotals: CalendarHeaderTotals?

  let displayMonth: Date
  let displayYear: Int
  let displayMonthNumber: Int
  let currency: String
  let presetTimeRanges: [TimeRangeCount]

  private let payrollDay: Int = 15
  private let snapshots: [WageSnapshot]
  private let existingShifts: [ShiftRow]
  private let existingShiftEarnings: [String: CalendarEarningsData]

  var displayMonthName: String {
    CalendarGridHelper.monthName(from: displayMonth, locale: .appLocale)
  }

  var monthPhase: MonthTransitionPhase {
    MonthTransitionPhase(year: displayYear, month: displayMonthNumber, direction: nil)
  }

  var canContinue: Bool {
    !selectedDates.isEmpty && hasValidTimes
  }

  init() {
    let current = Date.currentYearMonth()
    displayYear = current.year
    displayMonthNumber = current.month

    var components = DateComponents()
    components.year = current.year
    components.month = current.month
    components.day = 1
    displayMonth = Calendar.current.date(from: components) ?? Date()

    currency = Locale.current.isNorwegian ? "kr" : "$"

    presetTimeRanges = [
      TimeRangeCount(startTime: "08:00", endTime: "16:00", count: 9),
      TimeRangeCount(startTime: "09:00", endTime: "17:00", count: 7),
      TimeRangeCount(startTime: "12:00", endTime: "20:00", count: 5),
      TimeRangeCount(startTime: "14:00", endTime: "22:00", count: 3),
      TimeRangeCount(startTime: "22:00", endTime: "06:00", count: 2),
    ]

    let defaultHourlyWage = Locale.current.isNorwegian ? 200.0 : 25.0
    snapshots = [Self.makeBaselineSnapshot(hourlyWage: defaultHourlyWage)]

    existingShifts = Self.makeSeededShifts(year: current.year, month: current.month)

    existingShiftHours = Self.buildExistingHoursMap(from: existingShifts)
    existingShiftEarnings = Self.buildExistingEarningsMap(
      shifts: existingShifts,
      snapshots: snapshots,
      payrollDay: payrollDay
    )

    baselineToolbarTotals = computeToolbarTotals(
      previewByDate: [:],
      conflicts: []
    )

    updateConflictsAndPreviews()
  }

  func toggleDate(_ dateISO: String) {
    if selectedDates.contains(dateISO) {
      selectedDates.remove(dateISO)
    } else {
      selectedDates.insert(dateISO)
    }

    let generator = UIImpactFeedbackGenerator(style: .light)
    generator.impactOccurred()
  }

  // MARK: - Computation

  private var hasValidTimes: Bool {
    startTime != nil && endTime != nil
  }

  private var startTimeString: String {
    guard let time = startTime else { return "" }
    return Self.formatTimeAsHHmm(time)
  }

  private var endTimeString: String {
    guard let time = endTime else { return "" }
    let formatted = Self.formatTimeAsHHmm(time)
    if formatted == "00:00", let start = startTime, Self.formatTimeAsHHmm(start) != "00:00" {
      return "24:00"
    }
    return formatted
  }

  private func updateConflictsAndPreviews() {
    guard hasValidTimes, !selectedDates.isEmpty else {
      conflictDates = []
      previewEarnings = [:]
      updateToolbarTotals()
      return
    }

    let selected = Array(selectedDates)

    conflictDates = ShiftConflictDetector.detectConflicts(
      dates: selected,
      startTime: startTimeString,
      endTime: endTimeString,
      existingShifts: existingShifts
    )

    var nextPreview: [String: CalendarEarningsData] = [:]
    for dateISO in selected {
      if let earnings = computeEarningsForDate(dateISO) {
        nextPreview[dateISO] = earnings
      }
    }

    previewEarnings = nextPreview
    updateToolbarTotals()
  }

  private func updateToolbarTotals() {
    toolbarTotals = computeToolbarTotals(
      previewByDate: previewEarnings,
      conflicts: conflictDates
    )
  }

  private func computeToolbarTotals(
    previewByDate: [String: CalendarEarningsData],
    conflicts: Set<String>
  ) -> CalendarHeaderTotals? {
    let totals = ConflictExclusion.combinedEarnings(
      existingByDate: existingShiftEarnings,
      previewByDate: previewByDate,
      conflictDates: conflicts
    )

    guard totals.gross > 0 else {
      return nil
    }

    return CalendarHeaderTotals(
      primary: totals.hasTaxEnabled ? totals.net : totals.gross,
      secondary: totals.hasTaxEnabled ? totals.gross : nil
    )
  }

  private func computeEarningsForDate(_ dateISO: String) -> CalendarEarningsData? {
    let wageSnapshot = SnapshotsService.snapshotForDate(dateISO, from: snapshots)

    let payoutDate = PayrollEngine.calculatePayoutDate(
      shiftDate: dateISO,
      payrollDay: payrollDay
    )
    let taxSnapshot = SnapshotsService.snapshotForDate(payoutDate, from: snapshots)

    let shift = ShiftRow(
      id: "onboarding-preview-\(dateISO)",
      user_id: nil,
      shift_date: dateISO,
      start_time: startTimeString,
      end_time: endTimeString,
      custom_supplements: nil
    )

    let computed = PayrollCalculator.computeShift(shift, snapshot: wageSnapshot)
    let taxEnabled = taxSnapshot?.effectiveTaxEnabled ?? false
    let net = computed.netPay(
      taxEnabled: taxEnabled,
      taxPercentage: taxSnapshot?.effectiveTaxPercentage ?? 0
    )

    return CalendarEarningsData(net: net, gross: computed.gross, hasTaxEnabled: taxEnabled)
  }

  // MARK: - Seed Data

  private static func makeBaselineSnapshot(hourlyWage: Double) -> WageSnapshot {
    WageSnapshot(
      id: "onboarding-baseline",
      user_id: "onboarding-demo",
      from_date: nil,
      hourly_wage: hourlyWage,
      wage_level: nil,
      tariff_type_id: nil,
      supplements: SupplementRulesSnapshot(rules: []),
      tax_enabled: true,
      tax_percentage: 20,
      break_enabled: true,
      break_method: BreakMethod.proportional.rawValue,
      break_threshold_hours: 5.5,
      break_deduction_minutes: 30,
      created_at: nil
    )
  }

  private static func makeSeededShifts(year: Int, month: Int) -> [ShiftRow] {
    let daysInMonth = Date.daysInMonth(year: year, month: month)

    let seed: [(day: Int, start: String, end: String)] = [
      (3, "08:00", "16:00"),
      (7, "14:00", "22:00"),
      (12, "09:00", "17:00"),
      (19, "12:00", "20:00"),
      (24, "22:00", "06:00"),
    ]

    return seed.compactMap { item in
      guard item.day <= daysInMonth else { return nil }
      let dateISO = String(format: "%04d-%02d-%02d", year, month, item.day)

      return ShiftRow(
        id: "onboarding-seed-\(item.day)",
        user_id: nil,
        shift_date: dateISO,
        start_time: item.start,
        end_time: item.end,
        custom_supplements: nil
      )
    }
  }

  private static func buildExistingHoursMap(from shifts: [ShiftRow]) -> [String: HoursData] {
    var shiftTimesByDate: [String: [(start: String, end: String)]] = [:]

    for shift in shifts {
      shiftTimesByDate[shift.shift_date, default: []].append(
        (start: shift.start_time, end: shift.end_time))
    }

    var result: [String: HoursData] = [:]

    for (date, shiftsOnDate) in shiftTimesByDate {
      guard !shiftsOnDate.isEmpty else { continue }

      let sortedByStart = shiftsOnDate.sorted {
        CalendarGridHelper.timeToMinutes($0.start) < CalendarGridHelper.timeToMinutes($1.start)
      }

      let earliestStart = sortedByStart.first?.start ?? ""
      let latestEnd =
        shiftsOnDate.max(by: { lhs, rhs in
          let lhsStart = CalendarGridHelper.timeToMinutes(lhs.start)
          let lhsEnd = CalendarGridHelper.timeToMinutes(lhs.end)
          let lhsAdjustedEnd = lhsEnd <= lhsStart ? lhsEnd + 24 * 60 : lhsEnd

          let rhsStart = CalendarGridHelper.timeToMinutes(rhs.start)
          let rhsEnd = CalendarGridHelper.timeToMinutes(rhs.end)
          let rhsAdjustedEnd = rhsEnd <= rhsStart ? rhsEnd + 24 * 60 : rhsEnd

          return lhsAdjustedEnd < rhsAdjustedEnd
        })?.end ?? ""

      let crossesMidnight = shiftsOnDate.contains {
        CalendarGridHelper.timeToMinutes($0.end) <= CalendarGridHelper.timeToMinutes($0.start)
      }

      result[date] = HoursData(
        start: CalendarGridHelper.formatTime(earliestStart),
        end: CalendarGridHelper.formatTime(latestEnd),
        crossesMidnight: crossesMidnight
      )
    }

    return result
  }

  private static func buildExistingEarningsMap(
    shifts: [ShiftRow],
    snapshots: [WageSnapshot],
    payrollDay: Int
  ) -> [String: CalendarEarningsData] {
    var netByDate: [String: Double] = [:]
    var grossByDate: [String: Double] = [:]
    var hasTaxByDate: [String: Bool] = [:]

    for shift in shifts {
      let wageSnapshot = SnapshotsService.snapshotForDate(shift.shift_date, from: snapshots)
      let computed = PayrollCalculator.computeShift(shift, snapshot: wageSnapshot)

      let payoutDate = PayrollEngine.calculatePayoutDate(
        shiftDate: shift.shift_date, payrollDay: payrollDay)
      let taxSnapshot = SnapshotsService.snapshotForDate(payoutDate, from: snapshots)
      let taxEnabled = taxSnapshot?.effectiveTaxEnabled ?? false

      let net = computed.netPay(
        taxEnabled: taxEnabled,
        taxPercentage: taxSnapshot?.effectiveTaxPercentage ?? 0
      )

      netByDate[shift.shift_date, default: 0] += net
      grossByDate[shift.shift_date, default: 0] += computed.gross
      hasTaxByDate[shift.shift_date, default: false] =
        hasTaxByDate[shift.shift_date, default: false] || taxEnabled
    }

    var result: [String: CalendarEarningsData] = [:]
    for (date, net) in netByDate {
      result[date] = CalendarEarningsData(
        net: net,
        gross: grossByDate[date] ?? net,
        hasTaxEnabled: hasTaxByDate[date] ?? false
      )
    }

    return result
  }

  private static func formatTimeAsHHmm(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }
}
