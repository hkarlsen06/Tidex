import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import {
  internalAction,
  internalQuery,
  type MutationCtx,
  mutation,
  type QueryCtx,
  query,
} from "./_generated/server";
import { requireViewer, userByUuid } from "./lib/auth";
import { setClerkBan } from "./lib/clerk";
import { messagePayload } from "./lib/messaging";
import { enqueue, queueFeedbackResponded, scheduleSender } from "./lib/notify";
import { nextRevision } from "./lib/revision";
import { publicRow } from "./lib/syncWrite";
import { literals } from "./lib/validators";
import { softDeleteMessage } from "./messages";

// Ports of the admin_*_api functions in supabase/sql/functions/admin/mobile_admin_api.sql
// and the admin-user-ban and admin-user-role Edge Functions. The JSON keys match, so the
// app's admin screens decode them unchanged. Postgres also required a TOTP-verified
// session (aal2). N+1 has no TOTP, so the admin role is the check.
//
// ponytail: the stats and user list read whole tables in one query. The largest,
// user_shifts, had 3,283 rows in October 2026. Move them to a paginating action when a
// table nears Convex's per-query read limit.

const SUPERADMIN_USER_ID = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";
const DAY_MS = 86_400_000;

type Json = Record<string, unknown>;

/** The signed-in admin, not the impersonated user. */
async function requireAdmin(ctx: QueryCtx) {
  const { actor } = await requireViewer(ctx);
  if (actor.role !== "admin") throw new ConvexError({ code: "forbidden", message: "Admin access required" });
  return actor;
}

async function logAction(
  ctx: MutationCtx,
  admin: Doc<"users">,
  action: string,
  targetId: string | undefined,
  targetEmail: string | undefined,
  metadata: Json,
) {
  await ctx.db.insert("admin_audit_log", {
    id: crypto.randomUUID(),
    admin_id: admin.id,
    admin_email: admin.email ?? "unknown",
    action,
    target_user_id: targetId,
    target_email: targetEmail,
    metadata,
    created_at: new Date().toISOString(),
  });
}

const language = (locale: string | undefined) => (/^(no|nb|nn)([-_].*)?$/i.test(locale ?? "") ? "no" : "en");
const percent = (part: number, whole: number) => (whole === 0 ? "–" : `${Math.round((100 * part) / whole)}%`);

function requireTimeZone(timeZone: string) {
  try {
    new Intl.DateTimeFormat("en", { timeZone });
  } catch {
    throw new ConvexError({ code: "invalid", message: `Unknown time zone ${timeZone}` });
  }
}

/** YYYY-MM-DD of an instant in a time zone. */
const localDate = (ms: number, timeZone: string) => new Intl.DateTimeFormat("en-CA", { timeZone }).format(new Date(ms));
const addDays = (date: string, days: number) => new Date(Date.parse(`${date}T00:00:00Z`) + days * DAY_MS).toISOString().slice(0, 10);
/** The Monday of the week containing `date`, as date_trunc('week') picks it. */
const mondayOf = (date: string) => addDays(date, -((new Date(`${date}T00:00:00Z`).getUTCDay() + 6) % 7));

/** internal.admin_weekly_counts: one point per week for the last `weeks` weeks. */
function weeklyCounts(times: (string | undefined)[], timeZone: string, weeks: number) {
  const counts = new Map<string, number>();
  for (const t of times) {
    if (t === undefined) continue;
    const week = mondayOf(localDate(Date.parse(t), timeZone));
    counts.set(week, (counts.get(week) ?? 0) + 1);
  }
  const thisWeek = mondayOf(localDate(Date.now(), timeZone));
  return Array.from({ length: weeks }, (_, i) => addDays(thisWeek, -7 * (weeks - 1 - i))).map((date) => ({
    date,
    value: counts.get(date) ?? 0,
  }));
}

/** internal.admin_breakdown: the top 8 labels and "Other". */
function breakdown(title: string, labels: (string | null | undefined)[]): Json {
  const counts = new Map<string, number>();
  for (const label of labels) {
    const key = label === null || label === undefined || label === "" ? "Unknown" : label;
    counts.set(key, (counts.get(key) ?? 0) + 1);
  }
  const ranked = [...counts.entries()].sort(([la, a], [lb, b]) => b - a || la.localeCompare(lb));
  const grouped = new Map(ranked.slice(0, 8));
  const other = ranked.slice(8).reduce((sum, [, n]) => sum + n, 0);
  if (other > 0) grouped.set("Other", (grouped.get("Other") ?? 0) + other);
  return {
    kind: "bars",
    title,
    rows: [...grouped.entries()]
      .sort(([la, a], [lb, b]) => Number(la === "Other") - Number(lb === "Other") || b - a || la.localeCompare(lb))
      .map(([label, value]) => ({ label, value })),
  };
}

const nameOf = (u: Doc<"users"> | null | undefined) => u?.name ?? null;

async function avatarOf(ctx: QueryCtx, user: Doc<"users"> | null) {
  if (user === null) return null;
  const settings = await ctx.db
    .query("user_settings")
    .withIndex("by_user_revision", (q) => q.eq("user_id", user.id))
    .unique();
  const picture =
    settings?.profile_picture_storage_id === undefined ? null : await ctx.storage.getUrl(settings.profile_picture_storage_id);
  return picture ?? user.avatar_url ?? null;
}

/**
 * internal.admin_user_last_active: the last recorded app open, else the last sign-in.
 * GoTrue's session refreshes have no Convex equivalent.
 */
async function lastActiveByUser(ctx: QueryCtx) {
  const activity = new Map((await ctx.db.query("user_app_activity").collect()).map((a) => [a.user_id, a.last_active_at]));
  const users = await ctx.db.query("users").collect();
  return new Map(users.map((u) => [u.id, activity.get(u.id) ?? u.last_sign_in_at]));
}

const since = (days: number) => new Date(Date.now() - days * DAY_MS).toISOString();
const isAdminOrSuper = (u: Doc<"users">) => u.role === "admin" || u.id === SUPERADMIN_USER_ID;

// ---------- Users ----------

