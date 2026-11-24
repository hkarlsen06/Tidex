import { excludedConflictIds, inOutputOrder, overtimeWeekStart } from "../shared/liveActivityPay";
import {
  type LiveActivityRecurringShift,
  type LiveActivityRegularShift,
  projectedRecurringShifts,
} from "../shared/liveActivityScheduling";
import { applyWeeklyOvertime, computeShift } from "../shared/payroll/calc";
import type { UserSettings, WageSnapshot } from "../shared/payroll/types";
import {
  parseStoredPayPeriod,
  payoutDateForDate,
  payWindowsPaidInMonth,
  type PayWindow,
} from "./payPeriod";
import { addDays } from "./shiftTimes";

export type JobPayMeta = {
  id: string;
  name: string;
  currency: string;
  payroll_day?: number;
  half_tax_month?: 11 | 12;
  pay_period?: unknown;
  is_default?: boolean;
};

export type AdjustmentInput = {
  id: string;
  job_id?: string;
  amount: number;
  currency: string;
  category: string;
  tax_treatment: string;
  description: string;
  note?: string;
  earned_from_date?: string;
  earned_to_date?: string;
  payout_date: string;
};

export type ComputedShiftPay = {
  id: string;
  job_id: string;
  job_name: string | null;
  currency: string;
  shift_date: string;
  start_time: string;
  end_time: string;
  recurring_id: string | null;
  pay_set_up: boolean;
  excluded_by_overlap: boolean;
  duration_hours: number;
  paid_hours: number;
  break_minutes: number;
  base_pay: number;
  supplement_pay: number;
  gross_pay: number;
  net_pay: number;
  tax_deducted: number;
  tax_enabled: boolean;
  effective_tax_percent: number;
  half_tax_applied: boolean;
  overtime_applied: boolean;
  overtime_hours: number;
  payout_date: string;
  /** Unrounded values used to accumulate totals without per-shift rounding drift. */
  raw: {
    paidHours: number;
    basePay: number;
    supplementPay: number;
    gross: number;
    net: number;
    overtimeMinutes: number;
  };
};

export type ComputedAdjustment = {
  id: string;
  job_id: string | null;
  job_name: string | null;
  amount: number;
  net_amount: number;
  tax_deducted: number;
  effective_tax_percent: number;
  half_tax_applied: boolean;
  currency: string;
  category: string;
  tax_treatment: string;
  description: string;
  payout_date: string;
  note?: string;
  earned_from?: string;
  earned_to?: string;
  raw: { gross: number; net: number };
};

export type CurrencySummary = {
  currency: string;
  shifts: number;
  paid_hours: number;
  gross_pay: number;
  net_pay: number;
  tax_deducted: number;
};

const round = (value: number) => Math.round(value * 100) / 100;
const clampTax = (value: number | null | undefined) =>
  typeof value === "number" && Number.isFinite(value) ? Math.min(Math.max(value, 0), 100) : 0;

function resolvedHalfTaxMonth(job: JobPayMeta | undefined, fallbackHalfTaxMonth: 11 | 12 | null | undefined): 11 | 12 | null {
  // Matches SharingComputeCore.swift: an existing job's own half_tax_month wins even when unset.
  if (job !== undefined) return job.half_tax_month ?? null;
  return fallbackHalfTaxMonth ?? null;
}

function taxForPayout(
  payoutDate: string,
  taxSnapshot: WageSnapshot | null,
  halfTaxMonth: 11 | 12 | null,
) {
  const taxEnabled = taxSnapshot?.tax_enabled === true;
  const savedTax = clampTax(taxSnapshot?.tax_percentage);
  const payoutMonth = Number(payoutDate.slice(5, 7));
  const halfTaxApplied = taxEnabled && halfTaxMonth !== null && halfTaxMonth === payoutMonth;
  const effectiveTaxPercent = taxEnabled ? (halfTaxApplied ? savedTax / 2 : savedTax) : 0;
  return { taxEnabled, effectiveTaxPercent, halfTaxApplied };
}

