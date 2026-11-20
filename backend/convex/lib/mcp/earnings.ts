import { excludedConflictIds, inOutputOrder, overtimeWeekStart } from "../shared/liveActivityPay";
import {
  type LiveActivityRecurringShift,
  type LiveActivityRegularShift,
  projectedRecurringShifts,
} from "../shared/liveActivityScheduling";
import { applyWeeklyOvertime, computeShift } from "../shared/payroll/calc";
import type { UserSettings, WageSnapshot } from "../shared/payroll/types";
import { addDays } from "./shiftTimes";

export type EarningsTotal = { currency: string; gross_pay: number; paid_hours: number; shifts: number };

const round = (value: number) => Math.round(value * 100) / 100;

/**
 * Gross pay and paid hours for the shifts dated `from` to `to`, per currency, the way the
 * app's SharingComputeCore.computeShiftsInRange counts them: recurring occurrences
 * included, overlapping shifts on a date keep the lowest paid one, and weekly overtime
 * counts every shift from the Sunday before `from`'s ISO week.
 *
 * `regular` holds the user's live one-off shifts; any outside that window are ignored.
 */
export function shiftEarnings(input: {
  from: string;
  to: string;
  regular: LiveActivityRegularShift[];
  recurring: LiveActivityRecurringShift[];
  snapshotFor: (shift: LiveActivityRegularShift) => WageSnapshot | null;
  currencyFor: (jobId: string) => string;
}) {
  const start = overtimeWeekStart(input.from);
  const dates: string[] = [];
  for (let date = start; date <= input.to; date = addDays(date, 1)) dates.push(date);

  const byId = new Map<string, LiveActivityRegularShift>();
  for (const shift of [...input.regular, ...projectedRecurringShifts(input.recurring, dates)]) {
    if (shift.shift_date >= start && shift.shift_date <= input.to && !byId.has(shift.id)) byId.set(shift.id, shift);
  }
  const computed = [...byId.values()].map((shift) => ({
    ...shift,
    computed: computeShift(shift, {} as UserSettings, [], input.snapshotFor(shift), null),
  }));
  const excluded = excludedConflictIds(computed.map((s) => ({ ...s, gross: s.computed.gross })));
  const counted = applyWeeklyOvertime(computed.filter((s) => !excluded.has(s.id)).sort(inOutputOrder), {
    snapshotForShift: (shift) => input.snapshotFor(shift as LiveActivityRegularShift),
    effectiveJobIdForShift: (shift) => shift.job_id ?? null,
  });

  const totals = new Map<string, EarningsTotal>();
  let withoutPaySetup = 0;
  for (const shift of counted) {
    if (shift.shift_date < input.from) continue;
    const job = shift as LiveActivityRegularShift;
    if (input.snapshotFor(job) === null) {
      withoutPaySetup += 1;
      continue;
    }
    const currency = input.currencyFor(job.job_id);
    const total = totals.get(currency) ?? { currency, gross_pay: 0, paid_hours: 0, shifts: 0 };
    total.gross_pay += shift.computed.gross;
    total.paid_hours += shift.computed.paidHours;
    total.shifts += 1;
    totals.set(currency, total);
  }
  return {
    totals: [...totals.values()]
      .map((t) => ({ ...t, gross_pay: round(t.gross_pay), paid_hours: round(t.paid_hours) }))
      .sort((a, b) => b.shifts - a.shifts || a.currency.localeCompare(b.currency)),
    shifts_without_pay_setup: withoutPaySetup,
  };
}
