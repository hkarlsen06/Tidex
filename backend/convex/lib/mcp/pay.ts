import type { BreakMethod, OvertimeConfig, SupplementRule } from "../shared/payroll/types";
import { type CatalogueEntry, tariffCatalogue } from "../tariffCatalogue";
import {
  adds,
  allowOnly,
  type Args,
  boolean,
  date,
  destructive,
  integer,
  jobRef,
  numberRange,
  oneOf,
  optional,
  optionalString,
  positive,
  readOnly,
  requiredString,
  time,
  today,
  updates,
} from "./args";
import type { ToolSpec } from "./registry";
import { parseDate, parseTime, ToolError } from "./shiftTimes";

// The overview, job, pay and tariff tools, plus the job and wage_snapshots row builders.
// Rows match what the iOS app writes (JobsRepository, OnboardingData, WageSnapshotEditorSheet),
// verified by backend/scripts/mcp-contract-fixture.ts and MCPContractFixtureTests.swift.

// ---------- Data ----------

/** jobs.pay_period. A job without one is paid by calendar month (PayPeriod.swift). */
export type PayPeriod =
  | { type: "monthly"; startDay: number; payoutMonthOffset: 0 | 1 }
  | { type: "biweekly"; anchorEnd: string; payoutDelayDays: number };

export type HalfTaxMonth = 11 | 12;

/** The pay part of a wage snapshot row, as WageSnapshotEditorInput writes it. */
export type SnapshotFields = {
  hourly_wage: number;
  wage_level?: number;
  tariff_type_id?: string;
  supplements: { rules: SupplementRule[] };
  overtime: OvertimeConfig;
  tax_enabled: boolean;
  tax_percentage?: number;
  break_enabled: boolean;
  break_method: BreakMethod;
  break_threshold_hours: number;
  break_deduction_minutes: number;
};

/** A stored wage snapshot's pay fields. Rows the app wrote may leave any optional one out. */
export type StoredSnapshot = Partial<Omit<SnapshotFields, "hourly_wage" | "supplements" | "overtime">> & {
  hourly_wage: number;
  supplements: unknown;
  overtime: unknown;
};

export type PayChoice =
  | { type: "tariff"; tariff_type_id: string; level: number }
  | { type: "custom"; hourly_wage?: number; supplements?: SupplementRule[]; overtime?: OvertimeChoice };
export type OvertimeChoice = { enabled: false } | { enabled: true; weekly_threshold_hours?: number };
export type TaxChoice = { enabled: boolean; percentage?: number };
export type BreakChoice = { enabled: boolean; method?: BreakMethod; threshold_hours?: number; deduction_minutes?: number };

/** What set_pay and save_job (create) change. Anything omitted stays from the snapshot in effect. */
export type PaySettings = { pay?: PayChoice; tax?: TaxChoice; breaks?: BreakChoice };

/** WorkplaceColor.curatedHexPalette, the colors the app offers. */
export const JOB_COLORS = [
  "#3B82F6", "#22C55E", "#EF4444", "#F59E0B", "#A855F7", "#14B8A6", "#EC4899", "#06B6D4",
  "#6366F1", "#8B5CF6", "#10B981", "#84CC16", "#F97316", "#EAB308", "#F43F5E", "#D946EF",
  "#0EA5E9", "#2563EB", "#16A34A", "#DC2626", "#EA580C", "#7C3AED", "#0891B2", "#BE123C",
];
const DEFAULT_COLOR = JOB_COLORS[0]!;

/** CurrencyConfig.groups, the currency symbols the app offers. */
export const CURRENCIES = [
  "kr", "$", "€", "£", "¥", "C$", "A$", "S$", "R$", "zł", "Kč", "₹", "₽", "₩", "R", "฿", "NT$", "₺", "₴", "₪",
  "ر.س", "lei", "Ft", "Rp", "₫",
];

/** OvertimeConfig.disabled, encoded as the app encodes it. */
export const OVERTIME_OFF: OvertimeConfig = { enabled: false, retainSupplements: false, rules: [], weeklyThresholdHours: 40 };

/** OvertimeConfig.seededDefaults: the rules the app fills in when overtime is turned on. */
export function seededOvertime(weeklyThresholdHours = 40): OvertimeConfig {
  const weekdays = [1, 2, 3, 4, 5, 6];
  return {
    enabled: true,
    weeklyThresholdHours,
    retainSupplements: false,
    rules: [
      { days: weekdays, appliesOnHolidays: false, from: "00:00", to: "21:00", percent: 50 },
      { days: weekdays, appliesOnHolidays: false, from: "21:00", to: "24:00", percent: 100 },
      { days: [7], appliesOnHolidays: true, from: "00:00", to: "24:00", percent: 100 },
      { days: [1, 2, 3, 4, 5, 6, 7], appliesOnHolidays: true, from: "00:00", to: "24:00", percent: 100 },
    ],
  };
}

const BREAK_METHODS = ["proportional", "base_only", "end_of_shift"] as const;
const BREAK_DEFAULTS = { method: "proportional" as BreakMethod, threshold_hours: 5.5, deduction_minutes: 30 };
const MAX_SUPPLEMENT_RULES = 50;

// ---------- Tariffs ----------

export function tariffEntry(tariffTypeId: string): CatalogueEntry {
  const entry = tariffCatalogue.find((e) => e.type.id === tariffTypeId);
  if (entry === undefined) throw new ToolError(`No tariff with tariff_type_id ${tariffTypeId}. Use find_tariffs.`);
  return entry;
}

