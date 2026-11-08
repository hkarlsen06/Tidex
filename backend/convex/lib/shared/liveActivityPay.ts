import {
  type LiveActivityRecurringShift,
  type LiveActivityRegularShift,
  normalizeStoredTime,
  projectedRecurringShifts,
} from "./liveActivityScheduling";
import { applyWeeklyOvertime, computeShift } from "./payroll/calc";
import type { ShiftComputed, UserSettings, WageSnapshot } from "./payroll/types";

// Weekly overtime for a Live Activity shift, computed the way the app's
// SharingComputeCore computes it: every shift from the Sunday before the shift's
// ISO week counts, overlapping shifts on a date keep one, then overtime applies in
// start order per job.

const isoDate = (date: Date) => date.toISOString().slice(0, 10);

function addDays(dateISO: string, days: number): string {
  const date = new Date(`${dateISO}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return isoDate(date);
}

/** The Sunday before the ISO week that holds `dateISO`. Its night shift can carry hours into that week. */
export function overtimeWeekStart(dateISO: string): string {
  const date = new Date(`${dateISO}T00:00:00Z`);
  const daysSinceMonday = (date.getUTCDay() + 6) % 7;
  return addDays(dateISO, -daysSinceMonday - 1);
}

function minutes(time: string): number {
  const [hours, mins] = normalizeStoredTime(time).split(":").map(Number);
  return (hours ?? 0) * 60 + (mins ?? 0);
}

type ConflictShift = { id: string; shift_date: string; start_time: string; end_time: string; gross: number };

function overlaps(a: ConflictShift, b: ConflictShift): boolean {
  const aStart = minutes(a.start_time);
  const aEnd = minutes(a.end_time);
  const bStart = minutes(b.start_time);
  const bEnd = minutes(b.end_time);
  return aStart < (bEnd <= bStart ? bEnd + 1440 : bEnd) && bStart < (aEnd <= aStart ? aEnd + 1440 : aEnd);
}

type Ordered = { id: string; shift_date: string; start_time: string };

const inOutputOrder = (a: Ordered, b: Ordered) =>
  a.shift_date.localeCompare(b.shift_date) ||
  normalizeStoredTime(a.start_time).localeCompare(normalizeStoredTime(b.start_time)) ||
  (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

/**
 * Shifts the app leaves out of totals. Overlapping shifts on one date form a group,
 * and the group keeps its lowest-paid shift, the earliest one on a tie.
 * Port of `SharingComputeCore.conflictAnalysis`.
 */
export function excludedConflictIds(shifts: ConflictShift[]): Set<string> {
  const excluded = new Set<string>();
  const byDate = new Map<string, ConflictShift[]>();
  for (const shift of [...shifts].sort(inOutputOrder)) {
    byDate.set(shift.shift_date, [...(byDate.get(shift.shift_date) ?? []), shift]);
  }
  for (const onDate of byDate.values()) {
    const parent = new Map(onDate.map((s) => [s.id, s.id]));
    const find = (id: string): string => {
      const ancestor = parent.get(id) ?? id;
      if (ancestor === id) return id;
      const root = find(ancestor);
      parent.set(id, root);
      return root;
    };
    for (let i = 0; i < onDate.length; i++) {
      for (let j = i + 1; j < onDate.length; j++) {
        if (overlaps(onDate[i]!, onDate[j]!)) parent.set(find(onDate[i]!.id), find(onDate[j]!.id));
      }
    }
    const clusters = new Map<string, { shift: ConflictShift; offset: number }[]>();
    onDate.forEach((shift, offset) => {
      const root = find(shift.id);
      clusters.set(root, [...(clusters.get(root) ?? []), { shift, offset }]);
    });
    for (const cluster of clusters.values()) {
      if (cluster.length < 2) continue;
      const ranked = [...cluster].sort((a, b) => a.shift.gross - b.shift.gross || a.offset - b.offset);
      for (const { shift } of ranked.slice(1)) excluded.add(shift.id);
    }
  }
  return excluded;
}

/**
 * Pay for `target` with weekly overtime from the user's other shifts in its overtime week.
 * `regular` and `recurring` may hold shifts outside that week; they are filtered here.
 * Only shifts up to the target's date are needed, because later shifts cannot change
 * the overtime of an earlier one.
 */
export function computeLiveActivityShift(
  target: LiveActivityRegularShift,
  regular: LiveActivityRegularShift[],
  recurring: LiveActivityRecurringShift[],
  snapshotFor: (shift: LiveActivityRegularShift) => WageSnapshot | null,
  settings: UserSettings,
): ShiftComputed {
  const from = overtimeWeekStart(target.shift_date);
  const dates: string[] = [];
  for (let date = from; date <= target.shift_date; date = addDays(date, 1)) dates.push(date);

  const byId = new Map<string, LiveActivityRegularShift>();
  for (const shift of [...regular, ...projectedRecurringShifts(recurring, dates)]) {
    if (shift.shift_date >= from && shift.shift_date <= target.shift_date && !byId.has(shift.id)) {
      byId.set(shift.id, shift);
    }
  }
  byId.set(target.id, target);

  const computed = [...byId.values()].map((shift) => ({
    ...shift,
    computed: computeShift(shift, settings, [], snapshotFor(shift), null),
  }));
  const own = computed.find((shift) => shift.id === target.id)!.computed;
  const excluded = excludedConflictIds(computed.map((s) => ({ ...s, gross: s.computed.gross })));
  // A shift the app leaves out of totals has no overtime position; show its own pay.
  if (excluded.has(target.id)) return own;

  const adjusted = applyWeeklyOvertime(
    computed.filter((shift) => !excluded.has(shift.id)).sort(inOutputOrder),
    {
      snapshotForShift: (shift) => snapshotFor(shift as LiveActivityRegularShift),
      effectiveJobIdForShift: (shift) => shift.job_id ?? null,
    },
  );
  return adjusted.find((shift) => shift.id === target.id)?.computed ?? own;
}
