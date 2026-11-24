import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, internalQuery, type QueryCtx } from "./_generated/server";
import { deleteArchivedFor, jobWrites } from "./jobs";
import { activeJobs, checked, fail, jobsOf, live, matchJob, requireUser } from "./lib/mcp/db";
import * as specs from "./lib/mcp/pay";
import {
  archiveRefusal,
  findTariffs,
  jobRow,
  jobView,
  type PaySettings,
  placement,
  snapshotFields,
  snapshotInEffect,
  snapshotRow,
  snapshotUpdate,
} from "./lib/mcp/pay";
import { localNowInTimeZone } from "./lib/mcp/payPeriod";
import { recurringView } from "./lib/mcp/recurring";
import { type McpTool, tool } from "./lib/mcp/registry";
import { PAYROLL_REVISION } from "./lib/payrollCompatibility";
import { scheduleTimeZone } from "./lib/scheduleTimeZone";
import { sharesWith } from "./sharing";
import { inboxFor } from "./threads";
import { wageSnapshotWrites } from "./wageSnapshots";

// The MCP overview, job, pay and tariff tools. Each runs for the user the OAuth token names;
// mcp.ts checks the token, scope and arguments first. None of these functions is public.

const writes = { payroll_revision: PAYROLL_REVISION };

async function snapshotsOf(ctx: QueryCtx, userId: string, jobId?: string) {
  if (jobId !== undefined) {
    return live(
      await ctx.db
        .query("wage_snapshots")
        .withIndex("by_user_job_from_date", (q) => q.eq("user_id", userId).eq("job_id", jobId))
        .collect(),
    );
  }
  return live(
    await ctx.db
      .query("wage_snapshots")
      .withIndex("by_user_revision", (q) => q.eq("user_id", userId))
      .collect(),
  );
}

async function preferencesOf(ctx: QueryCtx, userId: string) {
  const row = await ctx.db
    .query("notification_preferences")
    .withIndex("by_user_revision", (q) => q.eq("user_id", userId))
    .unique();
  return {
    shared_shifts_enabled: row?.shared_shifts_enabled ?? true,
    shift_reminders_enabled: row?.shift_reminders_enabled ?? true,
    shift_reminder_minutes_array: row?.shift_reminder_minutes_array ?? (row === null ? [300] : []),
  };
}

// ---------- Overview ----------

export const getOverview = internalQuery({
  args: { user_id: v.string(), include_archived: v.boolean(), include_pay_history: v.boolean() },
  handler: async (ctx, { user_id, include_archived, include_pay_history }) => {
    const timeZone = await scheduleTimeZone(ctx, user_id);
    const { today, now } = localNowInTimeZone(timeZone);

    const [jobs, allSnapshots, rawRecurring, settings, prefs, shares, inbox] = await Promise.all([
      jobsOf(ctx, user_id),
      snapshotsOf(ctx, user_id),
      ctx.db.query("recurring_shifts").withIndex("by_user_revision", (q) => q.eq("user_id", user_id)).collect(),
      ctx.db.query("user_settings").withIndex("by_user_revision", (q) => q.eq("user_id", user_id)).unique(),
      preferencesOf(ctx, user_id),
      sharesWith(ctx, user_id),
      inboxFor(ctx, user_id, { limit: 1 }),
    ]);

    const snapshotsByJob = new Map<string, Doc<"wage_snapshots">[]>();
    for (const s of allSnapshots) {
      const list = snapshotsByJob.get(s.job_id) ?? [];
      list.push(s);
      snapshotsByJob.set(s.job_id, list);
    }

    const archived = include_archived ? jobs.filter((j) => j.archived_at !== undefined) : [];
    const visibleJobs = [...activeJobs(jobs), ...archived].map((j) =>
      jobView(j, snapshotsByJob.get(j.id) ?? [], { today, includePayHistory: include_pay_history }),
    );

    const jobName = (jobId: string) => jobs.find((j) => j.id === jobId)?.name ?? null;
    const recurringShifts = live(rawRecurring).map((r) => recurringView(r, jobName(r.job_id)));

    const blockedIds = new Set(
      [...shares.incoming, ...shares.outgoing]
        .filter((s) => s.blocked_by_user_id !== undefined)
        .map((s) => (s.owner_id === user_id ? s.viewer_id : s.owner_id)),
    );
    const friendIds = new Set(
      [...shares.incoming.map((s) => s.owner_id), ...shares.outgoing.map((s) => s.viewer_id)].filter(
        (id) => !blockedIds.has(id),
      ),
    );

    return {
      today,
      now,
      time_zone: timeZone,
      jobs: visibleJobs,
      recurring_shifts: recurringShifts,
      settings: {
        theme: settings?.theme ?? null,
        calendar_color_style: settings?.calendar_content_color_style ?? null,
        show_clock_buttons: settings?.show_dashboard_clock_buttons ?? null,
        startup_tab: settings?.default_startup_tab ?? null,
        shift_reminders_enabled: prefs.shift_reminders_enabled && prefs.shift_reminder_minutes_array.length > 0,
        shift_reminder_minutes: [...prefs.shift_reminder_minutes_array].sort((a, b) => b - a),
        shared_shifts_notifications: prefs.shared_shifts_enabled,
      },
      unread_messages: inbox.unread_direct_message_count,
      friends_count: friendIds.size,
    };
  },
});