function tariffChoices(entry: CatalogueEntry) {
  return Object.fromEntries((entry.type.presentation?.options ?? []).map((o) => [o.dimension_id, o.value_en]));
}

function tariffLevels(entry: CatalogueEntry) {
  return entry.version.categories.map((c) => ({
    level: c.level,
    label: c.label_en,
    label_nb: c.label_nb,
    hourly_wage: entry.version.rates[String(c.level)],
  }));
}

/** One tariff's full levels, rates and rules. */
export function getTariff(tariffTypeId: string) {
  const entry = tariffEntry(tariffTypeId);
  const { type, version } = entry;
  const ov = overtimeSummary(version.overtime);
  return {
    tariff_type_id: type.id,
    name: type.display_name_en,
    name_nb: type.display_name_nb,
    choices: tariffChoices(entry),
    currency: "kr",
    valid_from: version.effective_date,
    valid_through: version.valid_through,
    coverage: version.coverage_note_en,
    source_url: version.source_url,
    levels: tariffLevels(entry),
    supplement_rules_count: version.supplements.rules.length,
    ...ov,
  };
}

/**
 * Searches tariffs or inspects one tariff_type_id. When search narrows to at most 5
 * variants, includes levels directly on each variant so one call is enough.
 */
export function findTariffs(args: { search?: string; tariff_type_id?: string }) {
  if (args.tariff_type_id !== undefined) {
    return { tariff: getTariff(args.tariff_type_id) };
  }
  const needle = args.search?.trim().toLowerCase();
  const matched: CatalogueEntry[] = [];
  for (const entry of tariffCatalogue) {
    const p = entry.type.presentation;
    if (p === undefined) continue;
    const haystack = [p.name_en, p.name_nb, entry.type.display_name_en, entry.type.id, ...p.search_terms].join(" ").toLowerCase();
    if (needle && !haystack.includes(needle)) continue;
    matched.push(entry);
  }
  const includeLevels = needle !== undefined && matched.length <= 10;
  const families = new Map<
    string,
    {
      family_id: string;
      name: string;
      name_nb: string;
      kind: string;
      variants: Record<string, unknown>[];
    }
  >();
  for (const entry of matched) {
    const p = entry.type.presentation!;
    const family = families.get(p.family_id) ?? {
      family_id: p.family_id,
      name: p.name_en,
      name_nb: p.name_nb,
      kind: p.kind,
      variants: [],
    };
    family.variants.push({
      tariff_type_id: entry.type.id,
      choices: tariffChoices(entry),
      level_count: entry.version.categories.length,
      ...(includeLevels
        ? {
            valid_from: entry.version.effective_date,
            valid_through: entry.version.valid_through,
            levels: tariffLevels(entry),
          }
        : {}),
    });
    families.set(p.family_id, family);
  }
  return { tariffs: [...families.values()] };
}

/** The level's label in a tariff the catalogue still has, else null. */
export function tariffLevelLabel(tariffTypeId: string | undefined, level: number | undefined) {
  const entry = tariffCatalogue.find((e) => e.type.id === tariffTypeId);
  const category = entry?.version.categories.find((c) => c.level === level);
  return entry === undefined ? null : { tariff_name: entry.type.display_name_en, level_label: category?.label_en ?? null };
}

// ---------- Snapshot rows ----------

const isCustom = (s: StoredSnapshot | null) => s !== null && s.wage_level === undefined;
const clone = <T>(value: T): T => structuredClone(value);

/** A tariff level's pay on `date`, as OnboardingData builds it. Tariff pay is always in kr. */
function tariffPay(choice: { tariff_type_id: string; level: number }, dateStr: string) {
  const { type, version } = tariffEntry(choice.tariff_type_id);
  const rate = version.rates[String(choice.level)];
  if (rate === undefined) {
    const levels = version.categories.map((c) => c.level).join(", ");
    throw new ToolError(`${type.display_name_en} has no level ${choice.level}. Levels: ${levels}. Use find_tariffs.`);
  }
  if (dateStr < version.effective_date || dateStr > version.valid_through) {
    throw new ToolError(
      `Tidex has ${type.display_name_en} rates from ${version.effective_date} to ${version.valid_through}, not for ${dateStr}. ` +
        "Pass hourly_wage for custom pay on that date.",
    );
  }
  return {
    hourly_wage: rate,
    wage_level: choice.level,
    tariff_type_id: type.id,
    supplements: clone(version.supplements),
    overtime: clone(version.overtime ?? seededOvertime()),
  };
}

/**
 * The fields of the wage snapshot `settings` describe. `base` is the snapshot being changed,
 * else the one in effect on `date`, else null for a new job's base pay. Anything omitted
 * comes from `base`, or from the app's new-job defaults.
 */
