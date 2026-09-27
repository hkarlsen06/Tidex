import type { User } from "@supabase/supabase-js";

import type { WageyRequestContext } from "./context.ts";
import {
  getCurrentYearMonth,
  getMonthEnd,
  getMonthStart,
  parseDateAsUTC,
} from "./date-utils.ts";
import { getUserTier } from "./get-user-tier.ts";
import {
  applyWeeklyOvertime,
  computeShift,
  type CustomPauseWindows,
  type CustomSupplementsData,
  type Job,
  normalizeCustomPauseWindows,
  PRESET_SUPPLEMENT_RULES,
  type ShiftRow,
  type ShiftWithComputations,
  type UserSettings,
  type WageSnapshot,
} from "./payroll/index.ts";
import {
  detectAllRecurringConflicts,
  type ExistingShift,
} from "./recurring/conflicts.ts";
import {
  generateVirtualShiftsForMonth,
  resolveEndWindow,
  toISODate,
} from "./recurring/utils.ts";
import { cleanTime } from "./time-utils.ts";
import {
  getCurrentMonth,
  getResetDate,
  type WageyAccessResult,
  type WageyInvocationResult,
} from "./wagey-types.ts";

export type ShiftLoadOptions = {
  startDate?: string;
  endDate?: string;
  limit?: number;
  jobId?: string;
};

export type EventLoadOptions = {
  startDate?: string;
  endDate?: string;
  limit?: number;
};

export type ShiftIdentityRow = {
  id: string;
  shift_date: string;
  start_time: string;
  end_time: string;
  job_id: string | null;
};

export type JobPaySetupStatusCode =
  | "configured"
  | "pay_setup_required"
  | "archived";

export type JobPaySetupStatus = {
  jobId: string;
  jobName: string;
  isActive: boolean;
  hasBaselineSnapshot: boolean;
  requiresPaySetup: boolean;
  paySetupStatus: JobPaySetupStatusCode;
};

export type JobDeleteDependencyCounts = {
  userShifts: number;
  recurringShifts: number;
  payrollAdjustments: number;
  total: number;
};

export type ShiftJobResolution =
  | { ok: true; job: Job; status: JobPaySetupStatus }
  | {
    ok: false;
    code: "job_not_available" | "job_pay_setup_required";
    job?: Job;
    status?: JobPaySetupStatus;
  };

export type EventRecord = {
  id: string;
  user_id: string;
  start_date: string;
  end_date: string;
  is_all_day: boolean;
  start_time: string | null;
  end_time: string | null;
  note: string;
  notification_minutes_array: number[] | null;
  notification_anchor_time: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  deleted_at?: string | null;
};

type SubscriptionRow = {
  id: string;
  user_id: string;
  provider: "stripe" | "apple" | "admin_trial";
  status: string;
  product_id: string | null;
  current_period_end: string | null;
  price_id: string | null;
};

type ProfileRow = {
  id: string;
  before_paywall: boolean;
  wagey_invocations?:
    | { count: number; month: string | null; bonus: number }
    | null;
};

type DbRecurringShift = {
  id: string;
  user_id: string;
  job_id?: string | null;
  start_time: string;
  end_time: string;
  repeat_interval_weeks: number;
  selected_days: Record<"0" | "1" | "2" | "3" | "4" | "5" | "6", string>;
  end_condition: unknown;
  exclusions: string[];
  date_specific_pause_windows?: Record<string, CustomPauseWindows> | null;
  date_specific_supplements?: Record<string, CustomSupplementsData> | null;
  date_specific_notes?: Record<string, string> | null;
  created_at?: string;
  deleted_at?: string | null;
};

type SnapshotBucket = {
  dated: Array<WageSnapshot & { from_date: string }>;
  baseline: WageSnapshot | null;
};

type ShiftResources = {
  settings: UserSettings;
  jobs: Job[];
  snapshots: WageSnapshot[];
  recurringShifts: DbRecurringShift[];
};

type WageyAccessContextRow = {
  before_paywall: boolean;
  wagey_invocations:
    | { count: number; month: string | null; bonus: number }
    | null;
  status: string | null;
  product_id: string | null;
  current_period_end: string | null;
  price_id: string | null;
  provider: SubscriptionRow["provider"] | null;
};

export type LoadedShiftData = {
  shifts: ShiftWithComputations[];
  settings: UserSettings;
  jobs: Job[];
  showEarnings?: boolean;
};

type FriendEntry = {
  id: string;
  email: string | null;
  phone: string | null;
  firstName: string | null;
  profilePictureUrl: string | null;
  oauthAvatarUrl: string | null;
  sharesWithMe: {
    blocked: boolean;
    showEarningsToMe: boolean;
    sharedAt: string;
    notificationFrequency: "instant" | "muted";
  } | null;
  iShareWith: {
    showEarningsToThem: boolean;
    sharedAt: string;
    ownerMuted: boolean;
  } | null;
};

type BootstrapFriendEntry = Omit<FriendEntry, "sharesWithMe"> & {
  sharesWithMe:
    | (Omit<NonNullable<FriendEntry["sharesWithMe"]>, "blocked"> & {
      blocked?: boolean;
      hidden?: boolean;
    })
    | null;
};

const LEGACY_SNAPSHOT_KEY = "__legacy__";
const WAGEY_LIMITS = {
  free: 3,
  pro: 40,
  max: 90,
} as const;
const FALLBACK_WAGEY_ACCESS: WageyAccessResult = {
  level: "free",
  hasAccess: false,
  limit: 0,
  used: 0,
  remaining: 0,
  bonus: 0,
  resetDate: null,
};
const FALLBACK_WAGEY_INVOCATION: WageyInvocationResult = {
  allowed: false,
  count: 0,
  remaining: 0,
  bonus: 0,
};

export class ShiftMonthLimitError extends Error {
  readonly code = "shift_month_limit_reached";

  constructor(
    readonly existingMonths: string[],
    readonly targetMonths: string[],
  ) {
    super("Free users can only add shifts within one month.");
    this.name = "ShiftMonthLimitError";
  }
}

export function isShiftMonthLimitError(
  error: unknown,
): error is ShiftMonthLimitError {
  return error instanceof ShiftMonthLimitError ||
    (
      typeof error === "object" &&
      error !== null &&
      "code" in error &&
      (error as { code?: unknown }).code === "shift_month_limit_reached"
    );
}

const COMPUTED_SETTINGS_SELECT =
  "user_id, half_tax_month, payroll_day, monthly_goal, monthly_goals_by_month, currency";
const COMPUTED_JOB_SELECT =
  "id, user_id, name, color, is_default, sort_order, payroll_day, half_tax_month, monthly_goal, archived_at, deleted_at, created_at";
const COMPUTED_SNAPSHOT_SELECT =
  "id, user_id, job_id, from_date, hourly_wage, wage_level, tariff_type_id, supplements, overtime, tax_enabled, tax_percentage, break_enabled, break_method, break_threshold_hours, break_deduction_minutes, created_at";
const COMPUTED_SHIFT_SELECT =
  "id, user_id, job_id, shift_date, start_time, end_time, custom_pause_windows, custom_supplements";
const COMPUTED_EVENT_SELECT =
  "id, user_id, start_date, end_date, is_all_day, start_time, end_time, note, notification_minutes_array, notification_anchor_time, created_at, updated_at, deleted_at";
const COMPUTED_RECURRING_SELECT =
  "id, user_id, job_id, start_time, end_time, repeat_interval_weeks, selected_days, end_condition, exclusions, date_specific_pause_windows, date_specific_supplements, date_specific_notes, created_at, deleted_at";
const FAR_FUTURE_DATE = "2100-12-31";

function buildCacheKey(
  scope: string,
  payload: Record<string, unknown>,
): string {
  return `${scope}:${JSON.stringify(payload)}`;
}

async function getCachedValue<T>(
  ctx: WageyRequestContext,
  key: string,
  loader: () => Promise<T>,
): Promise<T> {
  const cached = ctx.cache.get(key);
  if (cached) {
    return await (cached as Promise<T>);
  }

  const pending = loader().catch((error) => {
    ctx.cache.delete(key);
    throw error;
  });
  ctx.cache.set(key, pending as Promise<unknown>);
  return await pending;
}

function snapshotKeyForJob(jobId?: string | null): string {
  return jobId ?? LEGACY_SNAPSHOT_KEY;
}

export function buildSnapshotBuckets(
  snapshots: readonly WageSnapshot[],
): ReadonlyMap<string, SnapshotBucket> {
  const buckets = new Map<string, SnapshotBucket>();

  for (const snapshot of snapshots) {
    const key = snapshotKeyForJob(snapshot.job_id ?? null);
    const bucket = buckets.get(key) ?? { dated: [], baseline: null };

    if (snapshot.from_date === null) {
      bucket.baseline = snapshot;
    } else {
      bucket.dated.push(snapshot as WageSnapshot & { from_date: string });
    }

    buckets.set(key, bucket);
  }

  for (const bucket of buckets.values()) {
    bucket.dated.sort((a, b) => b.from_date.localeCompare(a.from_date));
  }

  return buckets;
}

export function resolveSnapshotForDate(
  buckets: ReadonlyMap<string, SnapshotBucket>,
  snapshots: readonly WageSnapshot[],
  date: string,
  jobId?: string | null,
): WageSnapshot | null {
  const preferredKeys = [snapshotKeyForJob(jobId), LEGACY_SNAPSHOT_KEY];

  for (const key of preferredKeys) {
    const bucket = buckets.get(key);
    if (!bucket) continue;
    const dated = bucket.dated.find((snapshot) => snapshot.from_date <= date);
    if (dated) return dated;
  }

  for (const key of preferredKeys) {
    const baseline = buckets.get(key)?.baseline ?? null;
    if (baseline) return baseline;
  }

  return snapshots.find((snapshot) => snapshot.from_date === null) ?? null;
}

function getDefaultStartDate(): string {
  const { year, month } = getCurrentYearMonth();
  return getMonthStart(year, month);
}

function getDefaultEndDate(): string {
  const { year, month } = getCurrentYearMonth();
  return getMonthEnd(year, month);
}

function monthKeyForDate(isoDate: string): string {
  return isoDate.slice(0, 7);
}

async function getExistingActiveShiftMonths(
  ctx: WageyRequestContext,
  userId: string,
): Promise<Set<string>> {
  const { data, error } = await ctx.supabase
    .from("user_shifts")
    .select("shift_date")
    .eq("user_id", userId)
    .is("deleted_at", null);
  if (error) throw new Error(error.message);

  return new Set(
    ((data ?? []) as Array<{ shift_date: string }>)
      .map((shift) => monthKeyForDate(shift.shift_date)),
  );
}

export async function assertCanMutateShiftMonths(
  ctx: WageyRequestContext,
  dates: string[],
): Promise<void> {
  const targetMonths = Array.from(
    new Set(dates.filter(Boolean).map(monthKeyForDate)),
  ).sort();
  if (targetMonths.length === 0) return;

  const { profile, subscription } = await getProfileAndSubscription(
    ctx,
    ctx.user.id,
  );
  if (getUserTier(subscription, profile) !== "free") return;

  const existingMonths = await getExistingActiveShiftMonths(ctx, ctx.user.id);
  const isAllowed = existingMonths.size === 0
    ? targetMonths.length === 1
    : targetMonths.every((month) => existingMonths.has(month));

  if (!isAllowed) {
    throw new ShiftMonthLimitError(
      Array.from(existingMonths).sort(),
      targetMonths,
    );
  }
}

export function calculatePayoutDate(
  earningsDate: string,
  payrollDay: number,
): string {
  const [earningsYear, earningsMonth] = earningsDate.split("-").map(Number);
  let payoutYear = earningsYear;
  let payoutMonth = earningsMonth + 1;
  if (payoutMonth > 12) {
    payoutMonth = 1;
    payoutYear += 1;
  }

  const daysInPayoutMonth = new Date(Date.UTC(payoutYear, payoutMonth, 0))
    .getUTCDate();
  const effectivePayrollDay = Math.min(payrollDay, daysInPayoutMonth);
  return `${payoutYear}-${String(payoutMonth).padStart(2, "0")}-${
    String(effectivePayrollDay).padStart(2, "0")
  }`;
}

