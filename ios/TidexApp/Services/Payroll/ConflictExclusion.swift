/// Detects overlapping shifts and returns IDs to exclude from totals
/// Port of lib/shifts/conflictExclusion.ts
///
/// When shifts overlap, only the one with the LOWEST earnings contributes to totals.
/// All higher-earning overlapping shifts are excluded (their earnings are crossed out).
struct ConflictExclusion {

  // MARK: - Public API

  typealias ConflictAnalysis = PayrollConflictAnalysis

  /// Partition result after applying conflict exclusion.
  struct ShiftPartition {
    let includedShifts: [ShiftWithComputations]
    let analysis: ConflictAnalysis
  }

  /// Analyze shifts for conflicts and exclusions.
  ///
  /// Returns:
  /// - excludedIds: shifts excluded from totals
  /// - conflictingIds: shifts that overlap with at least one other shift
  /// - conflictDates: ISO dates that contain conflicts
  static func analyze(shifts: [ShiftWithComputations]) -> ConflictAnalysis {
    SharingComputeCore.conflictAnalysis(shifts.map(conflictShift))
  }

  private static func conflictShift(_ shift: ShiftWithComputations) -> PayrollConflictShift {
    PayrollConflictShift(
      id: shift.id, date: shift.shiftDate, startTime: shift.startTime, endTime: shift.endTime,
      gross: shift.computed.preOvertimeGross ?? shift.grossPay)
  }

  /// Build a set of shift IDs that should be excluded from earnings totals.
  ///
  /// Algorithm:
  /// 1. Group overlapping shifts into clusters (a cluster = all shifts that overlap with each other)
  /// 2. For each cluster, only the shift with the lowest gross earnings is kept in totals
  /// 3. All other shifts in the cluster are marked as excluded
  ///
  /// - Parameter shifts: All computed shifts
  /// - Returns: Set of shift IDs to exclude from totals
  static func buildExcludedShiftIds(shifts: [ShiftWithComputations]) -> Set<String> {
    analyze(shifts: shifts).excludedIds
  }

  /// Partition shifts into included and excluded sets using the standard conflict rule.
  ///
  /// - Parameter shifts: All computed shifts
  /// - Returns: Included shifts plus full conflict analysis metadata
  static func partition(shifts: [ShiftWithComputations]) -> ShiftPartition {
    let analysis = analyze(shifts: shifts)
    guard !analysis.excludedIds.isEmpty else {
      return ShiftPartition(includedShifts: shifts, analysis: analysis)
    }

    let included = shifts.filter { !analysis.excludedIds.contains($0.id) }
    return ShiftPartition(includedShifts: included, analysis: analysis)
  }

  // MARK: - Earnings Totals with Conflict Exclusion

  /// Aggregated earnings result from combining existing and preview earnings.
  struct EarningsTotals {
    let net: Double
    let gross: Double
    let hasTaxEnabled: Bool
  }

  /// Compute combined monthly earnings from existing shifts and preview (to-be-created) shifts,
  /// applying the same "lowest gross wins" conflict exclusion rule.
  ///
  /// For each date:
  /// - No conflict: both existing and preview earnings contribute.
  /// - Conflict: only the earnings with the lower gross are kept.
  ///
  /// - Parameters:
  ///   - existingByDate: Earnings per ISO date from existing (committed) shifts.
  ///   - previewByDate: Earnings per ISO date from preview (uncommitted) shifts.
  ///   - conflictDates: ISO dates where the preview shift overlaps an existing shift.
  /// - Returns: Aggregated totals with conflict exclusion applied.
  static func combinedEarnings(
    existingByDate: [String: CalendarEarningsData],
    previewByDate: [String: CalendarEarningsData],
    conflictDates: Set<String>
  ) -> EarningsTotals {
    var totalNet: Double = 0
    var totalGross: Double = 0
    var hasTax = false

    let allDates = Set(existingByDate.keys).union(previewByDate.keys)

    for date in allDates {
      let existing = existingByDate[date]
      let preview = previewByDate[date]
      let isConflict = conflictDates.contains(date)

      if let existing, let preview, isConflict {
        // Both exist and overlap: keep the one with lower gross
        let winner = preview.gross < existing.gross ? preview : existing
        totalNet += winner.net
        totalGross += winner.gross
        hasTax = hasTax || winner.hasTaxEnabled
      } else {
        // No conflict: both contribute
        if let existing {
          totalNet += existing.net
          totalGross += existing.gross
          hasTax = hasTax || existing.hasTaxEnabled
        }
        if let preview {
          totalNet += preview.net
          totalGross += preview.gross
          hasTax = hasTax || preview.hasTaxEnabled
        }
      }
    }

    return EarningsTotals(net: totalNet, gross: totalGross, hasTaxEnabled: hasTax)
  }

  /// Check same-date intervals, including shifts that finish after midnight.
  static func shiftsOverlap(_ a: ShiftWithComputations, _ b: ShiftWithComputations) -> Bool {
    conflictShift(a).overlaps(conflictShift(b))
  }
}