/**
 * Prices every shift (one-off and projected recurring) in `from..to`, matching
 * SharingComputeCore.computeShiftsInRange: weekly overtime from the Monday/Sunday
 * before `from`, overlap exclusion (keeping the lowest paid shift), payout-date
 * tax snapshot lookup, and Norwegian half-tax month.
 */
export function computeShiftsWithPay(input: {
  from: string;
  to: string;
  regular: LiveActivityRegularShift[];
  recurring: LiveActivityRecurringShift[];
  jobs: JobPayMeta[];
  snapshotFor: (shift: LiveActivityRegularShift) => WageSnapshot | null;
  fallbackPayrollDay?: number;
  fallbackHalfTaxMonth?: 11 | 12 | null;
}): { shifts: ComputedShiftPay[]; shifts_without_pay_setup: number } {
  const start = overtimeWeekStart(input.from);
  const dates: string[] = [];
  for (let date = start; date <= input.to; date = addDays(date, 1)) dates.push(date);

  const jobsById = new Map(input.jobs.map((j) => [j.id, j]));
  const byId = new Map<string, LiveActivityRegularShift>();
  const recurringIdByShiftId = new Map<string, string>();
  for (const shift of input.regular) {
    if (shift.shift_date >= start && shift.shift_date <= input.to && !byId.has(shift.id)) {
      byId.set(shift.id, shift);
      if (shift.recurring_id) recurringIdByShiftId.set(shift.id, shift.recurring_id);
    }
  }
  for (const rec of input.recurring) {
    for (const shift of projectedRecurringShifts([rec], dates)) {
      if (shift.shift_date >= start && shift.shift_date <= input.to && !byId.has(shift.id)) {
        byId.set(shift.id, shift);
        recurringIdByShiftId.set(shift.id, rec.id);
      }
    }
  }

  // Shifts without a wage snapshot are not priced and cannot push a paid shift out of an overlap.
  let withoutPaySetup = 0;
  const unpaidInRange: LiveActivityRegularShift[] = [];
  const priced: (LiveActivityRegularShift & { computed: ReturnType<typeof computeShift> })[] = [];

  for (const shift of byId.values()) {
    const snapshot = input.snapshotFor(shift);
    if (snapshot === null) {
      if (shift.shift_date >= input.from) {
        withoutPaySetup += 1;
        unpaidInRange.push(shift);
      }
      continue;
    }
    priced.push({ ...shift, computed: computeShift(shift, {} as UserSettings, [], snapshot, null) });
  }

  const excluded = excludedConflictIds(priced.map((s) => ({ ...s, gross: s.computed.gross })));
  const includedWithOvertime = applyWeeklyOvertime(
    priced.filter((s) => !excluded.has(s.id)).sort(inOutputOrder),
    {
      snapshotForShift: (shift) => input.snapshotFor(shift as LiveActivityRegularShift),
      effectiveJobIdForShift: (shift) => shift.job_id ?? null,
    },
  );
  const excludedShifts = priced.filter((s) => excluded.has(s.id));

  const formatPriced = (
    shift: (typeof includedWithOvertime)[number],
    excludedByOverlap: boolean,
  ): ComputedShiftPay => {
    const baseShift = shift as LiveActivityRegularShift;
    const job = jobsById.get(baseShift.job_id);
    const period = parseStoredPayPeriod(job?.pay_period);
    const payrollDay = job?.payroll_day ?? input.fallbackPayrollDay ?? 15;
    const payoutDate = payoutDateForDate(period, payrollDay, baseShift.shift_date);
    const taxSnapshot = input.snapshotFor({ ...baseShift, shift_date: payoutDate });
    const halfTaxMonth = resolvedHalfTaxMonth(job, input.fallbackHalfTaxMonth);
    const { taxEnabled, effectiveTaxPercent, halfTaxApplied } = taxForPayout(payoutDate, taxSnapshot, halfTaxMonth);
    const rawGross = shift.computed.gross;
    const rawNet = rawGross * (1 - effectiveTaxPercent / 100);
    const grossPay = round(rawGross);
    const netPay = round(rawNet);
    const breakMinutes = Math.round(shift.computed.breakAudit.deductedHours * 60);
    return {
      id: baseShift.id,
      job_id: baseShift.job_id,
      job_name: job?.name ?? null,
      currency: job?.currency ?? "kr",
      shift_date: baseShift.shift_date,
      start_time: baseShift.start_time,
      end_time: baseShift.end_time,
      recurring_id: recurringIdByShiftId.get(baseShift.id) ?? null,
      pay_set_up: true,
      excluded_by_overlap: excludedByOverlap,
      duration_hours: round(shift.computed.durationHours),
      paid_hours: round(shift.computed.paidHours),
      break_minutes: breakMinutes,
      base_pay: round(shift.computed.basePay),
      supplement_pay: round(shift.computed.supplementPay),
      gross_pay: grossPay,
      net_pay: netPay,
      tax_deducted: round(grossPay - netPay),
      tax_enabled: taxEnabled,
      effective_tax_percent: round(effectiveTaxPercent),
      half_tax_applied: halfTaxApplied,
      overtime_applied: shift.computed.overtimeApplied,
      overtime_hours: round(shift.computed.overtimeMinutes / 60),
      payout_date: payoutDate,
      raw: {
        paidHours: shift.computed.paidHours,
        basePay: shift.computed.basePay,
        supplementPay: shift.computed.supplementPay,
        gross: rawGross,
        net: rawNet,
        overtimeMinutes: shift.computed.overtimeMinutes,
      },
    };
  };

  const formatUnpaid = (shift: LiveActivityRegularShift): ComputedShiftPay => {
    const job = jobsById.get(shift.job_id);
    const period = parseStoredPayPeriod(job?.pay_period);
    const payrollDay = job?.payroll_day ?? input.fallbackPayrollDay ?? 15;
    const payoutDate = payoutDateForDate(period, payrollDay, shift.shift_date);
    const duration = rawShiftDurationHours(shift.start_time, shift.end_time);
    return {
      id: shift.id,
      job_id: shift.job_id,
      job_name: job?.name ?? null,
      currency: job?.currency ?? "kr",
      shift_date: shift.shift_date,
      start_time: shift.start_time,
      end_time: shift.end_time,
      recurring_id: recurringIdByShiftId.get(shift.id) ?? null,
      pay_set_up: false,
      excluded_by_overlap: false,
      duration_hours: round(duration),
      paid_hours: round(duration),
      break_minutes: 0,
      base_pay: 0,
      supplement_pay: 0,
      gross_pay: 0,
      net_pay: 0,
      tax_deducted: 0,
      tax_enabled: false,
      effective_tax_percent: 0,
      half_tax_applied: false,
      overtime_applied: false,
      overtime_hours: 0,
      payout_date: payoutDate,
      raw: { paidHours: 0, basePay: 0, supplementPay: 0, gross: 0, net: 0, overtimeMinutes: 0 },
    };
  };

  const results: ComputedShiftPay[] = [
    ...includedWithOvertime.filter((s) => s.shift_date >= input.from).map((s) => formatPriced(s, false)),
    ...excludedShifts.filter((s) => s.shift_date >= input.from).map((s) => formatPriced(s, true)),
    ...unpaidInRange.map(formatUnpaid),
  ].sort((a, b) => a.shift_date.localeCompare(b.shift_date) || a.start_time.localeCompare(b.start_time) || a.id.localeCompare(b.id));

  return { shifts: results, shifts_without_pay_setup: withoutPaySetup };
}

