import Foundation

/// Detects overlapping shifts and returns IDs to exclude from totals
/// Port of lib/shifts/conflictExclusion.ts
///
/// When shifts overlap, only the one with the LOWEST earnings contributes to totals.
/// All higher-earning overlapping shifts are excluded (their earnings are crossed out).
struct ConflictExclusion {

    // MARK: - Public API

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
        var result = Set<String>()

        // Group shifts by date
        var shiftsByDate: [String: [ShiftWithComputations]] = [:]
        for shift in shifts {
            let isoDate = shift.shiftDate
            shiftsByDate[isoDate, default: []].append(shift)
        }

        // For each date with multiple shifts, find overlapping clusters
        for (_, shiftsOnDate) in shiftsByDate {
            guard shiftsOnDate.count >= 2 else { continue }

            // Use union-find to group overlapping shifts into clusters
            var parent: [String: String] = [:]
            for shift in shiftsOnDate {
                parent[shift.id] = shift.id
            }

            func find(_ id: String) -> String {
                if parent[id] != id {
                    parent[id] = find(parent[id]!)
                }
                return parent[id]!
            }

            func union(_ a: String, _ b: String) {
                let rootA = find(a)
                let rootB = find(b)
                if rootA != rootB {
                    parent[rootA] = rootB
                }
            }

            // Check all pairs for overlap and union them
            for i in 0..<shiftsOnDate.count {
                for j in (i + 1)..<shiftsOnDate.count {
                    if shiftsOverlap(shiftsOnDate[i], shiftsOnDate[j]) {
                        union(shiftsOnDate[i].id, shiftsOnDate[j].id)
                    }
                }
            }

            // Group shifts by their cluster root
            var clusters: [String: [ShiftWithComputations]] = [:]
            for shift in shiftsOnDate {
                let root = find(shift.id)
                clusters[root, default: []].append(shift)
            }

            // For each cluster with 2+ shifts, exclude all but the one with lowest earnings
            for (_, cluster) in clusters {
                guard cluster.count >= 2 else { continue }

                // Sort by gross earnings ascending (lowest first)
                let sorted = cluster.sorted { $0.grossPay < $1.grossPay }

                // Keep only the first (lowest earning) shift, exclude the rest
                for i in 1..<sorted.count {
                    result.insert(sorted[i].id)
                }
            }
        }

        return result
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