export function snapshotFields(settings: PaySettings, base: StoredSnapshot | null, on: { date: string; currency: string }): SnapshotFields {
  const { pay, tax, breaks } = settings;

  let payFields: Pick<SnapshotFields, "hourly_wage" | "wage_level" | "tariff_type_id" | "supplements" | "overtime">;
  if (pay?.type === "tariff") {
    if (on.currency !== "kr") throw new ToolError("Tariff pay needs a job paid in kr. Pass hourly_wage for custom pay.");
    payFields = tariffPay(pay, on.date);
  } else if (pay?.type === "custom") {
    const keep = isCustom(base);
    if (pay.hourly_wage === undefined && !keep) {
      throw new ToolError("hourly_wage is required when setting custom pay or switching from a tariff.");
    }
    const baseOvertime = base?.overtime as Partial<OvertimeConfig> | undefined;
    const overtime = pay.overtime;
    payFields = {
      hourly_wage: pay.hourly_wage ?? base!.hourly_wage,
      supplements:
        pay.supplements !== undefined
          ? { rules: pay.supplements }
          : keep
            ? clone(base!.supplements as SnapshotFields["supplements"])
            : { rules: [] },
      overtime:
        overtime === undefined
          ? keep
            ? clone(base!.overtime as OvertimeConfig)
            : OVERTIME_OFF
          : overtime.enabled
            ? seededOvertime(overtime.weekly_threshold_hours ?? (keep ? baseOvertime?.weeklyThresholdHours : undefined) ?? 40)
            : OVERTIME_OFF,
    };
  } else {
    if (base === null) throw new ToolError("Give either hourly_wage (custom pay) or tariff_type_id and tariff_level.");
    payFields = {
      hourly_wage: base.hourly_wage,
      ...(base.wage_level === undefined ? {} : { wage_level: base.wage_level }),
      ...(base.tariff_type_id === undefined ? {} : { tariff_type_id: base.tariff_type_id }),
      supplements: clone(base.supplements as SnapshotFields["supplements"]),
      overtime: clone(base.overtime as OvertimeConfig),
    };
  }

  const taxEnabled = tax?.enabled ?? base?.tax_enabled ?? false;
  const taxPercentage = taxEnabled ? (tax?.percentage ?? base?.tax_percentage) : undefined;
  if (taxEnabled && taxPercentage === undefined) throw new ToolError("tax_percent is required when tax is enabled.");

  // Existing pay keeps its break behaviour unless changed; a missing break_enabled means on in the app.
  // New pay in a currency other than kr defaults to breaks off (OnboardingData.usesSimpleSetup).
  const breakEnabled = breaks?.enabled ?? (base === null ? on.currency === "kr" : (base.break_enabled ?? true));
  const storedMethod = breaks?.enabled === true && base?.break_method === "none" ? undefined : base?.break_method;

  return {
    ...payFields,
    tax_enabled: taxEnabled,
    ...(taxPercentage === undefined ? {} : { tax_percentage: taxPercentage }),
    break_enabled: breakEnabled,
    break_method: breaks?.method ?? storedMethod ?? BREAK_DEFAULTS.method,
    break_threshold_hours: breaks?.threshold_hours ?? base?.break_threshold_hours ?? BREAK_DEFAULTS.threshold_hours,
    break_deduction_minutes: breaks?.deduction_minutes ?? base?.break_deduction_minutes ?? BREAK_DEFAULTS.deduction_minutes,
  };
}

/** The wage_snapshots row the app's sync inserts, without the fields the server sets. */
export function snapshotRow(id: string, jobId: string, fromDate: string | undefined, fields: SnapshotFields) {
  return { id, job_id: jobId, ...(fromDate === undefined ? {} : { from_date: fromDate }), ...fields };
}

const OPTIONAL_SNAPSHOT_FIELDS = ["wage_level", "tariff_type_id", "tax_percentage"] as const;

/** The update that turns `prev` into `fields`, or null when they already match. */
export function snapshotUpdate(prev: StoredSnapshot, fields: SnapshotFields) {
  const set: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(fields)) {
    if (canonical(value) !== canonical(prev[key as keyof StoredSnapshot])) set[key] = value;
  }
  const clear = OPTIONAL_SNAPSHOT_FIELDS.filter((key) => prev[key] !== undefined && fields[key] === undefined);
  return Object.keys(set).length === 0 && clear.length === 0 ? null : { set, clear: [...clear] };
}

/** JSON with sorted keys, so stored and built JSON compare by value. */
function canonical(value: unknown): string {
  return JSON.stringify(value, (_key, v) =>
    v !== null && typeof v === "object" && !Array.isArray(v)
      ? Object.fromEntries(Object.entries(v).sort(([a], [b]) => a.localeCompare(b)))
      : v,
  );
}

/** The snapshot that prices a shift on `date`: the latest dated one on or before it, else the base. */
export function snapshotInEffect<S extends { from_date?: string }>(snapshots: S[], dateStr: string): S | null {
  const dated = snapshots.filter((s) => s.from_date !== undefined && s.from_date <= dateStr);
  dated.sort((a, b) => b.from_date!.localeCompare(a.from_date!));
  return dated[0] ?? snapshots.find((s) => s.from_date === undefined) ?? null;
}

// ---------- Job rows ----------

/** The jobs row JobsRepository.createJob inserts, without the fields the server sets. */
export function jobRow(input: {
  id: string;
  name: string;
  color: string;
  currency: string;
  isDefault: boolean;
  sortOrder: number;
  payrollDay: number;
  halfTaxMonth?: HalfTaxMonth;
  payPeriod?: PayPeriod;
}) {
  return {
    id: input.id,
    name: input.name,
    color: input.color,
    currency: input.currency,
    is_default: input.isDefault,
    sort_order: input.sortOrder,
    payroll_day: input.payrollDay,
    ...(input.halfTaxMonth === undefined ? {} : { half_tax_month: input.halfTaxMonth }),
    ...(input.payPeriod === undefined ? {} : { pay_period: input.payPeriod }),
  };
}