export const listUsers = query({
  args: {
    page: v.optional(v.number()),
    per_page: v.optional(v.number()),
    search: v.optional(v.string()),
    sort: v.optional(literals("name", "newest", "last_sign_in", "last_active", "shifts", "messages", "friends")),
    filter: v.optional(literals("all", "active", "new", "admins", "banned", "norwegian", "english")),
    reverse: v.optional(v.boolean()),
    account: v.optional(literals("any", "admins", "non_admins", "banned", "not_banned")),
    language: v.optional(literals("no", "en")),
    provider: v.optional(v.string()),
    signed_up_days: v.optional(v.number()),
    active_days: v.optional(v.number()),
    inactive_days: v.optional(v.number()),
    shifts: v.optional(literals("any", "with", "without")),
    messages: v.optional(literals("any", "with", "without")),
    friends: v.optional(literals("any", "with", "without")),
    app_version: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const page = Math.max(Math.floor(args.page ?? 1), 1);
    const perPage = Math.min(Math.max(Math.floor(args.per_page ?? 20), 1), 100);
    const sort = args.sort ?? "name";
    const lastActive = await lastActiveByUser(ctx);
    const activity = new Map((await ctx.db.query("user_app_activity").collect()).map((a) => [a.user_id, a]));
    const count = (values: string[]) => values.reduce((m, id) => m.set(id, (m.get(id) ?? 0) + 1), new Map<string, number>());
    const shiftCounts = count((await ctx.db.query("user_shifts").collect()).filter((s) => s.deleted_at === undefined).map((s) => s.user_id));
    const messageCounts = count(
      (await ctx.db.query("messages").collect())
        .filter((m) => m.deleted_at === undefined && m.message_type === "user")
        .map((m) => m.sender_user_id),
    );
    const friends = new Map<string, Set<string>>();
    for (const s of await ctx.db.query("shift_shares").collect()) {
      if (s.blocked_by_user_id !== undefined) continue;
      for (const [a, b] of [
        [s.owner_id, s.viewer_id],
        [s.viewer_id, s.owner_id],
      ]) {
        friends.set(a!, (friends.get(a!) ?? new Set()).add(b!));
      }
    }
    const search = args.search?.toLowerCase() ?? "";
    const after = (iso: string | undefined, days: number) => iso !== undefined && iso >= since(days);
    const withOrWithout = (mode: string | undefined, n: number) => mode === undefined || mode === "any" || (n > 0) === (mode === "with");

    const rows = (await ctx.db.query("users").collect())
      .map((u) => ({
        u,
        lastActive: lastActive.get(u.id),
        language: language(u.locale),
        appVersion: activity.get(u.id)?.app_version,
        shifts: shiftCounts.get(u.id) ?? 0,
        messages: messageCounts.get(u.id) ?? 0,
        friends: friends.get(u.id)?.size ?? 0,
      }))
      .filter(({ u }) =>
        search === "" ||
        (u.email ?? "").toLowerCase().includes(search) ||
        (u.name ?? "").toLowerCase().includes(search) ||
        u.id.includes(search),
      )
      .filter((r) => {
        const banned = r.u.banned_at !== undefined;
        const filterOk = {
          all: true,
          active: after(r.lastActive, 7),
          new: after(r.u.created_at, 7),
          admins: isAdminOrSuper(r.u),
          banned,
          norwegian: r.language === "no",
          english: r.language === "en",
        }[args.filter ?? "all"];
        const accountOk = {
          any: true,
          admins: isAdminOrSuper(r.u),
          non_admins: !isAdminOrSuper(r.u),
          banned,
          not_banned: !banned,
        }[args.account ?? "any"];
        return (
          filterOk &&
          accountOk &&
          (args.language === undefined || r.language === args.language) &&
          (args.provider === undefined || (r.u.providers ?? []).includes(args.provider)) &&
          (args.signed_up_days === undefined || after(r.u.created_at, args.signed_up_days)) &&
          (args.active_days === undefined || after(r.lastActive, args.active_days)) &&
          (args.inactive_days === undefined || r.lastActive === undefined || r.lastActive < since(args.inactive_days)) &&
          withOrWithout(args.shifts, r.shifts) &&
          withOrWithout(args.messages, r.messages) &&
          withOrWithout(args.friends, r.friends) &&
          (args.app_version === undefined ||
            r.appVersion === args.app_version ||
            (args.app_version === "none" && r.appVersion === undefined))
        );
      });

    const sortValue = (r: (typeof rows)[number]): number | undefined => {
      const time = (iso: string | undefined) => (iso === undefined ? undefined : Date.parse(iso));
      switch (sort) {
        case "newest":
          return time(r.u.created_at);
        case "last_sign_in":
          return time(r.u.last_sign_in_at);
        case "last_active":
          return time(r.lastActive);
        case "shifts":
          return r.shifts;
        case "messages":
          return r.messages;
        case "friends":
          return r.friends;
        default:
          return undefined;
      }
    };
    const nameKey = (r: (typeof rows)[number]) => (r.u.name ?? r.u.email ?? "").toLowerCase();
    const reverse = args.reverse ?? false;
    // Dates and counts run newest or highest first, names A to Z. reverse flips the
    // order. Users without a value stay last either way.
    rows.sort((a, b) => {
      const va = sortValue(a);
      const vb = sortValue(b);
      if (va !== vb) {
        if (va === undefined) return 1;
        if (vb === undefined) return -1;
        return reverse ? va - vb : vb - va;
      }
      const na = nameKey(a);
      const nb = nameKey(b);
      if (na !== nb) return (sort === "name" && reverse ? -1 : 1) * (na < nb ? -1 : 1);
      return b.u.created_at.localeCompare(a.u.created_at) || a.u.id.localeCompare(b.u.id);
    });

    const versions = new Map<string, string>();
    for (const a of activity.values()) {
      if (a.app_version === undefined) continue;
      if ((versions.get(a.app_version) ?? "") < a.last_active_at) versions.set(a.app_version, a.last_active_at);
    }
    const pageRows = rows.slice((page - 1) * perPage, page * perPage);
    return {
      users: await Promise.all(
        pageRows.map(async (r) => ({
          id: r.u.id,
          email: r.u.email ?? null,
          phone: null,
          name: nameOf(r.u),
          avatarUrl: await avatarOf(ctx, r.u),
          lastSignInAt: r.u.last_sign_in_at ?? null,
          lastActiveAt: r.lastActive ?? null,
          createdAt: r.u.created_at,
          language: r.language,
          isBanned: r.u.banned_at !== undefined,
          bannedUntil: r.u.banned_at ?? null,
          isAdmin: r.u.role === "admin",
          isSuperAdmin: r.u.id === SUPERADMIN_USER_ID,
          appVersion: r.appVersion ?? null,
          shiftCount: r.shifts,
          messageCount: r.messages,
          friendCount: r.friends,
        })),
      ),
      totalCount: rows.length,
      appVersions: [...versions.entries()].sort(([, a], [, b]) => b.localeCompare(a)).map(([version]) => version),
      page,
      perPage,
      resultsArePartial: false,
    };
  },
});