function rawShiftDurationHours(start: string, end: string): number {
  const toMin = (t: string) => Number(t.slice(0, 2)) * 60 + Number(t.slice(3, 5));
  const s = toMin(start);
  let e = toMin(end);
  if (e <= s) e += 24 * 60;
  return (e - s) / 60;
}

/**
 * Taxes a payroll adjustment the way PayrollAdjustmentCalculator.swift does:
 * gross_taxable uses the job's tax snapshot on payout_date with half-tax month;
 * net_manual and excluded_from_tax_estimate pay out as is.
 */
export function computeAdjustmentWithPay(
  adj: AdjustmentInput,
  jobs: JobPayMeta[],
  snapshotFor: (jobId: string, date: string) => WageSnapshot | null,
  fallbackHalfTaxMonth?: 11 | 12 | null,
): ComputedAdjustment {
  const defaultJob = jobs.find((j) => j.is_default);
  const job = adj.job_id !== undefined ? jobs.find((j) => j.id === adj.job_id) : defaultJob;
  const taxSnapshot = job !== undefined ? snapshotFor(job.id, adj.payout_date) : null;
  const halfTaxMonth = resolvedHalfTaxMonth(job, fallbackHalfTaxMonth);
  const usesTax = adj.tax_treatment === "gross_taxable";
  const tax = usesTax
    ? taxForPayout(adj.payout_date, taxSnapshot, halfTaxMonth)
    : { taxEnabled: false, effectiveTaxPercent: 0, halfTaxApplied: false };
  const rawNet = usesTax && tax.taxEnabled ? adj.amount * (1 - tax.effectiveTaxPercent / 100) : adj.amount;
  const gross = round(adj.amount);
  const net = round(rawNet);
  return {
    id: adj.id,
    job_id: adj.job_id ?? null,
    job_name: job?.name ?? null,
    amount: gross,
    net_amount: net,
    tax_deducted: round(gross - net),
    effective_tax_percent: round(tax.effectiveTaxPercent),
    half_tax_applied: tax.halfTaxApplied,
    currency: adj.currency,
    category: adj.category,
    tax_treatment: adj.tax_treatment,
    description: adj.description,
    payout_date: adj.payout_date,
    ...(adj.note ? { note: adj.note } : {}),
    ...(adj.earned_from_date ? { earned_from: adj.earned_from_date, earned_to: adj.earned_to_date } : {}),
    raw: { gross: adj.amount, net: rawNet },
  };
}