// ---------- Jobs ----------

export const createJob = internalMutation({
  args: {
    user_id: v.string(),
    name: v.string(),
    color: v.string(),
    currency: v.optional(v.string()),
    payroll_day: v.number(),
    half_tax_month: v.optional(v.union(v.literal(11), v.literal(12))),
    pay_period: v.optional(v.any()),
    settings: v.any(),
    today: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const jobs = await jobsOf(ctx, user.id);
    const active = activeJobs(jobs);
    const existing = active.find((j) => j.name.toLowerCase() === args.name.toLowerCase());
    if (existing !== undefined) {
      const snaps = await snapshotsOf(ctx, user.id, existing.id);
      return {
        job: jobView(existing, snaps, { today: args.today, includePayHistory: true }),
        already_existed: true,
      };
    }
    const currency = args.currency ?? active.find((j) => j.is_default)?.currency ?? "kr";
    const fields = checked(() => snapshotFields(args.settings as PaySettings, null, { date: args.today, currency }));
    const { sortOrder, isDefault } = placement(active);
    const { row: job } = await jobWrites.insert(ctx, user.id, {
      row: jobRow({
        id: crypto.randomUUID(),
        name: args.name,
        color: args.color,
        currency,
        isDefault,
        sortOrder,
        payrollDay: args.payroll_day,
        halfTaxMonth: args.half_tax_month,
        payPeriod: args.pay_period,
      }),
      ...writes,
    });
    const { row: snapshot } = await wageSnapshotWrites.insert(ctx, user.id, {
      row: snapshotRow(crypto.randomUUID(), job.id, undefined, fields),
      ...writes,
    });
    return {
      job: jobView(job as Doc<"jobs">, [snapshot as Doc<"wage_snapshots">], { today: args.today, includePayHistory: true }),
      already_existed: false,
    };
  },
});

