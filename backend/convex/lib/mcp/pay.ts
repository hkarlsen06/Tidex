import type { BreakMethod, OvertimeConfig, SupplementRule } from "../shared/payroll/types";
import { type CatalogueEntry, tariffCatalogue } from "../tariffCatalogue";
import { allowOnly, type Args, optional, optionalString, requiredString, today } from "./args";
import type { ToolSpec } from "./registry";
import { parseDate, parseTime, ToolError } from "./shiftTimes";

// The job, pay and tariff tools: their arguments, and the job and wage snapshot rows they
// write. The rows match what the app writes (JobsRepository, OnboardingData,
// WageSnapshotEditorSheet), because one row the app can't decode stops the user's sync of
// that table. The server barely checks the JSON columns, so everything is checked here.

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
  | { type: "custom"; hourly_wage: number; supplements?: SupplementRule[]; overtime?: OvertimeChoice };
export type OvertimeChoice = { enabled: false } | { enabled: true; weekly_threshold_hours: number };
export type TaxChoice = { enabled: boolean; percentage?: number };
export type BreakChoice = { enabled: boolean; method?: BreakMethod; threshold_hours?: number; deduction_minutes?: number };

/** What set_pay and add_job change. Whatever is left out comes from the snapshot in effect. */
export type PaySettings = { pay?: PayChoice; tax?: TaxChoice; breaks?: BreakChoice };

/** WorkplaceColor.curatedHexPalette, the colors the app offers. */
export const JOB_COLORS = [
  "#3B82F6", "#22C55E", "#EF4444", "#F59E0B", "#A855F7", "#14B8A6", "#EC4899", "#06B6D4",
  "#6366F1", "#8B5CF6", "#10B981", "#84CC16", "#F97316", "#EAB308", "#F43F5E", "#D946EF",
  "#0EA5E9", "#2563EB", "#16A34A", "#DC2626", "#EA580C", "#7C3AED", "#0891B2", "#BE123C",
];
const DEFAULT_COLOR = JOB_COLORS[0];

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
  if (entry === undefined) throw new ToolError(`No tariff with tariff_type_id ${tariffTypeId}. Use list_tariffs.`);
  return entry;
}

function tariffChoices(entry: CatalogueEntry) {
  return Object.fromEntries((entry.type.presentation?.options ?? []).map((o) => [o.dimension_id, o.value_en]));
}

/** The catalogue grouped by agreement, each variant with the choices that pick it. */
export function listTariffs(search: string | undefined) {
  const needle = search?.trim().toLowerCase();
  type Variant = { tariff_type_id: string; choices: Record<string, string>; levels: number };
  const families = new Map<string, { family_id: string; name: string; name_nb: string; kind: string; variants: Variant[] }>();
  for (const entry of tariffCatalogue) {
    const p = entry.type.presentation;
    if (p === undefined) continue;
    const haystack = [p.name_en, p.name_nb, entry.type.display_name_en, entry.type.id, ...p.search_terms].join(" ").toLowerCase();
    if (needle && !haystack.includes(needle)) continue;
    const family = families.get(p.family_id) ?? { family_id: p.family_id, name: p.name_en, name_nb: p.name_nb, kind: p.kind, variants: [] };
    family.variants.push({ tariff_type_id: entry.type.id, choices: tariffChoices(entry), levels: entry.version.categories.length });
    families.set(p.family_id, family);
  }
  return { tariffs: [...families.values()] };
}