export function resolveDefaultJob(jobs: readonly Job[]): Job | null {
  const normalizedJobs = jobs.filter((job) => job.deleted_at == null);
  return (
    normalizedJobs.find((job) => job.is_default && job.archived_at == null) ??
      normalizedJobs.find((job) => job.is_default) ??
      normalizedJobs[0] ??
      null
  );
}

function formatJobPaySetupStatus(
  job: Job,
  baselineJobIds: ReadonlySet<string>,
): JobPaySetupStatus {
  const isActive = job.deleted_at == null && job.archived_at == null;
  const hasBaselineSnapshot = baselineJobIds.has(job.id);
  const paySetupStatus: JobPaySetupStatusCode = !isActive
    ? "archived"
    : hasBaselineSnapshot
    ? "configured"
    : "pay_setup_required";

  return {
    jobId: job.id,
    jobName: job.name,
    isActive,
    hasBaselineSnapshot,
    requiresPaySetup: isActive && !hasBaselineSnapshot,
    paySetupStatus,
  };
}

export async function getJobPaySetupStatuses(
  ctx: WageyRequestContext,
  userId = ctx.user.id,
  jobs?: Job[],
): Promise<Map<string, JobPaySetupStatus>> {
  const [resolvedJobs, baselineSnapshots] = await Promise.all([
    jobs
      ? Promise.resolve(jobs)
      : getUserJobs(ctx, userId, { includeArchived: true }),
    (async () => {
      const { data, error } = await ctx.supabase
        .from("wage_snapshots")
        .select("id, job_id")
        .eq("user_id", userId)
        .is("deleted_at", null)
        .is("from_date", null);

      if (error) throw new Error(error.message);
      return data ?? [];
    })(),
  ]);

  const baselineJobIds = new Set(
    baselineSnapshots
      .map((snapshot) => (snapshot as { job_id?: string | null }).job_id)
      .filter((jobId): jobId is string => typeof jobId === "string"),
  );

  return new Map(
    resolvedJobs.map((job) => [
      job.id,
      formatJobPaySetupStatus(job, baselineJobIds),
    ]),
  );
}

export async function resolveShiftJobForMutation(
  ctx: WageyRequestContext,
  userId = ctx.user.id,
  requestedJobId?: string | null,
): Promise<ShiftJobResolution> {
  const jobs = await getUserJobs(ctx, userId, { includeArchived: false });
  const job = requestedJobId
    ? jobs.find((candidate) => candidate.id === requestedJobId) ?? null
    : resolveDefaultJob(jobs);

  if (!job) {
    return { ok: false, code: "job_not_available" };
  }

  const statuses = await getJobPaySetupStatuses(ctx, userId, jobs);
  const status = statuses.get(job.id) ??
    formatJobPaySetupStatus(job, new Set());

  if (!status.hasBaselineSnapshot) {
    return {
      ok: false,
      code: "job_pay_setup_required",
      job,
      status,
    };
  }

  return { ok: true, job, status };
}

export function payrollDayForJob(
  jobsById: ReadonlyMap<string, Job>,
  defaultJob: Job | null,
  settings: UserSettings,
  jobId?: string | null,
): number {
  return jobsById.get(jobId ?? "")?.payroll_day ?? defaultJob?.payroll_day ??
    settings.payroll_day ?? 1;
}

export function halfTaxMonthForJob(
  jobsById: ReadonlyMap<string, Job>,
  defaultJob: Job | null,
  settings: UserSettings,
  jobId?: string | null,
): number | null {
  return jobsById.get(jobId ?? "")?.half_tax_month ??
    defaultJob?.half_tax_month ?? settings.half_tax_month ?? null;
}

function timeToMinutes(time: string): number {
  const [hours, minutes] = cleanTime(time).split(":").map(Number);
  return hours * 60 + minutes;
}

function toShortId(id: string): string {
  return id.slice(0, 5);
}

function toDisplayShiftId(shiftId: string): string {
  if (shiftId.startsWith("virtual-")) {
    const match = shiftId.match(
      /^virtual-([a-f0-9-]{4,36})-(\d{4}-\d{2}-\d{2})$/i,
    );
    if (match) {
      return `virtual-${toShortId(match[1])}-${match[2]}`;
    }
  }
  return toShortId(shiftId);
}

function calculateNetPay(
  gross: number,
  taxSettings: { tax_enabled?: boolean; tax_percentage?: number },
  halfTaxMonth: number | null | undefined,
  shiftDate: string,
): number {
  if (!taxSettings.tax_enabled || !taxSettings.tax_percentage) {
    return gross;
  }

  let taxRate = taxSettings.tax_percentage / 100;
  if (halfTaxMonth) {
    const shiftMonth = parseDateAsUTC(shiftDate).getUTCMonth() + 1;
    const payoutMonth = shiftMonth === 12 ? 1 : shiftMonth + 1;
    if (payoutMonth === halfTaxMonth) {
      taxRate = taxRate / 2;
    }
  }

  return gross - gross * taxRate;
}

async function getProfileAndSubscription(
  ctx: WageyRequestContext,
  userId: string,
): Promise<
  { profile: ProfileRow | null; subscription: SubscriptionRow | null }
> {
  return await getCachedValue(
    ctx,
    buildCacheKey("wagey_access_context", { userId }),
    async () => {
      const { data, error } = await ctx.supabaseAdmin.rpc(
        "get_wagey_access_context",
        {
          p_user_id: userId,
        },
      );
      if (error) throw new Error(error.message);

      const row = (Array.isArray(data) ? data[0] : data) as
        | WageyAccessContextRow
        | null;
      if (!row) {
        return { profile: null, subscription: null };
      }

      return {
        profile: {
          id: userId,
          before_paywall: Boolean(row.before_paywall),
          wagey_invocations: row.wagey_invocations ?? null,
        },
        subscription: row.status
          ? {
            id: `subscription:${userId}`,
            user_id: userId,
            provider: row.provider ?? "stripe",
            status: row.status,
            product_id: row.product_id,
            current_period_end: row.current_period_end,
            price_id: row.price_id,
          }
          : null,
      };
    },
  );
}

export async function getWageyAccess(
  ctx: WageyRequestContext,
): Promise<WageyAccessResult> {
  const userId = ctx.user.id;

  try {
    const { profile, subscription } = await getProfileAndSubscription(
      ctx,
      userId,
    );
    const level = getUserTier(subscription, profile);
    const limit = WAGEY_LIMITS[level];
    const hasAccess = level !== "free";
    const currentMonth = getCurrentMonth();
    const invocations = profile?.wagey_invocations;
    const used = invocations?.month === currentMonth ? invocations.count : 0;
    const bonus = Math.max(0, invocations?.bonus ?? 0);
    const remaining = Math.max(0, limit - used);

    return {
      level,
      hasAccess,
      limit,
      used,
      remaining,
      bonus,
      resetDate: getResetDate(),
    };
  } catch (error) {
    console.error(JSON.stringify({
      scope: "wagey-data",
      userId,
      message: "Falling back after getWageyAccess failure",
      error: error instanceof Error ? error.message : String(error),
    }));

    return FALLBACK_WAGEY_ACCESS;
  }
}

export async function consumeWageyInvocation(
  ctx: WageyRequestContext,
  limit: number,
): Promise<WageyInvocationResult> {
  const userId = ctx.user.id;

  try {
    const { data, error } = await ctx.supabaseAdmin.rpc(
      "increment_wagey_invocation",
      {
        p_user_id: userId,
        p_current_month: getCurrentMonth(),
        p_max_invocations: limit,
      },
    );

    if (error || !data) {
      throw new Error(error?.message ?? "Failed to consume Wagey invocation");
    }

    return data as WageyInvocationResult;
  } catch (error) {
    console.error(JSON.stringify({
      scope: "wagey-data",
      userId,
      message: "Falling back after consumeWageyInvocation failure",
      error: error instanceof Error ? error.message : String(error),
    }));

    return FALLBACK_WAGEY_INVOCATION;
  }
}

export async function getUserSettings(
  ctx: WageyRequestContext,
  userId = ctx.user.id,
): Promise<UserSettings> {
  return await getCachedValue(
    ctx,
    buildCacheKey("user_settings", { userId }),
    async () => {
      const { data } = await ctx.supabase
        .from("user_settings")
        .select("*")
        .eq("user_id", userId)
        .maybeSingle();
      return (data ?? {}) as UserSettings;
    },
  );
}

export async function getUserCurrency(
  ctx: WageyRequestContext,
  userId = ctx.user.id,
): Promise<string> {
  const settings = await getUserSettings(ctx, userId);
  return settings.currency || "NOK";
}

export async function getUserJobs(
  ctx: WageyRequestContext,
  userId = ctx.user.id,
  options?: { includeArchived?: boolean },
): Promise<Job[]> {
  return await getCachedValue(
    ctx,
    buildCacheKey("user_jobs", {
      userId,
      includeArchived: options?.includeArchived ?? false,
    }),
    async () => {
      let query = ctx.supabase
        .from("jobs")
        .select("*")
        .eq("user_id", userId)
        .is("deleted_at", null)
        .order("sort_order", { ascending: true })
        .order("created_at", { ascending: true });

      if (!options?.includeArchived) {
        query = query.is("archived_at", null);
      }

      const { data, error } = await query;
      if (error) throw new Error(error.message);
      return (data ?? []) as Job[];
    },
  );
}

async function getWageSnapshots(
  ctx: WageyRequestContext,
  userId = ctx.user.id,
  jobId?: string,
): Promise<WageSnapshot[]> {
  return await getCachedValue(
    ctx,
    buildCacheKey("wage_snapshots", { userId, jobId: jobId ?? null }),
    async () => {
      let query = ctx.supabase
        .from("wage_snapshots")
        .select("*")
        .eq("user_id", userId)
        .is("deleted_at", null)
        .order("from_date", { ascending: false, nullsFirst: false });

      if (jobId) {
        query = query.eq("job_id", jobId);
      }

      const { data, error } = await query;
      if (error) throw new Error(error.message);
      return (data ?? []) as WageSnapshot[];
    },
  );
}

async function getRawUserShifts(
  ctx: WageyRequestContext,
  userId: string,
  options: ShiftLoadOptions = {},
): Promise<ShiftIdentityRow[]> {
  let query = ctx.supabase
    .from("user_shifts")
    .select("id, shift_date, start_time, end_time, job_id")
    .eq("user_id", userId)
    .is("deleted_at", null)
    .order("shift_date", { ascending: false });

  if (options.jobId) query = query.eq("job_id", options.jobId);
  if (options.startDate) query = query.gte("shift_date", options.startDate);
  if (options.endDate) query = query.lte("shift_date", options.endDate);
  if (options.limit) query = query.limit(options.limit);

  const { data, error } = await query;
  if (error) throw new Error(error.message);
  return (data ?? []) as ShiftIdentityRow[];
}

async function getRawUserEvents(
  ctx: WageyRequestContext,
  userId: string,
  options: EventLoadOptions = {},
): Promise<EventRecord[]> {
  return await getCachedValue(
    ctx,
    buildCacheKey("user_events", {
      userId,
      startDate: options.startDate ?? null,
      endDate: options.endDate ?? null,
      limit: options.limit ?? null,
    }),
    async () => {
      let query = ctx.supabase
        .from("events")
        .select(COMPUTED_EVENT_SELECT)
        .eq("user_id", userId)
        .is("deleted_at", null)
        .order("start_date", { ascending: true })
        .order("end_date", { ascending: true })
        .order("start_time", { ascending: true, nullsFirst: true });

      if (options.startDate) {
        query = query.gte("end_date", options.startDate);
      }
      if (options.endDate) {
        query = query.lte("start_date", options.endDate);
      }
      if (options.limit) {
        query = query.limit(options.limit);
      }

      const { data, error } = await query;
      if (error) throw new Error(error.message);
      return (data ?? []) as EventRecord[];
    },
  );
}

