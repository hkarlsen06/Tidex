import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalAction, internalMutation, internalQuery } from "./_generated/server";
import {
  buildLiveActivityEndPayload,
  buildLiveActivityHeaders,
  buildLiveActivityStartPayload,
  type LiveActivityPresentationInput,
} from "./lib/shared/liveActivityPayload";
import {
  findOngoingShift,
  type LiveActivityRecurringShift,
  type LiveActivityRegularShift,
  projectedRecurringShifts,
  zonedShiftRange,
} from "./lib/shared/liveActivityScheduling";
import { computeShift } from "./lib/shared/payroll/calc";
import type { UserSettings, WageSnapshot } from "./lib/shared/payroll/types";
import { allowedRecipients, apnsConfigured, mayPush, sendToApns } from "./push";

// Port of _shared/live-activity-delivery.ts and the internal.*_live_activity_* SQL
// functions. A cron pass every 15 minutes starts a Live Activity on each device for the
// shift in progress in the device's time zone, and ends the one for a shift that is
// over. The pay shown comes from the same calculation the app uses.

const MAX_ATTEMPTS = 10;
const STALE_CLAIM_MS = 15 * 60_000;
const OPEN = ["starting", "active", "ending"] as const;

type Snapshot = WageSnapshot & { user_id: string; job_id: string | null };

const isoDateOffset = (date: Date, days: number) => {
  const shifted = new Date(date);
  shifted.setUTCDate(shifted.getUTCDate() + days);
  return shifted.toISOString().slice(0, 10);
};

const numberValue = (value: unknown, fallback = 0) => {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
};

// The pay code compares these fields to null, as Postgres returned them.
const asRegularShift = (s: Doc<"user_shifts">): LiveActivityRegularShift => ({
  id: s.id,
  user_id: s.user_id,
  job_id: s.job_id,
  shift_date: s.shift_date,
  start_time: s.start_time,
  end_time: s.end_time,
  custom_pause_windows: s.custom_pause_windows ?? null,
  custom_supplements: s.custom_supplements ?? null,
});

const asRecurringShift = (r: Doc<"recurring_shifts">): LiveActivityRecurringShift => ({
  id: r.id,
  user_id: r.user_id,
  job_id: r.job_id,
  start_time: r.start_time,
  end_time: r.end_time,
  repeat_interval_weeks: r.repeat_interval_weeks,
  selected_days: r.selected_days,
  end_condition: r.end_condition ?? null,
  exclusions: r.exclusions ?? null,
  date_specific_pause_windows: r.date_specific_pause_windows ?? null,
  date_specific_supplements: r.date_specific_supplements ?? null,
});

const asSnapshot = (w: Doc<"wage_snapshots">): Snapshot => ({
  id: w.id,
  user_id: w.user_id,
  job_id: w.job_id ?? null,
  from_date: w.from_date ?? null,
  hourly_wage: numberValue(w.hourly_wage),
  wage_level: w.wage_level ?? null,
  tariff_type_id: w.tariff_type_id ?? null,
  supplements: w.supplements,
  overtime: w.overtime ?? null,
  created_at: w.created_at,
  tax_enabled: w.tax_enabled ?? false,
  tax_percentage: numberValue(w.tax_percentage),
  break_enabled: w.break_enabled ?? true,
  break_method: w.break_method ?? "proportional",
  break_threshold_hours: numberValue(w.break_threshold_hours, 5.5),
  break_deduction_minutes: numberValue(w.break_deduction_minutes, 30),
} as Snapshot);

/** The job's newest snapshot on or before the shift's date, else the job's baseline. */
export function applicableWageSnapshot(shift: LiveActivityRegularShift, snapshots: Snapshot[]) {
  const forJob = snapshots.filter((s) => s.user_id === shift.user_id && s.job_id === shift.job_id);
  const scoped = forJob.length > 0 ? forJob : snapshots.filter((s) => s.user_id === shift.user_id && s.job_id === null);
  const baseline = scoped.find((s) => s.from_date === null) ?? null;
  return (
    scoped
      .filter((s) => s.from_date !== null && s.from_date <= shift.shift_date)
      .sort((a, b) => (b.from_date ?? "").localeCompare(a.from_date ?? ""))[0] ?? baseline
  );
}

