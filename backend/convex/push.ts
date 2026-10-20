import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalAction, internalMutation, internalQuery, type QueryCtx } from "./_generated/server";
import { counterpartOf, pairBlocked } from "./lib/messaging";

// Port of the send-push-notifications edge function, APNs only. Every active device
// has an APNs token. The 13 FCM-only rows were last seen in January 2026, from app
// versions that used Firebase. This must run in the default Convex runtime: APNs
// needs HTTP/2, and fetch in the Node runtime can't speak it.

const BATCH_SIZE = 50;
const MAX_ATTEMPTS = 10;
const STALE_CLAIM_MS = 15 * 60_000;
const MAX_CONCURRENCY = 8;
const FETCH_TIMEOUT_MS = 15_000;

type Outbox = Doc<"notifications_outbox">;
type Payload = Record<string, unknown>;
type ApnsEnvironment = "production" | "sandbox";

// ---------- Claiming and recording (mutations) ----------

/** claim_outbox_notifications: resets stuck claims, then claims a batch of due rows. */
export const claim = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = new Date();
    const staleBefore = new Date(now.getTime() - STALE_CLAIM_MS).toISOString();
    for (const n of await ctx.db
      .query("notifications_outbox")
      .withIndex("by_status_due_at", (q) => q.eq("status", "sending"))
      .collect()) {
      if (n.claimed_at === undefined || n.claimed_at >= staleBefore) continue;
      const gaveUp = n.attempts >= MAX_ATTEMPTS;
      await ctx.db.patch(n._id, {
        status: gaveUp ? "failed" : "pending",
        claimed_at: undefined,
        attempts: n.attempts + 1,
        error_message: gaveUp ? "Max retry attempts exceeded" : n.error_message,
      });
    }
    const due = await ctx.db
      .query("notifications_outbox")
      .withIndex("by_status_due_at", (q) => q.eq("status", "pending").lte("due_at", now.toISOString()))
      .take(BATCH_SIZE * 2);
    const claimed = due.filter((n) => n.attempts < MAX_ATTEMPTS).slice(0, BATCH_SIZE);
    for (const n of claimed) {
      await ctx.db.patch(n._id, { status: "sending", claimed_at: now.toISOString() });
    }
    return claimed.map((n) => ({ ...n, status: "sending" as const, claimed_at: now.toISOString() }));
  },
});

/** The claimed rows still in "sending". A newer message can supersede a typing push. */
export const stillSending = internalQuery({
  args: { ids: v.array(v.string()) },
  handler: async (ctx, { ids }) => {
    const rows = await Promise.all(
      ids.map((id) =>
        ctx.db
          .query("notifications_outbox")
          .withIndex("by_uuid", (q) => q.eq("id", id))
          .unique(),
      ),
    );
    return rows.filter((n): n is Outbox => n !== null && n.status === "sending");
  },
});

async function unreadDirectCount(ctx: QueryCtx, userId: string) {
  let total = 0;
  for (const m of await ctx.db
    .query("thread_memberships")
    .withIndex("by_user_revision", (q) => q.eq("user_id", userId))
    .collect()) {
    if (m.status !== "active") continue;
    const thread = await ctx.db
      .query("threads")
      .withIndex("by_uuid", (q) => q.eq("id", m.thread_id))
      .unique();
    if (thread?.kind !== "direct") continue;
    const other = await counterpartOf(ctx, m.thread_id, userId);
    if (other !== null && (await pairBlocked(ctx, userId, other))) continue;
    const state = await ctx.db
      .query("thread_user_state")
      .withIndex("by_thread_user", (q) => q.eq("thread_id", m.thread_id).eq("user_id", userId))
      .unique();
    total += state?.unread_count ?? 0;
  }
  return total;
}

/** Devices and badge counts for the recipients of a batch. */
export const recipients = internalQuery({
  args: { user_ids: v.array(v.string()) },
  handler: async (ctx, { user_ids }) => {
    return await Promise.all(
      [...new Set(user_ids)].map(async (userId) => ({
        user_id: userId,
        badge: await unreadDirectCount(ctx, userId),
        devices: (
          await ctx.db
            .query("push_devices")
            .withIndex("by_user", (q) => q.eq("user_id", userId))
            .collect()
        ).map((d) => ({
          id: d.id,
          apns_token: d.apns_token ?? null,
          apns_environment: d.apns_environment ?? null,
        })),
      })),
    );
  },
});