export const userStats = query({
  args: { user_id: v.string() },
  handler: async (ctx, { user_id }) => {
    await requireAdmin(ctx);
    const today = new Date().toISOString().slice(0, 10);
    const monthAgo = addDays(today, -30);
    const byUser = <T extends { deleted_at?: string }>(rows: T[]) => rows.filter((r) => r.deleted_at === undefined);
    const shiftsAll = await ctx.db
      .query("user_shifts")
      .withIndex("by_user_shift_date", (q) => q.eq("user_id", user_id))
      .collect();
    const shifts = byUser(shiftsAll);
    const messages = byUser(
      await ctx.db
        .query("messages")
        .withIndex("by_sender", (q) => q.eq("sender_user_id", user_id))
        .collect(),
    );
    const tokens = (
      await ctx.db
        .query("calendar_subscription_tokens")
        .withIndex("by_user", (q) => q.eq("user_id", user_id))
        .collect()
    ).filter((t) => t.revoked_at === undefined);
    const activity = await ctx.db
      .query("user_app_activity")
      .withIndex("by_user", (q) => q.eq("user_id", user_id))
      .unique();
    const devices = await ctx.db
      .query("push_devices")
      .withIndex("by_user", (q) => q.eq("user_id", user_id))
      .collect();
    const max = (values: (string | undefined)[]) =>
      values.filter((x): x is string => x !== undefined).sort().at(-1) ?? null;
    const shares = await ctx.db.query("shift_shares").collect();
    const reports = await ctx.db.query("abuse_reports").collect();
    return {
      shiftCount: shifts.length,
      shiftsLast30Days: shifts.filter((s) => s.shift_date >= monthAgo && s.shift_date <= today).length,
      upcomingShiftCount: shifts.filter((s) => s.shift_date > today).length,
      firstShiftDate: shifts.map((s) => s.shift_date).sort()[0] ?? null,
      latestShiftDate: max(shifts.filter((s) => s.shift_date <= today).map((s) => s.shift_date)),
      lastShiftAddedAt: max(shiftsAll.map((s) => s.created_at)),
      jobCount: (
        await ctx.db
          .query("jobs")
          .withIndex("by_user_revision", (q) => q.eq("user_id", user_id))
          .collect()
      ).filter((j) => j.deleted_at === undefined && j.archived_at === undefined).length,
      recurringScheduleCount: byUser(
        await ctx.db
          .query("recurring_shifts")
          .withIndex("by_user_revision", (q) => q.eq("user_id", user_id))
          .collect(),
      ).length,
      eventCount: byUser(
        await ctx.db
          .query("events")
          .withIndex("by_user_revision", (q) => q.eq("user_id", user_id))
          .collect(),
      ).length,
      sharesTheirShiftsWith: shares.filter((s) => s.owner_id === user_id).length,
      seesShiftsFrom: shares.filter((s) => s.viewer_id === user_id).length,
      messagesSent: messages.length,
      messagesLast30Days: messages.filter((m) => m.created_at >= since(30)).length,
      feedbackCount: (
        await ctx.db
          .query("feedback")
          .withIndex("by_user", (q) => q.eq("user_id", user_id))
          .collect()
      ).length,
      reportsFiled: reports.filter((r) => r.reporter_user_id === user_id).length,
      reportsReceived: reports.filter((r) => r.reported_user_id === user_id).length,
      calendarFeedLastUsedAt: max(tokens.map((t) => t.last_used_at)),
      hasCalendarFeed: tokens.length > 0,
      appActivity:
        activity === null
          ? null
          : {
              firstActiveAt: activity.first_active_at,
              lastActiveAt: activity.last_active_at,
              openCount: activity.open_count,
              activeDays: activity.active_days,
              appVersion: activity.app_version ?? null,
              buildNumber: activity.build_number ?? null,
              previousAppVersion: activity.previous_app_version ?? null,
              previousBuildNumber: activity.previous_build_number ?? null,
              osVersion: activity.os_version ?? null,
              deviceModel: activity.device_model ?? null,
              locale: activity.locale ?? null,
              appLanguage: activity.app_language ?? null,
              timeZone: activity.time_zone ?? null,
              notificationPermission: activity.notification_permission ?? null,
              backgroundRefresh: activity.background_refresh ?? null,
              widgetKinds: activity.widget_kinds ?? null,
              appearance: activity.appearance ?? null,
              textSize: activity.text_size ?? null,
              reduceMotion: activity.reduce_motion ?? null,
            },
      devices: devices
        .map((d) => ({ id: d.id, platform: d.platform, appVersion: d.app_version ?? null, timeZone: d.time_zone, lastSeenAt: d.last_seen_at }))
        .sort((a, b) => b.lastSeenAt.localeCompare(a.lastSeenAt)),
    };
  },
});

export const userWageSetup = query({
  args: { user_id: v.string() },
  handler: async (ctx, { user_id }) => {
    await requireAdmin(ctx);
    const live = <T extends { deleted_at?: string }>(rows: T[]) => rows.filter((r) => r.deleted_at === undefined);
    const jobs = (
      await ctx.db
        .query("jobs")
        .withIndex("by_user_revision", (q) => q.eq("user_id", user_id))
        .collect()
    ).filter((j) => j.deleted_at === undefined && j.archived_at === undefined);
    const settings = await ctx.db
      .query("user_settings")
      .withIndex("by_user_revision", (q) => q.eq("user_id", user_id))
      .unique();
    return {
      jobs: jobs
        .sort((a, b) => Number(b.is_default) - Number(a.is_default) || a.sort_order - b.sort_order || a.created_at.localeCompare(b.created_at))
        .map(publicRow),
      snapshots: live(
        await ctx.db
          .query("wage_snapshots")
          .withIndex("by_user_revision", (q) => q.eq("user_id", user_id))
          .collect(),
      )
        .sort((a, b) => (a.from_date ?? "").localeCompare(b.from_date ?? "") || (a.created_at ?? "").localeCompare(b.created_at ?? ""))
        .map(publicRow),
      settings:
        settings === null
          ? null
          : {
              payrollDay: settings.payroll_day ?? null,
              monthlyGoal: settings.monthly_goal ?? null,
              currency: settings.currency ?? null,
              halfTaxMonth: settings.half_tax_month ?? null,
            },
      adjustments: live(
        await ctx.db
          .query("payroll_adjustments")
          .withIndex("by_user_revision", (q) => q.eq("user_id", user_id))
          .collect(),
      )
        .sort((a, b) => b.payout_date.localeCompare(a.payout_date) || b.created_at.localeCompare(a.created_at))
        .map(publicRow),
    };
  },
});

/** Distinct other people per hour for the last 24 hours and per day for the last 30. */
export const activeUsersChart = query({
  args: { time_zone: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const admin = await requireAdmin(ctx);
    const timeZone = args.time_zone ?? "Europe/Oslo";
    requireTimeZone(timeZone);
    const hourMs = 3_600_000;
    const currentHour = Math.floor(Date.now() / hourMs) * hourMs;
    const rows = (
      await ctx.db
        .query("app_activity_hours")
        .withIndex("by_hour_user", (q) => q.gte("hour", new Date(currentHour - 31 * DAY_MS).toISOString()))
        .collect()
    ).filter((r) => r.user_id !== admin.id);
    const hours = Array.from({ length: 24 }, (_, i) => new Date(currentHour - (23 - i) * hourMs).toISOString()).map((start) => ({
      start,
      users: rows.filter((r) => Date.parse(r.hour) === Date.parse(start)).length,
    }));
    const today = localDate(Date.now(), timeZone);
    const days = Array.from({ length: 30 }, (_, i) => addDays(today, -(29 - i))).map((date) => ({
      date,
      users: new Set(rows.filter((r) => localDate(Date.parse(r.hour), timeZone) === date).map((r) => r.user_id)).size,
    }));
    return { hours, days };
  },
});

// ---------- Dashboard ----------

