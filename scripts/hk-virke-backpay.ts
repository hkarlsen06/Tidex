import { createClient } from "npm:@supabase/supabase-js@2.45.4";

import {
  computeShift,
  PRESET_SUPPLEMENT_RULES,
  type BreakMethod,
  type ShiftRow,
  type WageSnapshot,
} from "../supabase/functions/_shared/wagey/payroll/index.ts";
import { generateVirtualShiftsForMonth } from "../supabase/functions/_shared/wagey/recurring/utils.ts";
import type { EndCondition, SelectedDays } from "../supabase/functions/_shared/wagey/recurring/types.ts";
import { cleanTime } from "../supabase/functions/_shared/wagey/time-utils.ts";

type UserSettingsRow = {
  user_id: string;
  currency: string | null;
};

type JobRow = {
  id: string;
  user_id: string;
  name: string;
  is_default: boolean;
  currency: string | null;
  archived_at: string | null;
  deleted_at: string | null;
};

type ShiftDbRow = ShiftRow & {
  deleted_at?: string | null;
};

type RecurringDbRow = {
  id: string;
  user_id: string;
  job_id: string | null;
  start_time: string;
  end_time: string;
  repeat_interval_weeks: number;
  selected_days: SelectedDays;
  end_condition: EndCondition;
  exclusions: string[] | null;
  date_specific_pause_windows: Record<string, ShiftRow["custom_pause_windows"]> | null;
  date_specific_supplements: Record<string, ShiftRow["custom_supplements"]> | null;
  deleted_at?: string | null;
};

type AdjustmentInsert = {
  user_id: string;
  job_id: string | null;
  amount: number;
  currency: string;
  category: "retro_pay";
  tax_treatment: "gross_taxable";
  description: string;
  curated_note: string;
  curated_description: string;
  curated_link: string;
  curated_link_title: string;
  note: string;
  earned_from_date: string;
  earned_to_date: string;
  payout_date: string;
};

type WageSnapshotInsert = {
  user_id: string;
  job_id: string;
  from_date: string;
  hourly_wage: number;
  wage_level: number;
  tariff_type_id: "hk_retail";
  supplements: WageSnapshot["supplements"];
  tax_enabled: boolean;
  tax_percentage: number;
  break_enabled: boolean;
  break_method: BreakMethod;
  break_threshold_hours: number;
  break_deduction_minutes: number;
};

type OperationalWageUpdate = {
  jobId: string;
  userId: string;
  jobName: string;
  sourceSnapshotId: string;
  wageLevel: number;
  oldHourlyWage: number;
  newHourlyWage: number;
  legacyTariffType: boolean;
  insert: WageSnapshotInsert;
};

type BackpayLine = {
  source: "shift" | "recurring";
  userId: string;
  jobId: string | null;
  shiftId: string;
  shiftDate: string;
  startTime: string;
  endTime: string;
  wageLevel: number;
  paidHours: number;
  oldHourlyWage: number;
  newHourlyWage: number;
  amount: number;
  oldGross: number;
  newGross: number;
  snapshotId: string;
  tariffTypeId: string | null;
};

type BackpayGroup = {
  userId: string;
  jobId: string | null;
  currency: string;
  amount: number;
  earnedFromDate: string;
  earnedToDate: string;
  lines: BackpayLine[];
};

type RunConfig = {
  json: boolean;
  strictTariffType: boolean;
  includeRecurring: boolean;
  userId: string | null;
  jobId: string | null;
  fromDate: string;
  payoutDate: string;
  throughDate: string;
};

const BACKPAY_MARKER = "hk_virke_2026_backpay";
const APPROVAL_NOT_BEFORE = "2026-05-27";
const JUNE_OPERATIONAL_TARIFF_DATE = "2026-06-01";
const HK_VIRKE_SOURCE_URL =
  "https://www.virke.no/tariff-og-lonn/finn-tariffavtale/landsoverenskomsten-hk/#sistenyttavtale";
const HK_VIRKE_ADJUSTMENT_DESCRIPTION = "Tariffoppgjøret HK - Virke 2026";
const HK_VIRKE_CURATED_NOTE = "Les mer om lønnsøkningen din";
const HK_VIRKE_CURATED_DESCRIPTION =
  "De nye satsene i tariffoppgjøret gjelder også for vakter som allerede er jobbet. Siden disse vaktene først ble beregnet med gammel sats, får du en egen etterbetaling som dekker forskjellen mellom gammel og ny lønn. Trykk nedenfor for å lese nøyaktig hvordan lønnen din økte.";
