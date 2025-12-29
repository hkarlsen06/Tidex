import type { ShiftWithComputations } from "@/lib/payroll";

type ISODate = string;

/**
 * Build a set of shift IDs that should be excluded from earnings totals.
 * When shifts overlap, only the one with the LOWEST earnings contributes to totals.
 * All higher-earning overlapping shifts are excluded (their earnings are crossed out).
 *
 * Algorithm:
 * 1. Group overlapping shifts into clusters (a cluster = all shifts that overlap with each other)
 * 2. For each cluster, only the shift with the lowest gross earnings is kept in totals
 * 3. All other shifts in the cluster are marked as excluded
 */
export function buildExcludedShiftIds(shifts: ShiftWithComputations[]): Set<string> {
  const result = new Set<string>();
  const shiftsByDate = new Map<ISODate, ShiftWithComputations[]>();

  // Group shifts by date
  for (const shift of shifts) {
    const isoDate = shift.shift_date as ISODate;
    const existing = shiftsByDate.get(isoDate) || [];
    existing.push(shift);
    shiftsByDate.set(isoDate, existing);
  }

  const timeToMinutes = (time: string): number => {
    const parts = time.split(':');
    return parseInt(parts[0]) * 60 + parseInt(parts[1]);
  };

  const shiftsOverlap = (a: ShiftWithComputations, b: ShiftWithComputations): boolean => {
    let startA = timeToMinutes(a.start_time);
    let endA = timeToMinutes(a.end_time);
    let startB = timeToMinutes(b.start_time);
    let endB = timeToMinutes(b.end_time);

    // Handle cross-midnight shifts
    if (endA <= startA) endA += 24 * 60;
    if (endB <= startB) endB += 24 * 60;

    return startA < endB && startB < endA;
  };

  // For each date with multiple shifts, find overlapping clusters
  shiftsByDate.forEach((shiftsOnDate) => {
    if (shiftsOnDate.length < 2) return;

    // Use union-find to group overlapping shifts into clusters
    const parent = new Map<string, string>();
    for (const shift of shiftsOnDate) {
      parent.set(shift.id, shift.id);
    }

    const find = (id: string): string => {
      if (parent.get(id) !== id) {
        parent.set(id, find(parent.get(id)!));
      }
      return parent.get(id)!;
    };

    const union = (a: string, b: string): void => {
      const rootA = find(a);
      const rootB = find(b);
      if (rootA !== rootB) {
        parent.set(rootA, rootB);
      }
    };

    // Check all pairs for overlap and union them
    for (let i = 0; i < shiftsOnDate.length; i++) {
      for (let j = i + 1; j < shiftsOnDate.length; j++) {
        if (shiftsOverlap(shiftsOnDate[i], shiftsOnDate[j])) {
          union(shiftsOnDate[i].id, shiftsOnDate[j].id);
        }
      }
    }

    // Group shifts by their cluster root
    const clusters = new Map<string, ShiftWithComputations[]>();
    for (const shift of shiftsOnDate) {
      const root = find(shift.id);
      const cluster = clusters.get(root) || [];
      cluster.push(shift);
      clusters.set(root, cluster);
    }

    // For each cluster with 2+ shifts, exclude all but the one with lowest earnings
    clusters.forEach((cluster) => {
      if (cluster.length < 2) return;

      // Sort by gross earnings ascending (lowest first)
      cluster.sort((a, b) => a.computed.gross - b.computed.gross);

      // Keep only the first (lowest earning) shift, exclude the rest
      for (let i = 1; i < cluster.length; i++) {
        result.add(cluster[i].id);
      }
    });
  });

  return result;
}