export const stats = query({
  args: { time_zone: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const admin = await requireAdmin(ctx);
    const tz = args.time_zone ?? "Europe/Oslo";
    requireTimeZone(tz);
    const users = await ctx.db.query("users").collect();
    const lastActive = await lastActiveByUser(ctx);
    const others = users.filter((u) => u.id !== admin.id);
    const active7 = others.filter((u) => (lastActive.get(u.id) ?? "") >= since(7)).length;
    const active30 = new Set(others.filter((u) => (lastActive.get(u.id) ?? "") >= since(30)).map((u) => u.id));
    const activity = await ctx.db.query("user_app_activity").collect();
    const openers = activity.filter((a) => a.last_active_at >= since(30) && a.user_id !== admin.id);
    const accounts = users.length;
    const providerLabel: Json = { apple: "Apple", google: "Google", email: "Email", phone: "Phone" };

    const usersSection = {
      title: "Users",
      items: [
        {
          kind: "tiles",
          tiles: [
            { label: "Accounts", value: String(accounts) },
            { label: "New in 30 days", value: String(users.filter((u) => u.created_at >= since(30)).length) },
            { label: "Active in 7 days", value: String(active7) },
            { label: "Active in 30 days", value: String(active30.size) },
          ],
        },
        { kind: "series", title: "New accounts per week", points: weeklyCounts(users.map((u) => u.created_at), tz, 26) },
        breakdown(
          "Sign-in method",
          users.map((u) => {
            const p = u.providers?.[0];
            return p === undefined ? undefined : ((providerLabel[p] as string | undefined) ?? p);
          }),
        ),
      ],
    };

    const preauth = await ctx.db.query("onboarding_preauth_steps").collect();
    const cohort = new Set(preauth.filter((p) => p.step === "welcome" && p.reached_at >= since(30)).map((p) => p.install_id));
    const preauthCount = (step: string) => preauth.filter((p) => p.step === step && cohort.has(p.install_id)).length;
    const beforeSignup = {
      title: "Before sign-up",
      items: [
        {
          kind: "funnel",
          title: "Installs in the last 30 days",
          rows: [
            { label: "Saw the welcome screen", value: preauthCount("welcome") },
            { label: "Opened the demo", value: preauthCount("add_shift_simulator") },
            { label: "Added a demo shift", value: preauthCount("demo_shift_added") },
            { label: "Reached sign-up", value: preauthCount("signup_screen") },
          ],
        },
        { kind: "list", rows: [{ label: "Went to log in", value: String(preauthCount("login_screen")) }] },
      ],
    };

    const funnel = await ctx.db.query("onboarding_funnel_steps").collect();
    const stepCount = (step: string) => funnel.filter((f) => f.step === step).length;
    const viaLabels: Json = { manual: "Add screen", recurring: "Recurring schedule", clock: "Clock in", calendar_import: "Calendar import" };
    const setup = {
      title: "Setup after sign-up",
      items: [
        {
          kind: "funnel",
          title: "Setup",
          rows: [
            ["postauth_purpose", "Purpose"],
            ["postauth_wage", "Wage"],
            ["postauth_supplements", "Supplements"],
            ["postauth_jobBasics", "Job"],
            ["postauth_settingsAccordion", "Settings"],
            ["onboarding_completed", "Finished setup"],
            ["first_shift_added", "Added a first shift"],
          ].map(([step, label]) => ({ label, value: stepCount(step!) })),
        },
        breakdown(
          "First shift added with",
          funnel
            .filter((f) => f.step.startsWith("first_shift_via_"))
            .map((f) => {
              const via = f.step.slice("first_shift_via_".length);
              return (viaLabels[via] as string | undefined) ?? via;
            }),
        ),
        { kind: "list", rows: [{ label: "Started from the demo shift", value: String(stepCount("demo_shift_prefilled")) }] },
      ],
    };

    const shifts = await ctx.db.query("user_shifts").collect();
    const recurring = await ctx.db.query("recurring_shifts").collect();
    const firstShift = new Map<string, string>();
    for (const s of [...shifts, ...recurring]) {
      if (s.created_at === undefined) continue;
      const current = firstShift.get(s.user_id);
      if (current === undefined || s.created_at < current) firstShift.set(s.user_id, s.created_at);
    }
    const accountRows = users.map((u) => ({ u, first: firstShift.get(u.id), active: active30.has(u.id) }));
    const within = (r: (typeof accountRows)[number], days: number) =>
      r.first !== undefined && Date.parse(r.first) < Date.parse(r.u.created_at) + days * DAY_MS;
    const recent = accountRows.filter((r) => r.u.created_at >= since(97) && r.u.created_at < since(7));
    const settled = accountRows.filter((r) => r.u.created_at >= since(120) && r.u.created_at < since(30));
    const dayOne = recent.filter((r) => within(r, 1)).length;
    const firstWeek = recent.filter((r) => within(r, 7)).length;
    const returned = settled.filter((r) => r.active).length;
    const monthStart = `${localDate(Date.now(), tz).slice(0, 7)}-01`;
    const cohortStart = (() => {
      const d = new Date(`${monthStart}T00:00:00Z`);
      d.setUTCMonth(d.getUTCMonth() - 5);
      return d.toISOString().slice(0, 7);
    })();
    const cohorts = new Map<string, { total: number; logged: number; active: number }>();
    for (const r of accountRows) {
      const month = localDate(Date.parse(r.u.created_at), tz).slice(0, 7);
      if (month < cohortStart) continue;
      const c = cohorts.get(month) ?? { total: 0, logged: 0, active: 0 };
      c.total += 1;
      if (r.first !== undefined) c.logged += 1;
      if (r.active) c.active += 1;
      cohorts.set(month, c);
    }
    const monthName = (month: string) =>
      new Date(`${month}-01T00:00:00Z`).toLocaleString("en", { month: "short", timeZone: "UTC" });
    const activation = {
      title: "Activation",
      items: [
        {
          kind: "tiles",
          tiles: [
            { label: "Shift on day one", value: percent(dayOne, recent.length), caption: `of ${recent.length} new accounts`, progress: recent.length > 0 ? dayOne / recent.length : null },
            { label: "Shift in week one", value: percent(firstWeek, recent.length), caption: `of ${recent.length} new accounts`, progress: recent.length > 0 ? firstWeek / recent.length : null },
            { label: "Came back", value: percent(returned, settled.length), caption: "after 30+ days", progress: settled.length > 0 ? returned / settled.length : null },
          ],
        },
        {
          kind: "cohorts",
          title: "By sign-up month",
          rows: [...cohorts.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([month, c]) => ({ label: monthName(month), ...c })),
        },
      ],
    };

    const snapshots = (await ctx.db.query("wage_snapshots").collect()).filter((w) => w.deleted_at === undefined);
    // DISTINCT ON (user_id) ... ORDER BY from_date DESC NULLS LAST, created_at DESC
    const latestWage = new Map<string, Doc<"wage_snapshots">>();
    for (const w of [...snapshots].sort(
      (a, b) =>
        Number(a.from_date === undefined) - Number(b.from_date === undefined) ||
        (b.from_date ?? "").localeCompare(a.from_date ?? "") ||
        (b.created_at ?? "").localeCompare(a.created_at ?? ""),
    )) {
      if (!latestWage.has(w.user_id)) latestWage.set(w.user_id, w);
    }
    const prefs = await ctx.db.query("notification_preferences").collect();
    const jobs = await ctx.db.query("jobs").collect();
    const liveJobsPerUser = jobs
      .filter((j) => j.deleted_at === undefined && j.archived_at === undefined)
      .reduce((m, j) => m.set(j.user_id, (m.get(j.user_id) ?? 0) + 1), new Map<string, number>());
    const distinctLive = async (table: "payroll_adjustments" | "recurring_shifts" | "events") =>
      new Set((await ctx.db.query(table).collect()).filter((r) => r.deleted_at === undefined).map((r) => r.user_id)).size;
    const shiftWeeks = new Map<string, string>();
    for (const s of shifts) {
      if (s.created_at === undefined) continue;
      const key = `${s.user_id}:${mondayOf(localDate(Date.parse(s.created_at), tz))}`;
      const current = shiftWeeks.get(key);
      if (current === undefined || s.created_at < current) shiftWeeks.set(key, s.created_at);
    }
    const settingsRows = await ctx.db.query("user_settings").collect();
    const feeds = new Set(
      (await ctx.db.query("calendar_subscription_tokens").collect()).filter((t) => t.revoked_at === undefined).map((t) => t.user_id),
    );
    const shiftsSection = {
      title: "Shifts and pay",
      items: [
        {
          kind: "tiles",
          tiles: [
            { label: "Shifts added", value: String(shifts.filter((s) => (s.created_at ?? "") >= since(30)).length), caption: "last 30 days" },
            { label: "People adding", value: String(new Set(shifts.filter((s) => (s.created_at ?? "") >= since(30)).map((s) => s.user_id)).size), caption: "last 30 days" },
            { label: "Shifts saved", value: String(shifts.filter((s) => s.deleted_at === undefined).length), caption: "in total" },
          ],
        },
        { kind: "series", title: "Shifts added per week", points: weeklyCounts(shifts.map((s) => s.created_at), tz, 26) },
        { kind: "series", title: "People adding shifts per week", collapsed: true, points: weeklyCounts([...shiftWeeks.values()], tz, 26) },
        breakdown("Pay setup", [...latestWage.values()].map((w) => (w.tariff_type_id !== undefined ? "Tariff" : "Own hourly wage"))),
        breakdown("Tax deduction", [...latestWage.values()].map((w) => (w.tax_enabled ? "On" : "Off"))),
        {
          kind: "bars",
          title: "Features in use",
          total: accounts,
          rows: [
            { label: "Shift reminders", value: prefs.filter((p) => p.shift_reminders_enabled).length },
            { label: "Friend shift alerts", value: prefs.filter((p) => p.shared_shifts_enabled).length },
            { label: "More than one job", value: [...liveJobsPerUser.values()].filter((n) => n > 1).length },
            { label: "Pay adjustments", value: await distinctLive("payroll_adjustments") },
            { label: "Recurring schedules", value: await distinctLive("recurring_shifts") },
            { label: "Calendar events", value: await distinctLive("events") },
            { label: "Calendar feed", value: feeds.size },
          ].sort((a, b) => b.value - a.value || a.label.localeCompare(b.label)),
        },
        { ...breakdown("Currency", settingsRows.map((s) => s.currency)), collapsed: true },
      ],
    };

    const shares = (await ctx.db.query("shift_shares").collect()).filter((s) => s.blocked_by_user_id === undefined);
    const messages = await ctx.db.query("messages").collect();
    const threadCount = (await ctx.db.query("threads").collect()).length;
    const friendsSection = {
      title: "Friends",
      items: [
        {
          kind: "tiles",
          tiles: [
            { label: "Shares", value: String(shares.length) },
            { label: "People sharing", value: String(new Set(shares.map((s) => s.owner_id)).size) },
            { label: "Messages", value: String(messages.filter((m) => m.created_at >= since(30)).length), caption: "last 30 days" },
          ],
        },
        { kind: "series", title: "Messages per week", points: weeklyCounts(messages.map((m) => m.created_at), tz, 26) },
        {
          kind: "list",
          rows: [
            { label: "People messaging in 30 days", value: String(new Set(messages.filter((m) => m.created_at >= since(30)).map((m) => m.sender_user_id)).size) },
            { label: "Chats", value: String(threadCount) },
          ],
        },
      ],
    };

    const devices = await ctx.db.query("push_devices").collect();
    const latestDevice = new Map<string, Doc<"push_devices">>();
    for (const d of devices) {
      if (d.last_seen_at < since(30) || d.user_id === admin.id) continue;
      const current = latestDevice.get(d.user_id);
      if (current === undefined || d.last_seen_at > current.last_seen_at) latestDevice.set(d.user_id, d);
    }
    const withToken = new Set(devices.filter((d) => d.apns_token !== undefined).map((d) => d.user_id));
    const activeWithToken = [...withToken].filter((id) => active30.has(id)).length;
    const relabel = (map: Json) => (value: string | undefined) => (value === undefined ? undefined : ((map[value] as string | undefined) ?? value));
    const collapsed = (item: Json) => ({ ...item, collapsed: true });
    const app = {
      title: "App and devices",
      items: [
        {
          kind: "tiles",
          tiles: [
            { label: "Accounts with a push token", value: percent(withToken.size, accounts), caption: `${withToken.size} of ${accounts}`, progress: accounts > 0 ? withToken.size / accounts : null },
            {
              label: "Active people with a push token",
              value: percent(activeWithToken, active30.size),
              caption: `${activeWithToken} of ${active30.size} active in 30 days`,
              progress: active30.size > 0 ? activeWithToken / active30.size : null,
            },
          ],
        },
        breakdown("App version", [...latestDevice.values()].map((d) => d.app_version)),
        collapsed(breakdown("iOS version", openers.map((o) => o.os_version?.match(/^iOS [0-9]+/)?.[0]))),
        collapsed(breakdown("Device", openers.map((o) => o.device_model))),
        collapsed(breakdown("App language", openers.map((o) => o.app_language))),
        collapsed(
          breakdown(
            "Notifications",
            openers.map((o) =>
              relabel({ authorized: "Allowed", denied: "Denied", not_determined: "Not asked yet", provisional: "Provisional", ephemeral: "Ephemeral" })(
                o.notification_permission,
              ),
            ),
          ),
        ),
        collapsed(breakdown("Background refresh", openers.map((o) => relabel({ available: "On", denied: "Off", restricted: "Restricted" })(o.background_refresh)))),
        {
          ...breakdown("Widgets", [
            ...openers.flatMap((o) => (o.widget_kinds ?? []).map((k) => k.replace(/Widget$/, ""))),
            ...openers.filter((o) => (o.widget_kinds?.length ?? 0) === 0).map(() => "None"),
          ]),
          collapsed: true,
          total: openers.length,
        },
        collapsed(breakdown("Appearance", openers.map((o) => relabel({ light: "Light", dark: "Dark" })(o.appearance)))),
        collapsed(breakdown("Text size", openers.map((o) => o.text_size))),
        collapsed(breakdown("Reduce Motion", openers.map((o) => (o.reduce_motion === undefined ? undefined : o.reduce_motion ? "On" : "Off")))),
      ],
    };

    const problems = (
      await ctx.db
        .query("auth_diagnostic_events")
        .withIndex("by_occurred_at", (q) => q.gte("occurred_at", since(7)))
        .collect()
    ).filter((e) => e.severity === "warning" || e.severity === "error");
    const signIn = {
      title: "Sign-in problems",
      items: [
        {
          kind: "tiles",
          tiles: [
            { label: "Warnings and errors", value: String(problems.length), caption: "last 7 days" },
            { label: "Installs", value: String(new Set(problems.map((e) => e.metadata?.install_id).filter((x) => x !== undefined)).size) },
            { label: "Signed-in people", value: String(new Set(problems.map((e) => e.user_id).filter((x) => x !== undefined)).size) },
          ],
        },
        collapsed(breakdown("By event", problems.map((e) => e.event_type.replaceAll("_", " ") + (e.severity === "error" ? " (error)" : "")))),
      ],
    };

    return {
      generatedAt: new Date().toISOString(),
      sections: [usersSection, beforeSignup, setup, activation, shiftsSection, friendsSection, app, signIn],
    };
  },
});

