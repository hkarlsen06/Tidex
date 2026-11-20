import { ConvexError, type Value, v } from "convex/values";
import type { JSONWebKeySet } from "jose";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { type ActionCtx, httpAction, internalMutation, internalQuery, type QueryCtx } from "./_generated/server";
import { userByClerkId, userByUuid } from "./lib/auth";
import { shiftEarnings } from "./lib/mcp/earnings";
import { handleMcpPost, resourceMetadata, type ToolOutcome } from "./lib/mcp/protocol";
import { addDays, clockTime, endsNextDay, movedTimes, shiftTimes, storedEndTime, ToolError } from "./lib/mcp/shiftTimes";
import { type KeySource, verifyAccessToken } from "./lib/mcp/token";
import { isWriteTool, parseArgs, type ToolName } from "./lib/mcp/tools";
import { PAYROLL_REVISION } from "./lib/payrollCompatibility";
import { scheduleTimeZone } from "./lib/scheduleTimeZone";
import { overtimeWeekStart } from "./lib/shared/liveActivityPay";
import { projectedRecurringShifts } from "./lib/shared/liveActivityScheduling";
import { applicableWageSnapshot, asRecurringShift, asRegularShift, asSnapshot } from "./liveActivities";
import { shiftWrites } from "./userShifts";

// The MCP server: lets a user's AI agent read and change their shifts. See
// docs/mcp-server.md. The HTTP action checks the OAuth token and the arguments, then
// runs these internal functions for the user the token names. None of them is public.

const KEYS_FRESH_MS = 60 * 60_000;
// Clerk's keys are fetched at most this often, failed attempts included, so junk tokens
// naming unknown keys can't make every request reach Clerk.
const KEY_FETCH_COOLDOWN_MS = 60_000;
const WINDOW_MS = 10 * 60_000;
const MAX_CALLS = 120;
const MAX_WRITES = 40;

/** A message the agent sees as the tool's result. */
function fail(message: string): never {
  throw new ConvexError({ code: "tool_error", message });
}

/** Runs a shift-time helper, turning its ToolError into a message the agent sees. */
function checked<T>(run: () => T): T {
  try {
    return run();
  } catch (error) {
    if (error instanceof ToolError) fail(error.message);
    throw error;
  }
}

const live = <T extends { deleted_at?: string }>(rows: T[]) => rows.filter((r) => r.deleted_at === undefined);

async function jobsOf(ctx: QueryCtx, userId: string) {
  return live(await ctx.db.query("jobs").withIndex("by_user_revision", (q) => q.eq("user_id", userId)).collect());
}

/** Jobs with a base wage snapshot, which the app requires before it adds shifts. */
async function jobsWithPay(ctx: QueryCtx, userId: string) {
  const snapshots = live(
    await ctx.db.query("wage_snapshots").withIndex("by_user_revision", (q) => q.eq("user_id", userId)).collect(),
  );
  return new Set(snapshots.filter((s) => s.from_date === undefined).map((s) => s.job_id));
}

const activeJobs = (jobs: Doc<"jobs">[]) =>
  jobs.filter((j) => j.archived_at === undefined).sort((a, b) => a.sort_order - b.sort_order || a.name.localeCompare(b.name));

type ShiftFields = Pick<Doc<"user_shifts">, "id" | "revision" | "shift_date" | "start_time" | "end_time" | "job_id" | "note">;

function oneOff(shift: ShiftFields, jobs: Doc<"jobs">[]) {
  return {
    kind: "one_off" as const,
    shift_id: shift.id,
    revision: shift.revision,
    date: shift.shift_date,
    start: clockTime(shift.start_time),
    end: clockTime(shift.end_time),
    ends_next_day: endsNextDay(shift.start_time, shift.end_time),
    job_id: shift.job_id,
    job_name: jobs.find((j) => j.id === shift.job_id)?.name ?? null,
    note: shift.note ?? null,
  };
}

/** A live, unarchived job of the user's with pay set up: the given one, else the default, else the first. */
async function jobForShift(ctx: QueryCtx, userId: string, jobId: string | undefined) {
  const jobs = activeJobs(await jobsOf(ctx, userId));
  const job = jobId === undefined ? (jobs.find((j) => j.is_default) ?? jobs[0]) : jobs.find((j) => j.id === jobId);
  if (job === undefined) {
    fail(jobId === undefined ? "The user has no jobs yet. Add one in the Tidex app first." : "No active job with that job_id. Use list_jobs.");
  }
  if (!(await jobsWithPay(ctx, userId)).has(job.id)) fail(`Set up pay for ${job.name} in the Tidex app first.`);
  return job;
}

