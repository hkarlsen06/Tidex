// deno-lint-ignore no-import-prefix
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  buildLiveActivityEndPayload,
  buildLiveActivityHeaders,
  buildLiveActivityStartPayload,
  type LiveActivityPresentationInput,
} from "./live-activity-payload.ts";
import {
  findOngoingShift,
  type LiveActivityRecurringShift,
  type LiveActivityRegularShift,
  projectedRecurringShifts,
  zonedShiftRange,
} from "./live-activity-scheduling.ts";
import { computeShift } from "./wagey/payroll/calc.ts";
import type { UserSettings, WageSnapshot } from "./wagey/payroll/types.ts";

type ApnsEnvironment = "production" | "sandbox";

interface LiveActivityDevice {
  id: string;
  user_id: string;
  live_activity_push_to_start_token: string | null;
  time_zone: string;
  apns_environment: ApnsEnvironment | null;
}

interface LiveActivityDelivery {
  id: string;
  push_device_id: string;
  shift_id: string;
  status: "starting" | "active" | "ending";
  update_token: string | null;
  start_sent_at: string | null;
}

interface UserSettingsRow extends UserSettings {
  user_id: string;
}

interface WageSnapshotRow extends WageSnapshot {
  user_id: string;
  job_id: string | null;
}

export interface LiveActivitySendResult {
  success: boolean;
  invalidToken?: boolean;
  environment?: ApnsEnvironment;
}

export type LiveActivitySender = (
  token: string,
  payload: Record<string, unknown>,
  headers: Record<string, string>,
  preferredEnvironment: ApnsEnvironment | null,
) => Promise<LiveActivitySendResult>;

export interface LiveActivityProcessingSummary {
  devices: number;
  started: number;
  ended: number;
  failed: number;
  waitingForUpdateToken: number;
}