// ---------- Feedback and reports ----------

export const feedback = query({
  args: { limit: v.optional(v.number()), offset: v.optional(v.number()) },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const rows = await ctx.db.query("feedback").withIndex("by_created_at").order("desc").collect();
    const limit = Math.min(Math.max(Math.floor(args.limit ?? 20), 1), 100);
    const offset = Math.max(Math.floor(args.offset ?? 0), 0);
    return {
      feedback: await Promise.all(
        rows.slice(offset, offset + limit).map(async (f) => {
          const user = await userByUuid(ctx, f.user_id);
          return {
            id: f.id,
            userId: f.user_id,
            message: f.message,
            userEmail: f.user_email,
            userName: nameOf(user),
            userProfilePicture: await avatarOf(ctx, user),
            createdAt: f.created_at,
            response: f.response ?? null,
            respondedAt: f.responded_at ?? null,
            respondedBy: f.responded_by ?? null,
          };
        }),
      ),
      total: rows.length,
    };
  },
});

export const respondFeedback = mutation({
  args: { feedback_id: v.string(), response: v.string() },
  handler: async (ctx, { feedback_id, response }) => {
    const admin = await requireAdmin(ctx);
    const row = await ctx.db
      .query("feedback")
      .withIndex("by_uuid", (q) => q.eq("id", feedback_id))
      .unique();
    if (row === null) return { success: false, error: "Feedback not found" };
    const firstResponse = row.response === undefined;
    await ctx.db.patch(row._id, { response: response.trim(), responded_at: new Date().toISOString(), responded_by: admin.id });
    // queue_feedback_responded_notification fired only on the first answer.
    if (firstResponse) await queueFeedbackResponded(ctx, (await ctx.db.get(row._id))!);
    return { success: true };
  },
});