/** The next sort order and default flag for a new or restored job, as JobsRepository picks them. */
export const placement = (active: { sort_order: number }[]) => ({
  sortOrder: Math.max(-1, ...active.map((j) => j.sort_order)) + 1,
  isDefault: active.length === 0,
});

/** Why archiving `job` is refused, as JobsRepository.archiveJob refuses it, or null. */
export function archiveRefusal(job: { id: string; is_default: boolean }, active: { id: string }[]) {
  if (active.length <= 1) return "The user's only active job can't be archived. Add another job first.";
  if (job.is_default) return "The default job can't be archived. Make another job the default with save_job first.";
  return null;
}

// ---------- Reading ----------

const HALF_TAX_NAMES = { 11: "november", 12: "december" } as const;

/** A stored pay_period as the app reads it: anything it can't decode is a calendar month. */
export function payPeriodView(stored: unknown) {
  const p = (stored ?? {}) as Record<string, unknown>;
  const int = (v: unknown) => (typeof v === "number" && Number.isInteger(v) ? v : Number.NaN);
  if (p.type === "biweekly" && typeof p.anchorEnd === "string" && int(p.payoutDelayDays) >= 0 && int(p.payoutDelayDays) <= 27) {
    return { type: "biweekly", period_end: p.anchorEnd, payout_delay_days: p.payoutDelayDays as number };
  }
  if (p.type === "monthly" && int(p.startDay) >= 1 && int(p.startDay) <= 28 && (p.payoutMonthOffset === 0 || p.payoutMonthOffset === 1)) {
    return { type: "monthly", start_day: p.startDay as number, payout_month_offset: p.payoutMonthOffset };
  }
  return { type: "calendar_month" };
}

function overtimeSummary(stored: unknown) {
  const o = stored as Partial<OvertimeConfig> | null | undefined;
  return o?.enabled === true
    ? { overtime_enabled: true, overtime_weekly_hours: o.weeklyThresholdHours ?? 40 }
    : { overtime_enabled: false };
}

function supplementView(rule: SupplementRule) {
  return {
    days: rule.days,
    from: rule.from,
    to: rule.to,
    ...(rule.rate !== undefined ? { amount: rule.rate } : {}),
    ...(rule.percent !== undefined ? { percent: rule.percent } : {}),
  };
}

/** Flat, consistent view of one wage snapshot. Never mixes string and array types. */
export function paySnapshotView(
  s: StoredSnapshot & { id: string; from_date?: string },
  options: { includeSupplements: boolean; untilDate?: string | null },
) {
  const rules = ((s.supplements as { rules?: SupplementRule[] } | null)?.rules ?? []) as SupplementRule[];
  const isTariff = s.wage_level !== undefined;
  const tariff = isTariff ? tariffLevelLabel(s.tariff_type_id, s.wage_level) : null;
  const breakEnabled = (s.break_enabled ?? true) && s.break_method !== "none";
  const taxEnabled = s.tax_enabled ?? false;
  return {
    ...(options.untilDate !== undefined ? { from_date: s.from_date ?? null, until_date: options.untilDate } : {}),
    type: isTariff ? ("tariff" as const) : ("custom" as const),
    hourly_wage: s.hourly_wage,
    ...(isTariff
      ? {
          tariff_type_id: s.tariff_type_id ?? null,
          tariff_level: s.wage_level,
          ...(tariff?.tariff_name ? { tariff_name: tariff.tariff_name } : {}),
          ...(tariff?.level_label ? { level_label: tariff.level_label } : {}),
        }
      : {}),
    supplement_rules_count: rules.length,
    ...(options.includeSupplements ? { supplements: rules.map(supplementView) } : {}),
    ...overtimeSummary(s.overtime),
    tax_enabled: taxEnabled,
    ...(taxEnabled ? { tax_percent: s.tax_percentage ?? 0 } : {}),
    break_enabled: breakEnabled,
    ...(breakEnabled
      ? {
          break_method: s.break_method ?? "proportional",
          break_threshold_hours: s.break_threshold_hours ?? 5.5,
          break_minutes: s.break_deduction_minutes ?? 30,
        }
      : {}),
  };
}

export function jobView(
  job: {
    id: string;
    name: string;
    color?: string;
    currency: string;
    is_default: boolean;
    archived_at?: string;
    payroll_day?: number;
    half_tax_month?: HalfTaxMonth;
    pay_period?: unknown;
  },
  snapshots: (StoredSnapshot & { id: string; from_date?: string })[],
  options: { today: string; includePayHistory?: boolean },
) {
  const ordered = [...snapshots].sort((a, b) => (a.from_date ?? "").localeCompare(b.from_date ?? ""));
  const hasBase = ordered.some((s) => s.from_date === undefined);
  const current = hasBase ? snapshotInEffect(ordered, options.today) : null;
  const dated = ordered.flatMap((s) => (s.from_date === undefined ? [] : [s.from_date]));

  return {
    id: job.id,
    name: job.name,
    currency: job.currency,
    is_default: job.is_default,
    ...(job.archived_at !== undefined ? { archived: true } : {}),
    ...(job.color ? { color: job.color } : {}),
    payroll_day: job.payroll_day ?? 15,
    half_tax_month: job.half_tax_month === undefined ? "none" : HALF_TAX_NAMES[job.half_tax_month],
    pay_period: payPeriodView(job.pay_period),
    current_pay: current === null ? null : paySnapshotView(current, { includeSupplements: false }),
    ...(options.includePayHistory
      ? {
          pay_history: ordered.map((s) => {
            const next = dated.find((d) => s.from_date === undefined || d > s.from_date) ?? null;
            return paySnapshotView(s, { includeSupplements: true, untilDate: next });
          }),
        }
      : {}),
  };
}