function presentationForShift(
  shift: LiveActivityRegularShift,
  timeZone: string,
  currency: string | undefined,
  snapshots: Snapshot[],
): LiveActivityPresentationInput {
  const snapshot = applicableWageSnapshot(shift, snapshots);
  const computed = computeShift(shift, { currency } as UserSettings, [], snapshot, null);
  const range = zonedShiftRange(shift, timeZone);
  return {
    shiftId: shift.id,
    date: shift.shift_date,
    start: shift.start_time.slice(0, 5),
    end: shift.end_time.slice(0, 5),
    hourly: computed.paidHours > 0 ? computed.basePay / computed.paidHours : numberValue(snapshot?.hourly_wage),
    supplement: computed.paidHours > 0 ? computed.supplementPay / computed.paidHours : 0,
    gross: computed.gross,
    net: snapshot?.tax_enabled ? computed.gross * (1 - numberValue(snapshot.tax_percentage) / 100) : null,
    currency: currency ?? "kr",
    startDate: range.startDate,
    endDate: range.endDate,
  };
}

const fallbackEndPresentation = (shiftId: string, now: Date): LiveActivityPresentationInput => ({
  shiftId,
  date: now.toISOString().slice(0, 10),
  start: "00:00",
  end: "00:00",
  hourly: 0,
  supplement: 0,
  gross: 0,
  net: null,
  currency: null,
  startDate: now,
  endDate: now,
});

// ---------- Inputs and state changes ----------

/** iOS devices that can start an activity or have one open, with their owners' shifts. */
export const inputs = internalQuery({
  args: {},
  handler: async (ctx) => {
    const now = new Date();
    const from = isoDateOffset(now, -2);
    const to = isoDateOffset(now, 2);
    const people = new Map<string, unknown>();
    const devices = [];
    for (const d of await ctx.db.query("push_devices").collect()) {
      if (d.platform !== "ios") continue;
      const open = (
        await ctx.db
          .query("live_activity_deliveries")
          .withIndex("by_push_device_shift", (q) => q.eq("push_device_id", d.id))
          .collect()
      ).find((x) => (OPEN as readonly string[]).includes(x.status));
      if (d.live_activity_push_to_start_token === undefined && open === undefined) continue;
      devices.push({
        id: d.id,
        user_id: d.user_id,
        token: d.live_activity_push_to_start_token ?? null,
        time_zone: d.time_zone,
        apns_environment: d.apns_environment ?? null,
        delivery:
          open === undefined
            ? null
            : {
                id: open.id,
                shift_id: open.shift_id,
                status: open.status,
                update_token: open.update_token ?? null,
                start_sent_at: open.start_sent_at ?? null,
              },
      });
      if (people.has(d.user_id)) continue;
      const live = <T extends { deleted_at?: string }>(rows: T[]) => rows.filter((r) => r.deleted_at === undefined);
      const settings = await ctx.db
        .query("user_settings")
        .withIndex("by_user_revision", (q) => q.eq("user_id", d.user_id))
        .unique();
      people.set(d.user_id, {
        currency: settings?.currency,
        regular: live(
          await ctx.db
            .query("user_shifts")
            .withIndex("by_user_shift_date", (q) => q.eq("user_id", d.user_id).gte("shift_date", from).lte("shift_date", to))
            .collect(),
        ).map(asRegularShift),
        recurring: live(
          await ctx.db
            .query("recurring_shifts")
            .withIndex("by_user_revision", (q) => q.eq("user_id", d.user_id))
            .collect(),
        ).map(asRecurringShift),
        snapshots: live(
          await ctx.db
            .query("wage_snapshots")
            .withIndex("by_user_revision", (q) => q.eq("user_id", d.user_id))
            .collect(),
        ).map(asSnapshot),
      });
    }
    return {
      devices,
      people: Object.fromEntries(people) as Record<
        string,
        { currency?: string; regular: LiveActivityRegularShift[]; recurring: LiveActivityRecurringShift[]; snapshots: Snapshot[] }
      >,
    };
  },
});