const statusUpdate = v.object({
  ids: v.array(v.string()),
  status: v.union(v.literal("sent"), v.literal("failed"), v.literal("skipped"), v.literal("pending")),
  attempts: v.optional(v.number()),
  error_message: v.optional(v.string()),
});

/** Records a batch's results, clears dead tokens and finishes admin broadcasts. */
export const record = internalMutation({
  args: {
    updates: v.array(statusUpdate),
    dead_token_device_ids: v.array(v.string()),
    environments: v.array(v.object({ device_id: v.string(), environment: v.union(v.literal("production"), v.literal("sandbox")) })),
  },
  handler: async (ctx, args) => {
    const now = new Date().toISOString();
    const broadcasts = new Set<string>();
    for (const u of args.updates) {
      for (const id of u.ids) {
        const n = await ctx.db
          .query("notifications_outbox")
          .withIndex("by_uuid", (q) => q.eq("id", id))
          .unique();
        if (n === null) continue;
        if (n.broadcast_id !== undefined) broadcasts.add(n.broadcast_id);
        await ctx.db.patch(n._id, {
          status: u.status,
          attempts: u.attempts ?? n.attempts,
          error_message: u.error_message,
          ...(u.status === "pending" ? { claimed_at: undefined } : { processed_at: now }),
          updated_at: now,
        });
      }
    }
    const device = (id: string) =>
      ctx.db
        .query("push_devices")
        .withIndex("by_uuid", (q) => q.eq("id", id))
        .unique();
    for (const id of args.dead_token_device_ids) {
      const d = await device(id);
      if (d !== null) await ctx.db.patch(d._id, { apns_token: undefined });
    }
    for (const { device_id, environment } of args.environments) {
      const d = await device(device_id);
      if (d !== null && d.apns_environment !== environment) await ctx.db.patch(d._id, { apns_environment: environment });
    }
    for (const broadcastId of broadcasts) {
      const open = (
        await ctx.db
          .query("notifications_outbox")
          .withIndex("by_broadcast", (q) => q.eq("broadcast_id", broadcastId))
          .collect()
      ).some((n) => n.status === "pending" || n.status === "sending");
      if (open) continue;
      const b = await ctx.db
        .query("admin_broadcasts")
        .withIndex("by_uuid", (q) => q.eq("id", broadcastId))
        .unique();
      if (b?.status === "queued") await ctx.db.patch(b._id, { status: "complete" });
    }
  },
});

/** Whether due rows are still waiting, so a full batch can schedule the next run. */
export const hasDue = internalQuery({
  args: {},
  handler: async (ctx) =>
    (await ctx.db
      .query("notifications_outbox")
      .withIndex("by_status_due_at", (q) => q.eq("status", "pending").lte("due_at", new Date().toISOString()))
      .first()) !== null,
});

// ---------- Payloads (pure, from the edge function) ----------

const richFormattingTypes = new Set(["thread_message", "thread_typing", "thread_reaction", "thread_screenshot", "shifts_screenshotted"]);
const messagePrefetchTypes = new Set(["thread_message", "thread_reaction", "thread_screenshot"]);

const str = (value: unknown) => (typeof value === "string" && value.trim() !== "" ? value.trim() : null);
const data = (n: Outbox) => (n.data_payload ?? {}) as Payload;

function messageCount(n: Outbox) {
  const raw = data(n).message_count;
  const count = typeof raw === "number" ? raw : typeof raw === "string" ? Number.parseInt(raw, 10) : Number.NaN;
  return Number.isFinite(count) && count > 0 ? Math.floor(count) : 1;
}

function threadIdOf(n: Outbox) {
  return ["thread_message", "thread_typing", "thread_reaction"].includes(n.notification_type)
    ? str(data(n).thread_id)
    : null;
}

const ownerIdOf = (n: Outbox) => str(n.owner_id) ?? str(data(n).owner_id);

function collapseId(n: Outbox) {
  if (n.notification_type === "shared_shift_added") {
    const owner = ownerIdOf(n);
    return owner === null ? null : `shared-shift:${owner}`;
  }
  const thread = threadIdOf(n);
  if (thread === null) return null;
  if (n.notification_type === "thread_typing") return `thread-typing:${thread}`;
  if (n.notification_type === "thread_reaction") return `thread-reaction:${thread}`;
  if (n.notification_type !== "thread_message" || messageCount(n) < 4) return null;
  return `thread-message:${thread}`;
}