// ---------- Argument parsers ----------

function object(value: unknown, field: string): Args {
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw new ToolError(`${field} must be an object.`);
  return value as Args;
}

function jobName(value: unknown): string {
  const name = typeof value === "string" ? value.trim() : "";
  if (name === "" || [...name].length > 100) throw new ToolError("name must be 1 to 100 characters.");
  return name;
}

function jobColor(value: unknown): string {
  const color = JOB_COLORS.find((c) => typeof value === "string" && c === value.toUpperCase());
  if (color === undefined) throw new ToolError(`color must be one of the app's colors: ${JOB_COLORS.join(", ")}.`);
  return color;
}

function currency(value: unknown): string {
  return oneOf(value, "currency", CURRENCIES);
}

const payrollDay = (value: unknown) => integer(value, "payroll_day", 1, 31);

function halfTaxMonth(value: unknown): HalfTaxMonth | null {
  const name = oneOf(value, "half_tax_month", ["none", "november", "december"] as const);
  return name === "none" ? null : name === "november" ? 11 : 12;
}

/** null is a calendar month, which the app stores as no pay_period. */
export function parsePayPeriod(value: unknown): PayPeriod | null {
  const p = object(value, "pay_period");
  const type = oneOf(p.type, "pay_period.type", ["calendar_month", "monthly", "biweekly"] as const);
  if (type === "calendar_month") {
    allowOnly(p, ["type"]);
    return null;
  }
  if (type === "monthly") {
    allowOnly(p, ["type", "start_day", "payout_month_offset"]);
    const startDay = integer(p.start_day, "pay_period.start_day", 1, 28);
    const payoutMonthOffset = integer(p.payout_month_offset, "pay_period.payout_month_offset", 0, 1) as 0 | 1;
    return startDay === 1 && payoutMonthOffset === 1 ? null : { type, startDay, payoutMonthOffset };
  }
  allowOnly(p, ["type", "period_end", "payout_delay_days"]);
  return {
    type,
    anchorEnd: parseDate(p.period_end, "pay_period.period_end"),
    payoutDelayDays: integer(p.payout_delay_days, "pay_period.payout_delay_days", 0, 27),
  };
}

/** A custom supplement as OnboardingSupplementRule.toSupplementRule saves it. */
export function parseSupplement(value: unknown, field: string): SupplementRule {
  const r = object(value, field);
  allowOnly(r, ["days", "from", "to", "amount", "percent"]);
  if (!Array.isArray(r.days) || r.days.length === 0) throw new ToolError(`${field}.days must list weekdays from 1 (Monday) to 7 (Sunday).`);
  const days = [...new Set(r.days.map((d) => integer(d, `${field}.days`, 1, 7)))].sort((a, b) => a - b);
  const from = parseTime(r.from, `${field}.from`) as SupplementRule["from"];
  const to = parseTime(r.to, `${field}.to`, true) as SupplementRule["to"];
  if (from === to) throw new ToolError(`${field}: from and to can't be the same time.`);
  const hasAmount = r.amount !== undefined && r.amount !== null;
  const hasPercent = r.percent !== undefined && r.percent !== null;
  if (hasAmount === hasPercent) {
    throw new ToolError(`${field} needs exactly one of amount (added per hour, in the job's currency) or percent (of the hourly wage).`);
  }
  return hasAmount
    ? { days, from, to, rate: positive(r.amount, `${field}.amount`, 100_000) }
    : { days, from, to, percent: positive(r.percent, `${field}.percent`, 1000) };
}