async function requireUser(ctx: QueryCtx, userId: string) {
  const user = await userByUuid(ctx, userId);
  if (user === null || user.banned_at !== undefined) fail("This Tidex account is not available.");
  return user;
}

// ---------- Access ----------

const keyRow = (ctx: QueryCtx, issuer: string) =>
  ctx.db.query("mcp_signing_keys").withIndex("by_issuer", (q) => q.eq("issuer", issuer)).unique();

export const storedKeys = internalQuery({
  args: { issuer: v.string() },
  handler: async (ctx, { issuer }) => {
    const row = await keyRow(ctx, issuer);
    return row?.keys === undefined ? null : { keys: row.keys as JSONWebKeySet, fetched_at: row.fetched_at };
  },
});

/** True for the one request a minute that may fetch Clerk's keys. */
export const claimKeyFetch = internalMutation({
  args: { issuer: v.string() },
  handler: async (ctx, { issuer }) => {
    const now = Date.now();
    const row = await keyRow(ctx, issuer);
    if (row !== null && now - (row.attempted_at ?? 0) < KEY_FETCH_COOLDOWN_MS) return false;
    if (row === null) await ctx.db.insert("mcp_signing_keys", { issuer, fetched_at: 0, attempted_at: now });
    else await ctx.db.patch(row._id, { attempted_at: now });
    return true;
  },
});

export const storeKeys = internalMutation({
  args: { issuer: v.string(), keys: v.any() },
  handler: async (ctx, { issuer, keys }) => {
    const row = await keyRow(ctx, issuer);
    if (row !== null) await ctx.db.patch(row._id, { keys, fetched_at: Date.now() });
  },
});

/**
 * Clerk's keys from mcp_signing_keys, fetched again after an hour, or sooner when a token
 * names a key they lack. Stored keys stand in while a fetch fails.
 */
function clerkKeys(ctx: ActionCtx, issuer: string): KeySource {
  return async (refresh) => {
    const stored = await ctx.runQuery(internal.mcp.storedKeys, { issuer });
    const age = stored === null ? Infinity : Date.now() - stored.fetched_at;
    // Keys fetched moments ago are current, so a key they lack doesn't exist.
    if (stored !== null && age < (refresh ? KEY_FETCH_COOLDOWN_MS : KEYS_FRESH_MS)) return stored.keys;
    const fallback = refresh ? null : (stored?.keys ?? null);
    if (!(await ctx.runMutation(internal.mcp.claimKeyFetch, { issuer }))) {
      if (fallback !== null) return fallback;
      throw new Error("Clerk's keys are being fetched by another request");
    }
    try {
      const response = await fetch(`${issuer}/.well-known/jwks.json`);
      if (!response.ok) throw new Error(`Clerk JWKS answered ${response.status}`);
      const keys = (await response.json()) as JSONWebKeySet;
      // Storing an empty or malformed set would turn every valid token away for an hour.
      const valid = Array.isArray(keys?.keys) && keys.keys.length > 0 &&
        keys.keys.every((key) => typeof key?.kty === "string" && typeof key.kid === "string");
      if (!valid) throw new Error("Clerk JWKS has no usable keys");
      await ctx.runMutation(internal.mcp.storeKeys, { issuer, keys });
      return keys;
    } catch (error) {
      if (fallback === null) throw error;
      console.error("Clerk JWKS fetch failed; using stored keys", error);
      return fallback;
    }
  };
}

export const userForToken = internalQuery({
  args: { clerk_user_id: v.string() },
  handler: async (ctx, { clerk_user_id }) => {
    const user = await userByClerkId(ctx, clerk_user_id);
    return user === null || user.banned_at !== undefined ? null : user.id;
  },
});