/** Compact currency summary for schedule and friend schedule responses. */
export function summarizeShiftsByCurrency(shifts: ComputedShiftPay[]): CurrencySummary[] {
  const byCurrency = new Map<string, { shifts: number; paidHours: number; gross: number; net: number }>();
  for (const s of shifts) {
    if (!s.pay_set_up || s.excluded_by_overlap) continue;
    const acc = byCurrency.get(s.currency) ?? { shifts: 0, paidHours: 0, gross: 0, net: 0 };
    acc.shifts += 1;
    acc.paidHours += s.raw.paidHours;
    acc.gross += s.raw.gross;
    acc.net += s.raw.net;
    byCurrency.set(s.currency, acc);
  }
  return [...byCurrency.entries()]
    .map(([currency, acc]) => {
      const gross = round(acc.gross);
      const net = round(acc.net);
      return {
        currency,
        shifts: acc.shifts,
        paid_hours: round(acc.paidHours),
        gross_pay: gross,
        net_pay: net,
        tax_deducted: round(gross - net),
      };
    })
    .sort((a, b) => b.shifts - a.shifts || a.currency.localeCompare(b.currency));
}

type Bucket = {
  shifts: number;
  paidHours: number;
  overtimeMinutes: number;
  basePay: number;
  supplementPay: number;
  shiftsGross: number;
  shiftsNet: number;
  adjustmentsGross: number;
  adjustmentsNet: number;
  adjustmentsCount: number;
  halfTaxApplied: boolean;
};