function numberValue(value: unknown, fallback = 0): number {
  const parsed = typeof value === "number" ? value : Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function applicableWageSnapshot(
  shift: LiveActivityRegularShift,
  snapshots: WageSnapshotRow[],
): WageSnapshotRow | null {
  const jobScoped = snapshots.filter((snapshot) =>
    snapshot.user_id === shift.user_id && snapshot.job_id === shift.job_id
  );
  const scoped = jobScoped.length > 0
    ? jobScoped
    : snapshots.filter((snapshot) =>
      snapshot.user_id === shift.user_id && snapshot.job_id === null
    );
  const baseline = scoped.find((snapshot) => snapshot.from_date === null) ??
    null;
  return scoped.filter((snapshot) =>
    snapshot.from_date !== null && snapshot.from_date <= shift.shift_date
  ).sort((lhs, rhs) =>
    (rhs.from_date ?? "").localeCompare(lhs.from_date ?? "")
  )[0] ?? baseline;
}

function normalizedSnapshot(row: WageSnapshotRow | null): WageSnapshot | null {
  if (!row) return null;
  return {
    ...row,
    hourly_wage: numberValue(row.hourly_wage),
    wage_level: row.wage_level === null ? null : numberValue(row.wage_level),
    tax_percentage: numberValue(row.tax_percentage),
    break_threshold_hours: numberValue(row.break_threshold_hours, 5.5),
    break_deduction_minutes: numberValue(row.break_deduction_minutes, 30),
  };
}

export function presentationForShift(
  shift: LiveActivityRegularShift,
  timeZone: string,
  settings: UserSettingsRow | null,
  snapshots: WageSnapshotRow[],
): LiveActivityPresentationInput {
  const snapshot = normalizedSnapshot(applicableWageSnapshot(shift, snapshots));
  const computed = computeShift(shift, settings ?? {}, [], snapshot, null);
  const hourly = computed.paidHours > 0
    ? computed.basePay / computed.paidHours
    : numberValue(snapshot?.hourly_wage);
  const supplement = computed.paidHours > 0
    ? computed.supplementPay / computed.paidHours
    : 0;
  const net = snapshot?.tax_enabled
    ? computed.gross * (1 - numberValue(snapshot.tax_percentage) / 100)
    : null;
  const range = zonedShiftRange(shift, timeZone);
  return {
    shiftId: shift.id,
    date: shift.shift_date,
    start: shift.start_time.slice(0, 5),
    end: shift.end_time.slice(0, 5),
    hourly,
    supplement,
    gross: computed.gross,
    net,
    currency: settings?.currency ?? "kr",
    startDate: range.startDate,
    endDate: range.endDate,
  };
}

function fallbackEndPresentation(
  shiftId: string,
  now: Date,
): LiveActivityPresentationInput {
  return {
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
  };
}

function assertNoError(result: { error?: unknown }, operation: string): void {
  if (result.error) {
    const message = typeof result.error === "object" && result.error !== null &&
        "message" in result.error
      ? String((result.error as { message: unknown }).message)
      : String(result.error);
    throw new Error(`${operation}: ${message}`);
  }
}

function isoDateOffset(date: Date, days: number): string {
  const shifted = new Date(date);
  shifted.setUTCDate(shifted.getUTCDate() + days);
  return shifted.toISOString().slice(0, 10);
}

async function fetchLiveActivityInputs(supabase: SupabaseClient, now: Date) {
  const devicesResult = await supabase.schema("internal").from("push_devices")
    .select(
      "id, user_id, live_activity_push_to_start_token, time_zone, apns_environment",
    )
    .eq("platform", "ios");
  assertNoError(devicesResult, "fetch live activity devices");
  const devices = (devicesResult.data ?? []) as LiveActivityDevice[];
  if (devices.length === 0) {
    return {
      devices,
      deliveries: [],
      regular: [],
      recurring: [],
      snapshots: [],
      settings: [],
    };
  }

  const deviceIds = devices.map((device) => device.id);
  const userIds = Array.from(new Set(devices.map((device) => device.user_id)));
  const startDate = isoDateOffset(now, -2);
  const endDate = isoDateOffset(now, 2);
  const [
    deliveriesResult,
    regularResult,
    recurringResult,
    snapshotsResult,
    settingsResult,
  ] = await Promise.all([
    supabase.schema("internal").from("live_activity_deliveries")
      .select(
        "id, push_device_id, shift_id, status, update_token, start_sent_at",
      )
      .in("push_device_id", deviceIds)
      .in("status", ["starting", "active", "ending"]),
    supabase.from("user_shifts")
      .select(
        "id, user_id, job_id, shift_date, start_time, end_time, custom_pause_windows, custom_supplements",
      )
      .in("user_id", userIds)
      .is("deleted_at", null)
      .gte("shift_date", startDate)
      .lte("shift_date", endDate),
    supabase.from("recurring_shifts")
      .select(
        "id, user_id, job_id, start_time, end_time, repeat_interval_weeks, selected_days, end_condition, exclusions, date_specific_pause_windows, date_specific_supplements",
      )
      .in("user_id", userIds)
      .is("deleted_at", null),
    supabase.from("wage_snapshots").select("*")
      .in("user_id", userIds)
      .is("deleted_at", null),
    supabase.from("user_settings").select("user_id, currency").in(
      "user_id",
      userIds,
    ),
  ]);
  assertNoError(deliveriesResult, "fetch live activity deliveries");
  assertNoError(regularResult, "fetch live activity shifts");
  assertNoError(recurringResult, "fetch recurring live activity shifts");
  assertNoError(snapshotsResult, "fetch live activity wage snapshots");
  assertNoError(settingsResult, "fetch live activity settings");

  return {
    devices,
    deliveries: (deliveriesResult.data ?? []) as LiveActivityDelivery[],
    regular: (regularResult.data ?? []) as LiveActivityRegularShift[],
    recurring: (recurringResult.data ?? []) as LiveActivityRecurringShift[],
    snapshots: (snapshotsResult.data ?? []) as WageSnapshotRow[],
    settings: (settingsResult.data ?? []) as UserSettingsRow[],
  };
}

async function rpc(
  supabase: SupabaseClient,
  name: string,
  params: Record<string, unknown>,
) {
  const result = await supabase.schema("internal").rpc(name, params);
  assertNoError(result, name);
  return result.data;
}

export async function processLiveActivityTransitions(
  supabase: SupabaseClient,
  send: LiveActivitySender,
  bundleId: string,
  now: Date = new Date(),
): Promise<LiveActivityProcessingSummary> {
  const inputs = await fetchLiveActivityInputs(supabase, now);
  const summary: LiveActivityProcessingSummary = {
    devices: inputs.devices.length,
    started: 0,
    ended: 0,
    failed: 0,
    waitingForUpdateToken: 0,
  };
  const deliveriesByDevice = new Map(
    inputs.deliveries.map((delivery) => [delivery.push_device_id, delivery]),
  );

  let nextDeviceIndex = 0;
  const concurrency = Math.min(8, inputs.devices.length);
  await Promise.all(Array.from({ length: concurrency }, async () => {
    while (true) {
      const deviceIndex = nextDeviceIndex;
      nextDeviceIndex += 1;
      if (deviceIndex >= inputs.devices.length) return;
      const device = inputs.devices[deviceIndex];
      const regular = inputs.regular.filter((shift) =>
        shift.user_id === device.user_id
      );
      const recurring = inputs.recurring.filter((shift) =>
        shift.user_id === device.user_id
      );
      const ongoing = findOngoingShift(
        now,
        device.time_zone,
        regular,
        recurring,
      );
      const delivery = deliveriesByDevice.get(device.id) ?? null;
      const settings = inputs.settings.find((row) =>
        row.user_id === device.user_id
      ) ?? null;

    if (delivery && delivery.shift_id !== ongoing?.id) {
      if (!delivery.update_token) {
        if (!delivery.start_sent_at) {
          const obsoleteResult = await supabase.schema("internal")
            .from("live_activity_deliveries")
            .update({
              status: "failed",
              claimed_at: null,
              last_error: "Shift ended before Live Activity start was accepted",
              updated_at: now.toISOString(),
            })
            .eq("id", delivery.id)
            .eq("status", "starting")
            .is("start_sent_at", null);
          assertNoError(obsoleteResult, "cancel obsolete live activity start");
          continue;
        }
        summary.waitingForUpdateToken += 1;
        continue;
      }
        const claimed = await rpc(supabase, "claim_live_activity_end", {
          p_delivery_id: delivery.id,
        });
        if (claimed !== true) continue;

        const projected = projectedRecurringShifts(recurring, [
          isoDateOffset(now, -1),
          isoDateOffset(now, 0),
        ]);
        const endedShift = [...regular, ...projected]
          .find((shift) => shift.id === delivery.shift_id);
        const presentation = endedShift
          ? presentationForShift(
            endedShift,
            device.time_zone,
            settings,
            inputs.snapshots,
          )
          : fallbackEndPresentation(delivery.shift_id, now);
        const result = await send(
          delivery.update_token,
          buildLiveActivityEndPayload(presentation, now) as unknown as Record<
            string,
            unknown
          >,
          buildLiveActivityHeaders({
            bundleId,
            expiration: new Date(now.getTime() + 5 * 60_000),
            collapseId: `live-activity:${device.id}`,
            now,
          }),
          device.apns_environment,
        );
        if (result.success) {
          await rpc(supabase, "complete_live_activity_end", {
            p_delivery_id: delivery.id,
          });
          summary.ended += 1;
        } else {
          await rpc(supabase, "fail_live_activity_end", {
            p_delivery_id: delivery.id,
            p_error: "APNs rejected Live Activity end",
            p_invalidate_token: result.invalidToken === true,
          });
          summary.failed += 1;
        }
        // Never replace an activity in the same cron pass; its end must settle first.
        continue;
      }

      if (!ongoing) continue;
      if (
        delivery?.start_sent_at || delivery?.status === "active" ||
        delivery?.status === "ending"
      ) {
        continue;
      }
      if (!device.live_activity_push_to_start_token) continue;

      const deliveryId = await rpc(supabase, "claim_live_activity_start", {
        p_push_device_id: device.id,
        p_shift_id: ongoing.id,
      });
      if (typeof deliveryId !== "string") continue;
      const presentation = presentationForShift(
        ongoing,
        device.time_zone,
        settings,
        inputs.snapshots,
      );
      const result = await send(
        device.live_activity_push_to_start_token,
        buildLiveActivityStartPayload(presentation, now) as unknown as Record<
          string,
          unknown
        >,
        buildLiveActivityHeaders({
          bundleId,
          expiration: presentation.endDate,
          collapseId: `live-activity:${device.id}`,
          now,
        }),
        device.apns_environment,
      );
      if (result.success && result.environment) {
        await rpc(supabase, "complete_live_activity_start", {
          p_delivery_id: deliveryId,
          p_apns_environment: result.environment,
        });
        summary.started += 1;
      } else {
        await rpc(supabase, "fail_live_activity_start", {
          p_delivery_id: deliveryId,
          p_error: "APNs rejected Live Activity start",
          p_invalidate_token: result.invalidToken === true,
        });
        summary.failed += 1;
      }
    }
  }));

  return summary;
}