const HK_VIRKE_CURATED_LINK_TITLE = "Se tariffavtalen hos Virke";
const EXPECTED_CURATED_FIELDS = {
  description: HK_VIRKE_ADJUSTMENT_DESCRIPTION,
  curated_note: HK_VIRKE_CURATED_NOTE,
  curated_description: HK_VIRKE_CURATED_DESCRIPTION,
  curated_link: HK_VIRKE_SOURCE_URL,
  curated_link_title: HK_VIRKE_CURATED_LINK_TITLE,
} as const;
const DEFAULT_CURRENCY = "kr";
const MIN_AMOUNT = 0.005;
const LOCAL_TIME_ZONE = "Europe/Oslo";

const RUN_CONFIG: RunConfig = {
  json: false,
  strictTariffType: false,
  includeRecurring: true,
  userId: null,
  jobId: null,
  fromDate: "2026-02-01",
  throughDate: "2026-05-31",
  payoutDate: "2026-06-15",
};

const HK_VIRKE_TARGET_RATES: Record<string, Record<number, number>> = {
  "2026-02-01": {
    6: 261.14,
  },
  "2026-04-01": {
    [-2]: 139.4,
    [-1]: 136.41,
    1: 195.04,
    2: 195.88,
    3: 197.96,
    4: 203.55,
    5: 221.31,
    6: 271.64,
  },
};

function usage(exitCode = 1): never {
  console.error(`Usage:
  pnpm tariff:hk-virke:backpay
  pnpm tariff:hk-virke:backpay -- --apply

This one-off script keeps dates, filters, and tariff values in RUN_CONFIG.
Without --apply it only performs a dry run.
`);
  Deno.exit(exitCode);
}

function parseRunMode(args: string[]): { apply: boolean } {
  let apply = false;

  for (const arg of args) {
    switch (arg) {
      case "--":
        break;
      case "--apply":
        apply = true;
        break;
      case "--help":
      case "-h":
        usage(0);
        break;
      default:
        console.error(`Unknown argument: ${arg}`);
        usage();
    }
  }

  return { apply };
}

function validateRunConfig(config: RunConfig, apply: boolean): void {
  if (
    !isISODate(config.payoutDate) || !isISODate(config.fromDate) ||
    !isISODate(config.throughDate)
  ) {
    throw new Error("RUN_CONFIG dates must use YYYY-MM-DD.");
  }

  if (config.throughDate < config.fromDate) {
    throw new Error("RUN_CONFIG.throughDate must be on or after RUN_CONFIG.fromDate.");
  }

  if (apply) {
    const today = localISODate();
    if (today < APPROVAL_NOT_BEFORE) {
      throw new Error(
        `Refusing --apply before ${APPROVAL_NOT_BEFORE}. Today is ${today}.`,
      );
    }
  }
}

function validateAdjustmentPayload(adjustment: AdjustmentInsert): void {
  for (const [field, expected] of Object.entries(EXPECTED_CURATED_FIELDS)) {
    if (adjustment[field as keyof typeof EXPECTED_CURATED_FIELDS] !== expected) {
      throw new Error(`Unexpected ${field} value in adjustment payload.`);
    }
  }
}

function isISODate(value: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(value);
}