const reportStatus = literals("open", "in_review", "actioned", "dismissed");

export const reports = query({
  args: { limit: v.optional(v.number()), offset: v.optional(v.number()), status: v.optional(reportStatus) },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const rows = (await ctx.db.query("abuse_reports").collect())
      .filter((r) => args.status === undefined || r.status === args.status)
      .sort((a, b) => b.created_at.localeCompare(a.created_at));
    const limit = Math.min(Math.max(Math.floor(args.limit ?? 20), 1), 100);
    const offset = Math.max(Math.floor(args.offset ?? 0), 0);
    return {
      reports: await Promise.all(
        rows.slice(offset, offset + limit).map(async (r) => {
          const reporter = await userByUuid(ctx, r.reporter_user_id);
          const reported = await userByUuid(ctx, r.reported_user_id);
          return {
            id: r.id,
            reporterUserId: r.reporter_user_id,
            reporterName: nameOf(reporter),
            reporterEmail: reporter?.email ?? null,
            reportedUserId: r.reported_user_id,
            reportedName: nameOf(reported),
            reportedEmail: reported?.email ?? null,
            threadId: r.thread_id,
            messageId: r.message_id ?? null,
            reason: r.reason,
            note: r.note ?? null,
            status: r.status,
            reviewerNotes: r.reviewer_notes ?? null,
            reviewedAt: r.reviewed_at ?? null,
            reviewedBy: r.reviewed_by ?? null,
            createdAt: r.created_at,
          };
        }),
      ),
      total: rows.length,
    };
  },
});

/** The messages around the reported one, or around the report time for user reports. */
export const reportMessages = query({
  args: { report_id: v.string(), context: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const admin = await requireAdmin(ctx);
    const report = await ctx.db
      .query("abuse_reports")
      .withIndex("by_uuid", (q) => q.eq("id", args.report_id))
      .unique();
    if (report === null) return { messages: [] };
    const context = Math.min(Math.max(Math.floor(args.context ?? 10), 1), 50);
    const anchorMessage =
      report.message_id === undefined
        ? null
        : await ctx.db
            .query("messages")
            .withIndex("by_uuid", (q) => q.eq("id", report.message_id!))
            .unique();
    // Without a message, messages sent at the report time count as "before".
    const anchor = { at: anchorMessage?.created_at ?? report.created_at, id: anchorMessage?.id ?? "ffffffff-ffff-ffff-ffff-ffffffffffff" };
    const all = await ctx.db
      .query("messages")
      .withIndex("by_thread_created_at", (q) => q.eq("thread_id", report.thread_id))
      .collect();
    const before = (m: Doc<"messages">) => m.created_at < anchor.at || (m.created_at === anchor.at && m.id <= anchor.id);
    const window = [...all.filter(before).slice(-(context + 1)), ...all.filter((m) => !before(m)).slice(0, context)];
    const reported = await userByUuid(ctx, report.reported_user_id);
    return {
      reportedAvatarUrl: await avatarOf(ctx, reported),
      messages: await Promise.all(window.map((m) => messagePayload(ctx, m, admin.id))),
    };
  },
});

export const deleteMessage = mutation({
  args: { message_id: v.string() },
  handler: async (ctx, { message_id }) => {
    const admin = await requireAdmin(ctx);
    const message = await ctx.db
      .query("messages")
      .withIndex("by_uuid", (q) => q.eq("id", message_id))
      .unique();
    if (message === null || message.deleted_at !== undefined) {
      return { success: false, error: "Message not found or already deleted" };
    }
    await softDeleteMessage(ctx, message);
    await logAction(ctx, admin, "message_deleted", message.sender_user_id, undefined, { message_id, thread_id: message.thread_id });
    return { success: true };
  },
});

export const updateReportStatus = mutation({
  args: { report_id: v.string(), status: reportStatus, reviewer_notes: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const admin = await requireAdmin(ctx);
    const report = await ctx.db
      .query("abuse_reports")
      .withIndex("by_uuid", (q) => q.eq("id", args.report_id))
      .unique();
    if (report === null) return { success: false, error: "Report not found" };
    await ctx.db.patch(report._id, {
      status: args.status,
      reviewer_notes: args.reviewer_notes?.trim() || undefined,
      reviewed_at: new Date().toISOString(),
      reviewed_by: admin.id,
    });
    return { success: true };
  },
});

export const auditLog = query({
  args: { limit: v.optional(v.number()), action_filter: v.optional(v.string()), target_filter: v.optional(v.string()) },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const limit = Math.min(Math.max(Math.floor(args.limit ?? 50), 1), 1000);
    const rows = (await ctx.db.query("admin_audit_log").withIndex("by_created_at").order("desc").collect())
      .filter((a) => (args.action_filter === undefined || a.action === args.action_filter) && (args.target_filter === undefined || a.target_user_id === args.target_filter))
      .slice(0, limit);
    return {
      success: true,
      entries: rows.map((a) => ({
        id: a.id,
        adminId: a.admin_id ?? null,
        adminEmail: a.admin_email,
        action: a.action,
        targetUserId: a.target_user_id ?? null,
        targetEmail: a.target_email ?? null,
        metadata: a.metadata ?? null,
        createdAt: a.created_at,
      })),
    };
  },
});

// ---------- Shares ----------

export const shares = query({
  args: { search: v.optional(v.string()), page: v.optional(v.number()), page_size: v.optional(v.number()) },
  handler: async (ctx, args) => {
    await requireAdmin(ctx);
    const page = Math.max(Math.floor(args.page ?? 1), 1);
    const pageSize = Math.min(Math.max(Math.floor(args.page_size ?? 20), 1), 100);
    const search = args.search?.toLowerCase() ?? "";
    const rows = [];
    for (const s of await ctx.db.query("shift_shares").collect()) {
      const owner = await userByUuid(ctx, s.owner_id);
      const viewer = await userByUuid(ctx, s.viewer_id);
      const haystack = [owner?.email, viewer?.email, owner?.name, viewer?.name, s.owner_id, s.viewer_id].map((x) => (x ?? "").toLowerCase());
      if (search !== "" && !haystack.some((x) => x.includes(search))) continue;
      rows.push({
        id: s.id,
        ownerId: s.owner_id,
        ownerEmail: owner?.email ?? null,
        ownerName: nameOf(owner),
        ownerPhone: null,
        viewerId: s.viewer_id,
        viewerEmail: viewer?.email ?? null,
        viewerName: nameOf(viewer),
        viewerPhone: null,
        createdAt: s.created_at,
        showEarnings: s.show_earnings,
        blocked: s.hidden,
        muted: s.muted,
      });
    }
    rows.sort((a, b) => b.createdAt.localeCompare(a.createdAt));
    return { success: true, shares: rows.slice((page - 1) * pageSize, page * pageSize), totalCount: rows.length, page, pageSize };
  },
});

async function shareById(ctx: QueryCtx, id: string) {
  return await ctx.db
    .query("shift_shares")
    .withIndex("by_uuid", (q) => q.eq("id", id))
    .unique();
}