/** Parses flat pay, tax and break fields into PaySettings. */
export function parseFlatPaySettings(args: Args): PaySettings {
  const tariffId = optionalString(args.tariff_type_id, "tariff_type_id");
  const tariffLevel = optional(args.tariff_level, (v) => integer(v, "tariff_level", -1000, 1000));
  const hourlyWage = optional(args.hourly_wage, (v) => positive(v, "hourly_wage", 1_000_000));
  const supplements = optional(args.supplements, (items) => {
    if (!Array.isArray(items) || items.length > MAX_SUPPLEMENT_RULES) {
      throw new ToolError(`supplements must be a list of at most ${MAX_SUPPLEMENT_RULES} rules.`);
    }
    return items.map((rule, i) => parseSupplement(rule, `supplements[${i}]`));
  });
  const overtimeEnabled = optional(args.overtime_enabled, (v) => boolean(v, "overtime_enabled"));
  const overtimeWeeklyHours = optional(args.overtime_weekly_hours, (v) => positive(v, "overtime_weekly_hours", 168));

  const hasTariff = tariffId !== undefined || tariffLevel !== undefined;
  const hasCustom =
    hourlyWage !== undefined || supplements !== undefined || overtimeEnabled !== undefined || overtimeWeeklyHours !== undefined;
  if (hasTariff && hasCustom) {
    throw new ToolError("Give either tariff fields (tariff_type_id, tariff_level) or custom pay fields (hourly_wage, supplements, overtime), not both.");
  }

  let pay: PayChoice | undefined;
  if (hasTariff) {
    if (tariffId === undefined || tariffLevel === undefined) {
      throw new ToolError("Tariff pay requires both tariff_type_id and tariff_level.");
    }
    pay = { type: "tariff", tariff_type_id: tariffId, level: tariffLevel };
  } else if (hasCustom) {
    let overtime: OvertimeChoice | undefined;
    if (overtimeEnabled === false) {
      if (overtimeWeeklyHours !== undefined) throw new ToolError("overtime_weekly_hours can't be set when overtime_enabled is false.");
      overtime = { enabled: false };
    } else if (overtimeEnabled === true || overtimeWeeklyHours !== undefined) {
      overtime = { enabled: true, ...(overtimeWeeklyHours !== undefined ? { weekly_threshold_hours: overtimeWeeklyHours } : {}) };
    }
    pay = {
      type: "custom",
      ...(hourlyWage !== undefined ? { hourly_wage: hourlyWage } : {}),
      ...(supplements !== undefined ? { supplements } : {}),
      ...(overtime !== undefined ? { overtime } : {}),
    };
  }

  const taxEnabled = optional(args.tax_enabled, (v) => boolean(v, "tax_enabled"));
  const taxPercent = optional(args.tax_percent, (v) => numberRange(v, "tax_percent", 0, 100));
  let tax: TaxChoice | undefined;
  if (taxEnabled === false) {
    tax = { enabled: false };
  } else if (taxEnabled === true || taxPercent !== undefined) {
    tax = { enabled: true, ...(taxPercent !== undefined ? { percentage: taxPercent } : {}) };
  }

  const breakEnabled = optional(args.break_enabled, (v) => boolean(v, "break_enabled"));
  const breakMethod = optional(args.break_method, (v) => oneOf(v, "break_method", BREAK_METHODS));
  const breakThreshold = optional(args.break_threshold_hours, (v) => numberRange(v, "break_threshold_hours", 1, 12));
  const breakMinutes = optional(args.break_minutes, (v) => integer(v, "break_minutes", 5, 120));
  let breaks: BreakChoice | undefined;
  if (breakEnabled === false) {
    breaks = { enabled: false };
  } else if (breakEnabled === true || breakMethod !== undefined || breakThreshold !== undefined || breakMinutes !== undefined) {
    breaks = {
      enabled: true,
      ...(breakMethod !== undefined ? { method: breakMethod } : {}),
      ...(breakThreshold !== undefined ? { threshold_hours: breakThreshold } : {}),
      ...(breakMinutes !== undefined ? { deduction_minutes: breakMinutes } : {}),
    };
  }

  return {
    ...(pay !== undefined ? { pay } : {}),
    ...(tax !== undefined ? { tax } : {}),
    ...(breaks !== undefined ? { breaks } : {}),
  };
}

// ---------- Shared schemas ----------

const endTimeSchema = { type: "string", pattern: "^(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$", description: "HH:mm, 24-hour clock" };

const payPeriodSchema = {
  type: "object",
  description:
    "How workdays group into paydays. calendar_month: 1st to last day, paid next month. " +
    "monthly: starts on start_day (1-28), paid in end month (payout_month_offset 0) or month after (1). " +
    "biweekly: 14-day periods, one ending on period_end, paid payout_delay_days (0-27) later.",
  properties: {
    type: { type: "string", enum: ["calendar_month", "monthly", "biweekly"] },
    start_day: { type: "integer", minimum: 1, maximum: 28 },
    payout_month_offset: { type: "integer", enum: [0, 1] },
    period_end: date,
    payout_delay_days: { type: "integer", minimum: 0, maximum: 27 },
  },
  required: ["type"],
  additionalProperties: false,
};

const payrollDaySchema = { type: "integer", minimum: 1, maximum: 31, description: "Day of month pay arrives for monthly pay periods (default 15)." };
const halfTaxSchema = {
  type: "string",
  enum: ["none", "november", "december"],
  description: "Month with half tax (Norwegian halv skatt), or none.",
};
const colorSchema = { type: "string", enum: JOB_COLORS, description: "Hex color from the app palette." };

const supplementSchema = {
  type: "object",
  description: "Extra pay per hour in a time window. Give either amount or percent. A window where to <= from crosses midnight.",
  properties: {
    days: { type: "array", items: { type: "integer", minimum: 1, maximum: 7 }, description: "Weekdays, 1 = Monday to 7 = Sunday." },
    from: time,
    to: endTimeSchema,
    amount: { type: "number", exclusiveMinimum: 0, description: "Fixed extra per hour in the job currency." },
    percent: { type: "number", exclusiveMinimum: 0, description: "Extra percent of the hourly wage." },
  },
  required: ["days", "from", "to"],
  additionalProperties: false,
};