export async function getUserEventById(
  ctx: WageyRequestContext,
  eventId: string,
  userId = ctx.user.id,
): Promise<EventRecord | null> {
  const { data, error } = await ctx.supabase
    .from("events")
    .select(COMPUTED_EVENT_SELECT)
    .eq("id", eventId)
    .eq("user_id", userId)
    .is("deleted_at", null)
    .maybeSingle();

  if (error) throw new Error(error.message);
  return (data as EventRecord | null) ?? null;
}

async function getRawRecurringShifts(
  client:
    | WageyRequestContext["supabase"]
    | WageyRequestContext["supabaseAdmin"],
  userId: string,
  jobId?: string,
): Promise<DbRecurringShift[]> {
  let query = client
    .from("recurring_shifts")
    .select("*")
    .eq("user_id", userId)
    .is("deleted_at", null);

  if (jobId) query = query.eq("job_id", jobId);

  const { data, error } = await query;
  if (error) throw new Error(error.message);
  return (data ?? []) as DbRecurringShift[];
}

async function getDefaultJobIdForUser(
  ctx: WageyRequestContext,
  userId: string,
): Promise<string | null> {
  return await getCachedValue(
    ctx,
    buildCacheKey("default_job_id", { userId }),
    async () => {
      const { data, error } = await ctx.supabase
        .from("jobs")
        .select(COMPUTED_JOB_SELECT)
        .eq("user_id", userId)
        .is("deleted_at", null)
        .order("sort_order", { ascending: true })
        .order("created_at", { ascending: true });
      if (error) throw new Error(error.message);
      return resolveDefaultJob((data ?? []) as Job[])?.id ?? null;
    },
  );
}

async function loadShiftResources(
  ctx: WageyRequestContext,
  userId: string,
  options: { jobId?: string; asAdmin?: boolean } = {},
): Promise<ShiftResources> {
  const asAdmin = options.asAdmin ?? false;
  const client = asAdmin ? ctx.supabaseAdmin : ctx.supabase;

  return await getCachedValue(
    ctx,
    buildCacheKey("shift_resources", {
      userId,
      jobId: options.jobId ?? null,
      asAdmin,
    }),
    async () => {
      const [settings, jobs, snapshots, recurringShifts] = await Promise.all([
        (async () => {
          const { data, error } = await client
            .from("user_settings")
            .select(COMPUTED_SETTINGS_SELECT)
            .eq("user_id", userId)
            .maybeSingle();
          if (error) throw new Error(error.message);
          return (data ?? {}) as UserSettings;
        })(),
        (async () => {
          let query = client
            .from("jobs")
            .select(COMPUTED_JOB_SELECT)
            .eq("user_id", userId)
            .is("deleted_at", null)
            .order("sort_order", { ascending: true })
            .order("created_at", { ascending: true });
          const { data, error } = await query;
          if (error) throw new Error(error.message);
          return (data ?? []) as Job[];
        })(),
        (async () => {
          let query = client
            .from("wage_snapshots")
            .select(COMPUTED_SNAPSHOT_SELECT)
            .eq("user_id", userId)
            .is("deleted_at", null)
            .order("from_date", { ascending: false, nullsFirst: false });
          if (options.jobId) {
            query = query.eq("job_id", options.jobId);
          }
          const { data, error } = await query;
          if (error) throw new Error(error.message);
          return (data ?? []) as WageSnapshot[];
        })(),
        (async () => {
          let query = client
            .from("recurring_shifts")
            .select(COMPUTED_RECURRING_SELECT)
            .eq("user_id", userId)
            .is("deleted_at", null);
          if (options.jobId) {
            query = query.eq("job_id", options.jobId);
          }
          const { data, error } = await query;
          if (error) throw new Error(error.message);
          return (data ?? []) as DbRecurringShift[];
        })(),
      ]);

      return { settings, jobs, snapshots, recurringShifts };
    },
  );
}

async function loadShiftRows(
  ctx: WageyRequestContext,
  userId: string,
  options: ShiftLoadOptions & { asAdmin?: boolean } = {},
): Promise<ShiftRow[]> {
  const asAdmin = options.asAdmin ?? false;
  const client = asAdmin ? ctx.supabaseAdmin : ctx.supabase;

  return await getCachedValue(
    ctx,
    buildCacheKey("shift_rows", {
      userId,
      startDate: options.startDate ?? null,
      endDate: options.endDate ?? null,
      limit: options.limit ?? null,
      jobId: options.jobId ?? null,
      asAdmin,
    }),
    async () => {
      let query = client
        .from("user_shifts")
        .select(COMPUTED_SHIFT_SELECT)
        .eq("user_id", userId)
        .is("deleted_at", null)
        .gte("shift_date", options.startDate ?? getDefaultStartDate())
        .lte("shift_date", options.endDate ?? getDefaultEndDate())
        .order("shift_date", { ascending: false });
      if (options.jobId) query = query.eq("job_id", options.jobId);
      if (options.limit) query = query.limit(options.limit);
      const { data, error } = await query;
      if (error) throw new Error(error.message);
      return (data ?? []) as ShiftRow[];
    },
  );
}

function buildComputedShiftData(params: {
  userId: string;
  settings: UserSettings;
  jobs: Job[];
  snapshots: WageSnapshot[];
  shifts: ShiftRow[];
  recurringShifts: DbRecurringShift[];
  startDate: string;
  endDate: string;
  returnStartDate?: string;
  returnEndDate?: string;
}): LoadedShiftData {
  const {
    userId,
    settings,
    jobs,
    snapshots,
    shifts,
    recurringShifts,
    startDate,
    endDate,
    returnStartDate = startDate,
    returnEndDate = endDate,
  } = params;
  const normalizedJobs = jobs.filter((job) => job.deleted_at == null);
  const jobsById = new Map(normalizedJobs.map((job) => [job.id, job] as const));
  const defaultJob = resolveDefaultJob(normalizedJobs);
  const defaultJobId = defaultJob?.id ?? null;
  const buckets = buildSnapshotBuckets(snapshots);
  const resolvePayrollDay = (jobId?: string | null): number =>
    payrollDayForJob(jobsById, defaultJob, settings, jobId);
  const snapshotsByComputedShiftId = new Map<string, WageSnapshot | null>();

  const computedStandalone: ShiftWithComputations[] = shifts.map((shift) => {
    const shiftJobId = shift.job_id ?? defaultJobId;
    const snapshot = resolveSnapshotForDate(
      buckets,
      snapshots,
      shift.shift_date,
      shiftJobId,
    );
    const payoutSnapshot = resolveSnapshotForDate(
      buckets,
      snapshots,
      calculatePayoutDate(shift.shift_date, resolvePayrollDay(shiftJobId)),
      shiftJobId,
    );
    snapshotsByComputedShiftId.set(shift.id, snapshot);

    return {
      ...shift,
      job_id: shiftJobId,
      supplement_rules_snapshot: snapshot?.supplements ?? null,
      computed: computeShift(
        shift,
        settings,
        PRESET_SUPPLEMENT_RULES,
        snapshot,
        shiftJobId ? jobsById.get(shiftJobId) ?? null : null,
      ),
      tax_enabled: payoutSnapshot?.tax_enabled ?? false,
      tax_percentage: payoutSnapshot?.tax_percentage ?? 0,
    };
  });

  const start = parseDateAsUTC(startDate);
  const end = parseDateAsUTC(endDate);
  const virtuals: ShiftWithComputations[] = [];

  for (const recurring of recurringShifts) {
    let currentYear = start.getUTCFullYear();
    let currentMonth = start.getUTCMonth() + 1;

    while (
      currentYear < end.getUTCFullYear() ||
      (currentYear === end.getUTCFullYear() &&
        currentMonth <= end.getUTCMonth() + 1)
    ) {
      const generated = generateVirtualShiftsForMonth(
        { year: currentYear, month: currentMonth },
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
          exclusions: recurring.exclusions || [],
        },
      );

      for (const generatedShift of generated) {
        if (generatedShift.date < startDate || generatedShift.date > endDate) {
          continue;
        }

        const jobId = recurring.job_id ?? defaultJobId;
        const snapshot = resolveSnapshotForDate(
          buckets,
          snapshots,
          generatedShift.date,
          jobId,
        );
        const payoutSnapshot = resolveSnapshotForDate(
          buckets,
          snapshots,
          calculatePayoutDate(generatedShift.date, resolvePayrollDay(jobId)),
          jobId,
        );
        const syntheticShift: ShiftRow = {
          id: `virtual-${recurring.id}-${generatedShift.date}`,
          user_id: userId,
          job_id: jobId,
          shift_date: generatedShift.date,
          start_time: cleanTime(recurring.start_time),
          end_time: cleanTime(recurring.end_time),
          custom_pause_windows:
            recurring.date_specific_pause_windows?.[generatedShift.date] ??
              null,
          custom_supplements:
            recurring.date_specific_supplements?.[generatedShift.date] ?? null,
          recurring_id: recurring.id,
          recurring_anchor_weekday: generatedShift.weekday,
        };
        snapshotsByComputedShiftId.set(syntheticShift.id, snapshot);

        virtuals.push({
          ...syntheticShift,
          supplement_rules_snapshot: snapshot?.supplements ?? null,
          computed: computeShift(
            syntheticShift,
            settings,
            PRESET_SUPPLEMENT_RULES,
            snapshot,
            jobId ? jobsById.get(jobId) ?? null : null,
          ),
          tax_enabled: payoutSnapshot?.tax_enabled ?? false,
          tax_percentage: payoutSnapshot?.tax_percentage ?? 0,
        });
      }

      currentMonth += 1;
      if (currentMonth > 12) {
        currentMonth = 1;
        currentYear += 1;
      }
    }
  }

  const computed = applyWeeklyOvertime(
    [...computedStandalone, ...virtuals],
    {
      snapshotForShift: (shift) =>
        snapshotsByComputedShiftId.get(shift.id) ?? null,
      effectiveJobIdForShift: (shift) => shift.job_id ?? defaultJobId,
    },
  );

  return {
    shifts: computed.filter((shift) =>
      shift.shift_date >= returnStartDate && shift.shift_date <= returnEndDate
    ).sort((a, b) => {
      const dateDiff = a.shift_date.localeCompare(b.shift_date);
      if (dateDiff !== 0) return dateDiff;
      return a.start_time.localeCompare(b.start_time);
    }),
    settings,
    jobs: normalizedJobs,
  };
}

function sliceLoadedShiftData(
  loaded: LoadedShiftData,
  startDate: string,
  endDate: string,
): LoadedShiftData {
  return {
    ...loaded,
    shifts: loaded.shifts.filter((shift) =>
      shift.shift_date >= startDate && shift.shift_date <= endDate
    ),
  };
}

function getEarlierDate(...dates: string[]): string {
  return dates.reduce((
    earliest,
    current,
  ) => (current < earliest ? current : earliest));
}

function getLaterDate(...dates: string[]): string {
  return dates.reduce((
    latest,
    current,
  ) => (current > latest ? current : latest));
}

function addDaysToIsoDate(date: string, days: number): string {
  const next = parseDateAsUTC(date);
  next.setUTCDate(next.getUTCDate() + days);
  return toISODate(next);
}

function expandToFullISOWeeks(startDate: string, endDate: string): {
  startDate: string;
  endDate: string;
} {
  const start = parseDateAsUTC(startDate);
  const end = parseDateAsUTC(endDate);
  const startOffset = (start.getUTCDay() + 6) % 7;
  const endOffset = (end.getUTCDay() + 6) % 7;
  start.setUTCDate(start.getUTCDate() - startOffset);
  end.setUTCDate(end.getUTCDate() + (6 - endOffset));
  return {
    startDate: toISODate(start),
    endDate: toISODate(end),
  };
}