async function deliveryById(ctx: { db: any }, id: string): Promise<Doc<"live_activity_deliveries"> | null> {
  return await ctx.db
    .query("live_activity_deliveries")
    .withIndex("by_uuid", (q: any) => q.eq("id", id))
    .unique();
}

/** claim_live_activity_start. Returns the delivery id, or null when another pass has it. */
export const claimStart = internalMutation({
  args: { push_device_id: v.string(), shift_id: v.string() },
  handler: async (ctx, { push_device_id, shift_id }) => {
    const device = await ctx.db
      .query("push_devices")
      .withIndex("by_uuid", (q) => q.eq("id", push_device_id))
      .unique();
    if (device?.live_activity_push_to_start_token === undefined) return null;
    const deliveries = await ctx.db
      .query("live_activity_deliveries")
      .withIndex("by_push_device_shift", (q) => q.eq("push_device_id", push_device_id))
      .collect();
    // One open activity per device, as the partial unique index required.
    if (deliveries.some((d) => d.shift_id !== shift_id && (OPEN as readonly string[]).includes(d.status))) return null;
    const now = new Date();
    const iso = now.toISOString();
    const existing = deliveries.find((d) => d.shift_id === shift_id);
    if (existing === undefined) {
      const id = crypto.randomUUID();
      await ctx.db.insert("live_activity_deliveries", {
        id,
        push_device_id,
        shift_id,
        status: "starting",
        claimed_at: iso,
        attempts: 1,
        created_at: iso,
        updated_at: iso,
      });
      return id;
    }
    const staleClaim =
      existing.claimed_at === undefined || Date.parse(existing.claimed_at) < now.getTime() - STALE_CLAIM_MS;
    const retryStart =
      existing.status === "starting" && existing.start_sent_at === undefined && existing.attempts < MAX_ATTEMPTS && staleClaim;
    // A failed start is retried once the device registers a new token.
    const retryFailed = existing.status === "failed" && device.updated_at > existing.updated_at;
    if (!retryStart && !retryFailed) return null;
    await ctx.db.patch(existing._id, {
      status: "starting",
      claimed_at: iso,
      attempts: existing.status === "failed" ? 1 : existing.attempts + 1,
      last_error: undefined,
      updated_at: iso,
    });
    return existing.id;
  },
});

export const completeStart = internalMutation({
  args: { delivery_id: v.string(), apns_environment: v.union(v.literal("production"), v.literal("sandbox")) },
  handler: async (ctx, { delivery_id, apns_environment }) => {
    const d = await deliveryById(ctx, delivery_id);
    if (d === null || d.status !== "starting" || d.start_sent_at !== undefined) return;
    const now = new Date().toISOString();
    await ctx.db.patch(d._id, { start_sent_at: now, claimed_at: undefined, last_error: undefined, updated_at: now });
    const device = await ctx.db
      .query("push_devices")
      .withIndex("by_uuid", (q) => q.eq("id", d.push_device_id))
      .unique();
    if (device !== null) await ctx.db.patch(device._id, { apns_environment, updated_at: now });
  },
});

export const failStart = internalMutation({
  args: { delivery_id: v.string(), error: v.string(), invalidate_token: v.boolean() },
  handler: async (ctx, { delivery_id, error, invalidate_token }) => {
    const d = await deliveryById(ctx, delivery_id);
    if (d === null || d.status !== "starting" || d.start_sent_at !== undefined) return;
    const now = new Date().toISOString();
    await ctx.db.patch(d._id, {
      status: invalidate_token || d.attempts >= MAX_ATTEMPTS ? "failed" : "starting",
      claimed_at: undefined,
      last_error: error.slice(0, 1000),
      updated_at: now,
    });
    if (!invalidate_token) return;
    const device = await ctx.db
      .query("push_devices")
      .withIndex("by_uuid", (q) => q.eq("id", d.push_device_id))
      .unique();
    if (device !== null) await ctx.db.patch(device._id, { live_activity_push_to_start_token: undefined, updated_at: now });
  },
});