const flatPayProperties = {
  hourly_wage: { type: "number", exclusiveMinimum: 0, description: "Custom hourly wage in the job currency." },
  tariff_type_id: { type: "string", description: "Norwegian tariff ID from find_tariffs (use with tariff_level; job must be in kr)." },
  tariff_level: { type: "integer", description: "Tariff level from find_tariffs (use with tariff_type_id)." },
  supplements: {
    type: "array",
    items: supplementSchema,
    maxItems: MAX_SUPPLEMENT_RULES,
    description: "Custom supplement rules (replaces existing rules for custom pay).",
  },
  overtime_enabled: { type: "boolean", description: "Enable standard weekly overtime rules (50% weekdays before 21:00, 100% evenings/Sundays/holidays)." },
  overtime_weekly_hours: { type: "number", exclusiveMinimum: 0, maximum: 168, description: "Weekly hours before overtime starts (default 40)." },
  tax_enabled: { type: "boolean", description: "Deduct tax percentage to estimate net pay." },
  tax_percent: { type: "number", minimum: 0, maximum: 100, description: "Tax percentage (0-100). Passing this enables tax." },
  break_enabled: { type: "boolean", description: "Deduct an unpaid break on long shifts (default on for kr jobs)." },
  break_method: { type: "string", enum: BREAK_METHODS, description: "How break time is deducted: proportional (default), base_only, or end_of_shift." },
  break_threshold_hours: { type: "number", minimum: 1, maximum: 12, description: "Minimum shift length in hours before break deduction applies (default 5.5)." },
  break_minutes: { type: "integer", minimum: 5, maximum: 120, description: "Unpaid break length in minutes (default 30)." },
};

const FLAT_PAY_KEYS = Object.keys(flatPayProperties);

// ---------- Tool definitions ----------

export const getOverview = {
  definition: {
    name: "get_overview",
    title: "Get overview",
    description:
      "Start here to orient yourself. Returns today's date and local time in the user's time zone, active jobs with their current pay and tax settings, " +
      "recurring shift series, app settings, unread message count and friend count. " +
      "Pass include_pay_history: true for full pay timelines and supplement rules, or include_archived: true for archived jobs.",
    inputSchema: {
      type: "object",
      properties: {
        include_archived: { type: "boolean", description: "Include archived jobs (default false)." },
        include_pay_history: { type: "boolean", description: "Include full pay history and supplement rules per job (default false)." },
      },
      additionalProperties: false,
    },
    annotations: { title: "Get overview", ...readOnly },
  },
  scope: "read",
  parse: (args) => {
    allowOnly(args, ["include_archived", "include_pay_history"]);
    return {
      include_archived: optional(args.include_archived, (v) => boolean(v, "include_archived")) ?? false,
      include_pay_history: optional(args.include_pay_history, (v) => boolean(v, "include_pay_history")) ?? false,
    };
  },
} satisfies ToolSpec;

export const saveJob = {
  definition: {
    name: "save_job",
    title: "Create or update job",
    description:
      "Creates a new job with its base pay (omit id) or updates an existing job's details (pass id). " +
      "When creating: pass name plus either hourly_wage or tariff_type_id and tariff_level (currency defaults to default job currency or kr; tariff jobs are always kr). " +
      "When updating: pass id plus any of name, color, payroll_day, half_tax_month, pay_period, make_default or archived. Use set_pay to change an existing job's pay.",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string", description: "Job ID or name to update. Omit to create a new job." },
        name: { type: "string", minLength: 1, maxLength: 100 },
        color: colorSchema,
        currency: { type: "string", enum: CURRENCIES, description: "Job currency (only when creating a job; cannot change later)." },
        payroll_day: payrollDaySchema,
        half_tax_month: halfTaxSchema,
        pay_period: payPeriodSchema,
        make_default: { type: "boolean", enum: [true], description: "Set this job as the default job (update only)." },
        archived: { type: "boolean", description: "true archives the job, false restores it (update only)." },
        ...flatPayProperties,
      },
      additionalProperties: false,
    },
    annotations: { title: "Create or update job", ...adds },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, [
      "id",
      "name",
      "color",
      "currency",
      "payroll_day",
      "half_tax_month",
      "pay_period",
      "make_default",
      "archived",
      ...FLAT_PAY_KEYS,
    ]);
    const id = optionalString(args.id, "id");
    if (id === undefined) {
      // Create mode
      if (args.make_default !== undefined || args.archived !== undefined) {
        throw new ToolError("make_default and archived apply only when updating an existing job with id.");
      }
      const settings = parseFlatPaySettings(args);
      if (settings.pay === undefined || (settings.pay.type === "custom" && settings.pay.hourly_wage === undefined)) {
        throw new ToolError("New jobs need hourly_wage (custom pay) or both tariff_type_id and tariff_level.");
      }
      const chosenCurrency = optional(args.currency, currency);
      if (settings.pay.type === "tariff" && chosenCurrency !== undefined && chosenCurrency !== "kr") {
        throw new ToolError("Tariff pay is in kr. Leave out currency or use custom pay.");
      }
      const halfTax = optional(args.half_tax_month, halfTaxMonth);
      const payPeriod = optional(args.pay_period, parsePayPeriod);
      return {
        mode: "create" as const,
        name: jobName(args.name),
        color: optional(args.color, jobColor) ?? DEFAULT_COLOR,
        currency: settings.pay.type === "tariff" ? "kr" : chosenCurrency,
        payroll_day: optional(args.payroll_day, payrollDay) ?? 15,
        ...(halfTax ? { half_tax_month: halfTax } : {}),
        ...(payPeriod ? { pay_period: payPeriod } : {}),
        settings,
        today: today(),
      };
    }

    // Update mode
    const payArgsUsed = FLAT_PAY_KEYS.filter((k) => args[k] !== undefined && args[k] !== null);
    if (payArgsUsed.length > 0) {
      throw new ToolError(`Use set_pay to change pay settings (${payArgsUsed.join(", ")}) on an existing job.`);
    }
    if (args.currency !== undefined && args.currency !== null) {
      throw new ToolError("A job's currency cannot be changed after creation.");
    }
    const makeDefault = optional(args.make_default, (v) => boolean(v, "make_default"));
    if (makeDefault === false) throw new ToolError("make_default can only be true. Make another job the default instead.");
    const archived = optional(args.archived, (v) => boolean(v, "archived"));
    if (makeDefault && archived) throw new ToolError("An archived job can't be the default.");
    const changes = {
      name: optional(args.name, jobName),
      color: optional(args.color, jobColor),
      payroll_day: optional(args.payroll_day, payrollDay),
      half_tax_month: optional(args.half_tax_month, halfTaxMonth),
      pay_period: optional(args.pay_period, parsePayPeriod),
      make_default: makeDefault,
      archived,
    };
    if (Object.values(changes).every((v) => v === undefined)) {
      throw new ToolError("Give at least one of name, color, payroll_day, half_tax_month, pay_period, make_default or archived.");
    }
    return { mode: "update" as const, job: id, ...changes };
  },
} satisfies ToolSpec;