function getRecurringEffectiveEndDate(
  recurring: DbRecurringShift,
  fallbackEndDate: string,
): string {
  if (recurring.end_condition === null) {
    return fallbackEndDate;
  }

  const window = resolveEndWindow(
    recurring.selected_days,
    recurring.end_condition as never,
    0,
  );
  if (!window) {
    return fallbackEndDate;
  }

  const resolvedEndDate = toISODate(window.maxDate);
  return resolvedEndDate < fallbackEndDate ? resolvedEndDate : fallbackEndDate;
}

function countRecurringOccurrencesInRange(
  recurring: DbRecurringShift,
  startDate: string,
  fallbackEndDate: string,
): number {
  const effectiveEndDate = getRecurringEffectiveEndDate(
    recurring,
    fallbackEndDate,
  );
  if (effectiveEndDate < startDate) {
    return 0;
  }

  const exclusions = new Set(recurring.exclusions ?? []);
  const stepDays = 7 * (Number(recurring.repeat_interval_weeks) + 1);
  let count = 0;

  for (const anchorDate of Object.values(recurring.selected_days ?? {})) {
    if (!anchorDate) continue;

    let currentDate = anchorDate;
    if (currentDate < startDate) {
      const diffDays = Math.floor(
        (parseDateAsUTC(startDate).getTime() -
          parseDateAsUTC(currentDate).getTime()) / (1000 * 60 * 60 * 24),
      );
      const skippedSteps = Math.ceil(diffDays / stepDays);
      currentDate = addDaysToIsoDate(currentDate, skippedSteps * stepDays);
    }

    while (currentDate <= effectiveEndDate) {
      if (!exclusions.has(currentDate)) {
        count += 1;
      }
      currentDate = addDaysToIsoDate(currentDate, stepDays);
    }
  }

  return count;
}

export async function getComputedShiftsForApi(
  ctx: WageyRequestContext,
  userId = ctx.user.id,
  options: ShiftLoadOptions = {},
): Promise<LoadedShiftData> {
  const startDate = options.startDate ?? getDefaultStartDate();
  const endDate = options.endDate ?? getDefaultEndDate();
  const expandedRange = expandToFullISOWeeks(startDate, endDate);

  return await getCachedValue(
    ctx,
    buildCacheKey("computed_shifts", {
      userId,
      startDate,
      endDate,
      limit: options.limit ?? null,
      jobId: options.jobId ?? null,
    }),
    async () => {
      const [{ settings, jobs, snapshots, recurringShifts }, rawShifts] =
        await Promise.all([
          loadShiftResources(ctx, userId, { jobId: options.jobId }),
          loadShiftRows(ctx, userId, {
            startDate: expandedRange.startDate,
            endDate: expandedRange.endDate,
            limit: options.limit,
            jobId: options.jobId,
          }),
        ]);

      return buildComputedShiftData({
        userId,
        settings,
        jobs,
        snapshots,
        shifts: rawShifts,
        recurringShifts,
        startDate: expandedRange.startDate,
        endDate: expandedRange.endDate,
        returnStartDate: startDate,
        returnEndDate: endDate,
      });
    },
  );
}

export async function countShiftsAffectedBySnapshot(
  ctx: WageyRequestContext,
  options: { startDate: string; jobId?: string; userId?: string },
): Promise<number> {
  const userId = options.userId ?? ctx.user.id;
  let query = ctx.supabase
    .from("user_shifts")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .is("deleted_at", null)
    .gte("shift_date", options.startDate);
  if (options.jobId) {
    query = query.eq("job_id", options.jobId);
  }

  const [{ count, error }, { recurringShifts }] = await Promise.all([
    query,
    loadShiftResources(ctx, userId, { jobId: options.jobId }),
  ]);
  if (error) throw new Error(error.message);

  const recurringCount = recurringShifts.reduce(
    (sum, recurring) =>
      sum +
      countRecurringOccurrencesInRange(
        recurring,
        options.startDate,
        FAR_FUTURE_DATE,
      ),
    0,
  );

  return (count ?? 0) + recurringCount;
}

export async function getShiftIdentityRowsForApi(
  ctx: WageyRequestContext,
  userId = ctx.user.id,
  options: ShiftLoadOptions = {},
): Promise<ShiftIdentityRow[]> {
  return await getRawUserShifts(ctx, userId, options);
}

export async function getUserEventsForApi(
  ctx: WageyRequestContext,
  userId = ctx.user.id,
  options: EventLoadOptions = {},
): Promise<EventRecord[]> {
  return await getRawUserEvents(ctx, userId, options);
}

export async function createShifts(
  ctx: WageyRequestContext,
  input: { dates: string[]; start: string; end: string; jobId?: string },
): Promise<{
  inserted: number;
  updated: number;
  skipped: number;
  shiftIds: string[];
  dates: string[];
  insertedDates: string[];
  updatedDates: string[];
  skippedDates: string[];
}> {
  await assertCanMutateShiftMonths(ctx, input.dates);

  const sortedDates = [...input.dates].sort();
  const [existingShifts, recurringShifts, defaultJobId] =
    sortedDates.length === 0 ? [[], [], null] : await Promise.all([
      getRawUserShifts(ctx, ctx.user.id, {
        startDate: sortedDates[0],
        endDate: sortedDates[sortedDates.length - 1],
      }),
      getRawRecurringShifts(ctx.supabase, ctx.user.id),
      getDefaultJobIdForUser(ctx, ctx.user.id),
    ]);
  const requestedJobId = input.jobId ?? defaultJobId ?? null;
  const existingByDateAndJob = new Map<string, ExistingShiftMatch[]>();

  for (const shift of existingShifts) {
    const key = `${shift.shift_date}|${shift.job_id ?? defaultJobId ?? ""}`;
    existingByDateAndJob.set(key, [
      ...(existingByDateAndJob.get(key) ?? []),
      { kind: "stored", shift },
    ]);
  }
  for (
    const recurring of projectRecurringShiftMatches(
      recurringShifts,
      sortedDates[0],
      sortedDates[sortedDates.length - 1],
      defaultJobId,
    )
  ) {
    const key = `${recurring.shift.shift_date}|${recurring.shift.job_id ?? ""}`;
    existingByDateAndJob.set(key, [
      ...(existingByDateAndJob.get(key) ?? []),
      recurring,
    ]);
  }

  const shiftIds: string[] = [];
  const dates: string[] = [];
  const insertedDates: string[] = [];
  const updatedDates: string[] = [];
  const skippedDates: string[] = [];

  for (const shift_date of input.dates) {
    const key = `${shift_date}|${requestedJobId ?? ""}`;
    const existingMatches = existingByDateAndJob.get(key) ?? [];

    if (existingMatches.length > 0) {
      const exactMatch = existingMatches.find((match) =>
        hasSameShiftTimes(match.shift, input.start, input.end)
      );
      if (exactMatch) {
        shiftIds.push(exactMatch.shift.id);
        dates.push(exactMatch.shift.shift_date);
        skippedDates.push(exactMatch.shift.shift_date);
        continue;
      }
    }

    if (existingMatches.length === 1) {
      const existing = existingMatches[0].shift;
      shiftIds.push(existing.id);
      dates.push(existing.shift_date);

      if (existingMatches[0].kind === "recurring") {
        const insertedShift = await convertRecurringShiftToStandalone(ctx, {
          recurringId: existingMatches[0].recurringId,
          shiftDate: existing.shift_date,
          startTime: input.start,
          endTime: input.end,
        });
        shiftIds[shiftIds.length - 1] = insertedShift.id;
        updatedDates.push(existing.shift_date);
        continue;
      }

      const { error } = await ctx.supabase
        .from("user_shifts")
        .update({
          ...(requestedJobId ? { job_id: requestedJobId } : {}),
          start_time: input.start,
          end_time: input.end,
        })
        .eq("id", existing.id)
        .eq("user_id", ctx.user.id)
        .is("deleted_at", null);
      if (error) throw new Error(error.message);

      existing.start_time = input.start;
      existing.end_time = input.end;
      existing.job_id = requestedJobId;
      updatedDates.push(existing.shift_date);
      continue;
    }

    const { data, error } = await ctx.supabase
      .from("user_shifts")
      .insert({
        user_id: ctx.user.id,
        ...(input.jobId ? { job_id: input.jobId } : {}),
        shift_date,
        start_time: input.start,
        end_time: input.end,
      })
      .select("id, shift_date, start_time, end_time, job_id")
      .single();
    if (error || !data) {
      throw new Error(error?.message ?? "Failed to create shift");
    }

    const insertedShift = {
      ...(data as ShiftIdentityRow),
      job_id: (data as ShiftIdentityRow).job_id ?? requestedJobId,
    };
    shiftIds.push(insertedShift.id);
    dates.push(insertedShift.shift_date);
    insertedDates.push(insertedShift.shift_date);
    existingByDateAndJob.set(key, [
      ...existingMatches,
      { kind: "stored", shift: insertedShift },
    ]);
  }

  return {
    inserted: insertedDates.length,
    updated: updatedDates.length,
    skipped: skippedDates.length,
    shiftIds,
    dates,
    insertedDates,
    updatedDates,
    skippedDates,
  };
}

type ExistingShiftMatch =
  | { kind: "stored"; shift: ShiftIdentityRow }
  | { kind: "recurring"; recurringId: string; shift: ShiftIdentityRow };

function hasSameShiftTimes(
  shift: Pick<ShiftIdentityRow, "start_time" | "end_time">,
  start: string,
  end: string,
): boolean {
  return shift.start_time.slice(0, 5) === start &&
    shift.end_time.slice(0, 5) === end;
}

function projectRecurringShiftMatches(
  recurringShifts: DbRecurringShift[],
  startDate: string,
  endDate: string,
  defaultJobId: string | null,
): ExistingShiftMatch[] {
  const start = parseDateAsUTC(startDate);
  const end = parseDateAsUTC(endDate);
  const matches: ExistingShiftMatch[] = [];

  let currentYear = start.getUTCFullYear();
  let currentMonth = start.getUTCMonth() + 1;
  while (
    currentYear < end.getUTCFullYear() ||
    (currentYear === end.getUTCFullYear() &&
      currentMonth <= end.getUTCMonth() + 1)
  ) {
    for (const recurring of recurringShifts) {
      const generated = generateVirtualShiftsForMonth(
        { year: currentYear, month: currentMonth },
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
          exclusions: recurring.exclusions || [],
        },
      );

      for (const generatedShift of generated) {
        if (generatedShift.date < startDate || generatedShift.date > endDate) {
          continue;
        }

        matches.push({
          kind: "recurring",
          recurringId: recurring.id,
          shift: {
            id: `virtual-${recurring.id}-${generatedShift.date}`,
            shift_date: generatedShift.date,
            start_time: cleanTime(recurring.start_time),
            end_time: cleanTime(recurring.end_time),
            job_id: recurring.job_id ?? defaultJobId,
          },
        });
      }
    }

    currentMonth += 1;
    if (currentMonth > 12) {
      currentMonth = 1;
      currentYear += 1;
    }
  }

  return matches;
}

export async function updateShift(
  ctx: WageyRequestContext,
  input: {
    id: string;
    job_id?: string;
    shift_date: string;
    start: string;
    end: string;
    recurring_id?: string;
  },
): Promise<{ updated: number }> {
  await assertCanMutateShiftMonths(ctx, [input.shift_date]);

  if (input.recurring_id) {
    await convertRecurringShiftToStandalone(ctx, {
      recurringId: input.recurring_id,
      shiftDate: input.shift_date,
      startTime: input.start,
      endTime: input.end,
    });
    return { updated: 1 };
  }

  const { error } = await ctx.supabase
    .from("user_shifts")
    .update({
      shift_date: input.shift_date,
      start_time: input.start,
      end_time: input.end,
      ...(input.job_id !== undefined ? { job_id: input.job_id } : {}),
    })
    .eq("id", input.id)
    .eq("user_id", ctx.user.id)
    .is("deleted_at", null);

  if (error) throw new Error(error.message);
  return { updated: 1 };
}