const emptyBucket = (): Bucket => ({
  shifts: 0,
  paidHours: 0,
  overtimeMinutes: 0,
  basePay: 0,
  supplementPay: 0,
  shiftsGross: 0,
  shiftsNet: 0,
  adjustmentsGross: 0,
  adjustmentsNet: 0,
  adjustmentsCount: 0,
  halfTaxApplied: false,
});

function addShiftToBucket(b: Bucket, s: ComputedShiftPay) {
  b.shifts += 1;
  b.paidHours += s.raw.paidHours;
  b.overtimeMinutes += s.raw.overtimeMinutes;
  b.basePay += s.raw.basePay;
  b.supplementPay += s.raw.supplementPay;
  b.shiftsGross += s.raw.gross;
  b.shiftsNet += s.raw.net;
  if (s.half_tax_applied) b.halfTaxApplied = true;
}

function addAdjToBucket(b: Bucket, a: ComputedAdjustment) {
  b.adjustmentsGross += a.raw.gross;
  b.adjustmentsNet += a.raw.net;
  b.adjustmentsCount += 1;
  if (a.half_tax_applied) b.halfTaxApplied = true;
}

function formatBucket(b: Bucket, includeAdjustmentsInTotal: boolean) {
  const shiftsGross = round(b.shiftsGross);
  const shiftsNet = round(b.shiftsNet);
  const adjGross = round(b.adjustmentsGross);
  const adjNet = round(b.adjustmentsNet);
  const gross = includeAdjustmentsInTotal ? round(b.shiftsGross + b.adjustmentsGross) : shiftsGross;
  const net = includeAdjustmentsInTotal ? round(b.shiftsNet + b.adjustmentsNet) : shiftsNet;
  const tax = round(gross - net);
  const effectiveTax = gross > 0 ? round((tax / gross) * 100) : 0;
  return {
    gross_pay: gross,
    net_pay: net,
    tax_deducted: tax,
    effective_tax_percent: effectiveTax,
    ...(b.halfTaxApplied ? { half_tax_applied: true } : {}),
    base_pay: round(b.basePay),
    supplement_pay: round(b.supplementPay),
    paid_hours: round(b.paidHours),
    ...(b.overtimeMinutes > 0 ? { overtime_hours: round(b.overtimeMinutes / 60) } : {}),
    shifts: b.shifts,
    ...(b.adjustmentsCount > 0
      ? {
          shifts_gross: shiftsGross,
          shifts_net: shiftsNet,
          adjustments_gross: adjGross,
          adjustments_net: adjNet,
          adjustments_count: b.adjustmentsCount,
        }
      : {}),
  };
}

function stripRaw(a: ComputedAdjustment) {
  const { raw: _raw, ...clean } = a;
  return clean;
}

/**
 * Earnings for shifts worked in `from..to` (by: "worked").
 * Totals reflect worked shifts; payroll adjustments paid out during `from..to` are listed
 * separately so nothing is hidden or double-counted against payout months.
 */