export const updateJob = internalMutation({
  args: {
    user_id: v.string(),
    job: v.string(),
    name: v.optional(v.string()),
    color: v.optional(v.string()),
    payroll_day: v.optional(v.number()),
    half_tax_month: v.optional(v.union(v.literal(11), v.literal(12), v.null())),
    pay_period: v.optional(v.any()),
    make_default: v.optional(v.boolean()),
    archived: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const allJobs = await jobsOf(ctx, user.id);
    const job = matchJob(allJobs, args.job, { includeArchived: true });
    const active = activeJobs(allJobs);
    const isArchived = job.archived_at !== undefined;
    const { today } = localNowInTimeZone(await scheduleTimeZone(ctx, user.id));

    const set: Record<string, unknown> = {};
    const clear: string[] = [];
    const change = (key: keyof Doc<"jobs">, value: unknown) => {
      const stored = job[key];
      if (value === null) {
        if (stored !== undefined) clear.push(key);
      } else if (value !== undefined && JSON.stringify(value) !== JSON.stringify(stored)) {
        set[key] = value;
      }
    };
    change("name", args.name);
    change("color", args.color);
    change("payroll_day", args.payroll_day);
    change("half_tax_month", args.half_tax_month);
    change("pay_period", args.pay_period);

    if (args.archived === true && !isArchived) {
      const refusal = archiveRefusal(job, active);
      if (refusal !== null) fail(refusal);
      Object.assign(set, { archived_at: new Date().toISOString(), is_default: false });
    } else if (args.archived === false && isArchived) {
      clear.push("archived_at");
      set.sort_order = placement(active).sortOrder;
    }

    if (args.make_default && !job.is_default) {
      if (isArchived && args.archived !== false) {
        fail("An archived job can't be the default. Restore it first with archived: false.");
      }
      const previous = active.find((j) => j.is_default);
      if (previous !== undefined) {
        const prevResult = await jobWrites.update(ctx, user.id, {
          id: previous.id,
          expected_revision: previous.revision,
          set: { is_default: false },
          ...writes,
        });
        if (prevResult.status !== "ok") fail("Another change to the user's jobs happened at the same time. Try again.");
      }
      set.is_default = true;
    }

    const snaps = await snapshotsOf(ctx, user.id, job.id);
    if (Object.keys(set).length === 0 && clear.length === 0) {
      return { job: jobView(job, snaps, { today }) };
    }
    const result = await jobWrites.update(ctx, user.id, {
      id: job.id,
      expected_revision: job.revision,
      set,
      clear,
      ...writes,
    });
    if (result.status !== "ok") fail("The job changed during the update. Try again.");
    return { job: jobView(result.row as Doc<"jobs">, snaps, { today }) };
  },
});

export const deleteJob = internalMutation({
  args: { user_id: v.string(), job: v.string(), confirmation_token: v.optional(v.string()) },
  handler: async (ctx, { user_id, job: jobRef, confirmation_token }) => {
    const user = await requireUser(ctx, user_id);
    const allRows = await ctx.db
      .query("jobs")
      .withIndex("by_user_revision", (q) => q.eq("user_id", user.id))
      .collect();
    const liveRows = live(allRows);
    // Retries with confirmation_token may match an already-deleted job by UUID.
    let target = allRows.find((j) => j.id === jobRef && (j.deleted_at === undefined || confirmation_token !== undefined));
    if (target === undefined) {
      target = matchJob(liveRows, jobRef, { includeArchived: true });
    }
    if (target.deleted_at === undefined && target.archived_at === undefined) {
      fail("Only an archived job can be deleted. Archive it with save_job (archived: true) first.");
    }
    let result;
    try {
      result = await deleteArchivedFor(ctx, user.id, { job_id: target.id, confirmation_token });
    } catch (error) {
      if (error instanceof ConvexError && (error.data as { code?: string }).code === "history_changed") {
        fail("The job's history changed since the preview call. Call delete_job again without confirmation_token.");
      }
      throw error;
    }
    const counts = {
      shifts: result.user_shifts,
      recurring_shifts: result.recurring_shifts,
      payroll_adjustments: result.payroll_adjustments,
      pay_settings: result.wage_snapshots,
    };
    if (result.deleted_at_epoch === null) {
      return {
        deleted: false,
        job_id: target.id,
        job_name: result.job_name,
        would_delete: counts,
        confirmation_token: result.confirmation_token,
        next: "Show these counts to the user, then call delete_job again with this confirmation_token after they confirm.",
      };
    }
    return { deleted: true, job_id: target.id, job_name: result.job_name, deleted_rows: counts };
  },
});

// ---------- Pay ----------