export const createShare = mutation({
  args: { owner_id: v.string(), viewer_id: v.string(), show_earnings: v.optional(v.boolean()) },
  handler: async (ctx, args) => {
    const admin = await requireAdmin(ctx);
    if (args.owner_id === args.viewer_id) return { success: false, message: "Owner and viewer cannot be the same user" };
    const owner = await userByUuid(ctx, args.owner_id);
    const viewer = await userByUuid(ctx, args.viewer_id);
    if (owner === null || viewer === null) return { success: false, message: "User not found" };
    const existing = await ctx.db
      .query("shift_shares")
      .withIndex("by_owner_viewer", (q) => q.eq("owner_id", args.owner_id).eq("viewer_id", args.viewer_id))
      .unique();
    if (existing !== null) return { success: false, message: "This share already exists" };
    const id = crypto.randomUUID();
    const showEarnings = args.show_earnings ?? true;
    await ctx.db.insert("shift_shares", {
      id,
      owner_id: args.owner_id,
      viewer_id: args.viewer_id,
      show_earnings: showEarnings,
      blocked: false,
      muted: false,
      owner_muted: false,
      hidden: false,
      created_at: new Date().toISOString(),
      revision: await nextRevision(ctx),
    });
    await logAction(ctx, admin, "shift_share_created", id, undefined, {
      share_id: id,
      owner_id: args.owner_id,
      owner_email: owner.email ?? null,
      viewer_id: args.viewer_id,
      viewer_email: viewer.email ?? null,
      show_earnings: showEarnings,
    });
    return { success: true, id };
  },
});

export const updateShare = mutation({
  args: {
    share_id: v.string(),
    show_earnings: v.optional(v.boolean()),
    blocked: v.optional(v.boolean()),
    muted: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const admin = await requireAdmin(ctx);
    const share = await shareById(ctx, args.share_id);
    if (share === null) return { success: false, message: "Share not found" };
    await ctx.db.patch(share._id, {
      ...(args.show_earnings === undefined ? {} : { show_earnings: args.show_earnings }),
      ...(args.blocked === undefined ? {} : { hidden: args.blocked, blocked: args.blocked }),
      ...(args.muted === undefined ? {} : { muted: args.muted }),
      revision: await nextRevision(ctx),
    });
    await logAction(ctx, admin, "shift_share_updated", args.share_id, undefined, {
      show_earnings: args.show_earnings ?? null,
      blocked: args.blocked ?? null,
      muted: args.muted ?? null,
    });
    return { success: true };
  },
});

export const deleteShare = mutation({
  args: { share_id: v.string() },
  handler: async (ctx, { share_id }) => {
    const admin = await requireAdmin(ctx);
    const share = await shareById(ctx, share_id);
    if (share === null) return { success: false, message: "Share not found" };
    await ctx.db.delete(share._id);
    await logAction(ctx, admin, "shift_share_deleted", share_id, undefined, {});
    return { success: true };
  },
});

// ---------- Broadcasts ----------

export const broadcastHistory = query({
  args: {},
  handler: async (ctx) => {
    await requireAdmin(ctx);
    const broadcasts = await ctx.db.query("admin_broadcasts").withIndex("by_created_at").order("desc").take(10);
    return {
      broadcasts: await Promise.all(
        broadcasts.map(async (b) => {
          const rows = await ctx.db
            .query("notifications_outbox")
            .withIndex("by_broadcast", (q) => q.eq("broadcast_id", b.id))
            .collect();
          const n = (statuses: string[]) => rows.filter((r) => statuses.includes(r.status)).length;
          return {
            id: b.id,
            title: b.title ?? b.title_no ?? null,
            body: b.body ?? b.body_no ?? null,
            target: b.target,
            targetCount: b.target_count,
            status: b.status,
            createdAt: b.created_at,
            sentCount: n(["sent"]),
            failedCount: n(["failed"]),
            skippedCount: n(["skipped"]),
            pendingCount: n(["pending", "sending"]),
          };
        }),
      ),
    };
  },
});

export const broadcastDetail = query({
  args: { broadcast_id: v.string() },
  handler: async (ctx, { broadcast_id }) => {
    await requireAdmin(ctx);
    const b = await ctx.db
      .query("admin_broadcasts")
      .withIndex("by_uuid", (q) => q.eq("id", broadcast_id))
      .unique();
    if (b === null) throw new ConvexError({ code: "not_found", message: "Broadcast not found" });
    const sender = await userByUuid(ctx, b.admin_id);
    const order: Json = { failed: 0, pending: 1, sending: 1, skipped: 2 };
    const recipients = await Promise.all(
      (
        await ctx.db
          .query("notifications_outbox")
          .withIndex("by_broadcast", (q) => q.eq("broadcast_id", b.id))
          .take(2000)
      ).map(async (n) => {
        const u = await userByUuid(ctx, n.recipient_id);
        return {
          id: n.id,
          userId: n.recipient_id,
          name: nameOf(u),
          email: u?.email ?? null,
          phone: null,
          status: n.status,
          title: n.title,
          deeplink: (n.data_payload as Json | undefined)?.deeplink ?? null,
          attempts: n.attempts,
          errorMessage: n.error_message ?? null,
          processedAt: n.processed_at ?? null,
        };
      }),
    );
    recipients.sort(
      (a, c) =>
        ((order[a.status] as number | undefined) ?? 3) - ((order[c.status] as number | undefined) ?? 3) ||
        (a.name ?? a.email ?? "").toLowerCase().localeCompare((c.name ?? c.email ?? "").toLowerCase()),
    );
    return {
      id: b.id,
      title: b.title ?? null,
      body: b.body ?? null,
      deeplink: b.deeplink ?? null,
      titleNo: b.title_no ?? null,
      bodyNo: b.body_no ?? null,
      deeplinkNo: b.deeplink_no ?? null,
      target: b.target,
      targetCount: b.target_count,
      status: b.status,
      createdAt: b.created_at,
      adminEmail: sender?.email ?? null,
      recipients,
    };
  },
});

const broadcastTarget = literals("all", "active", "new", "specific");

/** The users a broadcast reaches: people with a push device, as the SQL counted them. */
async function broadcastAudience(
  ctx: QueryCtx,
  admin: Doc<"users">,
  target: "all" | "active" | "new" | "specific",
  specific: string[] | undefined,
  includeSelf: boolean,
) {
  if (target === "specific") return [...new Set(specific ?? [])];
  const withDevice = [...new Set((await ctx.db.query("push_devices").collect()).map((d) => d.user_id))];
  if (target === "all") return withDevice.filter((id) => includeSelf || id !== admin.id);
  if (target === "active") {
    const lastActive = await lastActiveByUser(ctx);
    return withDevice.filter((id) => (lastActive.get(id) ?? "") >= since(7));
  }
  const fresh = new Set((await ctx.db.query("users").collect()).filter((u) => u.created_at >= since(7)).map((u) => u.id));
  return withDevice.filter((id) => fresh.has(id));
}

export const previewTarget = query({
  args: { target: broadcastTarget, specific_user_ids: v.optional(v.array(v.string())), include_self: v.optional(v.boolean()) },
  handler: async (ctx, args) => {
    const admin = await requireAdmin(ctx);
    return { count: (await broadcastAudience(ctx, admin, args.target, args.specific_user_ids, args.include_self ?? false)).length };
  },
});