const newer = (a: Outbox, b: Outbox) => a.created_at > b.created_at || (a.created_at === b.created_at && a.id > b.id);

type Job = { rows: Outbox[]; notification: Outbox };

/** Rows for the same recipient, type and thread go out as one push, the newest. */
export function coalesce(rows: Outbox[]): Job[] {
  const jobs = new Map<string, Job>();
  for (const n of rows) {
    const thread = threadIdOf(n);
    const key = thread === null ? n.id : `${n.notification_type}:${n.recipient_id}:${thread}`;
    const job = jobs.get(key);
    if (job === undefined) jobs.set(key, { rows: [n], notification: n });
    else {
      job.rows.push(n);
      if (newer(n, job.notification)) job.notification = n;
    }
  }
  return [...jobs.values()].map((job) => {
    if (job.rows.length === 1 || job.notification.notification_type !== "thread_message") return job;
    const count = Math.max(...job.rows.map(messageCount));
    return { rows: job.rows, notification: { ...job.notification, data_payload: { ...data(job.notification), message_count: count } } };
  });
}

function apsPayload(n: Outbox, badge: number): Payload {
  const aps: Payload = { alert: { title: n.title, body: n.body }, badge: Math.max(0, badge) };
  if (n.notification_type !== "shared_shift_added") aps.sound = "tidex_notification.caf";
  if (richFormattingTypes.has(n.notification_type)) aps["mutable-content"] = 1;
  const thread = threadIdOf(n);
  if (thread !== null) {
    if (n.notification_type === "thread_message") aps.category = "THREAD_MESSAGE";
    aps["thread-id"] = thread;
    aps["target-content-id"] = `friend-chat:${thread}`;
    aps["interruption-level"] = "active";
    aps["relevance-score"] =
      n.notification_type === "thread_typing"
        ? 0.8
        : n.notification_type === "thread_reaction"
          ? 0.85
          : messageCount(n) > 1
            ? 0.95
            : 0.9;
    return aps;
  }
  const group = (id: string, score: number) => {
    aps["thread-id"] = id;
    aps["target-content-id"] = id;
    aps["interruption-level"] = "active";
    aps["relevance-score"] = score;
  };
  switch (n.notification_type) {
    case "shared_shift_added": {
      const owner = ownerIdOf(n);
      aps["thread-id"] = owner === null ? "shared-shifts" : `shared-shifts:${owner}`;
      aps["target-content-id"] = owner === null ? "shared-calendar" : `shared-calendar:${owner}`;
      aps["interruption-level"] = "active";
      aps["relevance-score"] = 0.7;
      break;
    }
    case "share_started":
      group("sharing", 0.65);
      break;
    case "feedback_responded":
      group("feedback", 0.55);
      break;
    case "feedback_submitted":
      group("admin-feedback", 0.55);
      break;
    case "abuse_report_submitted":
      group("admin-reports", 0.7);
      break;
    default:
      group(n.notification_type, 0.5);
  }
  return aps;
}

function apnsHeaders(n: Outbox): Record<string, string> {
  const headers: Record<string, string> = { "apns-push-type": "alert", "apns-priority": "10" };
  const id = collapseId(n);
  if (id !== null) headers["apns-collapse-id"] = id;
  const seconds = Math.floor(Date.now() / 1000);
  if (n.notification_type === "thread_typing") headers["apns-expiration"] = String(seconds + 60);
  if (n.notification_type === "shared_shift_added") headers["apns-expiration"] = String(seconds + 86_400);
  return headers;
}

function alertPayload(n: Outbox, badge: number): Payload {
  const visible = Object.fromEntries(Object.entries(data(n)).filter(([k]) => !k.startsWith("_internal_")));
  return { aps: apsPayload(n, badge), type: n.notification_type, ...visible };
}