/** Counts a tool call. Returns null when allowed, else the seconds until the window resets. */
export const consume = internalMutation({
  args: { user_id: v.string(), write: v.boolean() },
  handler: async (ctx, { user_id, write }) => {
    const now = Date.now();
    const row = await ctx.db.query("mcp_rate_limits").withIndex("by_user", (q) => q.eq("user_id", user_id)).unique();
    if (row === null || now - row.window_start >= WINDOW_MS) {
      const fresh = { user_id, window_start: now, calls: 1, writes: write ? 1 : 0 };
      if (row === null) await ctx.db.insert("mcp_rate_limits", fresh);
      else await ctx.db.replace(row._id, fresh);
      return null;
    }
    if (row.calls >= MAX_CALLS || (write && row.writes >= MAX_WRITES)) {
      return Math.ceil((row.window_start + WINDOW_MS - now) / 1000);
    }
    await ctx.db.patch(row._id, { calls: row.calls + 1, writes: row.writes + (write ? 1 : 0) });
    return null;
  },
});

// ---------- Reads ----------

export const listJobs = internalQuery({
  args: { user_id: v.string() },
  handler: async (ctx, { user_id }) => {
    const withPay = await jobsWithPay(ctx, user_id);
    return {
      jobs: activeJobs(await jobsOf(ctx, user_id)).map((j) => ({
        job_id: j.id,
        name: j.name,
        currency: j.currency,
        is_default: j.is_default,
        pay_set_up: withPay.has(j.id),
      })),
    };
  },
});

export const listShifts = internalQuery({
  args: { user_id: v.string(), from: v.string(), to: v.string() },
  handler: async (ctx, { user_id, from, to }) => {
    const jobs = await jobsOf(ctx, user_id);
    const dates: string[] = [];
    for (let date = from; date <= to; date = addDays(date, 1)) dates.push(date);
    const oneOffs = live(
      await ctx.db
        .query("user_shifts")
        .withIndex("by_user_shift_date", (q) => q.eq("user_id", user_id).gte("shift_date", from).lte("shift_date", to))
        .collect(),
    ).map((s) => oneOff(s, jobs));
    const recurring = live(
      await ctx.db.query("recurring_shifts").withIndex("by_user_revision", (q) => q.eq("user_id", user_id)).collect(),
    ).flatMap((r) =>
      projectedRecurringShifts([asRecurringShift(r)], dates).map((s) => ({
        kind: "recurring" as const,
        recurring_shift_id: r.id,
        date: s.shift_date,
        start: clockTime(s.start_time),
        end: clockTime(s.end_time),
        ends_next_day: endsNextDay(s.start_time, s.end_time),
        job_id: r.job_id,
        job_name: jobs.find((j) => j.id === r.job_id)?.name ?? null,
        note: (r.date_specific_notes as Record<string, string> | undefined)?.[s.shift_date] ?? null,
      })),
    );
    return {
      time_zone: await scheduleTimeZone(ctx, user_id),
      shifts: [...oneOffs, ...recurring].sort((a, b) => a.date.localeCompare(b.date) || a.start.localeCompare(b.start)),
    };
  },
});

export const earnings = internalQuery({
  args: { user_id: v.string(), from: v.string(), to: v.string() },
  handler: async (ctx, { user_id, from, to }) => {
    const jobs = await jobsOf(ctx, user_id);
    const snapshots = live(
      await ctx.db.query("wage_snapshots").withIndex("by_user_revision", (q) => q.eq("user_id", user_id)).collect(),
    ).map(asSnapshot);
    const regular = live(
      await ctx.db
        .query("user_shifts")
        .withIndex("by_user_shift_date", (q) =>
          q.eq("user_id", user_id).gte("shift_date", overtimeWeekStart(from)).lte("shift_date", to),
        )
        .collect(),
    ).map(asRegularShift);
    const recurring = live(
      await ctx.db.query("recurring_shifts").withIndex("by_user_revision", (q) => q.eq("user_id", user_id)).collect(),
    ).map(asRecurringShift);
    return {
      from,
      to,
      ...shiftEarnings({
        from,
        to,
        regular,
        recurring,
        snapshotFor: (shift) => applicableWageSnapshot(shift, snapshots),
        currencyFor: (jobId) => jobs.find((j) => j.id === jobId)?.currency ?? "NOK",
      }),
    };
  },
});

// ---------- Writes ----------