/** The shift ended before ActivityKit accepted the start, so nothing is on screen to end. */
export const cancelStart = internalMutation({
  args: { delivery_id: v.string() },
  handler: async (ctx, { delivery_id }) => {
    const d = await deliveryById(ctx, delivery_id);
    if (d === null || d.status !== "starting" || d.start_sent_at !== undefined) return;
    await ctx.db.patch(d._id, {
      status: "failed",
      claimed_at: undefined,
      last_error: "Shift ended before Live Activity start was accepted",
      updated_at: new Date().toISOString(),
    });
  },
});

/** claim_live_activity_end */
export const claimEnd = internalMutation({
  args: { delivery_id: v.string() },
  handler: async (ctx, { delivery_id }) => {
    const d = await deliveryById(ctx, delivery_id);
    if (d === null || d.update_token === undefined || d.end_sent_at !== undefined) return false;
    const now = Date.now();
    const retry =
      d.status === "ending" &&
      d.attempts < MAX_ATTEMPTS &&
      (d.claimed_at === undefined || Date.parse(d.claimed_at) < now - STALE_CLAIM_MS);
    if (d.status !== "active" && !retry) return false;
    const iso = new Date(now).toISOString();
    await ctx.db.patch(d._id, {
      status: "ending",
      claimed_at: iso,
      attempts: d.status === "active" ? 1 : d.attempts + 1,
      updated_at: iso,
    });
    return true;
  },
});

export const completeEnd = internalMutation({
  args: { delivery_id: v.string() },
  handler: async (ctx, { delivery_id }) => {
    const d = await deliveryById(ctx, delivery_id);
    if (d === null || d.status !== "ending") return;
    const now = new Date().toISOString();
    await ctx.db.patch(d._id, {
      status: "ended",
      end_sent_at: d.end_sent_at ?? now,
      ended_at: d.ended_at ?? now,
      claimed_at: undefined,
      last_error: undefined,
      updated_at: now,
    });
  },
});

export const failEnd = internalMutation({
  args: { delivery_id: v.string(), error: v.string(), invalidate_token: v.boolean() },
  handler: async (ctx, { delivery_id, error, invalidate_token }) => {
    const d = await deliveryById(ctx, delivery_id);
    if (d === null || d.status !== "ending" || d.end_sent_at !== undefined) return;
    await ctx.db.patch(d._id, {
      status: invalidate_token || d.attempts >= MAX_ATTEMPTS ? "failed" : "ending",
      update_token: invalidate_token ? undefined : d.update_token,
      claimed_at: undefined,
      last_error: error.slice(0, 1000),
      updated_at: new Date().toISOString(),
    });
  },
});

// ---------- The pass ----------

/** One pass of process-live-activities. crons.ts runs it at :01, :16, :31 and :46. */
type Inputs = {
  devices: {
    id: string;
    user_id: string;
    token: string | null;
    time_zone: string;
    apns_environment: "production" | "sandbox" | null;
    delivery: { id: string; shift_id: string; status: string; update_token: string | null; start_sent_at: string | null } | null;
  }[];
  people: Record<string, { currency?: string; regular: LiveActivityRegularShift[]; recurring: LiveActivityRecurringShift[]; snapshots: Snapshot[] }>;
};

