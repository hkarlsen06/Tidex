import Foundation

/// The closing line in the celebration sheet.
internal enum CelebrationMessage: Equatable {
  case firstShiftThisMonth
  case bestShiftThisMonth
  case greatJob
  case niceWork
  case wellEarned
  case keepItUp
  case payday

  static let rotating: [CelebrationMessage] = [.greatJob, .niceWork, .wellEarned, .keepItUp]
}

struct CelebrationData: Equatable {
  let previousDisplayValue: Double
  let newDisplayValue: Double
  /// Nil for payday, which has no single shift to show.
  let featuredShift: ShiftWithComputations?
  let completedShiftCount: Int
  let currency: String
  let animateFrom: Double?
  let message: CelebrationMessage
}

struct CelebrationState: Codable, Equatable {
  let lastDisplayValue: Double
  let completedShiftIds: [String]
  let displayTaxEnabled: Bool
}

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

  /// Pick the closing line for a completed-shift celebration.
  /// - Parameters:
  ///   - featuredShift: The shift shown in the sheet.
  ///   - earlierCompleted: Shifts this month that were already celebrated or baselined.
  ///   - newlyCompletedCount: How many shifts completed since the last celebration.
  internal static func message(
    featuredShift: ShiftWithComputations,
    earlierCompleted: [ShiftWithComputations],
    newlyCompletedCount: Int
  ) -> CelebrationMessage {
    guard let earlierBest = earlierCompleted.map(\.grossPay).max() else {
      return .firstShiftThisMonth
    }

    // Beating a single earlier shift is not much of a record.
    if earlierCompleted.count >= 2, featuredShift.grossPay > earlierBest {
      return .bestShiftThisMonth
    }

    // Rotate by how many shifts are done, so back-to-back celebrations read differently.
    let rotating = CelebrationMessage.rotating
    return rotating[(earlierCompleted.count + newlyCompletedCount) % rotating.count]
  }

  /// The next moment a shift in the list ends after `now`, used to check again while the app is open.
  internal static func nextShiftEnd(
    shifts: [ShiftWithComputations],
    after now: Date,
    includeVirtual: Bool = false
  ) -> Date? {
    shifts
      .filter { includeVirtual || !$0.isVirtual }
      .compactMap {
        Date.shiftEndDate(shiftDate: $0.shiftDate, startTime: $0.startTime, endTime: $0.endTime)
      }
      .filter { $0 > now }
      .min()
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