export async function deleteShift(
  ctx: WageyRequestContext,
  input: string | { shiftId: string; recurringId?: string; shiftDate?: string },
): Promise<{ deleted: number }> {
  const shiftId = typeof input === "string" ? input : input.shiftId;
  const recurringId = typeof input === "string" ? undefined : input.recurringId;
  const shiftDate = typeof input === "string" ? undefined : input.shiftDate;

  if (recurringId && shiftDate) {
    const { data: recurring, error } = await ctx.supabase
      .from("recurring_shifts")
      .select("exclusions")
      .eq("id", recurringId)
      .eq("user_id", ctx.user.id)
      .is("deleted_at", null)
      .single();
    if (error || !recurring) throw new Error("Recurring shift not found");

    const exclusions = Array.from(
      new Set([...(recurring.exclusions ?? []), shiftDate]),
    ).sort();
    const { error: updateError } = await ctx.supabase
      .from("recurring_shifts")
      .update({ exclusions })
      .eq("id", recurringId)
      .eq("user_id", ctx.user.id)
      .is("deleted_at", null);
    if (updateError) throw new Error(updateError.message);
    return { deleted: 1 };
  }

  const { error } = await ctx.supabase
    .from("user_shifts")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", shiftId)
    .eq("user_id", ctx.user.id)
    .is("deleted_at", null);
  if (error) throw new Error(error.message);

  return { deleted: 1 };
}

export async function createEvent(
  ctx: WageyRequestContext,
  input: {
    startDate: string;
    endDate: string;
    isAllDay: boolean;
    startTime?: string | null;
    endTime?: string | null;
    note: string;
    notificationMinutesArray?: number[] | null;
    notificationAnchorTime?: string | null;
  },
): Promise<EventRecord> {
  const { data, error } = await ctx.supabase
    .from("events")
    .insert({
      user_id: ctx.user.id,
      start_date: input.startDate,
      end_date: input.endDate,
      is_all_day: input.isAllDay,
      start_time: input.startTime ?? null,
      end_time: input.endTime ?? null,
      note: input.note,
      notification_minutes_array: input.notificationMinutesArray ?? null,
      notification_anchor_time: input.notificationAnchorTime ?? null,
    })
    .select(COMPUTED_EVENT_SELECT)
    .single();
  if (error || !data) {
    throw new Error(error?.message ?? "Failed to create event");
  }
  return data as EventRecord;
}

export async function updateEvent(
  ctx: WageyRequestContext,
  input: {
    id: string;
    startDate: string;
    endDate: string;
    isAllDay: boolean;
    startTime?: string | null;
    endTime?: string | null;
    note: string;
    notificationMinutesArray?: number[] | null;
    notificationAnchorTime?: string | null;
  },
): Promise<EventRecord | null> {
  const { error } = await ctx.supabase
    .from("events")
    .update({
      start_date: input.startDate,
      end_date: input.endDate,
      is_all_day: input.isAllDay,
      start_time: input.startTime ?? null,
      end_time: input.endTime ?? null,
      note: input.note,
      notification_minutes_array: input.notificationMinutesArray ?? null,
      notification_anchor_time: input.notificationAnchorTime ?? null,
    })
    .eq("id", input.id)
    .eq("user_id", ctx.user.id)
    .is("deleted_at", null);
  if (error) throw new Error(error.message);
  return await getUserEventById(ctx, input.id);
}

export async function deleteEvent(
  ctx: WageyRequestContext,
  eventId: string,
): Promise<{ deleted: number }> {
  const { error } = await ctx.supabase
    .from("events")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", eventId)
    .eq("user_id", ctx.user.id)
    .is("deleted_at", null);
  if (error) throw new Error(error.message);
  return { deleted: 1 };
}

export async function createJob(
  ctx: WageyRequestContext,
  userId: string,
  input: Partial<Job> & { name: string },
): Promise<Job> {
  const { data, error } = await ctx.supabase
    .from("jobs")
    .insert({
      user_id: userId,
      name: input.name,
      color: input.color ?? null,
      is_default: input.is_default ?? false,
      sort_order: input.sort_order ?? 0,
      payroll_day: input.payroll_day ?? null,
      half_tax_month: input.half_tax_month ?? null,
      monthly_goal: input.monthly_goal ?? null,
    })
    .select("*")
    .single();
  if (error || !data) {
    throw new Error(error?.message ?? "Failed to create workplace");
  }
  return data as Job;
}

export async function updateJob(
  ctx: WageyRequestContext,
  userId: string,
  jobId: string,
  input: Partial<Job>,
): Promise<Job> {
  const { data, error } = await ctx.supabase
    .from("jobs")
    .update(input)
    .eq("id", jobId)
    .eq("user_id", userId)
    .is("deleted_at", null)
    .select("*")
    .single();
  if (error || !data) {
    throw new Error(error?.message ?? "Failed to update workplace");
  }
  return data as Job;
}

export async function archiveJob(
  ctx: WageyRequestContext,
  userId: string,
  jobId: string,
): Promise<Job> {
  return await updateJob(
    ctx,
    userId,
    jobId,
    { archived_at: new Date().toISOString() } as Partial<Job>,
  );
}

export async function deleteJob(
  ctx: WageyRequestContext,
  userId: string,
  jobId: string,
): Promise<void> {
  const { error } = await ctx.supabase
    .from("jobs")
    .update({ deleted_at: new Date().toISOString(), is_default: false })
    .eq("id", jobId)
    .eq("user_id", userId)
    .is("deleted_at", null);
  if (error) throw new Error(error.message);
}

export async function countJobDeleteDependencies(
  ctx: WageyRequestContext,
  userId: string,
  jobId: string,
): Promise<JobDeleteDependencyCounts> {
  const [userShifts, recurringShifts, payrollAdjustments] = await Promise.all([
    ctx.supabase
      .from("user_shifts")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("job_id", jobId)
      .is("deleted_at", null),
    ctx.supabase
      .from("recurring_shifts")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("job_id", jobId)
      .is("deleted_at", null),
    ctx.supabase
      .from("payroll_adjustments")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .eq("job_id", jobId)
      .is("deleted_at", null),
  ]);

  for (const result of [userShifts, recurringShifts, payrollAdjustments]) {
    if (result.error) throw new Error(result.error.message);
  }

  const counts = {
    userShifts: userShifts.count ?? 0,
    recurringShifts: recurringShifts.count ?? 0,
    payrollAdjustments: payrollAdjustments.count ?? 0,
  };

  return {
    ...counts,
    total: counts.userShifts + counts.recurringShifts +
      counts.payrollAdjustments,
  };
}

export async function draftRecurringShift(
  ctx: WageyRequestContext,
  draft: {
    start_time: string;
    end_time: string;
    repeat_interval_weeks: number;
    selected_days: Record<string, string>;
    end_condition: unknown;
    exclusions: string[];
    job_id?: string;
  },
): Promise<
  {
    conflictDates: string[];
    conflictCount: number;
    projectedShiftCount: number;
  }
> {
  const [{ data, error }, defaultJobId] = await Promise.all([
    ctx.supabase
      .from("user_shifts")
      .select("shift_date, start_time, end_time, job_id")
      .eq("user_id", ctx.user.id)
      .is("deleted_at", null),
    getDefaultJobIdForUser(ctx, ctx.user.id),
  ]);
  if (error) throw new Error(error.message);

  const targetJobId = draft.job_id ?? defaultJobId ?? null;
  const existingShifts = ((data ?? []) as Array<
    ExistingShift & { job_id?: string | null }
  >)
    .filter((shift) => (shift.job_id ?? defaultJobId ?? null) === targetJobId);
  const conflictDates = await detectAllRecurringConflicts(
    draft as never,
    existingShifts,
  );

  const window = draft.end_condition !== null
    ? resolveEndWindow(
      draft.selected_days as never,
      draft.end_condition as never,
    )
    : resolveEndWindow(draft.selected_days as never, null, 6);

  let projectedShiftCount = 0;
  if (window) {
    const startYear = window.minMonth.getUTCFullYear();
    const endYear = window.maxMonth.getUTCFullYear();

    for (let year = startYear; year <= endYear; year++) {
      const startMonth = year === startYear
        ? window.minMonth.getUTCMonth() + 1
        : 1;
      const endMonth = year === endYear
        ? window.maxMonth.getUTCMonth() + 1
        : 12;
      for (let month = startMonth; month <= endMonth; month++) {
        projectedShiftCount +=
          generateVirtualShiftsForMonth({ year, month }, draft as never).length;
      }
    }
  }

  return {
    conflictDates: conflictDates.sort(),
    conflictCount: conflictDates.length,
    projectedShiftCount,
  };
}

function currentTimeZoneSuffix(): string {
  const now = new Date();
  const offset = -now.getTimezoneOffset();
  const sign = offset >= 0 ? "+" : "-";
  const hours = String(Math.floor(Math.abs(offset) / 60)).padStart(2, "0");
  const minutes = String(Math.abs(offset) % 60).padStart(2, "0");
  return `${sign}${hours}:${minutes}`;
}

export async function createRecurringShift(
  ctx: WageyRequestContext,
  draft: {
    start_time: string;
    end_time: string;
    repeat_interval_weeks: number;
    selected_days: Record<string, string>;
    end_condition: unknown;
    exclusions: string[];
    job_id?: string;
  },
  options?: { conflictResolution?: "exclude_conflicts" | "keep_existing" },
): Promise<{ id: string }> {
  let exclusions = draft.exclusions || [];
  if (
    (options?.conflictResolution ?? "exclude_conflicts") === "exclude_conflicts"
  ) {
    const validation = await draftRecurringShift(ctx, draft);
    exclusions = Array.from(
      new Set([...exclusions, ...validation.conflictDates]),
    ).sort();
  }

  const timezoneSuffix = currentTimeZoneSuffix();
  const { data, error } = await ctx.supabase
    .from("recurring_shifts")
    .insert({
      user_id: ctx.user.id,
      ...(draft.job_id ? { job_id: draft.job_id } : {}),
      start_time: `${draft.start_time}${timezoneSuffix}`,
      end_time: `${draft.end_time}${timezoneSuffix}`,
      repeat_interval_weeks: draft.repeat_interval_weeks,
      selected_days: draft.selected_days,
      end_condition: draft.end_condition,
      exclusions,
    })
    .select("id")
    .single();
  if (error || !data) {
    throw new Error(error?.message ?? "Failed to create recurring shift");
  }
  return { id: data.id };
}

export async function updateRecurringShift(
  ctx: WageyRequestContext,
  input: {
    id: string;
    selected_days: Record<string, string>;
    start_time: string;
    end_time: string;
    repeat_interval_weeks: number;
    end_condition: unknown;
    exclusions: string[];
  },
): Promise<void> {
  const { error } = await ctx.supabase
    .from("recurring_shifts")
    .update({
      selected_days: input.selected_days,
      start_time: `${cleanTime(input.start_time)}${currentTimeZoneSuffix()}`,
      end_time: `${cleanTime(input.end_time)}${currentTimeZoneSuffix()}`,
      repeat_interval_weeks: input.repeat_interval_weeks,
      end_condition: input.end_condition,
      exclusions: input.exclusions,
    })
    .eq("id", input.id)
    .eq("user_id", ctx.user.id)
    .is("deleted_at", null);
  if (error) throw new Error(error.message);
}

export async function deleteRecurringShift(
  ctx: WageyRequestContext,
  recurringId: string,
): Promise<void> {
  const { error } = await ctx.supabase
    .from("recurring_shifts")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", recurringId)
    .eq("user_id", ctx.user.id)
    .is("deleted_at", null);
  if (error) throw new Error(error.message);
}