export const addShift = internalMutation({
  args: {
    user_id: v.string(),
    date: v.string(),
    start: v.string(),
    end: v.string(),
    job_id: v.optional(v.string()),
    note: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const job = await jobForShift(ctx, user.id, args.job_id);
    const times = checked(() => shiftTimes(args.start, args.end));
    const jobs = await jobsOf(ctx, user.id);
    // A retried call finds the shift its first attempt added.
    const existing = live(
      await ctx.db
        .query("user_shifts")
        .withIndex("by_user_shift_date", (q) => q.eq("user_id", user.id).eq("shift_date", args.date))
        .collect(),
    ).find((s) => {
      const start = clockTime(s.start_time);
      // Older rows may store a midnight end as 00:00.
      return s.job_id === job.id && start === times.start_time && storedEndTime(clockTime(s.end_time), start) === times.end_time;
    });
    if (existing !== undefined) return { shift: oneOff(existing, jobs), already_existed: true };
    const note = args.note?.trim();
    const { row } = await shiftWrites.insert(ctx, user.id, {
      row: {
        id: crypto.randomUUID(),
        job_id: job.id,
        shift_date: args.date,
        ...times,
        ...(note ? { note } : {}),
      },
      payroll_revision: PAYROLL_REVISION,
    });
    return { shift: oneOff(row as ShiftFields, jobs), already_existed: false };
  },
});

const STALE = "The shift changed since you listed it. Call list_shifts again and use the new revision.";
const NOT_FOUND = "No one-off shift with that shift_id. Use a shift_id from list_shifts; recurring shifts can only be changed in the Tidex app.";

async function ownShift(ctx: QueryCtx, userId: string, shiftId: string, revision: number) {
  const shift = await ctx.db.query("user_shifts").withIndex("by_uuid", (q) => q.eq("id", shiftId)).unique();
  if (shift === null || shift.user_id !== userId || shift.deleted_at !== undefined) fail(NOT_FOUND);
  if (shift.revision !== revision) fail(STALE);
  return shift;
}

export const updateShift = internalMutation({
  args: {
    user_id: v.string(),
    shift_id: v.string(),
    revision: v.number(),
    date: v.optional(v.string()),
    start: v.optional(v.string()),
    end: v.optional(v.string()),
    job_id: v.optional(v.string()),
    note: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const prev = await ownShift(ctx, user.id, args.shift_id, args.revision);
    const set: Record<string, unknown> = {};
    const clear: string[] = [];
    // Only what differs from the stored shift is written.
    if (args.date !== undefined && args.date !== prev.shift_date) set.shift_date = args.date;
    if (args.start !== undefined || args.end !== undefined) {
      const moved = checked(() => movedTimes({ start: prev.start_time, end: prev.end_time }, args.start, args.end));
      const start = clockTime(prev.start_time);
      if (moved.start_time !== start || moved.end_time !== storedEndTime(clockTime(prev.end_time), start)) {
        Object.assign(set, moved);
      }
    }
    if (args.job_id !== undefined && args.job_id !== prev.job_id) set.job_id = (await jobForShift(ctx, user.id, args.job_id)).id;
    if (args.note !== undefined) {
      const note = args.note.trim();
      if (note === "" && prev.note !== undefined) clear.push("note");
      else if (note !== "" && note !== prev.note) set.note = note;
    }
    // Nothing to change keeps the revision the agent holds.
    if (Object.keys(set).length === 0 && clear.length === 0) return { shift: oneOff(prev, await jobsOf(ctx, user.id)) };
    const result = await shiftWrites.update(ctx, user.id, {
      id: prev.id,
      expected_revision: prev.revision,
      set,
      clear,
      payroll_revision: PAYROLL_REVISION,
    });
    if (result.status !== "ok") fail(STALE);
    return { shift: oneOff(result.row as ShiftFields, await jobsOf(ctx, user.id)) };
  },
});

export const deleteShift = internalMutation({
  args: { user_id: v.string(), shift_id: v.string(), revision: v.number() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const prev = await ownShift(ctx, user.id, args.shift_id, args.revision);
    const result = await shiftWrites.remove(ctx, user.id, {
      id: prev.id,
      expected_revision: prev.revision,
      payroll_revision: PAYROLL_REVISION,
    });
    if (result.status !== "ok") fail(STALE);
    return { deleted: oneOff(result.row as ShiftFields, await jobsOf(ctx, user.id)) };
  },
});

// ---------- HTTP ----------

