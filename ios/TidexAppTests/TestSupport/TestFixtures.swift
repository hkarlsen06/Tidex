import Foundation

@testable import Tidex

enum TestFixtures {
  static func wageSnapshot(
    id: String = UUID().uuidString,
    fromDate: String? = nil,
    hourlyWage: Double = 200,
    supplements: [SupplementRule] = [],
    taxEnabled: Bool? = nil,
    taxPercentage: Double? = nil,
    breakEnabled: Bool? = nil,
    breakMethod: String? = nil,
    breakThresholdHours: Double? = nil,
    breakDeductionMinutes: Int? = nil,
    jobId: String? = nil,
    overtime: OvertimeConfig = .disabled
  ) -> WageSnapshot {
    WageSnapshot(
      id: id,
      user_id: "user-1",
      job_id: jobId,
      from_date: fromDate,
      hourly_wage: hourlyWage,
      wage_level: nil,
      tariff_type_id: nil,
      supplements: SupplementRulesSnapshot(rules: supplements),
      overtime: overtime,
      tax_enabled: taxEnabled,
      tax_percentage: taxPercentage,
      break_enabled: breakEnabled,
      break_method: breakMethod,
      break_threshold_hours: breakThresholdHours,
      break_deduction_minutes: breakDeductionMinutes,
      created_at: nil
    )
  }

  static func shift(
    id: String = UUID().uuidString,
    shiftDate: String,
    startTime: String,
    endTime: String,
    jobId: String? = nil,
    note: String? = nil,
    customPauseWindows: CustomPauseWindows? = nil,
    customSupplements: CustomSupplementsData? = nil
  ) -> ShiftRow {
    ShiftRow(
      id: id,
      user_id: "user-1",
      job_id: jobId,
      shift_date: shiftDate,
      start_time: startTime,
      end_time: endTime,
      note: note,
      custom_pause_windows: customPauseWindows,
      custom_supplements: customSupplements,
      created_at: nil,
      updated_at: nil,
      recurring_id: nil,
      recurring_anchor_weekday: nil
    )
  }

  static func job(
    id: String,
    isDefault: Bool,
    currency: String = "kr",
    payrollDay: Int? = 25,
    halfTaxMonth: Int? = nil,
    payPeriod: PayPeriod? = nil
  ) -> Job {
    Job(
      id: id,
      user_id: "user-1",
      name: "Job \(id)",
      color: nil,
      currency: currency,
      is_default: isDefault,
      sort_order: 0,
      payroll_day: payrollDay,
      half_tax_month: halfTaxMonth,
      monthly_goal: nil,
      archived_at: nil,
      deleted_at: nil,
      created_at: nil,
      updated_at: nil,
      pay_period: payPeriod
    )
  }

  static func computedShift(
    id: String,
    shiftDate: String,
    startTime: String,
    endTime: String,
    jobId: String? = nil,
    gross: Double,
    supplementPay: Double = 0,
    taxEnabled: Bool = false,
    taxPercentage: Double = 0
  ) -> ShiftWithComputations {
    let shift = self.shift(
      id: id,
      shiftDate: shiftDate,
      startTime: startTime,
      endTime: endTime,
      jobId: jobId,
      note: nil,
      customPauseWindows: nil,
      customSupplements: nil
    )

    let basePay = max(0, gross - supplementPay)
    let computed = ShiftComputed(
      id: id,
      durationHours: 8,
      paidHours: 8,
      basePay: basePay,
      supplementPay: supplementPay,
      gross: gross,
      wagePeriods: [],
      originalWagePeriods: [],
      breakAudit: BreakAudit(method: .none, thresholdHours: 0, deductedHours: 0, notes: [])
    )

    return ShiftWithComputations(
      shift: shift,
      computed: computed,
      taxEnabled: taxEnabled,
      taxPercentage: taxPercentage
    )
  }

  static func event(
    id: String = UUID().uuidString,
    startDate: String,
    endDate: String,
    isAllDay: Bool,
    startTime: String? = nil,
    endTime: String? = nil,
    note: String = "Event"
  ) -> EventRow {
    EventRow(
      id: id,
      user_id: "user-1",
      start_date: startDate,
      end_date: endDate,
      is_all_day: isAllDay,
      start_time: startTime,
      end_time: endTime,
      note: note
    )
  }
}