export async function copyShifts(
  ctx: WageyRequestContext,
  input: { shiftIds: string[]; targetDate: string },
): Promise<{ copied: number }> {
  await assertCanMutateShiftMonths(ctx, [input.targetDate]);

  const sourceShifts: Array<
    { start_time: string; end_time: string; job_id?: string | null }
  > = [];
  const virtualIds = input.shiftIds.filter((id) => id.startsWith("virtual-"));
  const regularIds = input.shiftIds.filter((id) => !id.startsWith("virtual-"));

  if (regularIds.length > 0) {
    const { data, error } = await ctx.supabase
      .from("user_shifts")
      .select("*")
      .eq("user_id", ctx.user.id)
      .is("deleted_at", null)
      .in("id", regularIds);
    if (error) throw new Error(error.message);
    sourceShifts.push(
      ...((data ?? []) as Array<
        { start_time: string; end_time: string; job_id?: string | null }
      >),
    );
  }

  if (virtualIds.length > 0) {
    const recurringIds = Array.from(
      new Set(
        virtualIds
          .map((id) =>
            id.match(/^virtual-([a-f0-9-]+)-\d{4}-\d{2}-\d{2}$/)?.[1]
          )
          .filter((id): id is string => Boolean(id)),
      ),
    );

    if (recurringIds.length > 0) {
      const { data, error } = await ctx.supabase
        .from("recurring_shifts")
        .select("id, start_time, end_time, job_id")
        .eq("user_id", ctx.user.id)
        .is("deleted_at", null)
        .in("id", recurringIds);
      if (error) throw new Error(error.message);

      const recurringMap = new Map((data ?? []).map((row) => [row.id, row]));
      for (const virtualId of virtualIds) {
        const recurringId = virtualId.match(
          /^virtual-([a-f0-9-]+)-\d{4}-\d{2}-\d{2}$/,
        )?.[1];
        if (!recurringId) continue;
        const recurring = recurringMap.get(recurringId);
        if (!recurring) continue;
        sourceShifts.push({
          start_time: recurring.start_time,
          end_time: recurring.end_time,
          job_id: recurring.job_id ?? null,
        });
      }
    }
  }

  const rows = sourceShifts.map((shift) => ({
    user_id: ctx.user.id,
    ...(shift.job_id ? { job_id: shift.job_id } : {}),
    shift_date: input.targetDate,
    start_time: cleanTime(shift.start_time),
    end_time: cleanTime(shift.end_time),
  }));

  const { error } = await ctx.supabase.from("user_shifts").insert(rows);
  if (error) throw new Error(error.message);
  return { copied: rows.length };
}

export async function updateCustomSupplements(
  ctx: WageyRequestContext,
  input: {
    shiftId: string;
    customSupplements: CustomSupplementsData | null;
    recurringId?: string;
    shiftDate?: string;
  },
): Promise<{ updated: number }> {
  if (input.recurringId && input.shiftDate) {
    const { data: recurring, error } = await ctx.supabase
      .from("recurring_shifts")
      .select("date_specific_supplements")
      .eq("id", input.recurringId)
      .eq("user_id", ctx.user.id)
      .is("deleted_at", null)
      .single();
    if (error || !recurring) {
      throw new Error(error?.message ?? "Recurring shift not found");
    }

    const updatedDateSpecific = {
      ...(recurring.date_specific_supplements ?? {}),
    };
    if (input.customSupplements) {
      updatedDateSpecific[input.shiftDate] = input.customSupplements;
    } else {
      delete updatedDateSpecific[input.shiftDate];
    }

    const { error: updateError } = await ctx.supabase
      .from("recurring_shifts")
      .update({
        date_specific_supplements: Object.keys(updatedDateSpecific).length > 0
          ? updatedDateSpecific
          : null,
      })
      .eq("id", input.recurringId)
      .eq("user_id", ctx.user.id)
      .is("deleted_at", null);

    if (updateError) throw new Error(updateError.message);
    return { updated: 1 };
  }

  const { error } = await ctx.supabase
    .from("user_shifts")
    .update({ custom_supplements: input.customSupplements })
    .eq("id", input.shiftId)
    .eq("user_id", ctx.user.id)
    .is("deleted_at", null);
  if (error) throw new Error(error.message);
  return { updated: 1 };
}

export async function updateCustomPauseWindows(
  ctx: WageyRequestContext,
  input: {
    shiftId: string;
    customPauseWindows: CustomPauseWindows | null;
    recurringId?: string;
    shiftDate?: string;
  },
): Promise<{ updated: number }> {
  const normalizedPauseWindows = normalizeCustomPauseWindows(
    input.customPauseWindows,
  );

  if (input.recurringId && input.shiftDate) {
    const { data: recurring, error } = await ctx.supabase
      .from("recurring_shifts")
      .select("date_specific_pause_windows")
      .eq("id", input.recurringId)
      .eq("user_id", ctx.user.id)
      .is("deleted_at", null)
      .single();
    if (error || !recurring) {
      throw new Error(error?.message ?? "Recurring shift not found");
    }

    const updatedDateSpecific = {
      ...(recurring.date_specific_pause_windows ?? {}),
    };
    if (normalizedPauseWindows) {
      updatedDateSpecific[input.shiftDate] = normalizedPauseWindows;
    } else {
      delete updatedDateSpecific[input.shiftDate];
    }

    const { error: updateError } = await ctx.supabase
      .from("recurring_shifts")
      .update({
        date_specific_pause_windows: Object.keys(updatedDateSpecific).length > 0
          ? updatedDateSpecific
          : null,
      })
      .eq("id", input.recurringId)
      .eq("user_id", ctx.user.id)
      .is("deleted_at", null);

    if (updateError) throw new Error(updateError.message);
    return { updated: 1 };
  }

  const { error } = await ctx.supabase
    .from("user_shifts")
    .update({ custom_pause_windows: normalizedPauseWindows })
    .eq("id", input.shiftId)
    .eq("user_id", ctx.user.id)
    .is("deleted_at", null);
  if (error) throw new Error(error.message);
  return { updated: 1 };
}

export async function convertRecurringShiftToStandalone(
  ctx: WageyRequestContext,
  input: {
    recurringId: string;
    shiftDate: string;
    startTime: string;
    endTime: string;
  },
  options: { skipMonthLimit?: boolean } = {},
): Promise<ShiftIdentityRow> {
  if (!options.skipMonthLimit) {
    await assertCanMutateShiftMonths(ctx, [input.shiftDate]);
  }

  const { data: recurring, error } = await ctx.supabase
    .from("recurring_shifts")
    .select(
      "exclusions, job_id, date_specific_pause_windows, date_specific_supplements, date_specific_notes",
    )
    .eq("id", input.recurringId)
    .eq("user_id", ctx.user.id)
    .is("deleted_at", null)
    .single();
  if (error || !recurring) {
    throw new Error(error?.message ?? "Recurring shift not found");
  }

  const exclusions = Array.from(
    new Set([...(recurring.exclusions ?? []), input.shiftDate]),
  ).sort();
  const customPauseWindows = normalizeCustomPauseWindows(
    recurring.date_specific_pause_windows?.[input.shiftDate] ?? null,
  );
  const customSupplements =
    recurring.date_specific_supplements?.[input.shiftDate] ?? null;
  const note = recurring.date_specific_notes?.[input.shiftDate] ?? null;

  const insertData: Record<string, unknown> = {
    user_id: ctx.user.id,
    ...(recurring.job_id ? { job_id: recurring.job_id } : {}),
    shift_date: input.shiftDate,
    start_time: input.startTime,
    end_time: input.endTime,
    ...(customPauseWindows ? { custom_pause_windows: customPauseWindows } : {}),
    ...(customSupplements ? { custom_supplements: customSupplements } : {}),
    ...(note ? { note } : {}),
  };

  const [{ error: updateError }, { data: insertedShift, error: insertError }] =
    await Promise.all([
      ctx.supabase
        .from("recurring_shifts")
        .update({ exclusions })
        .eq("id", input.recurringId)
        .eq("user_id", ctx.user.id)
        .is("deleted_at", null),
      ctx.supabase.from("user_shifts").insert(insertData).select(
        "id, shift_date, start_time, end_time, job_id",
      ).single(),
    ]);
  if (updateError) throw new Error(updateError.message);
  if (insertError) throw new Error(insertError.message);
  if (!insertedShift) throw new Error("Failed to create standalone shift");
  return insertedShift as ShiftIdentityRow;
}

export async function moveRecurringShift(
  ctx: WageyRequestContext,
  input: {
    recurringId: string;
    sourceDate: string;
    targetDate: string;
    startTime: string;
    endTime: string;
  },
): Promise<void> {
  await assertCanMutateShiftMonths(ctx, [input.targetDate]);

  await convertRecurringShiftToStandalone(ctx, {
    recurringId: input.recurringId,
    shiftDate: input.sourceDate,
    startTime: cleanTime(input.startTime),
    endTime: cleanTime(input.endTime),
  }, {
    skipMonthLimit: true,
  });

  const { error } = await ctx.supabase
    .from("user_shifts")
    .update({ shift_date: input.targetDate })
    .eq("user_id", ctx.user.id)
    .eq("shift_date", input.sourceDate)
    .eq("start_time", cleanTime(input.startTime))
    .eq("end_time", cleanTime(input.endTime))
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .limit(1);
  if (error) throw new Error(error.message);
}

export async function submitFeedback(
  ctx: WageyRequestContext,
  message: string,
): Promise<void> {
  const trimmed = message.trim();
  if (!trimmed) throw new Error("Feedback cannot be empty");
  const { error } = await ctx.supabase.from("feedback").insert({
    user_id: ctx.user.id,
    message: trimmed,
    user_email: ctx.user.email ?? "unknown",
  });
  if (error) throw new Error(error.message);
}

export async function getUserFeedback(
  ctx: WageyRequestContext,
): Promise<Array<Record<string, unknown>>> {
  const { data, error } = await ctx.supabase
    .from("feedback")
    .select("id, message, created_at, response, responded_at")
    .eq("user_id", ctx.user.id)
    .order("created_at", { ascending: false });
  if (error) throw new Error(error.message);
  return (data ?? []) as Array<Record<string, unknown>>;
}

export async function updateProfileSettings(
  ctx: WageyRequestContext,
  data: { firstName: string; profilePictureUrl?: string | null },
): Promise<void> {
  const metadata = ctx.user.user_metadata ?? {};
  const { error: authError } = await ctx.supabase.auth.updateUser({
    data: {
      ...metadata,
      full_name: data.firstName,
      name: data.firstName,
    },
  });
  if (authError) throw new Error(authError.message);

  if (data.profilePictureUrl !== undefined) {
    const { error } = await ctx.supabase
      .from("user_settings")
      .update({ profile_picture_url: data.profilePictureUrl })
      .eq("user_id", ctx.user.id);
    if (error) throw new Error(error.message);
  }
}

export async function updateDisplaySettings(
  ctx: WageyRequestContext,
  data: Record<string, unknown>,
): Promise<void> {
  const { error } = await ctx.supabase.from("user_settings").update(data).eq(
    "user_id",
    ctx.user.id,
  );
  if (error) throw new Error(error.message);
}

export async function updatePaySettings(
  ctx: WageyRequestContext,
  data: Record<string, unknown>,
): Promise<void> {
  const { monthly_goals_by_month: overridePatch, ...scalarData } = data;
  const updateData: Record<string, unknown> = { ...scalarData };

  if (
    overridePatch && typeof overridePatch === "object" &&
    !Array.isArray(overridePatch)
  ) {
    const { data: current, error: fetchError } = await ctx.supabase
      .from("user_settings")
      .select("monthly_goals_by_month")
      .eq("user_id", ctx.user.id)
      .single();
    if (fetchError) throw new Error(fetchError.message);

    const merged = {
      ...((current?.monthly_goals_by_month ?? {}) as Record<string, number>),
    };
    for (
      const [month, value] of Object.entries(
        overridePatch as Record<string, number | null>,
      )
    ) {
      if (value === null) {
        delete merged[month];
      } else {
        merged[month] = value;
      }
    }
    updateData.monthly_goals_by_month = merged;
  }

  const { error } = await ctx.supabase.from("user_settings").update(updateData)
    .eq("user_id", ctx.user.id);
  if (error) throw new Error(error.message);
}