/** The silent push that lets the app fetch a chat message before the user opens it. */
function prefetch(n: Outbox): { payload: Payload; headers: Record<string, string> } | null {
  if (!messagePrefetchTypes.has(n.notification_type)) return null;
  const thread = str(data(n).thread_id);
  const message = str(data(n).message_id);
  if (thread === null || message === null) return null;
  const payload: Payload = { aps: { "content-available": 1 }, delivery_mode: "prefetch", type: n.notification_type, thread_id: thread, message_id: message };
  const senderId = str(data(n).sender_user_id);
  if (senderId !== null) payload.sender_user_id = senderId;
  const createdAt = str(data(n).message_created_at);
  if (createdAt !== null) payload.message_created_at = createdAt;
  return { payload, headers: { "apns-push-type": "background", "apns-priority": "5", "apns-collapse-id": `friend-prefetch:${thread}` } };
}

/**
 * Only 410 and the token-specific 400 reasons prove a token is dead. A token from the
 * other APNs environment also reads as BadDeviceToken, so that only counts on the last
 * environment tried.
 */
export function classifyApnsFailure(status: number, body: string, lastEnvironment: boolean) {
  let reason: unknown = null;
  try {
    reason = JSON.parse(body)?.reason ?? null;
  } catch {
    // APNs sends JSON, but a proxy error page may not be.
  }
  if (reason === "BadDeviceToken" && !lastEnvironment) return "try_next_environment" as const;
  if (status === 410 || (status === 400 && (reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic"))) {
    return "invalid_token" as const;
  }
  if (status === 429 || status >= 500) return "retryable" as const;
  return "failed" as const;
}

// ---------- APNs ----------

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

function pkcs8(pem: string) {
  const base64 = pem.replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "").replace(/\s/g, "");
  return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
}

const apnsTokens = new Map<ApnsEnvironment, { token: string; expiresAt: number }>();

function apnsCredentials(environment: ApnsEnvironment) {
  const pem = (name: string) => (process.env[name] ?? "").replace(/\\n/g, "\n");
  const sandboxKeyId = process.env.APNS_SANDBOX_KEY_ID ?? "";
  const sandboxKey = pem("APNS_SANDBOX_PRIVATE_KEY");
  return environment === "sandbox" && sandboxKeyId && sandboxKey
    ? { keyId: sandboxKeyId, privateKey: sandboxKey }
    : { keyId: process.env.APNS_KEY_ID ?? "", privateKey: pem("APNS_PRIVATE_KEY") };
}

const apnsConfigured = () => Boolean(process.env.APNS_KEY_ID && process.env.APNS_TEAM_ID && process.env.APNS_PRIVATE_KEY);
const sandboxConfigured = () => Boolean(process.env.APNS_SANDBOX_KEY_ID && process.env.APNS_SANDBOX_PRIVATE_KEY);

/** An ES256 provider token. Web Crypto returns the raw r||s signature APNs expects. */
async function apnsToken(environment: ApnsEnvironment) {
  const cached = apnsTokens.get(environment);
  if (cached !== undefined && Date.now() < cached.expiresAt - 300_000) return cached.token;
  const { keyId, privateKey } = apnsCredentials(environment);
  const encode = (o: object) => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const input = `${encode({ alg: "ES256", typ: "JWT", kid: keyId })}.${encode({ iss: process.env.APNS_TEAM_ID, iat: Math.floor(Date.now() / 1000) })}`;
  const key = await crypto.subtle.importKey("pkcs8", pkcs8(privateKey), { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const signature = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input)));
  if (signature.length !== 64) throw new Error(`Unexpected ECDSA signature length ${signature.length}`);
  const token = `${input}.${b64url(signature)}`;
  apnsTokens.set(environment, { token, expiresAt: Date.now() + 3_600_000 });
  return token;
}

type SendResult = { success: boolean; invalidToken?: boolean; retryable?: boolean; environment?: ApnsEnvironment };

