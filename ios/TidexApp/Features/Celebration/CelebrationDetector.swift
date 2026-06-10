import Foundation

/// Pure helpers for detecting completed shifts and celebration data.
internal enum CelebrationDetector {
  /// Return IDs for completed shifts (optionally including virtual).
  internal static func completedShiftIds(
    shifts: [ShiftWithComputations],
    now: Date = Date(),
    includeVirtual: Bool = false
  ) -> Set<String> {
    let completed: [ShiftWithComputations] = shifts.filter { shift in
      if !includeVirtual, shift.isVirtual {
        return false
      }
      return Date.hasShiftEnded(
        shiftDate: shift.shiftDate,
        startTime: shift.startTime,
        endTime: shift.endTime,
        referenceDate: now
      )
    }
    return Set(completed.map(\.id))
  }

  /// Find newly completed shifts since the previous completed ID set.
  internal static func newlyCompletedShifts(
    shifts: [ShiftWithComputations],
    previousCompletedIds: Set<String>,
    now: Date = Date(),
    includeVirtual: Bool = false
  ) -> [ShiftWithComputations] {
    shifts.filter { shift in
      if !includeVirtual, shift.isVirtual {
        return false
      }
      guard !previousCompletedIds.contains(shift.id) else {
        return false
      }
      return Date.hasShiftEnded(
        shiftDate: shift.shiftDate,
        startTime: shift.startTime,
        endTime: shift.endTime,
        referenceDate: now
      )
    }
  }

  /// Select the highest-earning shift by gross pay (earliest date wins ties).
  internal static func selectHighestEarningShift(from shifts: [ShiftWithComputations])
    -> ShiftWithComputations?
  {
    guard !shifts.isEmpty else {
      return nil
    }

    let maxGross: Double = shifts.map(\.grossPay).max() ?? 0
    if maxGross == 0 {
      return shifts.min { $0.shiftDate < $1.shiftDate }
    }

    return
      shifts
      .filter { $0.grossPay == maxGross }
      .min { $0.shiftDate < $1.shiftDate }
  }

  /// Compute the TotalCard "earned to date" display value.
  internal static func displayValue(
    dashboardData: DashboardData
  ) -> (value: Double, taxEnabled: Bool) {
    if dashboardData.currentMonthTaxEnabled {
      return (
        dashboardData.currentMonthCompletedNet ?? dashboardData.currentMonthCompletedGross,
        true
      )
    }
    return (dashboardData.currentMonthCompletedGross, false)
  }
}