function localISODate(): string {
  return new Intl.DateTimeFormat("sv-SE", {
    timeZone: LOCAL_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

function roundCurrency(value: number): number {
  return Math.round(value * 100) / 100;
}

function normalizeSnapshot(row: Record<string, unknown>): WageSnapshot {
  return {
    id: String(row.id),
    user_id: String(row.user_id),
    job_id: row.job_id ? String(row.job_id) : null,
    from_date: row.from_date ? String(row.from_date) : null,
    hourly_wage: Number(row.hourly_wage),
    wage_level: row.wage_level === null || row.wage_level === undefined
      ? null
      : Number(row.wage_level),
    tariff_type_id: row.tariff_type_id ? String(row.tariff_type_id) : null,
    supplements: normalizeSupplements(row.supplements),
    created_at: row.created_at ? String(row.created_at) : undefined,
    tax_enabled: Boolean(row.tax_enabled),
    tax_percentage: Number(row.tax_percentage ?? 0),
    break_enabled: row.break_enabled === null || row.break_enabled === undefined
      ? true
      : Boolean(row.break_enabled),
    break_method: (row.break_method ?? "proportional") as BreakMethod,
    break_threshold_hours: Number(row.break_threshold_hours ?? 5.5),
    break_deduction_minutes: Number(row.break_deduction_minutes ?? 30),
  };
}

function normalizeSupplements(value: unknown): WageSnapshot["supplements"] {
  if (
    value &&
    typeof value === "object" &&
    "rules" in value &&
    Array.isArray((value as { rules?: unknown }).rules)
  ) {
    return value as WageSnapshot["supplements"];
  }
  if (Array.isArray(value)) {
    return { rules: value as WageSnapshot["supplements"]["rules"] };
  }
  return { rules: [] };
}

function snapshotForDate(date: string, snapshots: WageSnapshot[]): WageSnapshot | null {
  const baseline = snapshots.find((snapshot) => snapshot.from_date === null) ?? null;
  const dated = snapshots
    .filter((snapshot): snapshot is WageSnapshot & { from_date: string } =>
      snapshot.from_date !== null
    )
    .sort((a, b) => a.from_date.localeCompare(b.from_date));

  let result: WageSnapshot | null = null;
  for (const snapshot of dated) {
    if (snapshot.from_date <= date) {
      result = snapshot;
    } else {
      break;
    }
  }
  return result ?? baseline;
}

function snapshotsForJob(
  snapshots: WageSnapshot[],
  jobId: string | null | undefined,
  defaultJobId: string | null,
): WageSnapshot[] {
  const legacy = snapshots.filter((snapshot) => snapshot.job_id === null);
  if (!jobId) return legacy.length > 0 ? legacy : snapshots;

  const scoped = snapshots.filter((snapshot) => snapshot.job_id === jobId);
  if (scoped.length > 0) return scoped;

  if (defaultJobId) {
    const defaultScoped = snapshots.filter((snapshot) => snapshot.job_id === defaultJobId);
    if (defaultScoped.length > 0) return defaultScoped;
  }

  return legacy.length > 0 ? legacy : snapshots;
}

function jobKey(userId: string, jobId: string | null): string {
  return `${userId}:${jobId ?? ""}`;
}

function effectiveJobIdFor(
  userId: string,
  jobId: string | null | undefined,
  defaultJobByUserId: Map<string, string>,
): string | null {
  return jobId ?? defaultJobByUserId.get(userId) ?? null;
}

function isHkVirkeTariffSnapshot(snapshot: WageSnapshot, strictTariffType: boolean): boolean {
  if (snapshot.wage_level === null) return false;
  if (snapshot.tariff_type_id === "hk_retail") return true;
  return !strictTariffType && snapshot.tariff_type_id === null;
}

function buildEligibleJobKeys(
  jobs: JobRow[],
  snapshotsByUserId: Map<string, WageSnapshot[]>,
  defaultJobByUserId: Map<string, string>,
  strictTariffType: boolean,
  eligibilityDate: string,
  userFilter: string | null,
  jobFilter: string | null,
): Set<string> {
  const eligible = new Set<string>();
  const candidates = jobs
    .filter((job) => job.deleted_at === null)
    .filter((job) => !userFilter || job.user_id === userFilter)
    .filter((job) => !jobFilter || job.id === jobFilter);

  for (const job of candidates) {
    const userSnapshots = snapshotsByUserId.get(job.user_id) ?? [];
    const currentSnapshot = snapshotForDate(
      eligibilityDate,
      snapshotsForJob(userSnapshots, job.id, defaultJobByUserId.get(job.user_id) ?? null),
    );

    if (currentSnapshot && isHkVirkeTariffSnapshot(currentSnapshot, strictTariffType)) {
      eligible.add(jobKey(job.user_id, job.id));
    }
  }

  for (const [userId, userSnapshots] of snapshotsByUserId) {
    if (userFilter && userId !== userFilter) continue;
    const defaultJobId = defaultJobByUserId.get(userId) ?? null;
    if (jobFilter && defaultJobId !== jobFilter) continue;
    if (defaultJobId && eligible.has(jobKey(userId, defaultJobId))) continue;

    const currentSnapshot = snapshotForDate(
      eligibilityDate,
      snapshotsForJob(userSnapshots, defaultJobId, defaultJobId),
    );
    if (currentSnapshot && isHkVirkeTariffSnapshot(currentSnapshot, strictTariffType)) {
      eligible.add(jobKey(userId, defaultJobId));
    }
  }

  return eligible;
}

function targetRateFor(level: number, shiftDate: string): number | null {
  const effectiveDates = Object.keys(HK_VIRKE_TARGET_RATES)
    .filter((date) => date <= shiftDate)
    .sort();

  for (let index = effectiveDates.length - 1; index >= 0; index -= 1) {
    const rate = HK_VIRKE_TARGET_RATES[effectiveDates[index]][level];
    if (rate !== undefined) return rate;
  }

  return null;
}

function adjustedSnapshotForDate(
  snapshot: WageSnapshot,
  shiftDate: string,
): WageSnapshot | null {
  const wageLevel = snapshot.wage_level;
  if (wageLevel === null) return null;

  const targetRate = targetRateFor(wageLevel, shiftDate);
  if (targetRate === null || targetRate <= snapshot.hourly_wage) return null;

  return {
    ...snapshot,
    hourly_wage: targetRate,
  };
}

function makeShift(row: ShiftDbRow): ShiftRow {
  return {
    id: row.id,
    user_id: row.user_id,
    job_id: row.job_id ?? null,
    shift_date: row.shift_date,
    start_time: row.start_time,
    end_time: row.end_time,
    custom_pause_windows: row.custom_pause_windows ?? null,
    custom_supplements: row.custom_supplements ?? null,
  };
}

function monthsInRange(startDate: string, endDate: string): Array<{ year: number; month: number }> {
  const [startYear, startMonth] = startDate.split("-").map(Number);
  const [endYear, endMonth] = endDate.split("-").map(Number);
  const months: Array<{ year: number; month: number }> = [];
  let year = startYear;
  let month = startMonth;

  while (year < endYear || (year === endYear && month <= endMonth)) {
    months.push({ year, month });
    month += 1;
    if (month > 12) {
      month = 1;
      year += 1;
    }
  }

  return months;
}

function makeRecurringShifts(
  recurringRows: RecurringDbRow[],
  startDate: string,
  endDate: string,
  defaultJobByUserId: Map<string, string>,
  eligibleJobKeys: Set<string>,
  jobFilter: string | null,
): ShiftRow[] {
  const result: ShiftRow[] = [];
  const months = monthsInRange(startDate, endDate);

  for (const recurring of recurringRows) {
    const effectiveJobId = effectiveJobIdFor(
      recurring.user_id,
      recurring.job_id,
      defaultJobByUserId,
    );
    if (jobFilter && effectiveJobId !== jobFilter) continue;
    if (!eligibleJobKeys.has(jobKey(recurring.user_id, effectiveJobId))) continue;

    for (const { year, month } of months) {
      const generated = generateVirtualShiftsForMonth(
        { year, month },
        {
          start_time: cleanTime(recurring.start_time),
          end_time: cleanTime(recurring.end_time),
          repeat_interval_weeks: recurring.repeat_interval_weeks as
            | 0
            | 1
            | 2
            | 3
            | 4
            | 5
            | 6
            | 7
            | 8,
          selected_days: recurring.selected_days,
          end_condition: recurring.end_condition as never,
          exclusions: recurring.exclusions ?? [],
        },
      );

      for (const generatedShift of generated) {
        if (generatedShift.date < startDate || generatedShift.date > endDate) continue;

        result.push({
          id: `virtual-${recurring.id}-${generatedShift.date}`,
          user_id: recurring.user_id,
          job_id: effectiveJobId,
          shift_date: generatedShift.date,
          start_time: cleanTime(recurring.start_time),
          end_time: cleanTime(recurring.end_time),
          custom_pause_windows:
            recurring.date_specific_pause_windows?.[generatedShift.date] ?? null,
          custom_supplements:
            recurring.date_specific_supplements?.[generatedShift.date] ?? null,
          recurring_id: recurring.id,
          recurring_anchor_weekday: generatedShift.weekday,
        });
      }
    }
  }

  return result;
}

function computeLine(
  shift: ShiftRow,
  snapshots: WageSnapshot[],
  defaultJobId: string | null,
  eligibleJobKeys: Set<string>,
  strictTariffType: boolean,
  source: BackpayLine["source"],
): BackpayLine | null {
  const effectiveJobId = shift.job_id ?? defaultJobId;
  if (!eligibleJobKeys.has(jobKey(shift.user_id, effectiveJobId))) return null;

  const scopedSnapshots = snapshotsForJob(snapshots, effectiveJobId, defaultJobId);
  const snapshot = snapshotForDate(shift.shift_date, scopedSnapshots);
  if (!snapshot || !isHkVirkeTariffSnapshot(snapshot, strictTariffType)) return null;

  const wageLevel = snapshot.wage_level;
  if (wageLevel === null) return null;

  const adjustedSnapshot = adjustedSnapshotForDate(snapshot, shift.shift_date);
  if (!adjustedSnapshot) return null;

  const oldComputed = computeShift(shift, {}, PRESET_SUPPLEMENT_RULES, snapshot);
  const newComputed = computeShift(shift, {}, PRESET_SUPPLEMENT_RULES, adjustedSnapshot);
  const amount = roundCurrency(newComputed.gross - oldComputed.gross);
  if (amount < MIN_AMOUNT) return null;

  return {
    source,
    userId: shift.user_id,
    jobId: effectiveJobId,
    shiftId: shift.id,
    shiftDate: shift.shift_date,
    startTime: shift.start_time,
    endTime: shift.end_time,
    wageLevel,
    paidHours: oldComputed.paidHours,
    oldHourlyWage: snapshot.hourly_wage,
    newHourlyWage: adjustedSnapshot.hourly_wage,
    amount,
    oldGross: oldComputed.gross,
    newGross: newComputed.gross,
    snapshotId: snapshot.id,
    tariffTypeId: snapshot.tariff_type_id,
  };
}

function timeToMinutes(time: string): number {
  const [hours, minutes] = cleanTime(time).split(":").map(Number);
  return hours * 60 + minutes;
}

function shiftsOverlap(a: BackpayLine, b: BackpayLine): boolean {
  const startA = timeToMinutes(a.startTime);
  let endA = timeToMinutes(a.endTime);
  const startB = timeToMinutes(b.startTime);
  let endB = timeToMinutes(b.endTime);

  if (endA <= startA) endA += 24 * 60;
  if (endB <= startB) endB += 24 * 60;

  return startA < endB && startB < endA;
}

function buildExcludedShiftIds(lines: BackpayLine[]): Set<string> {
  const excludedIds = new Set<string>();
  const linesByDate = new Map<string, BackpayLine[]>();
  for (const line of lines) {
    linesByDate.set(line.shiftDate, [...(linesByDate.get(line.shiftDate) ?? []), line]);
  }

  for (const linesOnDate of linesByDate.values()) {
    if (linesOnDate.length < 2) continue;

    const parent = new Map(linesOnDate.map((line) => [line.shiftId, line.shiftId]));

    const find = (id: string): string => {
      const currentParent = parent.get(id) ?? id;
      if (currentParent !== id) {
        const root = find(currentParent);
        parent.set(id, root);
        return root;
      }
      return currentParent;
    };

    const union = (a: string, b: string) => {
      const rootA = find(a);
      const rootB = find(b);
      if (rootA !== rootB) parent.set(rootA, rootB);
    };

    for (let i = 0; i < linesOnDate.length; i += 1) {
      for (let j = i + 1; j < linesOnDate.length; j += 1) {
        if (shiftsOverlap(linesOnDate[i], linesOnDate[j])) {
          union(linesOnDate[i].shiftId, linesOnDate[j].shiftId);
        }
      }
    }

    const clusters = new Map<string, BackpayLine[]>();
    for (const line of linesOnDate) {
      const root = find(line.shiftId);
      clusters.set(root, [...(clusters.get(root) ?? []), line]);
    }

    for (const cluster of clusters.values()) {
      if (cluster.length < 2) continue;
      const sorted = cluster
        .map((line, index) => ({ line, index }))
        .sort((lhs, rhs) => {
          if (lhs.line.source !== rhs.line.source) {
            return lhs.line.source === "shift" ? -1 : 1;
          }
          if (lhs.line.oldGross !== rhs.line.oldGross) {
            return rhs.line.oldGross - lhs.line.oldGross;
          }
          return lhs.index - rhs.index;
        })
        .map(({ line }) => line);

      for (let index = 1; index < sorted.length; index += 1) {
        excludedIds.add(sorted[index].shiftId);
      }
    }
  }

  return excludedIds;
}

function applyConflictExclusion(lines: BackpayLine[]): BackpayLine[] {
  const excludedIds = buildExcludedShiftIds(lines);
  if (excludedIds.size === 0) return lines;
  return lines.filter((line) => !excludedIds.has(line.shiftId));
}

function groupLines(
  lines: BackpayLine[],
  jobsById: Map<string, JobRow>,
  settingsByUserId: Map<string, UserSettingsRow>,
): BackpayGroup[] {
  const groups = new Map<string, BackpayGroup>();

  for (const line of lines) {
    const key = `${line.userId}:${line.jobId ?? ""}`;
    const jobCurrency = line.jobId ? jobsById.get(line.jobId)?.currency : null;
    const userCurrency = settingsByUserId.get(line.userId)?.currency;
    const group = groups.get(key) ?? {
      userId: line.userId,
      jobId: line.jobId,
      currency: jobCurrency ?? userCurrency ?? DEFAULT_CURRENCY,
      amount: 0,
      earnedFromDate: line.shiftDate,
      earnedToDate: line.shiftDate,
      lines: [],
    };

    group.amount = roundCurrency(group.amount + line.amount);
    group.earnedFromDate = line.shiftDate < group.earnedFromDate
      ? line.shiftDate
      : group.earnedFromDate;
    group.earnedToDate = line.shiftDate > group.earnedToDate
      ? line.shiftDate
      : group.earnedToDate;
    group.lines.push(line);
    groups.set(key, group);
  }

  return [...groups.values()].filter((group) => group.amount >= MIN_AMOUNT);
}

async function fetchAll<T>(
  queryFactory: (
    from: number,
    to: number,
  ) => PromiseLike<{ data: T[] | null; error: unknown }>,
): Promise<T[]> {
  const pageSize = 1000;
  const rows: T[] = [];

  for (let from = 0;; from += pageSize) {
    const { data, error } = await queryFactory(from, from + pageSize - 1);
    if (error) {
      const message = error instanceof Error ? error.message : JSON.stringify(error);
      throw new Error(message);
    }
    const page = data ?? [];
    rows.push(...page);
    if (page.length < pageSize) break;
  }

  return rows;
}

function toAdjustment(group: BackpayGroup, payoutDate: string): AdjustmentInsert {
  const levelSummary = [...new Set(group.lines.map((line) => line.wageLevel))]
    .sort((a, b) => a - b)
    .join(", ");
  const hours = roundCurrency(group.lines.reduce((sum, line) => sum + line.paidHours, 0));
  const recurringCount = group.lines.filter((line) => line.source === "recurring").length;
  const shiftCount = group.lines.length - recurringCount;

  return {
    user_id: group.userId,
    job_id: group.jobId,
    amount: group.amount,
    currency: group.currency,
    category: "retro_pay",
    tax_treatment: "gross_taxable",
    description: HK_VIRKE_ADJUSTMENT_DESCRIPTION,
    curated_note: HK_VIRKE_CURATED_NOTE,
    curated_description: HK_VIRKE_CURATED_DESCRIPTION,
    curated_link: HK_VIRKE_SOURCE_URL,
    curated_link_title: HK_VIRKE_CURATED_LINK_TITLE,
    note:
      `${BACKPAY_MARKER}; levels=${levelSummary}; paid_hours=${hours}; shifts=${shiftCount}; recurring=${recurringCount}`,
    earned_from_date: group.earnedFromDate,
    earned_to_date: group.earnedToDate,
    payout_date: payoutDate,
  };
}

function buildOperationalWageUpdates(
  jobs: JobRow[],
  snapshotsByUserId: Map<string, WageSnapshot[]>,
  defaultJobByUserId: Map<string, string>,
  eligibleJobKeys: Set<string>,
  eligibilityDate: string,
): {
  updates: OperationalWageUpdate[];
  skippedExisting: number;
  skippedNotIncreased: number;
} {
  const updates: OperationalWageUpdate[] = [];
  let skippedExisting = 0;
  let skippedNotIncreased = 0;

  for (const job of jobs) {
    if (job.deleted_at !== null || job.archived_at !== null) continue;
    if (!eligibleJobKeys.has(jobKey(job.user_id, job.id))) continue;

    const userSnapshots = snapshotsByUserId.get(job.user_id) ?? [];
    const jobSnapshots = snapshotsForJob(
      userSnapshots,
      job.id,
      defaultJobByUserId.get(job.user_id) ?? null,
    );

    if (jobSnapshots.some((snapshot) => snapshot.from_date === JUNE_OPERATIONAL_TARIFF_DATE)) {
      skippedExisting += 1;
      continue;
    }

    const currentSnapshot = snapshotForDate(eligibilityDate, jobSnapshots);
    if (!currentSnapshot || !isHkVirkeTariffSnapshot(currentSnapshot, false)) continue;

    const wageLevel = currentSnapshot.wage_level;
    if (wageLevel === null) continue;

    const targetRate = targetRateFor(wageLevel, JUNE_OPERATIONAL_TARIFF_DATE);
    if (targetRate === null) continue;
    if (targetRate <= currentSnapshot.hourly_wage) {
      skippedNotIncreased += 1;
      continue;
    }

    updates.push({
      jobId: job.id,
      userId: job.user_id,
      jobName: job.name,
      sourceSnapshotId: currentSnapshot.id,
      wageLevel,
      oldHourlyWage: currentSnapshot.hourly_wage,
      newHourlyWage: targetRate,
      legacyTariffType: currentSnapshot.tariff_type_id === null,
      insert: {
        user_id: job.user_id,
        job_id: job.id,
        from_date: JUNE_OPERATIONAL_TARIFF_DATE,
        hourly_wage: targetRate,
        wage_level: wageLevel,
        tariff_type_id: "hk_retail",
        supplements: currentSnapshot.supplements,
        tax_enabled: currentSnapshot.tax_enabled,
        tax_percentage: currentSnapshot.tax_percentage,
        break_enabled: currentSnapshot.break_enabled,
        break_method: currentSnapshot.break_method,
        break_threshold_hours: currentSnapshot.break_threshold_hours,
        break_deduction_minutes: currentSnapshot.break_deduction_minutes,
      },
    });
  }

  return { updates, skippedExisting, skippedNotIncreased };
}

async function main() {
  const { apply } = parseRunMode(Deno.args);
  validateRunConfig(RUN_CONFIG, apply);
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ??
    Deno.env.get("NEXT_PUBLIC_SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE") ?? "";

  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const [settings, jobs, snapshots, shifts, recurringShifts] = await Promise.all([
    fetchAll<UserSettingsRow>((from, to) =>
      supabase
        .from("user_settings")
        .select("user_id,currency")
        .range(from, to)
    ),
    fetchAll<JobRow>((from, to) =>
      supabase
        .from("jobs")
        .select("id,user_id,name,is_default,currency,archived_at,deleted_at")
        .is("deleted_at", null)
        .range(from, to)
    ),
    fetchAll<Record<string, unknown>>((from, to) => {
      let query = supabase
        .from("wage_snapshots")
        .select("*")
        .is("deleted_at", null)
        .range(from, to);
      if (RUN_CONFIG.userId) query = query.eq("user_id", RUN_CONFIG.userId);
      return query;
    }),
    fetchAll<ShiftDbRow>((from, to) => {
      let query = supabase
        .from("user_shifts")
        .select(
          "id,user_id,job_id,shift_date,start_time,end_time,custom_pause_windows,custom_supplements,deleted_at",
        )
        .is("deleted_at", null)
        .gte("shift_date", RUN_CONFIG.fromDate)
        .lte("shift_date", RUN_CONFIG.throughDate)
        .range(from, to);
      if (RUN_CONFIG.userId) query = query.eq("user_id", RUN_CONFIG.userId);
      return query;
    }),
    RUN_CONFIG.includeRecurring
      ? fetchAll<RecurringDbRow>((from, to) => {
        let query = supabase
          .from("recurring_shifts")
          .select(
            "id,user_id,job_id,start_time,end_time,repeat_interval_weeks,selected_days,end_condition,exclusions,date_specific_pause_windows,date_specific_supplements,deleted_at",
          )
          .is("deleted_at", null)
          .range(from, to);
        if (RUN_CONFIG.userId) query = query.eq("user_id", RUN_CONFIG.userId);
        return query;
      })
      : Promise.resolve([] as RecurringDbRow[]),
  ]);

  const settingsByUserId = new Map(settings.map((row) => [row.user_id, row]));
  const jobsById = new Map(jobs.map((job) => [job.id, job]));
  const defaultJobByUserId = new Map(
    jobs
      .filter((job) => job.is_default && job.deleted_at === null)
      .map((job) => [job.user_id, job.id]),
  );
  const snapshotsByUserId = new Map<string, WageSnapshot[]>();

  for (const row of snapshots) {
    const snapshot = normalizeSnapshot(row);
    const existing = snapshotsByUserId.get(snapshot.user_id) ?? [];
    existing.push(snapshot);
    snapshotsByUserId.set(snapshot.user_id, existing);
  }

  const eligibilityDate = localISODate();
  const eligibleJobKeys = buildEligibleJobKeys(
    jobs,
    snapshotsByUserId,
    defaultJobByUserId,
    RUN_CONFIG.strictTariffType,
    eligibilityDate,
    RUN_CONFIG.userId,
    RUN_CONFIG.jobId,
  );

  const actualShifts = shifts.map(makeShift).filter((shift) => {
    const effectiveJobId = effectiveJobIdFor(shift.user_id, shift.job_id, defaultJobByUserId);
    if (RUN_CONFIG.jobId && effectiveJobId !== RUN_CONFIG.jobId) return false;
    return eligibleJobKeys.has(jobKey(shift.user_id, effectiveJobId));
  });
  const recurringVirtualShifts = RUN_CONFIG.includeRecurring
    ? makeRecurringShifts(
      recurringShifts,
      RUN_CONFIG.fromDate,
      RUN_CONFIG.throughDate,
      defaultJobByUserId,
      eligibleJobKeys,
      RUN_CONFIG.jobId,
    )
    : [];

  const shiftLines = actualShifts
    .map((shift) =>
      computeLine(
        shift,
        snapshotsByUserId.get(shift.user_id) ?? [],
        defaultJobByUserId.get(shift.user_id) ?? null,
        eligibleJobKeys,
        RUN_CONFIG.strictTariffType,
        "shift",
      )
    )
    .filter((line): line is BackpayLine => line !== null);
  const recurringLines = recurringVirtualShifts
    .map((shift) =>
      computeLine(
        shift,
        snapshotsByUserId.get(shift.user_id) ?? [],
        defaultJobByUserId.get(shift.user_id) ?? null,
        eligibleJobKeys,
        RUN_CONFIG.strictTariffType,
        "recurring",
      )
    )
    .filter((line): line is BackpayLine => line !== null);

  const candidateLines = [...shiftLines, ...recurringLines];
  const lines = applyConflictExclusion(candidateLines);

  const groups = groupLines(lines, jobsById, settingsByUserId);
  const adjustments = groups.map((group) => toAdjustment(group, RUN_CONFIG.payoutDate));
  adjustments.forEach(validateAdjustmentPayload);
  const operationalWages = buildOperationalWageUpdates(
    jobs,
    snapshotsByUserId,
    defaultJobByUserId,
    eligibleJobKeys,
    eligibilityDate,
  );

  let inserted = 0;
  let skippedExisting = 0;
  let wageSnapshotsInserted = 0;

  if (apply && adjustments.length > 0) {
    for (const adjustment of adjustments) {
      let existingQuery = supabase
        .from("payroll_adjustments")
        .select("id")
        .eq("user_id", adjustment.user_id)
        .eq("payout_date", adjustment.payout_date)
        .eq("category", "retro_pay")
        .ilike("note", `%${BACKPAY_MARKER}%`)
        .is("deleted_at", null)
        .limit(1);
      existingQuery = adjustment.job_id === null
        ? existingQuery.is("job_id", null)
        : existingQuery.eq("job_id", adjustment.job_id);

      const { data: existing, error: existingError } = await existingQuery;

      if (existingError) throw new Error(existingError.message);
      if ((existing ?? []).length > 0) {
        skippedExisting += 1;
        continue;
      }

      const { error } = await supabase.from("payroll_adjustments").insert(adjustment);
      if (error) throw new Error(error.message);
      inserted += 1;
    }
  }

  if (apply && operationalWages.updates.length > 0) {
    const { error } = await supabase.from("wage_snapshots").insert(
      operationalWages.updates.map((update) => update.insert),
    );
    if (error) throw new Error(error.message);
    wageSnapshotsInserted = operationalWages.updates.length;
  }

  const totalAmount = roundCurrency(groups.reduce((sum, group) => sum + group.amount, 0));
  const result = {
    mode: apply ? "apply" : "dry-run",
    tariff: "hk_retail",
    operationalTariffEffectiveDate: JUNE_OPERATIONAL_TARIFF_DATE,
    backpayStart: RUN_CONFIG.fromDate,
    throughDate: RUN_CONFIG.throughDate,
    payoutDate: RUN_CONFIG.payoutDate,
    eligibilityDate,
    eligibleJobs: eligibleJobKeys.size,
    users: new Set(groups.map((group) => group.userId)).size,
    groups: groups.length,
    shifts: lines.filter((line) => line.source === "shift").length,
    recurringShifts: lines.filter((line) => line.source === "recurring").length,
    excludedConflicts: candidateLines.length - lines.length,
    totalAmount,
    inserted,
    skippedExisting,
    operationalWageSnapshots: operationalWages.updates.length,
    operationalWageSnapshotsInserted: wageSnapshotsInserted,
    operationalWageSnapshotsSkippedExisting: operationalWages.skippedExisting,
    operationalWageSnapshotsSkippedNotIncreased: operationalWages.skippedNotIncreased,
    operationalWageUpdates: operationalWages.updates.map((update) => ({
      userId: update.userId,
      jobId: update.jobId,
      jobName: update.jobName,
      sourceSnapshotId: update.sourceSnapshotId,
      wageLevel: update.wageLevel,
      oldHourlyWage: update.oldHourlyWage,
      newHourlyWage: update.newHourlyWage,
      legacyTariffType: update.legacyTariffType,
    })),
    adjustments,
  };

  if (RUN_CONFIG.json) {
    console.log(JSON.stringify(result, null, 2));
    return;
  }

  console.log(`HK/Virke 2026 backpay ${result.mode}`);
  console.log(`Operational tariff effective date: ${JUNE_OPERATIONAL_TARIFF_DATE}`);
  console.log(`Backpay period: ${RUN_CONFIG.fromDate}..${RUN_CONFIG.throughDate}`);
  console.log(`Payout date: ${RUN_CONFIG.payoutDate}`);
  console.log(`Eligibility date: ${eligibilityDate}`);
  console.log(`Eligible jobs: ${result.eligibleJobs}`);
  console.log(`Users: ${result.users}`);
  console.log(`Adjustment groups: ${result.groups}`);
  console.log(`Shifts included: ${result.shifts}`);
  console.log(`Recurring shifts included: ${result.recurringShifts}`);
  console.log(`Conflicting entries excluded: ${result.excludedConflicts}`);
  console.log(`Total gross backpay: ${result.totalAmount.toFixed(2)} ${DEFAULT_CURRENCY}`);
  console.log(
    `Operational wage snapshots for ${JUNE_OPERATIONAL_TARIFF_DATE}: ${result.operationalWageSnapshots}`,
  );
  console.log(
    `Existing operational wage snapshots skipped: ${result.operationalWageSnapshotsSkippedExisting}`,
  );
  console.log(
    `Operational wage snapshots skipped without an increase: ${result.operationalWageSnapshotsSkippedNotIncreased}`,
  );
  if (apply) {
    console.log(`Inserted: ${inserted}`);
    console.log(`Skipped existing: ${skippedExisting}`);
    console.log(`Wage snapshots inserted: ${wageSnapshotsInserted}`);
  } else {
    console.log("No rows inserted. Re-run with --apply after approval.");
  }
}

if (import.meta.main) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    Deno.exit(1);
  });
}