/** Tries the device's known environment first, then the other one. */
async function sendToApns(
  deviceToken: string,
  payload: Payload,
  headers: Record<string, string>,
  preferred: ApnsEnvironment | null,
): Promise<SendResult> {
  const order: ApnsEnvironment[] = preferred === "sandbox" ? ["sandbox", "production"] : ["production", "sandbox"];
  const environments = order.filter((e) => e === "production" || sandboxConfigured());
  for (const [index, environment] of environments.entries()) {
    const host = environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
    const response = await fetch(`https://${host}/3/device/${deviceToken}`, {
      method: "POST",
      headers: {
        Authorization: `bearer ${await apnsToken(environment)}`,
        "apns-topic": process.env.APNS_BUNDLE_ID ?? "no.tidex.app",
        ...headers,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    });
    if (response.ok) return { success: true, environment };
    const body = await response.text();
    console.error(`APNs ${response.status} via ${host} for token ${deviceToken.slice(0, 20)}...: ${body}`);
    const outcome = classifyApnsFailure(response.status, body, index === environments.length - 1);
    if (outcome === "try_next_environment") continue;
    return { success: false, invalidToken: outcome === "invalid_token", retryable: outcome === "retryable" };
  }
  return { success: false };
}

// ---------- The run ----------

/** One sender pass. Queueing schedules it, and crons.ts runs it every minute as well. */
export const run = internalAction({
  args: {},
  handler: async (ctx) => {
    if (!apnsConfigured()) return { skipped: "APNs is not configured" };
    const claimed: Outbox[] = await ctx.runMutation(internal.push.claim, {});
    if (claimed.length === 0) return { processed: 0 };
    const jobs = coalesce(claimed);
    const people = new Map(
      (await ctx.runQuery(internal.push.recipients, { user_ids: jobs.map((j) => j.notification.recipient_id) })).map(
        (r) => [r.user_id, r] as const,
      ),
    );

    const updates: { ids: string[]; status: "sent" | "failed" | "skipped" | "pending"; attempts?: number; error_message?: string }[] = [];
    const deadTokens: string[] = [];
    const environments: { device_id: string; environment: ApnsEnvironment }[] = [];
    const retryOrFail = (rows: Outbox[], error: string) => {
      const attempts = Math.max(0, ...rows.map((r) => r.attempts)) + 1;
      return attempts >= MAX_ATTEMPTS
        ? { ids: rows.map((r) => r.id), status: "failed" as const, attempts, error_message: error }
        : { ids: rows.map((r) => r.id), status: "pending" as const, attempts, error_message: error };
    };

    let next = 0;
    const worker = async () => {
      while (next < jobs.length) {
        const job = jobs[next++]!;
        try {
          const fresh: Outbox[] = await ctx.runQuery(internal.push.stillSending, { ids: job.rows.map((r) => r.id) });
          const current = coalesce(fresh)[0];
          if (current === undefined) continue;
          const ids = current.rows.map((r) => r.id);
          const n = current.notification;
          const internalChanges = data(n)._internal_changes;
          if (n.notification_type === "shared_shift_added" && Array.isArray(internalChanges) && internalChanges.length === 0) {
            updates.push({ ids, status: "skipped", error_message: "No shared shift additions remained before delivery" });
            continue;
          }
          const person = people.get(n.recipient_id);
          const devices = person?.devices ?? [];
          if (devices.length === 0) {
            updates.push({ ids, status: "skipped" });
            continue;
          }
          const results = await Promise.all(
            devices.map(async (device) => {
              if (device.apns_token === null) return { success: false } as SendResult;
              const result = await sendToApns(device.apns_token, alertPayload(n, person!.badge), apnsHeaders(n), device.apns_environment);
              if (result.invalidToken) deadTokens.push(device.id);
              if (result.environment !== undefined) environments.push({ device_id: device.id, environment: result.environment });
              const silent = result.success ? prefetch(n) : null;
              if (silent !== null) {
                const prefetched = await sendToApns(device.apns_token, silent.payload, silent.headers, result.environment ?? device.apns_environment);
                if (!prefetched.success) console.warn(`[Push] Prefetch failed for ${n.id} on device ${device.id}`);
              }
              return result;
            }),
          );
          if (results.some((r) => r.success)) updates.push({ ids, status: "sent" });
          else if (results.some((r) => r.retryable)) updates.push(retryOrFail(current.rows, "All devices failed, retrying"));
          else updates.push({ ids, status: "failed", error_message: "All devices failed" });
        } catch (error) {
          console.error(`Error processing notification ${job.notification.id}:`, error);
          updates.push(retryOrFail(job.rows, error instanceof Error ? error.message : "Unknown error"));
        }
      }
    };
    await Promise.all(Array.from({ length: Math.min(MAX_CONCURRENCY, jobs.length) }, worker));

    await ctx.runMutation(internal.push.record, { updates, dead_token_device_ids: deadTokens, environments });
    if (claimed.length === BATCH_SIZE && (await ctx.runQuery(internal.push.hasDue, {}))) {
      await ctx.scheduler.runAfter(0, internal.push.run, {});
    }
    return { claimed: claimed.length, jobs: jobs.length };
  },
});
