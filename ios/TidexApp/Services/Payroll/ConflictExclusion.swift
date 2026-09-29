/// Detects overlapping shifts and returns IDs to exclude from totals
/// Port of lib/shifts/conflictExclusion.ts
///
/// When shifts overlap, only the one with the LOWEST earnings contributes to totals.
/// All higher-earning overlapping shifts are excluded (their earnings are crossed out).
struct ConflictExclusion {

  // MARK: - Public API

  struct ConflictAnalysis {
    let excludedIds: Set<String>
    let conflictingIds: Set<String>
    let conflictDates: Set<String>
  }

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
    var excludedIds = Set<String>()
    var conflictingIds = Set<String>()
    var conflictDates = Set<String>()

    // Group shifts by date
    var shiftsByDate: [String: [ShiftWithComputations]] = [:]
    for shift in shifts {
      let isoDate = shift.shiftDate
      shiftsByDate[isoDate, default: []].append(shift)
    }

    // For each date with multiple shifts, find overlapping clusters
    for (date, shiftsOnDate) in shiftsByDate {
      guard shiftsOnDate.count >= 2 else { continue }

      // For each cluster with 2+ shifts, mark conflicts and exclusions
      for cluster in overlapClusters(in: shiftsOnDate) {
        guard cluster.count >= 2 else { continue }

        conflictDates.insert(date)
        for shift in cluster {
          conflictingIds.insert(shift.id)
        }

        // Sort by gross earnings ascending (lowest first).
        // Keep original order for equal gross values to match web behavior.
        // Rank by gross before overtime: PayrollEngine decides exclusions before applying it.
        let sorted = cluster.enumerated().sorted { lhs, rhs in
          let lhsGross = lhs.element.computed.preOvertimeGross ?? lhs.element.grossPay
          let rhsGross = rhs.element.computed.preOvertimeGross ?? rhs.element.grossPay
          if lhsGross != rhsGross {
            return lhsGross < rhsGross
          }
          return lhs.offset < rhs.offset
        }.map(\.element)

        // Keep only the first (lowest earning) shift, exclude the rest
        for i in 1..<sorted.count {
          excludedIds.insert(sorted[i].id)
        }
      }
    }

    return ConflictAnalysis(
      excludedIds: excludedIds,
      conflictingIds: conflictingIds,
      conflictDates: conflictDates
    )
  }

  /// Group overlapping shifts on one date into clusters using union-find.
  private static func overlapClusters(in shiftsOnDate: [ShiftWithComputations])
    -> [[ShiftWithComputations]]
  {
    // Use union-find to group overlapping shifts into clusters
    var parent: [String: String] = [:]
    for shift in shiftsOnDate {
      parent[shift.id] = shift.id
    }

    func find(_ id: String) -> String {
      guard let currentParent = parent[id] else { return id }
      if currentParent != id {
        parent[id] = find(currentParent)
      }
      return parent[id] ?? id
    }

    func union(_ first: String, _ second: String) {
      let rootA = find(first)
      let rootB = find(second)
      if rootA != rootB {
        parent[rootA] = rootB
      }
    }

    // Check all pairs for overlap and union them
    for first in 0..<shiftsOnDate.count {
      for second in (first + 1)..<shiftsOnDate.count
      where shiftsOverlap(shiftsOnDate[first], shiftsOnDate[second]) {
        union(shiftsOnDate[first].id, shiftsOnDate[second].id)
      }
    }

    // Group shifts by their cluster root
    var clusters: [String: [ShiftWithComputations]] = [:]
    for shift in shiftsOnDate {
      let root = find(shift.id)
      clusters[root, default: []].append(shift)
    }

    return Array(clusters.values)
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

  // MARK: - Private Helpers

  /// Convert HH:mm time string to minutes since midnight
  private static func timeToMinutes(_ time: String) -> Int {
    let parts = time.split(separator: ":").compactMap { Int($0) }
    guard parts.count >= 2 else { return 0 }
    return parts[0] * 60 + parts[1]
  }

  /// Check if two shifts overlap in time
  /// Handles cross-midnight shifts correctly
  static func shiftsOverlap(_ a: ShiftWithComputations, _ b: ShiftWithComputations) -> Bool {
    let startA = timeToMinutes(a.startTime)
    var endA = timeToMinutes(a.endTime)
    let startB = timeToMinutes(b.startTime)
    var endB = timeToMinutes(b.endTime)

    // Handle cross-midnight shifts
    if endA <= startA { endA += 24 * 60 }
    if endB <= startB { endB += 24 * 60 }

    // Two intervals [startA, endA) and [startB, endB) overlap if:
    // startA < endB AND startB < endA
    return startA < endB && startB < endA
  }
}