export function workedEarningsReport(input: {
  from: string;
  to: string;
  regular: LiveActivityRegularShift[];
  recurring: LiveActivityRecurringShift[];
  jobs: JobPayMeta[];
  adjustments: AdjustmentInput[];
  snapshotFor: (shift: LiveActivityRegularShift) => WageSnapshot | null;
  snapshotForJobDate: (jobId: string, date: string) => WageSnapshot | null;
  fallbackPayrollDay?: number;
  fallbackHalfTaxMonth?: 11 | 12 | null;
  filterJobId?: string;
}) {
  const computed = computeShiftsWithPay(input);
  const filteredShifts = input.filterJobId
    ? computed.shifts.filter((s) => s.job_id === input.filterJobId)
    : computed.shifts;
  const unpaidCount = input.filterJobId
    ? filteredShifts.filter((s) => !s.pay_set_up).length
    : computed.shifts_without_pay_setup;

  const byCurrency = new Map<string, Bucket>();
  const byJob = new Map<string, { job_id: string; job_name: string | null; currency: string; bucket: Bucket }>();

  for (const s of filteredShifts) {
    if (!s.pay_set_up || s.excluded_by_overlap) continue;
    const cBucket = byCurrency.get(s.currency) ?? emptyBucket();
    addShiftToBucket(cBucket, s);
    byCurrency.set(s.currency, cBucket);

    const jEntry = byJob.get(s.job_id) ?? { job_id: s.job_id, job_name: s.job_name, currency: s.currency, bucket: emptyBucket() };
    addShiftToBucket(jEntry.bucket, s);
    byJob.set(s.job_id, jEntry);
  }

  const adjustmentsInRange = input.adjustments
    .filter((a) => a.payout_date >= input.from && a.payout_date <= input.to)
    .filter((a) => !input.filterJobId || a.job_id === input.filterJobId)
    .sort((a, b) => a.payout_date.localeCompare(b.payout_date))
    .map((a) => computeAdjustmentWithPay(a, input.jobs, input.snapshotForJobDate, input.fallbackHalfTaxMonth));

  return {
    mode: "worked" as const,
    from: input.from,
    to: input.to,
    totals: [...byCurrency.entries()]
      .map(([currency, bucket]) => ({ currency, ...formatBucket(bucket, false) }))
      .sort((a, b) => b.shifts - a.shifts || a.currency.localeCompare(b.currency)),
    by_job: [...byJob.values()]
      .map(({ job_id, job_name, currency, bucket }) => ({ job_id, job_name, currency, ...formatBucket(bucket, false) }))
      .sort((a, b) => b.gross_pay - a.gross_pay || (a.job_name ?? "").localeCompare(b.job_name ?? "")),
    adjustments_paid_in_range: adjustmentsInRange.map(stripRaw),
    ...(unpaidCount > 0 ? { shifts_without_pay_setup: unpaidCount } : {}),
  };
}

/**
 * Paycheck earnings paid out in `year`-`month` (by: "payout").
 * Matches the Tidex dashboard payout calculation: each job uses its pay period windows
 * paid in that month, plus payroll adjustments with payout_date in that month.
 */