export async function updatePreferencesSettings(
  ctx: WageyRequestContext,
  data: Record<string, unknown>,
): Promise<void> {
  const { error } = await ctx.supabase.from("user_settings").update(data).eq(
    "user_id",
    ctx.user.id,
  );
  if (error) throw new Error(error.message);
}

export async function getTariffTypes(
  ctx: WageyRequestContext,
): Promise<Array<Record<string, unknown>>> {
  const { data, error } = await ctx.supabase.rpc("get_tariff_types");
  if (error) throw new Error(error.message);
  return (data ?? []) as Array<Record<string, unknown>>;
}

export async function getLatestTariffVersion(
  ctx: WageyRequestContext,
  tariffType: string,
): Promise<Record<string, unknown> | null> {
  const { data, error } = await ctx.supabase.rpc("get_tariff_versions", {
    p_tariff_type: tariffType,
  });
  if (error) throw new Error(error.message);
  return (Array.isArray(data) ? data[0] : data) as
    | Record<string, unknown>
    | null;
}

export async function getTariffVersionForDate(
  ctx: WageyRequestContext,
  tariffType: string,
  targetDate: string,
): Promise<Record<string, unknown> | null> {
  const { data, error } = await ctx.supabase.rpc(
    "get_tariff_version_for_date",
    {
      p_tariff_type: tariffType,
      p_target_date: targetDate,
    },
  );
  if (error) throw new Error(error.message);
  return (Array.isArray(data) ? data[0] : data) as
    | Record<string, unknown>
    | null;
}

export async function getUsersByIds(
  ctx: WageyRequestContext,
  userIds: string[],
): Promise<
  Map<
    string,
    {
      email: string | null;
      phone: string | null;
      firstName: string | null;
      oauthAvatarUrl: string | null;
    }
  >
> {
  if (userIds.length === 0) return new Map();
  const { data, error } = await ctx.supabaseAdmin.rpc("get_users_by_ids", {
    user_ids: userIds,
  });
  if (error) throw new Error(error.message);

  return new Map(
    ((data ?? []) as Array<Record<string, unknown>>).map((row) => [
      String(row.id),
      {
        email: (row.email as string | null) ?? null,
        phone: (row.phone as string | null) ?? null,
        firstName: (row.first_name as string | null) ?? null,
        oauthAvatarUrl: (row.oauth_avatar_url as string | null) ?? null,
      },
    ]),
  );
}

function normalizeShareIdentifier(
  identifier: string,
): { type: "email" | "phone"; value: string } | null {
  const trimmed = identifier.trim();
  if (!trimmed) return null;
  if (trimmed.includes("@")) {
    return { type: "email", value: trimmed.toLowerCase() };
  }

  const digits = trimmed.replace(/\D/g, "");
  let local = digits;
  if (digits.length === 12 && digits.startsWith("0047")) {
    local = digits.slice(4);
  } else if (digits.length === 10 && digits.startsWith("47")) {
    local = digits.slice(2);
  } else if (digits.length === 9 && digits.startsWith("0")) {
    local = digits.slice(1);
  }
  return local.length === 8 ? { type: "phone", value: `+47${local}` } : null;
}

// Shares are created through manage_sharing_action, which enforces the share
// limit and blocks. Direct inserts into shift_shares are denied by RLS.
async function manageSharingAction(
  ctx: WageyRequestContext,
  params: Record<string, unknown>,
): Promise<{ success: boolean; error?: string }> {
  const { data, error } = await ctx.supabase.rpc(
    "manage_sharing_action",
    params,
  );
  if (error) throw new Error(error.message);
  const result = (data ?? {}) as { success?: boolean; error?: string };
  return result.success
    ? { success: true }
    : { success: false, error: result.error ?? "Kunne ikke dele vaktene" };
}

export async function createShare(
  ctx: WageyRequestContext,
  identifier: string,
  options?: { showEarnings?: boolean },
): Promise<{ success: boolean; error?: string }> {
  const normalized = normalizeShareIdentifier(identifier);
  if (!normalized) {
    return {
      success: false,
      error: "Vennligst oppgi en gyldig e-post eller telefonnummer",
    };
  }

  return await manageSharingAction(ctx, {
    p_action: "createShare",
    p_identifier: normalized.value,
    p_show_earnings: options?.showEarnings ?? false,
  });
}

export async function removeShare(
  ctx: WageyRequestContext,
  recipientId: string,
): Promise<{ success: boolean }> {
  const { error } = await ctx.supabase
    .from("shift_shares")
    .delete()
    .eq("owner_id", ctx.user.id)
    .eq("viewer_id", recipientId);
  if (error) throw new Error(error.message);
  return { success: true };
}

export async function toggleShareEarnings(
  ctx: WageyRequestContext,
  recipientId: string,
  showEarnings: boolean,
): Promise<{ success: boolean }> {
  const { error } = await ctx.supabase
    .from("shift_shares")
    .update({ show_earnings: showEarnings })
    .eq("owner_id", ctx.user.id)
    .eq("viewer_id", recipientId);
  if (error) throw new Error(error.message);
  return { success: true };
}

export async function blockSharer(
  ctx: WageyRequestContext,
  ownerId: string,
): Promise<{ success: boolean }> {
  const { error } = await ctx.supabase
    .from("shift_shares")
    .update({ hidden: true })
    .eq("viewer_id", ctx.user.id)
    .eq("owner_id", ownerId);
  if (error) throw new Error(error.message);
  return { success: true };
}

export async function unblockSharer(
  ctx: WageyRequestContext,
  ownerId: string,
): Promise<{ success: boolean }> {
  const { error } = await ctx.supabase
    .from("shift_shares")
    .update({ hidden: false })
    .eq("viewer_id", ctx.user.id)
    .eq("owner_id", ownerId);
  if (error) throw new Error(error.message);
  return { success: true };
}

export async function shareBack(
  ctx: WageyRequestContext,
  recipientId: string,
): Promise<{ success: boolean; error?: string }> {
  return await manageSharingAction(ctx, {
    p_action: "shareBack",
    p_recipient_id: recipientId,
    p_show_earnings: false,
  });
}

export async function toggleSharerMuted(
  ctx: WageyRequestContext,
  ownerId: string,
  muted: boolean,
): Promise<{ success: boolean }> {
  const { error } = await ctx.supabase
    .from("shift_shares")
    .update({ muted })
    .eq("viewer_id", ctx.user.id)
    .eq("owner_id", ownerId);
  if (error) throw new Error(error.message);
  return { success: true };
}

export async function removeSharer(
  ctx: WageyRequestContext,
  ownerId: string,
): Promise<{ success: boolean }> {
  const { error } = await ctx.supabase
    .from("shift_shares")
    .delete()
    .eq("viewer_id", ctx.user.id)
    .eq("owner_id", ownerId);
  if (error) throw new Error(error.message);
  return { success: true };
}

export async function getAllFriends(
  ctx: WageyRequestContext,
): Promise<FriendEntry[]> {
  const { data, error } = await ctx.supabase.rpc("get_friends_tab_bootstrap", {
    p_preview_start_date: null,
    p_preview_end_date: null,
  });
  if (error) throw new Error(error.message);

  const payload = (data ?? {}) as { friends?: BootstrapFriendEntry[] };
  return (payload.friends ?? []).map((friend) => ({
    ...friend,
    sharesWithMe: friend.sharesWithMe
      ? {
        ...friend.sharesWithMe,
        blocked: friend.sharesWithMe.blocked ?? friend.sharesWithMe.hidden ??
          false,
      }
      : null,
  }));
}

async function loadSharedOwnerData(
  ctx: WageyRequestContext,
  ownerId: string,
  options: ShiftLoadOptions = {},
): Promise<LoadedShiftData & { showEarnings: boolean }> {
  const startDate = options.startDate ?? getDefaultStartDate();
  const endDate = options.endDate ?? getDefaultEndDate();
  const expandedRange = expandToFullISOWeeks(startDate, endDate);

  return await getCachedValue(
    ctx,
    buildCacheKey("shared_owner_data", {
      ownerId,
      viewerId: ctx.user.id,
      startDate,
      endDate,
      limit: options.limit ?? null,
      jobId: options.jobId ?? null,
    }),
    async () => {
      const { data: share, error: shareError } = await ctx.supabase
        .from("shift_shares")
        .select("show_earnings, hidden, blocked_by_user_id")
        .eq("owner_id", ownerId)
        .eq("viewer_id", ctx.user.id)
        .maybeSingle();
      if (shareError) throw new Error(shareError.message);
      if (!share || share.blocked_by_user_id) {
        throw new Error("No access to shared shifts");
      }

      const [{ settings, jobs, snapshots, recurringShifts }, shifts] =
        await Promise.all([
          loadShiftResources(ctx, ownerId, {
            jobId: options.jobId,
            asAdmin: true,
          }),
          loadShiftRows(ctx, ownerId, {
            startDate: expandedRange.startDate,
            endDate: expandedRange.endDate,
            limit: options.limit,
            jobId: options.jobId,
            asAdmin: true,
          }),
        ]);

      const loaded = buildComputedShiftData({
        userId: ownerId,
        settings,
        jobs,
        snapshots,
        shifts,
        recurringShifts,
        startDate: expandedRange.startDate,
        endDate: expandedRange.endDate,
        returnStartDate: startDate,
        returnEndDate: endDate,
      });

      return {
        ...loaded,
        showEarnings: Boolean(share.show_earnings),
      };
    },
  );
}

export async function getSharedUserShifts(
  ctx: WageyRequestContext,
  ownerId: string,
  options: ShiftLoadOptions = {},
): Promise<LoadedShiftData & { showEarnings: boolean }> {
  return await loadSharedOwnerData(ctx, ownerId, options);
}

export async function getSharerShiftPreviews(
  ctx: WageyRequestContext,
  sharerIds: string[],
): Promise<
  Array<
    {
      sharerId: string;
      showEarnings: boolean;
      status: "active" | "upcoming" | "past" | null;
      shift: ShiftWithComputations | null;
    }
  >
> {
  const now = new Date();
  const startDate = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() - 30),
  )
    .toISOString()
    .slice(0, 10);
  const endDate = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 30),
  )
    .toISOString()
    .slice(0, 10);

  const previews = await Promise.all(
    sharerIds.map(async (sharerId) => {
      try {
        const shared = await loadSharedOwnerData(ctx, sharerId, {
          startDate,
          endDate,
          limit: 1000,
        });
        const shifts = [...shared.shifts].sort((a, b) => {
          const dateDiff = a.shift_date.localeCompare(b.shift_date);
          if (dateDiff !== 0) return dateDiff;
          return a.start_time.localeCompare(b.start_time);
        });

        const active = shifts.find((shift) => {
          const start = new Date(
            `${shift.shift_date}T${cleanTime(shift.start_time)}:00Z`,
          ).getTime();
          let end = new Date(
            `${shift.shift_date}T${cleanTime(shift.end_time)}:00Z`,
          ).getTime();
          if (
            timeToMinutes(shift.end_time) <= timeToMinutes(shift.start_time)
          ) {
            end += 24 * 60 * 60 * 1000;
          }
          const current = now.getTime();
          return current >= start && current <= end;
        });
        if (active) {
          return {
            sharerId,
            showEarnings: shared.showEarnings,
            status: "active" as const,
            shift: active,
          };
        }

        const upcoming = shifts.find((shift) => {
          const start = new Date(
            `${shift.shift_date}T${cleanTime(shift.start_time)}:00Z`,
          ).getTime();
          return start > now.getTime();
        });
        if (upcoming) {
          return {
            sharerId,
            showEarnings: shared.showEarnings,
            status: "upcoming" as const,
            shift: upcoming,
          };
        }

        const past = [...shifts].reverse().find((shift) => {
          const start = new Date(
            `${shift.shift_date}T${cleanTime(shift.start_time)}:00Z`,
          ).getTime();
          return start < now.getTime();
        });
        return {
          sharerId,
          showEarnings: shared.showEarnings,
          status: past ? "past" as const : null,
          shift: past ?? null,
        };
      } catch {
        return { sharerId, showEarnings: false, status: null, shift: null };
      }
    }),
  );

  return previews;
}