export const setPay = internalMutation({
  args: {
    user_id: v.string(),
    job: v.optional(v.string()),
    from_date: v.optional(v.string()),
    settings: v.any(),
    today: v.string(),
  },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const jobs = await jobsOf(ctx, user.id);
    const job = matchJob(jobs, args.job, { includeArchived: true });
    if (job.archived_at !== undefined) fail("The job is archived. Restore it with save_job (archived: false) first.");
    const snapshots = await snapshotsOf(ctx, user.id, job.id);
    if (args.from_date !== undefined && !snapshots.some((s) => s.from_date === undefined)) {
      fail("Set the job's base pay first by calling set_pay without from_date.");
    }
    const target = snapshots.find((s) => s.from_date === args.from_date);
    const base = target ?? (args.from_date === undefined ? null : snapshotInEffect(snapshots, args.from_date));
    const fields = checked(() =>
      snapshotFields(args.settings as PaySettings, base, { date: args.from_date ?? args.today, currency: job.currency }),
    );
    const formatResult = (changed: boolean, rows: Doc<"wage_snapshots">[]) => ({
      changed,
      job: jobView(job, rows, { today: args.today, includePayHistory: true }),
    });

    if (target === undefined) {
      const { row } = await wageSnapshotWrites.insert(ctx, user.id, {
        row: snapshotRow(crypto.randomUUID(), job.id, args.from_date, fields),
        ...writes,
      });
      return formatResult(true, [...snapshots, row as Doc<"wage_snapshots">]);
    }
    const update = snapshotUpdate(target, fields);
    if (update === null) return formatResult(false, snapshots);
    const result = await wageSnapshotWrites.update(ctx, user.id, {
      id: target.id,
      expected_revision: target.revision,
      ...update,
      ...writes,
    });
    if (result.status !== "ok") fail("Pay settings changed during the update. Try again.");
    return formatResult(
      true,
      snapshots.map((s) => (s.id === target.id ? (result.row as Doc<"wage_snapshots">) : s)),
    );
  },
});

export const removePayChange = internalMutation({
  args: { user_id: v.string(), job: v.optional(v.string()), from_date: v.string() },
  handler: async (ctx, args) => {
    const user = await requireUser(ctx, args.user_id);
    const jobs = await jobsOf(ctx, user.id);
    const job = matchJob(jobs, args.job, { includeArchived: true });
    const snapshots = await snapshotsOf(ctx, user.id, job.id);
    const target = snapshots.find((s) => s.from_date === args.from_date);
    if (target === undefined) {
      const dates = snapshots.flatMap((s) => (s.from_date ? [s.from_date] : [])).sort();
      fail(
        dates.length === 0
          ? `${job.name} has no dated pay changes to remove.`
          : `No pay change on ${args.from_date} for ${job.name}. Existing dates: ${dates.join(", ")}.`,
      );
    }
    const result = await wageSnapshotWrites.remove(ctx, user.id, {
      id: target.id,
      expected_revision: target.revision,
      ...writes,
    });
    if (result.status !== "ok") fail("Pay settings changed during deletion. Try again.");
    const { today } = localNowInTimeZone(await scheduleTimeZone(ctx, user.id));
    return {
      removed_from_date: args.from_date,
      job: jobView(
        job,
        snapshots.filter((s) => s.id !== target.id),
        { today, includePayHistory: true },
      ),
    };
  },
});

export const payTools: McpTool[] = [
  tool(specs.getOverview, (ctx, user_id, args) => ctx.runQuery(internal.mcpPay.getOverview, { user_id, ...args })),
  tool(specs.saveJob, (ctx, user_id, args) =>
    args.mode === "create"
      ? ctx.runMutation(internal.mcpPay.createJob, {
          user_id,
          name: args.name,
          color: args.color,
          currency: args.currency,
          payroll_day: args.payroll_day,
          half_tax_month: args.half_tax_month,
          pay_period: args.pay_period,
          settings: args.settings,
          today: args.today,
        })
      : ctx.runMutation(internal.mcpPay.updateJob, {
          user_id,
          job: args.job,
          name: args.name,
          color: args.color,
          payroll_day: args.payroll_day,
          half_tax_month: args.half_tax_month,
          pay_period: args.pay_period,
          make_default: args.make_default,
          archived: args.archived,
        }),
  ),
  tool(specs.deleteJob, (ctx, user_id, args) => ctx.runMutation(internal.mcpPay.deleteJob, { user_id, ...args })),
  tool(specs.findTariffsSpec, async (_ctx, _user_id, args) => findTariffs(args)),
  tool(specs.setPay, (ctx, user_id, args) =>
    args.action === "remove"
      ? ctx.runMutation(internal.mcpPay.removePayChange, { user_id, job: args.job, from_date: args.from_date })
      : ctx.runMutation(internal.mcpPay.setPay, {
          user_id,
          job: args.job,
          from_date: args.from_date,
          settings: args.settings,
          today: args.today,
        }),
  ),
];