/** One tariff's levels, rates and rules, in plain terms. */
export function getTariff(tariffTypeId: string) {
  const { type, version } = tariffEntry(tariffTypeId);
  return {
    tariff_type_id: type.id,
    name: type.display_name_en,
    name_nb: type.display_name_nb,
    choices: tariffChoices({ type, version }),
    currency: "kr",
    valid_from: version.effective_date,
    valid_through: version.valid_through,
    coverage: version.coverage_note_en,
    source_url: version.source_url,
    levels: version.categories.map((c) => ({
      level: c.level,
      label: c.label_en,
      label_nb: c.label_nb,
      hourly_wage: version.rates[String(c.level)],
    })),
    supplement_rules: version.supplements.rules.length,
    overtime: overtimeView(version.overtime),
  };
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
function tariffPay(choice: { tariff_type_id: string; level: number }, date: string) {
  const { type, version } = tariffEntry(choice.tariff_type_id);
  const rate = version.rates[String(choice.level)];
  if (rate === undefined) {
    const levels = version.categories.map((c) => c.level).join(", ");
    throw new ToolError(`${type.display_name_en} has no level ${choice.level}. Levels: ${levels}. Use get_tariff.`);
  }
  if (date < version.effective_date || date > version.valid_through) {
    throw new ToolError(
      `Tidex has ${type.display_name_en} rates from ${version.effective_date} to ${version.valid_through}, not for ${date}. ` +
        "Use custom pay for that date.",
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
 * else the one in effect on `date`, else null for a new job's base pay. What `settings`
 * leaves out comes from `base`, as the app's editor pre-fills from it, else from the app's
 * new-job defaults.
 */
export function snapshotFields(settings: PaySettings, base: StoredSnapshot | null, on: { date: string; currency: string }): SnapshotFields {
  const { pay, tax, breaks } = settings;

  let payFields: Pick<SnapshotFields, "hourly_wage" | "wage_level" | "tariff_type_id" | "supplements" | "overtime">;
  if (pay?.type === "tariff") {
    if (on.currency !== "kr") throw new ToolError("Tariff pay needs a job paid in kr. Use custom pay for this job.");
    payFields = tariffPay(pay, on.date);
  } else if (pay?.type === "custom") {
    const keep = isCustom(base);
    const overtime = pay.overtime;
    payFields = {
      hourly_wage: pay.hourly_wage,
      supplements: pay.supplements !== undefined ? { rules: pay.supplements } : keep ? clone(base!.supplements as SnapshotFields["supplements"]) : { rules: [] },
      overtime:
        overtime === undefined
          ? keep ? clone(base!.overtime as OvertimeConfig) : OVERTIME_OFF
          : overtime.enabled ? seededOvertime(overtime.weekly_threshold_hours) : OVERTIME_OFF,
    };
  } else {
    if (base === null) throw new ToolError("pay is required: give a tariff level or a custom hourly wage.");
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
  if (taxEnabled && taxPercentage === undefined) throw new ToolError("tax.percentage is required when tax is on.");

  // OnboardingData.usesSimpleSetup: a new job paid in another currency than kr gets no break deduction.
  const breakEnabled = breaks?.enabled ?? base?.break_enabled ?? on.currency === "kr";
  const storedMethod = base?.break_method === "none" ? undefined : base?.break_method;

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
export function snapshotInEffect<S extends { from_date?: string }>(snapshots: S[], date: string): S | null {
  const dated = snapshots.filter((s) => s.from_date !== undefined && s.from_date <= date);
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
  if (job.is_default) return "The default job can't be archived. Make another job the default with update_job first.";
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

export function jobView(
  job: {
    id: string;
    revision: number;
    name: string;
    color?: string;
    currency: string;
    is_default: boolean;
    archived_at?: string;
    payroll_day?: number;
    half_tax_month?: HalfTaxMonth;
    pay_period?: unknown;
  },
  paySetUp: boolean,
) {
  return {
    job_id: job.id,
    revision: job.revision,
    name: job.name,
    color: job.color ?? null,
    currency: job.currency,
    is_default: job.is_default,
    archived: job.archived_at !== undefined,
    pay_set_up: paySetUp,
    payroll_day: job.payroll_day ?? 15,
    half_tax_month: job.half_tax_month === undefined ? "none" : HALF_TAX_NAMES[job.half_tax_month],
    pay_period: payPeriodView(job.pay_period),
  };
}

function overtimeView(stored: unknown) {
  const o = stored as Partial<OvertimeConfig> | null | undefined;
  return o?.enabled === true ? { enabled: true, weekly_threshold_hours: o.weeklyThresholdHours ?? 40 } : { enabled: false };
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

/** A job's wage snapshots in plain terms, base pay first, then each dated change. */
export function payView(
  job: { id: string; name: string; currency: string },
  snapshots: (StoredSnapshot & { id: string; revision: number; from_date?: string })[],
) {
  const ordered = [...snapshots].sort((a, b) => (a.from_date ?? "").localeCompare(b.from_date ?? ""));
  const dates = ordered.flatMap((s) => (s.from_date === undefined ? [] : [s.from_date]));
  return {
    job_id: job.id,
    job_name: job.name,
    currency: job.currency,
    pay_set_up: ordered.some((s) => s.from_date === undefined),
    pay: ordered.map((s) => {
      const next = dates.find((d) => s.from_date === undefined || d > s.from_date);
      const rules = ((s.supplements as { rules?: SupplementRule[] } | null)?.rules ?? []) as SupplementRule[];
      const tariff = s.wage_level === undefined ? null : tariffLevelLabel(s.tariff_type_id, s.wage_level);
      return {
        snapshot_id: s.id,
        revision: s.revision,
        from_date: s.from_date ?? null,
        until_date: next === undefined ? null : next,
        pay:
          s.wage_level === undefined
            ? { type: "custom" }
            : { type: "tariff", tariff_type_id: s.tariff_type_id ?? null, level: s.wage_level, ...tariff },
        hourly_wage: s.hourly_wage,
        supplements: s.wage_level === undefined ? rules.map(supplementView) : `${rules.length} rules from the tariff`,
        overtime: overtimeView(s.overtime),
        tax: { enabled: s.tax_enabled ?? false, percentage: s.tax_enabled ? (s.tax_percentage ?? 0) : null },
        breaks: {
          enabled: (s.break_enabled ?? true) && s.break_method !== "none",
          method: s.break_method ?? "proportional",
          threshold_hours: s.break_threshold_hours ?? 5.5,
          deduction_minutes: s.break_deduction_minutes ?? 30,
        },
      };
    }),
  };
}

// ---------- Argument parsers ----------

function object(value: unknown, field: string): Args {
  if (typeof value !== "object" || value === null || Array.isArray(value)) throw new ToolError(`${field} must be an object.`);
  return value as Args;
}

function number(value: unknown, field: string, min: number, max: number, integer = false): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < min || value > max || (integer && !Number.isInteger(value))) {
    throw new ToolError(`${field} must be ${integer ? "a whole number" : "a number"} from ${min} to ${max}.`);
  }
  return value;
}

function positive(value: unknown, field: string, max: number): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value <= 0 || value > max) {
    throw new ToolError(`${field} must be a number above 0 and at most ${max}.`);
  }
  return value;
}

function boolean(value: unknown, field: string): boolean {
  if (typeof value !== "boolean") throw new ToolError(`${field} must be true or false.`);
  return value;
}

function oneOf<T extends string>(value: unknown, field: string, options: readonly T[]): T {
  if (!options.includes(value as T)) throw new ToolError(`${field} must be one of: ${options.join(", ")}.`);
  return value as T;
}

function requiredRevision(value: unknown, from: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) throw new ToolError(`revision is required. Get it from ${from}.`);
  return value;
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

const payrollDay = (value: unknown) => number(value, "payroll_day", 1, 31, true);

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
    const startDay = number(p.start_day, "pay_period.start_day", 1, 28, true);
    const payoutMonthOffset = number(p.payout_month_offset, "pay_period.payout_month_offset", 0, 1, true) as 0 | 1;
    // PayPeriod.calendarMonth: the app stores it as no value.
    return startDay === 1 && payoutMonthOffset === 1 ? null : { type, startDay, payoutMonthOffset };
  }
  allowOnly(p, ["type", "period_end", "payout_delay_days"]);
  return {
    type,
    anchorEnd: parseDate(p.period_end, "pay_period.period_end"),
    payoutDelayDays: number(p.payout_delay_days, "pay_period.payout_delay_days", 0, 27, true),
  };
}

/** A custom supplement as OnboardingSupplementRule.toSupplementRule saves it. */
export function parseSupplement(value: unknown, field: string): SupplementRule {
  const r = object(value, field);
  allowOnly(r, ["days", "from", "to", "amount", "percent"]);
  if (!Array.isArray(r.days) || r.days.length === 0) throw new ToolError(`${field}.days must list weekdays from 1 (Monday) to 7 (Sunday).`);
  const days = [...new Set(r.days.map((d) => number(d, `${field}.days`, 1, 7, true)))].sort((a, b) => a - b);
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

function parsePay(value: unknown): PayChoice {
  const p = object(value, "pay");
  const type = oneOf(p.type, "pay.type", ["tariff", "custom"] as const);
  if (type === "tariff") {
    allowOnly(p, ["type", "tariff_type_id", "level"]);
    return {
      type,
      tariff_type_id: requiredString(p.tariff_type_id, "pay.tariff_type_id"),
      level: number(p.level, "pay.level", -1000, 1000, true),
    };
  }
  allowOnly(p, ["type", "hourly_wage", "supplements", "overtime"]);
  const supplements = optional(p.supplements, (list) => {
    if (!Array.isArray(list) || list.length > MAX_SUPPLEMENT_RULES) {
      throw new ToolError(`pay.supplements must be a list of at most ${MAX_SUPPLEMENT_RULES} rules.`);
    }
    return list.map((rule, i) => parseSupplement(rule, `pay.supplements[${i}]`));
  });
  const overtime = optional(p.overtime, (v): OvertimeChoice => {
    const o = object(v, "pay.overtime");
    allowOnly(o, ["enabled", "weekly_threshold_hours"]);
    if (!boolean(o.enabled, "pay.overtime.enabled")) return { enabled: false };
    const hours = optional(o.weekly_threshold_hours, (h) => positive(h, "pay.overtime.weekly_threshold_hours", 168));
    return { enabled: true, weekly_threshold_hours: hours ?? 40 };
  });
  return {
    type,
    hourly_wage: positive(p.hourly_wage, "pay.hourly_wage", 1_000_000),
    ...(supplements === undefined ? {} : { supplements }),
    ...(overtime === undefined ? {} : { overtime }),
  };
}

function parseTax(value: unknown): TaxChoice {
  const t = object(value, "tax");
  allowOnly(t, ["enabled", "percentage"]);
  const percentage = optional(t.percentage, (v) => number(v, "tax.percentage", 0, 100));
  return { enabled: boolean(t.enabled, "tax.enabled"), ...(percentage === undefined ? {} : { percentage }) };
}

function parseBreaks(value: unknown): BreakChoice {
  const b = object(value, "breaks");
  allowOnly(b, ["enabled", "method", "threshold_hours", "deduction_minutes"]);
  const method = optional(b.method, (v) => oneOf(v, "breaks.method", BREAK_METHODS));
  const threshold = optional(b.threshold_hours, (v) => number(v, "breaks.threshold_hours", 1, 12));
  const minutes = optional(b.deduction_minutes, (v) => number(v, "breaks.deduction_minutes", 5, 120, true));
  return {
    enabled: boolean(b.enabled, "breaks.enabled"),
    ...(method === undefined ? {} : { method }),
    ...(threshold === undefined ? {} : { threshold_hours: threshold }),
    ...(minutes === undefined ? {} : { deduction_minutes: minutes }),
  };
}

function paySettings(args: Args): PaySettings {
  const pay = optional(args.pay, parsePay);
  const tax = optional(args.tax, parseTax);
  const breaks = optional(args.breaks, parseBreaks);
  return { ...(pay && { pay }), ...(tax && { tax }), ...(breaks && { breaks }) };
}

// ---------- Tool definitions ----------

const readOnly = { readOnlyHint: true, openWorldHint: false };
const jobId = { type: "string", description: "A job_id from list_jobs" };
const jobRevision = {
  type: "number",
  description: "The job's revision from list_jobs. A change made since then makes the call fail; list the jobs again.",
};
const date = { type: "string", format: "date", description: "YYYY-MM-DD" };
const time = { type: "string", pattern: "^(([01][0-9]|2[0-3]):[0-5][0-9]|24:00)$", description: "HH:mm, 24-hour clock" };

const payPeriodSchema = {
  type: "object",
  description:
    "How workdays group into paydays. calendar_month: the 1st to the last day, paid the month after. " +
    "monthly: a month starting on start_day (1-28), paid in the month the period ends (payout_month_offset 0) or the month after (1). " +
    "biweekly: 14-day periods, one of which ends on period_end, paid payout_delay_days (0-27) after each period ends.",
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
const payrollDaySchema = { type: "integer", minimum: 1, maximum: 31, description: "Day of the month pay arrives, for monthly pay periods." };
const halfTaxSchema = {
  type: "string",
  enum: ["none", "november", "december"],
  description: "The month with half tax (Norwegian halv skatt), or none.",
};
const colorSchema = { type: "string", enum: JOB_COLORS, description: "The job's color in the app." };

const supplementSchema = {
  type: "object",
  description: "Extra pay for hours worked in a time window. Give amount or percent, not both. A window with to before from runs past midnight.",
  properties: {
    days: { type: "array", items: { type: "integer", minimum: 1, maximum: 7 }, description: "Weekdays, 1 = Monday to 7 = Sunday" },
    from: time,
    to: time,
    amount: { type: "number", description: "Added per hour, in the job's currency" },
    percent: { type: "number", description: "Percent of the hourly wage added per hour" },
  },
  required: ["days", "from", "to"],
  additionalProperties: false,
};
const paySchema = {
  type: "object",
  description:
    "tariff: a level of a Norwegian collective agreement from list_tariffs and get_tariff, with its supplements and overtime rules, in kr. " +
    "custom: the user's own hourly_wage with optional supplements and overtime. " +
    "Overtime on uses the app's standard rules (50% before 21:00 on weekdays, 100% after, on Sundays and on holidays) above weekly_threshold_hours (default 40).",
  properties: {
    type: { type: "string", enum: ["tariff", "custom"] },
    tariff_type_id: { type: "string" },
    level: { type: "integer" },
    hourly_wage: { type: "number", exclusiveMinimum: 0 },
    supplements: { type: "array", items: supplementSchema, maxItems: MAX_SUPPLEMENT_RULES },
    overtime: {
      type: "object",
      properties: { enabled: { type: "boolean" }, weekly_threshold_hours: { type: "number", exclusiveMinimum: 0, maximum: 168 } },
      required: ["enabled"],
      additionalProperties: false,
    },
  },
  required: ["type"],
  additionalProperties: false,
};
const taxSchema = {
  type: "object",
  description: "The tax percentage the app deducts to estimate net pay.",
  properties: { enabled: { type: "boolean" }, percentage: { type: "number", minimum: 0, maximum: 100 } },
  required: ["enabled"],
  additionalProperties: false,
};
const breaksSchema = {
  type: "object",
  description:
    "An unpaid break deducted from shifts longer than threshold_hours. method: proportional spreads it over the shift, " +
    "base_only takes it from hours without supplements first, end_of_shift from the shift's end.",
  properties: {
    enabled: { type: "boolean" },
    method: { type: "string", enum: BREAK_METHODS },
    threshold_hours: { type: "number", minimum: 1, maximum: 12 },
    deduction_minutes: { type: "integer", minimum: 5, maximum: 120 },
  },
  required: ["enabled"],
  additionalProperties: false,
};

export const listJobs = {
  definition: {
    name: "list_jobs",
    title: "List jobs",
    description:
      "The user's jobs with their currency, color, pay period, payday and whether pay is set up. " +
      "Each has a revision for update_job. Archived jobs are left out unless include_archived is true.",
    inputSchema: {
      type: "object",
      properties: { include_archived: { type: "boolean" } },
      additionalProperties: false,
    },
    annotations: { title: "List jobs", ...readOnly },
  },
  scope: "read",
  parse: (args) => {
    allowOnly(args, ["include_archived"]);
    return { include_archived: optional(args.include_archived, (v) => boolean(v, "include_archived")) ?? false };
  },
} satisfies ToolSpec;

export const addJob = {
  definition: {
    name: "add_job",
    title: "Add job",
    description:
      "Adds a job with its base pay, as adding a job in the app does. The first active job becomes the default. " +
      "currency defaults to the default job's currency, else kr; tariff pay is always in kr. " +
      "Without tax the app shows gross pay as net; without breaks a 30-minute break is deducted from shifts over 5.5 hours in kr jobs. " +
      "An active job with the same name is returned unchanged instead of a copy.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", minLength: 1, maxLength: 100 },
        color: colorSchema,
        currency: { type: "string", enum: CURRENCIES },
        payroll_day: payrollDaySchema,
        half_tax_month: halfTaxSchema,
        pay_period: payPeriodSchema,
        pay: paySchema,
        tax: taxSchema,
        breaks: breaksSchema,
      },
      required: ["name", "pay"],
      additionalProperties: false,
    },
    annotations: { title: "Add job", readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["name", "color", "currency", "payroll_day", "half_tax_month", "pay_period", "pay", "tax", "breaks"]);
    const settings = paySettings(args);
    if (settings.pay === undefined) throw new ToolError("pay is required: give a tariff level or a custom hourly wage.");
    const chosenCurrency = optional(args.currency, currency);
    if (settings.pay.type === "tariff" && chosenCurrency !== undefined && chosenCurrency !== "kr") {
      throw new ToolError("Tariff pay is in kr. Leave out currency or use custom pay.");
    }
    const halfTax = optional(args.half_tax_month, halfTaxMonth);
    const payPeriod = optional(args.pay_period, parsePayPeriod);
    return {
      name: jobName(args.name),
      color: optional(args.color, jobColor) ?? DEFAULT_COLOR,
      currency: settings.pay.type === "tariff" ? "kr" : chosenCurrency,
      payroll_day: optional(args.payroll_day, payrollDay) ?? 15,
      ...(halfTax ? { half_tax_month: halfTax } : {}),
      ...(payPeriod ? { pay_period: payPeriod } : {}),
      settings,
      today: today(),
    };
  },
} satisfies ToolSpec;

export const updateJob = {
  definition: {
    name: "update_job",
    title: "Change job",
    description:
      "Changes a job's name, color, payday, half-tax month or pay period, makes it the default job, or archives or restores it. " +
      "Give only what changes. Archiving hides the job from new shifts and keeps its history; the default job and the only active job can't be archived. " +
      "The currency can't change.",
    inputSchema: {
      type: "object",
      properties: {
        job_id: jobId,
        revision: jobRevision,
        name: { type: "string", minLength: 1, maxLength: 100 },
        color: colorSchema,
        payroll_day: payrollDaySchema,
        half_tax_month: halfTaxSchema,
        pay_period: payPeriodSchema,
        make_default: { type: "boolean", enum: [true], description: "true makes this the default job." },
        archived: { type: "boolean", description: "true archives the job, false restores it." },
      },
      required: ["job_id", "revision"],
      additionalProperties: false,
    },
    annotations: { title: "Change job", readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["job_id", "revision", "name", "color", "payroll_day", "half_tax_month", "pay_period", "make_default", "archived"]);
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
    return { job_id: requiredString(args.job_id, "job_id"), revision: requiredRevision(args.revision, "list_jobs"), ...changes };
  },
} satisfies ToolSpec;

export const deleteJob = {
  definition: {
    name: "delete_job",
    title: "Delete job",
    description:
      "Deletes an archived job with all its shifts, recurring shifts, pay settings and payroll adjustments. It can't be undone. " +
      "Call it first without confirmation_token: it deletes nothing and returns what would be deleted and a token. " +
      "Show that to the user, and call again with the token only after they confirm. Archive the job with update_job first.",
    inputSchema: {
      type: "object",
      properties: { job_id: jobId, confirmation_token: { type: "string", description: "The token from the first call" } },
      required: ["job_id"],
      additionalProperties: false,
    },
    annotations: { title: "Delete job", readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["job_id", "confirmation_token"]);
    const token = optionalString(args.confirmation_token, "confirmation_token");
    return { job_id: requiredString(args.job_id, "job_id"), ...(token ? { confirmation_token: token } : {}) };
  },
} satisfies ToolSpec;

export const listTariffsSpec = {
  definition: {
    name: "list_tariffs",
    title: "List tariffs",
    description:
      "The Norwegian collective agreements and statutory minimum wages Tidex can calculate, grouped by agreement. " +
      "An agreement with several variants lists the choices (such as week length or work arrangement) that pick each tariff_type_id. " +
      "search filters by name in English or Norwegian.",
    inputSchema: { type: "object", properties: { search: { type: "string", maxLength: 100 } }, additionalProperties: false },
    annotations: { title: "List tariffs", ...readOnly },
  },
  scope: "read",
  parse: (args) => {
    allowOnly(args, ["search"]);
    return { search: optionalString(args.search, "search") };
  },
} satisfies ToolSpec;

export const getTariffSpec = {
  definition: {
    name: "get_tariff",
    title: "Get tariff",
    description: "A tariff's levels with the hourly wage of each, the dates its rates cover, what it includes, and its overtime rule. Pass a level to set_pay.",
    inputSchema: {
      type: "object",
      properties: { tariff_type_id: { type: "string", description: "A tariff_type_id from list_tariffs" } },
      required: ["tariff_type_id"],
      additionalProperties: false,
    },
    annotations: { title: "Get tariff", ...readOnly },
  },
  scope: "read",
  parse: (args) => {
    allowOnly(args, ["tariff_type_id"]);
    return { tariff_type_id: requiredString(args.tariff_type_id, "tariff_type_id") };
  },
} satisfies ToolSpec;

export const getPay = {
  definition: {
    name: "get_pay",
    title: "Get pay",
    description:
      "A job's pay settings: the base pay, then each dated change. Each applies from its from_date until the next one; " +
      "the base pay applies before the first dated change. Each has a snapshot_id and revision for set_pay and delete_pay_change.",
    inputSchema: { type: "object", properties: { job_id: jobId }, required: ["job_id"], additionalProperties: false },
    annotations: { title: "Get pay", ...readOnly },
  },
  scope: "read",
  parse: (args) => {
    allowOnly(args, ["job_id"]);
    return { job_id: requiredString(args.job_id, "job_id") };
  },
} satisfies ToolSpec;

export const setPay = {
  definition: {
    name: "set_pay",
    title: "Set pay",
    description:
      "Sets a job's pay. Without from_date it changes the base pay; with from_date it sets the pay from that date on, such as a raise, " +
      "and changes the pay already set for that date if there is one. Give only what changes: pay, tax and breaks left out are kept from the pay in effect on that date. " +
      "Changing pay that exists needs its revision from get_pay. Tariff pay uses the agreement's rates, supplements and overtime rules.",
    inputSchema: {
      type: "object",
      properties: {
        job_id: jobId,
        from_date: date,
        revision: { type: "number", description: "The revision from get_pay of the pay being changed" },
        pay: paySchema,
        tax: taxSchema,
        breaks: breaksSchema,
      },
      required: ["job_id"],
      additionalProperties: false,
    },
    annotations: { title: "Set pay", readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["job_id", "from_date", "revision", "pay", "tax", "breaks"]);
    const settings = paySettings(args);
    if (Object.keys(settings).length === 0) throw new ToolError("Give at least one of pay, tax or breaks.");
    const fromDate = optional(args.from_date, (v) => parseDate(v, "from_date"));
    const revision = optional(args.revision, (v) => requiredRevision(v, "get_pay"));
    return {
      job_id: requiredString(args.job_id, "job_id"),
      ...(fromDate ? { from_date: fromDate } : {}),
      ...(revision !== undefined ? { revision } : {}),
      settings,
      today: today(),
    };
  },
} satisfies ToolSpec;

export const deletePayChange = {
  definition: {
    name: "delete_pay_change",
    title: "Delete pay change",
    description: "Deletes a dated pay change, so the pay before it applies again. The base pay can't be deleted; change it with set_pay.",
    inputSchema: {
      type: "object",
      properties: { snapshot_id: { type: "string", description: "A snapshot_id from get_pay" }, revision: { type: "number" } },
      required: ["snapshot_id", "revision"],
      additionalProperties: false,
    },
    annotations: { title: "Delete pay change", readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false },
  },
  scope: "write",
  parse: (args) => {
    allowOnly(args, ["snapshot_id", "revision"]);
    return { snapshot_id: requiredString(args.snapshot_id, "snapshot_id"), revision: requiredRevision(args.revision, "get_pay") };
  },
} satisfies ToolSpec;