export function payoutEarningsReport(input: {
  monthKey: string;
  year: number;
  month: number;
  monthFrom: string;
  monthTo: string;
  regular: LiveActivityRegularShift[];
  recurring: LiveActivityRecurringShift[];
  jobs: JobPayMeta[];
  adjustments: AdjustmentInput[];
  snapshotFor: (shift: LiveActivityRegularShift) => WageSnapshot | null;
  snapshotForJobDate: (jobId: string, date: string) => WageSnapshot | null;
  fallbackPayrollDay?: number;
  fallbackHalfTaxMonth?: 11 | 12 | null;
  filterJobId?: string;
}) {
  const targetJobs = input.filterJobId ? input.jobs.filter((j) => j.id === input.filterJobId) : input.jobs;
  const windowsByJob: { job: JobPayMeta; window: PayWindow }[] = [];
  for (const job of targetJobs) {
    const period = parseStoredPayPeriod(job.pay_period);
    const payrollDay = job.payroll_day ?? input.fallbackPayrollDay ?? 15;
    for (const w of payWindowsPaidInMonth(period, payrollDay, input.year, input.month)) {
      windowsByJob.push({ job, window: w });
    }
  }

  let allShifts: ComputedShiftPay[] = [];
  if (windowsByJob.length > 0) {
    const minFrom = windowsByJob.map((x) => x.window.start).sort()[0]!;
    const maxTo = windowsByJob.map((x) => x.window.end).sort().at(-1)!;
    allShifts = computeShiftsWithPay({
      from: minFrom,
      to: maxTo,
      regular: input.regular,
      recurring: input.recurring,
      jobs: input.jobs,
      snapshotFor: input.snapshotFor,
      fallbackPayrollDay: input.fallbackPayrollDay,
      fallbackHalfTaxMonth: input.fallbackHalfTaxMonth,
    }).shifts;
  }

  const defaultJobId = input.jobs.find((j) => j.is_default)?.id;
  const monthAdjustments = input.adjustments
    .filter((a) => a.payout_date >= input.monthFrom && a.payout_date <= input.monthTo)
    .filter((a) => !input.filterJobId || (a.job_id ?? defaultJobId) === input.filterJobId)
    .sort((a, b) => a.payout_date.localeCompare(b.payout_date))
    .map((a) => computeAdjustmentWithPay(a, input.jobs, input.snapshotForJobDate, input.fallbackHalfTaxMonth));

  const byCurrency = new Map<string, Bucket>();
  const payouts: Record<string, unknown>[] = [];
  let unpaidCount = 0;

  // Assign each adjustment to the matching window of its job (closest payout_date if biweekly).
  const assignedAdjIds = new Set<string>();

  for (const { job, window: w } of windowsByJob) {
    const bucket = emptyBucket();
    const jobShifts = allShifts.filter(
      (s) => s.job_id === job.id && s.shift_date >= w.start && s.shift_date <= w.end,
    );
    for (const s of jobShifts) {
      if (!s.pay_set_up) {
        unpaidCount += 1;
        continue;
      }
      if (s.excluded_by_overlap) continue;
      addShiftToBucket(bucket, s);
    }

    const jobWindows = windowsByJob.filter((x) => x.job.id === job.id);
    const matchingAdjs = monthAdjustments.filter((a) => {
      if (assignedAdjIds.has(a.id)) return false;
      const adjJobId = a.job_id ?? defaultJobId;
      if (adjJobId !== job.id) return false;
      if (jobWindows.length === 1) return true;
      // For biweekly jobs with 2 payouts in one month, match the window whose payoutDate is closest.
      const closest = jobWindows.reduce((best, cur) =>
        Math.abs(Date.parse(cur.window.payoutDate) - Date.parse(a.payout_date)) <
        Math.abs(Date.parse(best.window.payoutDate) - Date.parse(a.payout_date))
          ? cur
          : best,
      );
      return closest.window.payoutDate === w.payoutDate;
    });

    for (const a of matchingAdjs) {
      assignedAdjIds.add(a.id);
      addAdjToBucket(bucket, a);
    }

    if (bucket.shifts === 0 && bucket.adjustmentsCount === 0) continue;

    const cBucket = byCurrency.get(job.currency) ?? emptyBucket();
    for (const s of jobShifts) {
      if (s.pay_set_up && !s.excluded_by_overlap) addShiftToBucket(cBucket, s);
    }
    for (const a of matchingAdjs) addAdjToBucket(cBucket, a);
    byCurrency.set(job.currency, cBucket);

    payouts.push({
      job_id: job.id,
      job_name: job.name,
      currency: job.currency,
      work_from: w.start,
      work_to: w.end,
      payout_date: w.payoutDate,
      ...formatBucket(bucket, true),
    });
  }

  // Include any adjustments whose job wasn't in windowsByJob (for example, an unassigned adjustment).
  for (const a of monthAdjustments) {
    if (assignedAdjIds.has(a.id)) continue;
    const cBucket = byCurrency.get(a.currency) ?? emptyBucket();
    addAdjToBucket(cBucket, a);
    byCurrency.set(a.currency, cBucket);
  }

  payouts.sort((a, b) => String(a.payout_date).localeCompare(String(b.payout_date)) || String(a.job_name).localeCompare(String(b.job_name)));

  return {
    mode: "payout" as const,
    month: input.monthKey,
    totals: [...byCurrency.entries()]
      .map(([currency, bucket]) => ({ currency, ...formatBucket(bucket, true) }))
      .sort((a, b) => b.gross_pay - a.gross_pay || a.currency.localeCompare(b.currency)),
    payouts,
    adjustments: monthAdjustments.map(stripRaw),
    ...(unpaidCount > 0 ? { shifts_without_pay_setup: unpaidCount } : {}),
  };
}