/** The MCP URL and Clerk issuer, or null while the server is off or misconfigured. */
function config() {
  const resourceUrl = process.env.MCP_RESOURCE_URL;
  const issuer = process.env.CLERK_JWT_ISSUER_DOMAIN;
  if (!resourceUrl || !issuer) return null;
  try {
    if (new URL(resourceUrl).pathname === "/mcp") return { resourceUrl, issuer };
  } catch {
    // Reported below.
  }
  console.error("MCP_RESOURCE_URL must be an absolute URL ending in /mcp", resourceUrl);
  return null;
}

const notFound = () => new Response("Not found", { status: 404 });

function errorMessage(error: ConvexError<Value>) {
  const data = error.data as { code?: string; message?: string } | string;
  if (typeof data === "string") return data;
  return data.message ?? `Tidex refused the change (${data.code ?? "error"}).`;
}

async function runTool(ctx: ActionCtx, userId: string, name: ToolName, rawArgs: Record<string, unknown>): Promise<ToolOutcome> {
  const retryAfter = await ctx.runMutation(internal.mcp.consume, { user_id: userId, write: isWriteTool(name) });
  if (retryAfter !== null) return { ok: false, message: `Too many requests. Try again in ${retryAfter} seconds.` };
  try {
    const user_id = userId;
    switch (name) {
      case "list_jobs":
        parseArgs.list_jobs(rawArgs);
        return { ok: true, value: await ctx.runQuery(internal.mcp.listJobs, { user_id }) };
      case "list_shifts":
        return { ok: true, value: await ctx.runQuery(internal.mcp.listShifts, { user_id, ...parseArgs.list_shifts(rawArgs) }) };
      case "get_earnings":
        return { ok: true, value: await ctx.runQuery(internal.mcp.earnings, { user_id, ...parseArgs.get_earnings(rawArgs) }) };
      case "add_shift":
        return { ok: true, value: await ctx.runMutation(internal.mcp.addShift, { user_id, ...parseArgs.add_shift(rawArgs) }) };
      case "update_shift":
        return { ok: true, value: await ctx.runMutation(internal.mcp.updateShift, { user_id, ...parseArgs.update_shift(rawArgs) }) };
      case "delete_shift":
        return { ok: true, value: await ctx.runMutation(internal.mcp.deleteShift, { user_id, ...parseArgs.delete_shift(rawArgs) }) };
    }
  } catch (error) {
    if (error instanceof ToolError) return { ok: false, message: error.message };
    if (error instanceof ConvexError) return { ok: false, message: errorMessage(error) };
    console.error("mcp tool failed", name, error);
    return { ok: false, message: "Tidex couldn't do that right now. Try again later." };
  }
}

/** POST /mcp. Answers 404 until MCP_RESOURCE_URL is set, so a deploy alone doesn't turn it on. */
export const endpoint = httpAction(async (ctx, request) => {
  const settings = config();
  if (settings === null) return notFound();
  const { resourceUrl, issuer } = settings;
  try {
    return await handleMcpPost(request, {
      resourceUrl,
      authenticate: async (token) => {
        const clerkUserId = await verifyAccessToken(token, issuer, resourceUrl, clerkKeys(ctx, issuer));
        if (clerkUserId === null) return "invalid_token";
        const userId = await ctx.runQuery(internal.mcp.userForToken, { clerk_user_id: clerkUserId });
        return userId === null ? "no_account" : { userId };
      },
      callTool: (userId, name, args) => runTool(ctx, userId, name, args),
    });
  } catch (error) {
    console.error("mcp request failed", error);
    return Response.json({ error: "temporarily_unavailable" }, { status: 503, headers: { "Retry-After": "30" } });
  }
});

/** GET and DELETE /mcp. There is no SSE stream and no session to end. */
export const methodNotAllowed = httpAction(async () =>
  config() === null ? notFound() : new Response(null, { status: 405, headers: { Allow: "POST" } }),
);

/** OAuth protected resource metadata (RFC 9728), which tells clients to get a token from Clerk. */
export const protectedResource = httpAction(async () => {
  const settings = config();
  if (settings === null) return notFound();
  return Response.json(resourceMetadata(settings.resourceUrl, settings.issuer), {
    headers: { "Access-Control-Allow-Origin": "*", "Cache-Control": "public, max-age=3600" },
  });
});