export const run = internalAction({
  args: {},
  handler: async (ctx): Promise<Record<string, unknown>> => {
    if (!apnsConfigured()) return { skipped: "APNs is not configured" };
    const allowed = allowedRecipients();
    if (allowed !== "all" && allowed.size === 0) return { skipped: "APNS_RECIPIENTS is not set" };
    const now = new Date();
    const inputs: Inputs = await ctx.runQuery(internal.liveActivities.inputs, {});
    const people = inputs.people;
    const devices = inputs.devices.filter((d) => mayPush(allowed, d.user_id));
    const summary = { devices: devices.length, started: 0, ended: 0, failed: 0, waitingForUpdateToken: 0 };
    const bundleId = process.env.APNS_BUNDLE_ID ?? "no.tidex.app";
    const headers = (expiration: Date, deviceId: string) =>
      buildLiveActivityHeaders({ bundleId, expiration, collapseId: `live-activity:${deviceId}`, now });

    let next = 0;
    const worker = async () => {
      while (next < devices.length) {
        const device = devices[next++]!;
        const person = people[device.user_id] ?? { regular: [], recurring: [], snapshots: [] };
        const ongoing = findOngoingShift(now, device.time_zone, person.regular, person.recurring);
        const delivery = device.delivery;

        if (delivery !== null && delivery.shift_id !== ongoing?.id) {
          if (delivery.update_token === null) {
            if (delivery.start_sent_at === null) {
              await ctx.runMutation(internal.liveActivities.cancelStart, { delivery_id: delivery.id });
            } else {
              summary.waitingForUpdateToken += 1;
            }
            continue;
          }
          if (!(await ctx.runMutation(internal.liveActivities.claimEnd, { delivery_id: delivery.id }))) continue;
          const projected = projectedRecurringShifts(person.recurring, [isoDateOffset(now, -1), isoDateOffset(now, 0)]);
          const ended = [...person.regular, ...projected].find((s) => s.id === delivery.shift_id);
          const presentation =
            ended === undefined
              ? fallbackEndPresentation(delivery.shift_id, now)
              : presentationForShift(ended, device.time_zone, person.currency, person.snapshots);
          const result = await sendToApns(
            delivery.update_token,
            buildLiveActivityEndPayload(presentation, now) as unknown as Record<string, unknown>,
            headers(new Date(now.getTime() + 5 * 60_000), device.id),
            device.apns_environment,
          ).catch(() => ({ success: false as const }));
          if (result.success) {
            await ctx.runMutation(internal.liveActivities.completeEnd, { delivery_id: delivery.id });
            summary.ended += 1;
          } else {
            await ctx.runMutation(internal.liveActivities.failEnd, {
              delivery_id: delivery.id,
              error: "APNs rejected Live Activity end",
              invalidate_token: "invalidToken" in result && result.invalidToken === true,
            });
            summary.failed += 1;
          }
          // An end must settle before the next activity starts, in a later pass.
          continue;
        }

        if (ongoing === null || ongoing === undefined) continue;
        if (delivery?.start_sent_at || delivery?.status === "active" || delivery?.status === "ending") continue;
        if (device.token === null) continue;
        const deliveryId = await ctx.runMutation(internal.liveActivities.claimStart, {
          push_device_id: device.id,
          shift_id: ongoing.id,
        });
        if (deliveryId === null) continue;
        const presentation = presentationForShift(ongoing, device.time_zone, person.currency, person.snapshots);
        const result = await sendToApns(
          device.token,
          buildLiveActivityStartPayload(presentation, now) as unknown as Record<string, unknown>,
          headers(presentation.endDate, device.id),
          device.apns_environment,
        ).catch(() => ({ success: false as const }));
        if (result.success && "environment" in result && result.environment !== undefined) {
          await ctx.runMutation(internal.liveActivities.completeStart, {
            delivery_id: deliveryId,
            apns_environment: result.environment,
          });
          summary.started += 1;
        } else {
          await ctx.runMutation(internal.liveActivities.failStart, {
            delivery_id: deliveryId,
            error: "APNs rejected Live Activity start",
            invalidate_token: "invalidToken" in result && result.invalidToken === true,
          });
          summary.failed += 1;
        }
      }
    };
    await Promise.all(Array.from({ length: Math.min(8, devices.length) }, worker));
    return summary;
  },
});