export const deleteJob = {
  definition: {
    name: "delete_job",
    title: "Delete job",
    description:
      "Permanently deletes an archived job and all its shifts, recurring shifts, pay settings and payroll adjustments. " +
      "First call without confirmation_token to preview row counts and get a token. Show the counts to the user, then call again with confirmation_token after they confirm. " +
      "Archive the job with save_job first.",
    inputSchema: {
      type: "object",
      properties: {
        job: { type: "string", description: "Archived job ID or name." },
        confirmation_token: { type: "string", description: "Token returned by the first preview call." },
      },
      required: ["job"],
      additionalProperties: false,
    },
    annotations: { title: "Delete job", ...destructive, idempotentHint: true },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["job", "confirmation_token"]);
    const token = optionalString(args.confirmation_token, "confirmation_token");
    return { job: requiredString(args.job, "job"), ...(token ? { confirmation_token: token } : {}) };
  },
} satisfies ToolSpec;

export const findTariffsSpec = {
  definition: {
    name: "find_tariffs",
    title: "Find tariffs",
    description:
      "Searches Norwegian collective agreements and statutory minimum wages, or returns full details for one tariff_type_id. " +
      "Pass search (English or Norwegian name, e.g. 'rema', 'varehandel', 'renhold') to list matching agreements, or pass tariff_type_id for all levels, hourly rates, valid dates and overtime rules.",
    inputSchema: {
      type: "object",
      properties: {
        search: { type: "string", maxLength: 100, description: "Filter agreements by English or Norwegian name." },
        tariff_type_id: { type: "string", description: "Exact tariff_type_id to inspect full levels and rates." },
      },
      additionalProperties: false,
    },
    annotations: { title: "Find tariffs", ...readOnly },
  },
  scope: "read",
  parse: (args) => {
    allowOnly(args, ["search", "tariff_type_id"]);
    const search = optionalString(args.search, "search");
    const tariff_type_id = optionalString(args.tariff_type_id, "tariff_type_id");
    if (search !== undefined && tariff_type_id !== undefined) {
      throw new ToolError("Give either search or tariff_type_id, not both.");
    }
    return {
      ...(search !== undefined ? { search } : {}),
      ...(tariff_type_id !== undefined ? { tariff_type_id } : {}),
    };
  },
} satisfies ToolSpec;

export const setPay = {
  definition: {
    name: "set_pay",
    title: "Set pay",
    description:
      "Sets a job's base pay (omit from_date), sets or updates pay starting on from_date (e.g. a raise), or removes a dated pay change (pass from_date and remove: true). " +
      "Pass only the fields to change; omitted pay, tax and break fields stay as they are on that date. " +
      "Omit job to update the default job.",
    inputSchema: {
      type: "object",
      properties: {
        job: jobRef,
        from_date: { ...date, description: "Date this pay change starts (YYYY-MM-DD). Omit to change base pay." },
        remove: { type: "boolean", enum: [true], description: "Pass true with from_date to delete that dated pay change." },
        ...flatPayProperties,
      },
      additionalProperties: false,
    },
    annotations: { title: "Set pay", ...updates },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["job", "from_date", "remove", ...FLAT_PAY_KEYS]);
    const job = optionalString(args.job, "job");
    const fromDate = optional(args.from_date, (v) => parseDate(v, "from_date"));
    const remove = optional(args.remove, (v) => boolean(v, "remove"));
    if (remove === true) {
      if (fromDate === undefined) throw new ToolError("from_date is required when remove is true. Base pay cannot be deleted.");
      const extra = FLAT_PAY_KEYS.filter((k) => args[k] !== undefined && args[k] !== null);
      if (extra.length > 0) throw new ToolError("remove: true cannot be combined with pay fields.");
      return { action: "remove" as const, ...(job !== undefined ? { job } : {}), from_date: fromDate };
    }
    if (remove === false) throw new ToolError("remove can only be true.");
    const settings = parseFlatPaySettings(args);
    if (Object.keys(settings).length === 0) {
      throw new ToolError("Give at least one pay, tax or break field to change.");
    }
    return {
      action: "set" as const,
      ...(job !== undefined ? { job } : {}),
      ...(fromDate !== undefined ? { from_date: fromDate } : {}),
      settings,
      today: today(),
    };
  },
} satisfies ToolSpec;