export async function getStatistics(
  ctx: WageyRequestContext,
  options: {
    year?: number;
    month?: number;
    startDate?: string;
    endDate?: string;
    limit?: number;
    jobId?: string;
  } = {},
): Promise<{
  currentMonth: Record<string, unknown>;
  lastMonth: Record<string, unknown>;
  yearToDate: Record<string, unknown>;
  fullYear: Record<string, unknown>;
  yearlyMonths: Array<Record<string, unknown>>;
  thisWeek: Array<Record<string, unknown>>;
  monthlyGoal: Record<string, unknown>;
  currentMonthBreakdown: Record<string, unknown>;
  shiftGaps: Record<string, unknown>;
}> {
  const now = new Date();
  const year = options.year ?? now.getUTCFullYear();
  const month = options.month ?? now.getUTCMonth() + 1;

  const currentMonthStart = getMonthStart(year, month);
  const currentMonthEnd = getMonthEnd(year, month);
  const prevMonthYear = month === 1 ? year - 1 : year;
  const prevMonth = month === 1 ? 12 : month - 1;
  const lastMonthStart = getMonthStart(prevMonthYear, prevMonth);
  const lastMonthEnd = getMonthEnd(prevMonthYear, prevMonth);
  const yearStart = `${year}-01-01`;
  const yearEnd = `${year}-12-31`;
  const weekStart = new Date(now);
  const day = weekStart.getUTCDay();
  const diffToMonday = day === 0 ? -6 : 1 - day;
  weekStart.setUTCDate(weekStart.getUTCDate() + diffToMonday);
  const weekEnd = new Date(weekStart);
  weekEnd.setUTCDate(weekEnd.getUTCDate() + 6);
  const weekStartDate = weekStart.toISOString().slice(0, 10);
  const weekEndDate = weekEnd.toISOString().slice(0, 10);
  const shiftGapStart = options.startDate ?? yearStart;
  const shiftGapEnd = options.endDate ?? (
    options.year === undefined && options.month === undefined
      ? now.toISOString().slice(0, 10)
      : yearEnd
  );
  const aggregateStart = getEarlierDate(
    yearStart,
    lastMonthStart,
    weekStartDate,
    shiftGapStart,
  );
  const aggregateEnd = getLaterDate(
    yearEnd,
    currentMonthEnd,
    weekEndDate,
    shiftGapEnd,
  );
  const aggregateData = await getComputedShiftsForApi(ctx, ctx.user.id, {
    startDate: aggregateStart,
    endDate: aggregateEnd,
    jobId: options.jobId,
  });
  const settings = aggregateData.settings;
  const currentMonthData = sliceLoadedShiftData(
    aggregateData,
    currentMonthStart,
    currentMonthEnd,
  );
  const lastMonthData = sliceLoadedShiftData(
    aggregateData,
    lastMonthStart,
    lastMonthEnd,
  );
  const yearData = sliceLoadedShiftData(aggregateData, yearStart, yearEnd);
  const weekData = sliceLoadedShiftData(
    aggregateData,
    weekStartDate,
    weekEndDate,
  );
  const shiftGapData = sliceLoadedShiftData(
    aggregateData,
    shiftGapStart,
    shiftGapEnd,
  );

  const summarize = (loaded: LoadedShiftData) => {
    const jobsById = new Map(loaded.jobs.map((job) => [job.id, job] as const));
    const defaultJob = resolveDefaultJob(loaded.jobs);
    const totalEarnings = loaded.shifts.reduce(
      (sum, shift) => sum + shift.computed.gross,
      0,
    );
    const totalEarningsNet = loaded.shifts.reduce(
      (sum, shift) =>
        sum + calculateNetPay(
          shift.computed.gross,
          {
            tax_enabled: shift.tax_enabled,
            tax_percentage: shift.tax_percentage,
          },
          halfTaxMonthForJob(
            jobsById,
            defaultJob,
            loaded.settings,
            shift.job_id,
          ),
          shift.shift_date,
        ),
      0,
    );
    const totalHours = loaded.shifts.reduce(
      (sum, shift) => sum + shift.computed.paidHours,
      0,
    );
    return {
      totalEarnings: Number(totalEarnings.toFixed(2)),
      totalEarningsNet: Number(totalEarningsNet.toFixed(2)),
      totalHours: Number(totalHours.toFixed(2)),
      shiftCount: loaded.shifts.length,
      averageRate: totalHours > 0
        ? Number((totalEarnings / totalHours).toFixed(2))
        : 0,
    };
  };

  const yearlyMonths = Array.from({ length: 12 }, (_, index) => index + 1).map(
    (monthNumber) => {
      const start = getMonthStart(year, monthNumber);
      const end = getMonthEnd(year, monthNumber);
      const monthShifts = yearData.shifts.filter((shift) =>
        shift.shift_date >= start && shift.shift_date <= end
      );
      const totalGross = monthShifts.reduce(
        (sum, shift) => sum + shift.computed.gross,
        0,
      );
      const totalHours = monthShifts.reduce(
        (sum, shift) => sum + shift.computed.paidHours,
        0,
      );
      return {
        monthNumber,
        totalEarnings: Number(totalGross.toFixed(2)),
        totalHours: Number(totalHours.toFixed(2)),
        shiftCount: monthShifts.length,
      };
    },
  );

  const thisWeek = weekData.shifts.map((shift) => ({
    fullDate: shift.shift_date,
    totalEarnings: Number(shift.computed.gross.toFixed(2)),
    totalHours: Number(shift.computed.paidHours.toFixed(2)),
    shiftCount: 1,
  }));

  const currentMonthBreakdown = {
    basePay: Number(
      currentMonthData.shifts.reduce(
        (sum, shift) => sum + shift.computed.basePay,
        0,
      ).toFixed(2),
    ),
    supplementPay: Number(
      currentMonthData.shifts.reduce(
        (sum, shift) => sum + shift.computed.supplementPay,
        0,
      ).toFixed(2),
    ),
    basePercentage: 0,
    supplementPercentage: 0,
  };

  const totalBreakdown = currentMonthBreakdown.basePay +
    currentMonthBreakdown.supplementPay;
  currentMonthBreakdown.basePercentage = totalBreakdown > 0
    ? Number(
      ((currentMonthBreakdown.basePay / totalBreakdown) * 100).toFixed(2),
    )
    : 0;
  currentMonthBreakdown.supplementPercentage = totalBreakdown > 0
    ? Number(
      ((currentMonthBreakdown.supplementPay / totalBreakdown) * 100).toFixed(2),
    )
    : 0;

  const monthlyGoalTarget = settings.monthly_goals_by_month
    ?.[`${year}-${String(month).padStart(2, "0")}`] ??
    settings.monthly_goal ?? 0;
  const currentSummary = summarize(currentMonthData);
  const shiftGaps = summarizeShiftGaps(
    shiftGapData.shifts,
    shiftGapStart,
    shiftGapEnd,
    options.limit ?? 10,
  );

  return {
    currentMonth: currentSummary,
    lastMonth: summarize(lastMonthData),
    yearToDate: {
      totalEarnings: Number(
        yearData.shifts
          .filter((shift) => shift.shift_date <= currentMonthEnd)
          .reduce((sum, shift) => sum + shift.computed.gross, 0)
          .toFixed(2),
      ),
      totalHours: Number(
        yearData.shifts
          .filter((shift) => shift.shift_date <= currentMonthEnd)
          .reduce((sum, shift) => sum + shift.computed.paidHours, 0)
          .toFixed(2),
      ),
      shiftCount:
        yearData.shifts.filter((shift) => shift.shift_date <= currentMonthEnd)
          .length,
    },
    fullYear: {
      totalEarnings: Number(
        yearData.shifts.reduce((sum, shift) => sum + shift.computed.gross, 0)
          .toFixed(2),
      ),
      totalHours: Number(
        yearData.shifts.reduce(
          (sum, shift) => sum + shift.computed.paidHours,
          0,
        ).toFixed(2),
      ),
      shiftCount: yearData.shifts.length,
    },
    yearlyMonths,
    thisWeek,
    monthlyGoal: {
      enabled: monthlyGoalTarget > 0,
      target: monthlyGoalTarget,
      progress: currentSummary.totalEarnings,
      percentage: monthlyGoalTarget > 0
        ? Number(
          ((currentSummary.totalEarnings / monthlyGoalTarget) * 100).toFixed(2),
        )
        : 0,
      remaining: Math.max(
        0,
        Number((monthlyGoalTarget - currentSummary.totalEarnings).toFixed(2)),
      ),
    },
    currentMonthBreakdown,
    shiftGaps,
  };
}

function shiftBoundaryDateTime(
  shift: ShiftWithComputations,
  boundary: "start" | "end",
): Date {
  const time = boundary === "start" ? shift.start_time : shift.end_time;
  const date = parseDateAsUTC(shift.shift_date);
  const [hours, minutes] = cleanTime(time).split(":").map(Number);
  date.setUTCHours(hours, minutes, 0, 0);

  if (
    boundary === "end" &&
    timeToMinutes(shift.end_time) <= timeToMinutes(shift.start_time)
  ) {
    date.setUTCDate(date.getUTCDate() + 1);
  }

  return date;
}

function summarizeShiftGaps(
  shifts: ShiftWithComputations[],
  startDate: string,
  endDate: string,
  limit: number,
): Record<string, unknown> {
  const sorted = [...shifts].sort((a, b) => {
    const startDiff = shiftBoundaryDateTime(a, "start").getTime() -
      shiftBoundaryDateTime(b, "start").getTime();
    if (startDiff !== 0) return startDiff;
    return shiftBoundaryDateTime(a, "end").getTime() -
      shiftBoundaryDateTime(b, "end").getTime();
  });

  const gaps = sorted.slice(1).map((shift, index) => {
    const previousShift = sorted[index];
    const previousEnd = shiftBoundaryDateTime(previousShift, "end");
    const nextStart = shiftBoundaryDateTime(shift, "start");
    const gapMs = Math.max(0, nextStart.getTime() - previousEnd.getTime());
    const gapHours = Number((gapMs / (1000 * 60 * 60)).toFixed(2));
    return {
      previousShift: {
        id: toDisplayShiftId(previousShift.id),
        date: previousShift.shift_date,
        start: cleanTime(previousShift.start_time),
        end: cleanTime(previousShift.end_time),
      },
      nextShift: {
        id: toDisplayShiftId(shift.id),
        date: shift.shift_date,
        start: cleanTime(shift.start_time),
        end: cleanTime(shift.end_time),
      },
      gapHours,
      gapDays: Number((gapHours / 24).toFixed(2)),
      gapCalendarDays: Math.floor(gapMs / (1000 * 60 * 60 * 24)),
    };
  })
    .sort((a, b) => b.gapHours - a.gapHours)
    .map((gap, index) => ({ rank: index + 1, ...gap }));

  return {
    startDate,
    endDate,
    shiftCount: sorted.length,
    gapCount: Math.max(0, sorted.length - 1),
    longestGap: gaps[0] ?? null,
    gaps: gaps.slice(0, limit),
  };
}