export const sendBroadcast = mutation({
  args: {
    title: v.optional(v.string()),
    title_no: v.optional(v.string()),
    body: v.optional(v.string()),
    body_no: v.optional(v.string()),
    target: broadcastTarget,
    deeplink: v.optional(v.string()),
    deeplink_no: v.optional(v.string()),
    specific_user_ids: v.optional(v.array(v.string())),
    include_self: v.optional(v.boolean()),
  },
  handler: async (ctx, args) => {
    const admin = await requireAdmin(ctx);
    const clean = (s: string | undefined) => s?.trim() || undefined;
    const [title, body, deeplink] = [clean(args.title), clean(args.body), clean(args.deeplink)];
    const [titleNo, bodyNo, deeplinkNo] = [clean(args.title_no), clean(args.body_no), clean(args.deeplink_no)];
    const hasEn = title !== undefined && body !== undefined;
    const hasNo = titleNo !== undefined && bodyNo !== undefined;
    const len = (s: string | undefined) => [...(s ?? "")].length;
    if (!hasEn && !hasNo) return { success: false, message: "Add a title and message in at least one language" };
    if (len(title) > 100 || len(titleNo) > 100) return { success: false, message: "Titles can be at most 100 characters" };
    if (len(body) > 500 || len(bodyNo) > 500) return { success: false, message: "Messages can be at most 500 characters" };
    const audience = await broadcastAudience(ctx, admin, args.target, args.specific_user_ids, args.include_self ?? false);
    if (audience.length === 0) return { success: false, message: "No users match target criteria" };

    const now = new Date().toISOString();
    const broadcastId = crypto.randomUUID();
    const docId = await ctx.db.insert("admin_broadcasts", {
      id: broadcastId,
      admin_id: admin.id,
      title: hasEn ? title : undefined,
      body: hasEn ? body : undefined,
      deeplink: hasEn ? deeplink : undefined,
      title_no: hasNo ? titleNo : undefined,
      body_no: hasNo ? bodyNo : undefined,
      deeplink_no: hasNo ? deeplinkNo : undefined,
      target: args.target,
      target_count: audience.length,
      status: "pending",
      created_at: now,
    });
    for (const userId of audience) {
      const user = await userByUuid(ctx, userId);
      if (user === null) continue;
      const useNo = (language(user.locale) === "no" && hasNo) || !hasEn;
      await enqueue(ctx, {
        owner_id: admin.id,
        recipient_id: userId,
        broadcast_id: broadcastId,
        notification_type: "admin_broadcast",
        title: (useNo ? titleNo : title)!,
        body: (useNo ? bodyNo : body)!,
        data_payload: { type: "admin_broadcast", deeplink: (useNo ? (deeplinkNo ?? deeplink) : deeplink) ?? null, broadcast_id: broadcastId },
        idempotency_key: `broadcast:${broadcastId}:${userId}`,
      });
    }
    await ctx.db.patch(docId, { status: "queued" });
    await scheduleSender(ctx, now);
    await logAction(ctx, admin, "broadcast_sent", undefined, undefined, {
      broadcast_id: broadcastId,
      title: (hasEn ? title : undefined) ?? titleNo ?? null,
      languages: [...(hasEn ? ["en"] : []), ...(hasNo ? ["no"] : [])],
      target: args.target,
      target_count: audience.length,
      deeplink: deeplink ?? deeplinkNo ?? null,
    });
    return { success: true, message: `Notification queued for ${audience.length} users` };
  },
});

// ---------- Ban and role (the admin-user-ban and admin-user-role Edge Functions) ----------

/**
 * Bans or unbans a user. Convex rejects a banned user's requests at once, and Clerk's
 * ban, applied to every Clerk user of the row, revokes their sessions.
 */
export const setBanned = mutation({
  args: { target_user_id: v.string(), ban: v.boolean() },
  handler: async (ctx, { target_user_id, ban }) => {
    const admin = await requireAdmin(ctx);
    const target = await userByUuid(ctx, target_user_id);
    const intended = ban ? "user_ban" : "user_unban";
    const fail = async (status: number, error: string) => {
      await logAction(ctx, admin, "admin_action_failed", target_user_id, target?.email, { error, intended_action: intended });
      return { success: false, status, error };
    };
    if (target_user_id === admin.id) return await fail(403, "Cannot ban yourself");
    if (target === null) return await fail(404, "User not found");
    if (ban && target.role === "admin") return await fail(403, "Cannot ban another admin");
    const wasBanned = target.banned_at !== undefined;
    if (wasBanned === ban) {
      // Clerk may have missed the earlier change, so a repeat syncs it again.
      await ctx.scheduler.runAfter(0, internal.admin.syncClerkBan, { user_id: target.id, attempt: 0 });
      return { success: true, message: ban ? "User is already banned" : "User is not banned" };
    }
    await ctx.db.patch(target._id, { banned_at: ban ? new Date().toISOString() : undefined, revision: await nextRevision(ctx) });
    await ctx.scheduler.runAfter(0, internal.admin.syncClerkBan, { user_id: target.id, attempt: 0 });
    await logAction(ctx, admin, intended, target_user_id, target.email, {
      old_value: { banned: wasBanned, banned_until: target.banned_at ?? null },
      new_value: { banned: ban },
    });
    return { success: true, message: ban ? "User banned successfully" : "User unbanned successfully" };
  },
});

export const clerkBanState = internalQuery({
  args: { user_id: v.string() },
  handler: async (ctx, { user_id }) => {
    const user = await userByUuid(ctx, user_id);
    if (user === null) return null;
    const aliases = await ctx.db
      .query("clerk_user_aliases")
      .withIndex("by_user", (q) => q.eq("user_id", user_id))
      .collect();
    return {
      banned: user.banned_at !== undefined,
      clerk_user_ids: [...(user.clerk_user_id === undefined ? [] : [user.clerk_user_id]), ...aliases.map((a) => a.clerk_user_id)],
    };
  },
});

/**
 * Makes Clerk match the ban state stored at the time it runs, so a late retry never
 * undoes a newer change. Scheduled actions aren't retried, so this reschedules itself.
 */
export const syncClerkBan = internalAction({
  args: { user_id: v.string(), attempt: v.number() },
  handler: async (ctx, { user_id, attempt }) => {
    const state = await ctx.runQuery(internal.admin.clerkBanState, { user_id });
    if (state === null) return;
    try {
      for (const id of state.clerk_user_ids) await setClerkBan(id, state.banned);
    } catch (error) {
      if (attempt >= 8) throw error;
      console.warn(`[admin] Clerk ban sync failed, retrying: ${error instanceof Error ? error.message : error}`);
      await ctx.scheduler.runAfter(Math.min(60_000 * 2 ** attempt, 3_600_000), internal.admin.syncClerkBan, { user_id, attempt: attempt + 1 });
    }
  },
});

/** Grants or revokes admin. Only the superadmin can, and not on themselves. */
export const setAdmin = mutation({
  args: { target_user_id: v.string(), grant: v.boolean() },
  handler: async (ctx, { target_user_id, grant }) => {
    const admin = await requireAdmin(ctx);
    if (admin.id !== SUPERADMIN_USER_ID) return { success: false, status: 403, error: "Superadmin access required" };
    const target = await userByUuid(ctx, target_user_id);
    const fail = async (status: number, error: string) => {
      await logAction(ctx, admin, "admin_action_failed", target_user_id, target?.email, {
        error,
        intended_action: grant ? "grant_admin" : "revoke_admin",
      });
      return { success: false, status, error };
    };
    if (target_user_id === admin.id) return await fail(403, "Cannot modify your own admin status");
    if (target === null) return await fail(404, "User not found");
    if ((target.role === "admin") === grant) {
      return { success: true, message: grant ? "User is already an admin" : "User is not an admin" };
    }
    await ctx.db.patch(target._id, { role: grant ? "admin" : undefined, revision: await nextRevision(ctx) });
    await logAction(ctx, admin, grant ? "grant_admin" : "revoke_admin", target_user_id, target.email, {
      old_value: { role: target.role ?? null },
      new_value: { role: grant ? "admin" : null },
    });
    return { success: true, message: grant ? "Admin privileges granted" : "Admin privileges revoked" };
  },
});
