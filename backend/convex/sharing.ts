import { ConvexError, v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import {
  action,
  internalMutation,
  internalQuery,
  mutation,
  type QueryCtx,
  query,
} from "./_generated/server";
import { getViewer, requireViewer, userByClerkId, userByUuid } from "./lib/auth";
import { clerkUsersWithVerifiedEmail } from "./lib/clerk";
import { isObjectionable } from "./lib/messaging";
import { queueScreenshot, queueShareStarted } from "./lib/notify";
import { nextRevision } from "./lib/revision";
import { publicRow, reject } from "./lib/syncWrite";

// Ports of get_friends_tab_bootstrap, get_shared_month_payload, get_my_profile_username
// and update_my_profile_last_synced_at. The JSON keeps the Postgres shapes so the app's
// decoders still work. Users have no phone in Convex, so `phone` is always null.

type Share = Doc<"shift_shares">;

const dayMs = 86_400_000;
const isoDate = (ms: number) => new Date(ms).toISOString().slice(0, 10);
const isoWeekday = (date: string) => (new Date(`${date}T00:00:00Z`).getUTCDay() + 6) % 7; // Monday is 0
/** The Monday on or before `date`. */
const weekStart = (date: string) => isoDate(Date.parse(`${date}T00:00:00Z`) - isoWeekday(date) * dayMs);
/** The Sunday on or after `date`. */
const weekEnd = (date: string) => isoDate(Date.parse(`${date}T00:00:00Z`) + (6 - isoWeekday(date)) * dayMs);

const emptyOvertime = { enabled: false, weeklyThresholdHours: 40, rules: [] };

async function profileOf(ctx: QueryCtx, userId: string) {
  const user = await userByUuid(ctx, userId);
  const profile = await ctx.db
    .query("profiles")
    .withIndex("by_uuid", (q) => q.eq("id", userId))
    .unique();
  const settings = await settingsOf(ctx, userId);
  return {
    id: userId,
    email: user?.email ?? null,
    phone: null,
    username: profile?.username ?? null,
    firstName: user?.name ?? null,
    profilePictureUrl: await pictureUrl(ctx, settings),
    oauthAvatarUrl: user?.avatar_url ?? null,
  };
}

async function settingsOf(ctx: QueryCtx, userId: string) {
  return await ctx.db
    .query("user_settings")
    .withIndex("by_user_revision", (q) => q.eq("user_id", userId))
    .unique();
}

async function pictureUrl(ctx: QueryCtx, settings: Doc<"user_settings"> | null) {
  return settings?.profile_picture_storage_id === undefined
    ? null
    : await ctx.storage.getUrl(settings.profile_picture_storage_id);
}

/**
 * What a viewer may see of an owner's schedule. Pay details are blanked unless the
 * owner turned on show_earnings for this viewer. `range` limits the shifts, and
 * `goalMonth` (YYYY-MM) picks that month's goal from monthly_goals_by_month.
 */
async function sharedSchedule(
  ctx: QueryCtx,
  ownerId: string,
  showEarnings: boolean,
  range: { from?: string; to?: string },
  goalMonth?: string,
) {
  const settings = await settingsOf(ctx, ownerId);
  const monthGoal = goalMonth === undefined ? undefined : settings?.monthly_goals_by_month?.[goalMonth];
  const settingsJson =
    settings === null
      ? { user_id: ownerId }
      : {
          user_id: settings.user_id,
          created_at: settings.created_at ?? null,
          updated_at: settings.updated_at,
          last_active: settings.last_active ?? null,
          monthly_goal:
            Number.isInteger(monthGoal) && monthGoal >= 0 ? monthGoal : (settings.monthly_goal ?? null),
          monthly_goals_by_month: settings.monthly_goals_by_month,
          default_shifts_view: settings.default_shifts_view ?? null,
          profile_picture_url: await pictureUrl(ctx, settings),
          payroll_day: settings.payroll_day ?? null,
          theme: settings.theme,
          half_tax_month: settings.half_tax_month ?? null,
          currency: settings.currency ?? null,
        };

  const shifts = (
    await ctx.db
      .query("user_shifts")
      .withIndex("by_user_shift_date", (q) => {
        const user = q.eq("user_id", ownerId);
        if (range.from !== undefined && range.to !== undefined) {
          return user.gte("shift_date", range.from).lte("shift_date", range.to);
        }
        if (range.from !== undefined) return user.gte("shift_date", range.from);
        if (range.to !== undefined) return user.lte("shift_date", range.to);
        return user;
      })
      .collect()
  )
    .filter((s) => s.deleted_at === undefined)
    .sort(
      (a, b) =>
        a.shift_date.localeCompare(b.shift_date) ||
        a.start_time.localeCompare(b.start_time) ||
        a.id.localeCompare(b.id),
    )
    .map((s) => ({
      id: s.id,
      user_id: s.user_id,
      job_id: s.job_id,
      shift_date: s.shift_date,
      start_time: s.start_time,
      end_time: s.end_time,
      custom_pause_windows: s.custom_pause_windows ?? null,
      custom_supplements: showEarnings ? (s.custom_supplements ?? null) : null,
      recurring_id: null,
      recurring_anchor_weekday: null,
    }));

  const recurring = (await liveRows(ctx, "recurring_shifts", ownerId))
    .sort((a, b) => a.id.localeCompare(b.id))
    .map((r) => ({
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
      date_specific_supplements: showEarnings ? (r.date_specific_supplements ?? null) : null,
    }));

  const snapshots = (await liveRows(ctx, "wage_snapshots", ownerId))
    .sort(
      (a, b) =>
        (b.from_date ?? "").localeCompare(a.from_date ?? "") || a.id.localeCompare(b.id),
    )
    .map((w) => {
      const shared = {
        id: w.id,
        user_id: w.user_id,
        job_id: w.job_id,
        from_date: w.from_date ?? null,
        break_enabled: w.break_enabled ?? null,
        break_method: w.break_method ?? null,
        break_threshold_hours: w.break_threshold_hours ?? null,
        break_deduction_minutes: w.break_deduction_minutes ?? null,
        created_at: w.created_at ?? null,
      };
      return showEarnings
        ? {
            ...shared,
            hourly_wage: w.hourly_wage,
            wage_level: w.wage_level ?? null,
            tariff_type_id: w.tariff_type_id ?? null,
            supplements: w.supplements,
            overtime: w.overtime ?? emptyOvertime,
            tax_enabled: w.tax_enabled ?? null,
            tax_percentage: w.tax_percentage ?? null,
          }
        : {
            ...shared,
            hourly_wage: 0,
            wage_level: null,
            tariff_type_id: null,
            supplements: { rules: [] },
            overtime: emptyOvertime,
            tax_enabled: false,
            tax_percentage: 0,
          };
    });

  const jobs = (
    await ctx.db
      .query("jobs")
      .withIndex("by_user_revision", (q) => q.eq("user_id", ownerId))
      .collect()
  )
    .sort(
      (a, b) =>
        a.sort_order - b.sort_order ||
        (a.created_at ?? "").localeCompare(b.created_at ?? "") ||
        a.id.localeCompare(b.id),
    )
    .map((j) => {
      const { revision, ...job } = publicRow(j);
      return job;
    });

  return { settings: settingsJson, shifts, recurring_shifts: recurring, snapshots, jobs };
}

/** A user's rows that are not soft-deleted. These tables hold few rows per user. */
async function liveRows<T extends "recurring_shifts" | "wage_snapshots">(
  ctx: QueryCtx,
  table: T,
  userId: string,
): Promise<Doc<T>[]> {
  // Both tables have this index, but TypeScript can't see that through the generic.
  const db = ctx.db as any;
  const rows: Doc<T>[] = await db
    .query(table)
    .withIndex("by_user_revision", (q: any) => q.eq("user_id", userId))
    .collect();
  return rows.filter((r) => r.deleted_at === undefined);
}

async function sharesWith(ctx: QueryCtx, userId: string) {
  const incoming = await ctx.db
    .query("shift_shares")
    .withIndex("by_viewer_revision", (q) => q.eq("viewer_id", userId))
    .collect();
  const outgoing = await ctx.db
    .query("shift_shares")
    .withIndex("by_owner_revision", (q) => q.eq("owner_id", userId))
    .collect();
  return { incoming, outgoing };
}

export const friendsBootstrap = query({
  args: {
    preview_start_date: v.optional(v.string()),
    preview_end_date: v.optional(v.string()),
  },
  handler: async (ctx, { preview_start_date, preview_end_date }) => {
    const { user } = await requireViewer(ctx);
    const { incoming, outgoing } = await sharesWith(ctx, user.id);
    const incomingBy = new Map(incoming.map((s) => [s.owner_id, s]));
    const outgoingBy = new Map(outgoing.map((s) => [s.viewer_id, s]));
    const ids = [...new Set([...incomingBy.keys(), ...outgoingBy.keys()])];
    const profiles = new Map(await Promise.all(ids.map(async (id) => [id, await profileOf(ctx, id)] as const)));

    const friendRows = ids
      .filter((id) => profiles.get(id) !== undefined)
      .map((id) => {
        const p = profiles.get(id)!;
        const i: Share | undefined = incomingBy.get(id);
        const o: Share | undefined = outgoingBy.get(id);
        return {
          json: {
            ...p,
            sharesWithMe:
              i === undefined
                ? null
                : {
                    hidden: i.hidden,
                    showEarningsToMe: i.show_earnings,
                    sharedAt: i.created_at,
                    notificationFrequency: i.muted ? "muted" : "instant",
                  },
            iShareWith:
              o === undefined
                ? null
                : { showEarningsToThem: o.show_earnings, sharedAt: o.created_at, ownerMuted: o.owner_muted },
          },
          blockedBy: i?.blocked_by_user_id ?? o?.blocked_by_user_id,
          sortName: (p.firstName ?? p.username ?? p.email ?? "").toLowerCase(),
        };
      });
    const bySortName = (a: { sortName: string }, b: { sortName: string }) =>
      a.sortName < b.sortName ? -1 : a.sortName > b.sortName ? 1 : 0;

    const visibleIncoming = incoming.filter((s) => s.blocked_by_user_id === undefined);
    const sharers = await Promise.all(
      [...visibleIncoming]
        .sort((a, b) => b.created_at.localeCompare(a.created_at))
        .map(async (s) => {
          const latest = (
            await ctx.db
              .query("user_shifts")
              .withIndex("by_user_shift_date", (q) => q.eq("user_id", s.owner_id))
              .order("desc")
              .filter((q) => q.eq(q.field("deleted_at"), undefined))
              .first()
          )?.shift_date;
          const hasRecurring = (await liveRows(ctx, "recurring_shifts", s.owner_id)).length > 0;
          return {
            ...profiles.get(s.owner_id)!,
            sharedAt: s.created_at,
            showEarnings: s.show_earnings,
            hidden: s.hidden,
            hasSharedCalendarContent: latest !== undefined || hasRecurring,
            latestSharedShiftDate: latest ?? null,
            hasRecurringSharedShifts: hasRecurring,
          };
        }),
    );

    const range = {
      from: preview_start_date === undefined ? undefined : weekStart(preview_start_date),
      to: preview_end_date === undefined ? undefined : weekEnd(preview_end_date),
    };
    const previewPayloads = await Promise.all(
      [...visibleIncoming]
        .sort((a, b) => a.owner_id.localeCompare(b.owner_id))
        .map(async (s) => ({
          sharer_id: s.owner_id,
          show_earnings: s.show_earnings,
          ...(await sharedSchedule(ctx, s.owner_id, s.show_earnings, range)),
        })),
    );

    return {
      sharers,
      friends: friendRows.filter((f) => f.blockedBy === undefined).sort(bySortName).map((f) => f.json),
      blockedFriends: friendRows.filter((f) => f.blockedBy === user.id).sort(bySortName).map((f) => f.json),
      capacity: { canAdd: true, currentCount: outgoing.length, limit: 0 },
      previewPayloads,
    };
  },
});

/** One month of a friend's schedule, padded to whole ISO weeks. Null without a share. */
export const sharedMonth = query({
  args: { owner_id: v.string(), year: v.number(), month: v.number() },
  handler: async (ctx, { owner_id, year, month }) => {
    const { user } = await requireViewer(ctx);
    const share = await ctx.db
      .query("shift_shares")
      .withIndex("by_owner_viewer", (q) => q.eq("owner_id", owner_id).eq("viewer_id", user.id))
      .unique();
    if (share === null || share.blocked_by_user_id !== undefined) return null;
    const first = isoDate(Date.UTC(year, month - 1, 1));
    const last = isoDate(Date.UTC(year, month, 0));
    return {
      owner_id,
      show_earnings: share.show_earnings,
      ...(await sharedSchedule(
        ctx,
        owner_id,
        share.show_earnings,
        { from: weekStart(first), to: weekEnd(last) },
        first.slice(0, 7),
      )),
    };
  },
});

export const myUsername = query({
  args: {},
  handler: async (ctx) => {
    const { user } = await requireViewer(ctx);
    const profile = await ctx.db
      .query("profiles")
      .withIndex("by_uuid", (q) => q.eq("id", user.id))
      .unique();
    return profile?.username ?? null;
  },
});

/**
 * Port of set_my_profile_username. An empty name clears it. Errors carry the codes
 * "username_invalid", "username_blocked" and "username_taken".
 */
export const setMyUsername = mutation({
  args: { username: v.string() },
  handler: async (ctx, { username }) => {
    const { user } = await requireViewer(ctx);
    const value = username.trim().toLowerCase();
    if (value !== "") {
      if (isObjectionable(value)) reject("username_blocked", "Username blocked by safety filter");
      if (!/^[a-z0-9_]{3,20}$/.test(value) || !/[a-z]/.test(value)) reject("username_invalid");
      const taken = await ctx.db
        .query("profiles")
        .withIndex("by_username", (q) => q.eq("username", value))
        .first();
      if (taken !== null && taken.id !== user.id) reject("username_taken");
    }
    const profile = await ctx.db
      .query("profiles")
      .withIndex("by_uuid", (q) => q.eq("id", user.id))
      .unique();
    const now = new Date().toISOString();
    const revision = await nextRevision(ctx);
    if (profile === null) {
      await ctx.db.insert("profiles", {
        id: user.id,
        before_paywall: true,
        username: value === "" ? undefined : value,
        created_at: now,
        updated_at: now,
        revision,
      });
    } else {
      await ctx.db.patch(profile._id, {
        username: value === "" ? undefined : value,
        updated_at: now,
        revision,
      });
    }
    return value === "" ? null : value;
  },
});

export const setLastSyncedAt = mutation({
  args: { last_synced_at: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const { user } = await requireViewer(ctx);
    const parsed = args.last_synced_at === undefined ? Number.NaN : Date.parse(args.last_synced_at);
    const now = new Date().toISOString();
    const lastSyncedAt = Number.isNaN(parsed) ? now : new Date(parsed).toISOString();
    const profile = await ctx.db
      .query("profiles")
      .withIndex("by_uuid", (q) => q.eq("id", user.id))
      .unique();
    const revision = await nextRevision(ctx);
    if (profile === null) {
      await ctx.db.insert("profiles", {
        id: user.id,
        before_paywall: true,
        last_synced_at: lastSyncedAt,
        created_at: now,
        updated_at: now,
        revision,
      });
    } else {
      await ctx.db.patch(profile._id, { last_synced_at: lastSyncedAt, updated_at: now, revision });
    }
    return lastSyncedAt;
  },
});

// ---- Writes ----

async function shareBetween(ctx: QueryCtx, ownerId: string, viewerId: string) {
  return await ctx.db
    .query("shift_shares")
    .withIndex("by_owner_viewer", (q) => q.eq("owner_id", ownerId).eq("viewer_id", viewerId))
    .unique();
}

/** I stop sharing with `viewer_id`. A block by the other user keeps the row. */
export const removeShare = mutation({
  args: { viewer_id: v.string() },
  handler: async (ctx, { viewer_id }) => {
    const { user } = await requireViewer(ctx);
    const share = await shareBetween(ctx, user.id, viewer_id);
    if (share === null || (share.blocked_by_user_id ?? user.id) !== user.id) return false;
    await ctx.db.delete(share._id);
    return true;
  },
});

/** I remove `owner_id` from the people who share with me. */
export const removeSharer = mutation({
  args: { owner_id: v.string() },
  handler: async (ctx, { owner_id }) => {
    const { user } = await requireViewer(ctx);
    const share = await shareBetween(ctx, owner_id, user.id);
    if (share === null || (share.blocked_by_user_id ?? user.id) !== user.id) return false;
    await ctx.db.delete(share._id);
    return true;
  },
});

/** The owner's side of a share: show_earnings and owner_muted. */
export const updateMyShare = mutation({
  args: {
    viewer_id: v.string(),
    show_earnings: v.optional(v.boolean()),
    owner_muted: v.optional(v.boolean()),
  },
  handler: async (ctx, { viewer_id, ...fields }) => {
    const { user } = await requireViewer(ctx);
    const share = await shareBetween(ctx, user.id, viewer_id);
    if (share === null) return false;
    await ctx.db.patch(share._id, { ...fields, revision: await nextRevision(ctx) });
    return true;
  },
});

/** The viewer's side of a share: hidden (and the legacy `blocked` copy) and muted. */
export const updateSharer = mutation({
  args: {
    owner_id: v.string(),
    hidden: v.optional(v.boolean()),
    muted: v.optional(v.boolean()),
  },
  handler: async (ctx, { owner_id, hidden, muted }) => {
    const { user } = await requireViewer(ctx);
    const share = await shareBetween(ctx, owner_id, user.id);
    if (share === null) return false;
    await ctx.db.patch(share._id, {
      ...(hidden === undefined ? {} : { hidden, blocked: hidden }),
      ...(muted === undefined ? {} : { muted }),
      revision: await nextRevision(ctx),
    });
    return true;
  },
});

/** Port of block_user_pair. Hides both directions of the pair's share. */
export const blockUser = mutation({
  args: { other_user_id: v.string() },
  handler: async (ctx, { other_user_id }) => {
    const { user } = await requireViewer(ctx);
    if (other_user_id === user.id) reject("invalid", "Cannot block yourself");
    const shares = [await shareBetween(ctx, user.id, other_user_id), await shareBetween(ctx, other_user_id, user.id)];
    if (shares.every((s) => s === null)) reject("not_found", "No sharing relationship exists for this user pair");
    // One block per pair. Overwriting the other user's block would let the blocked user
    // take it over and then unblock themselves.
    if (shares.some((s) => s !== null && s.blocked_by_user_id !== undefined && s.blocked_by_user_id !== user.id)) {
      reject("blocked_by_other", "The other user has blocked this pair");
    }
    for (const share of shares) {
      if (share === null) continue;
      await ctx.db.patch(share._id, {
        hidden: true,
        blocked: true,
        blocked_by_user_id: user.id,
        revision: await nextRevision(ctx),
      });
    }
    return null;
  },
});

/** Port of unblock_user_pair. Only the user who blocked can unblock. */
export const unblockUser = mutation({
  args: { other_user_id: v.string() },
  handler: async (ctx, { other_user_id }) => {
    const { user } = await requireViewer(ctx);
    if (other_user_id === user.id) reject("invalid", "Cannot unblock yourself");
    const shares = [await shareBetween(ctx, user.id, other_user_id), await shareBetween(ctx, other_user_id, user.id)]
      .filter((s) => s !== null && s.blocked_by_user_id === user.id);
    if (shares.length === 0) reject("not_found", "No active block exists for this user pair");
    for (const share of shares) {
      await ctx.db.patch(share!._id, {
        hidden: false,
        blocked: false,
        blocked_by_user_id: undefined,
        revision: await nextRevision(ctx),
      });
    }
    return null;
  },
});

// The app shows these Norwegian messages as they are. manage_sharing_action's versions also named phone numbers.
const shareErrors = {
  noIdentifier: "Vennligst oppgi en gyldig e-post eller et brukernavn",
  notFound: "Fant ingen bruker med denne e-posten eller dette brukernavnet",
  self: "Du kan ikke dele med deg selv",
  blocked: "Du kan ikke dele vaktene dine med denne brukeren",
  exists: "Du deler allerede vaktene dine med denne brukeren",
};

type ShareResult = { success: true } | { success: false; error: string };

/** Starts sharing my shifts with `target_id`. Shared by createShare and shareBack. */
export const startShare = internalMutation({
  args: { owner_id: v.string(), target_id: v.union(v.string(), v.null()), show_earnings: v.boolean() },
  handler: async (ctx, { owner_id, target_id, show_earnings }): Promise<ShareResult> => {
    if (target_id === null || (await userByUuid(ctx, target_id)) === null) {
      return { success: false, error: shareErrors.notFound };
    }
    if (target_id === owner_id) return { success: false, error: shareErrors.self };
    const mine = await shareBetween(ctx, owner_id, target_id);
    const theirs = await shareBetween(ctx, target_id, owner_id);
    if ([mine, theirs].some((s) => s?.blocked_by_user_id !== undefined && s !== null)) {
      return { success: false, error: shareErrors.blocked };
    }
    if (mine !== null) return { success: false, error: shareErrors.exists };
    await ctx.db.insert("shift_shares", {
      id: crypto.randomUUID(),
      owner_id,
      viewer_id: target_id,
      show_earnings,
      blocked: false,
      muted: false,
      owner_muted: false,
      hidden: false,
      created_at: new Date().toISOString(),
      revision: await nextRevision(ctx),
    });
    await queueShareStarted(ctx, owner_id, target_id);
    return { success: true };
  },
});

export const shareBack = mutation({
  args: { recipient_id: v.string(), show_earnings: v.optional(v.boolean()) },
  handler: async (ctx, { recipient_id, show_earnings }): Promise<ShareResult> => {
    const { user } = await requireViewer(ctx);
    return await ctx.runMutation(internal.sharing.startShare, {
      owner_id: user.id,
      target_id: recipient_id,
      show_earnings: show_earnings ?? false,
    });
  },
});

/**
 * Port of manage_sharing_action's createShare. An identifier with @ inside it is an
 * email, matched only against verified addresses in Clerk. Anything else is a username,
 * with or without a leading @. N+1 has no phone sign-in, so phone numbers match nobody.
 */
export const createShare = action({
  args: { identifier: v.string(), show_earnings: v.optional(v.boolean()) },
  handler: async (ctx, { identifier, show_earnings }): Promise<ShareResult> => {
    const owner = await ctx.runQuery(internal.sharing.viewerId, {});
    if (owner === null) throw new ConvexError({ code: "not_authorized" });
    const trimmed = identifier.trim();
    if (trimmed === "") return { success: false, error: shareErrors.noIdentifier };

    let target: string | null;
    if (trimmed.includes("@") && !trimmed.startsWith("@")) {
      const clerkUsers = await clerkUsersWithVerifiedEmail(trimmed);
      target = await ctx.runQuery(internal.sharing.userIdForClerkUsers, {
        clerk_user_ids: clerkUsers.map((u) => u.id),
      });
    } else {
      const username = trimmed.toLowerCase().replace(/^@/, "");
      target = await ctx.runQuery(internal.sharing.userIdForUsername, { username });
    }
    return await ctx.runMutation(internal.sharing.startShare, {
      owner_id: owner,
      target_id: target,
      show_earnings: show_earnings ?? false,
    });
  },
});

export const viewerId = internalQuery({
  args: {},
  handler: async (ctx) => (await getViewer(ctx))?.user.id ?? null,
});

export const userIdForClerkUsers = internalQuery({
  args: { clerk_user_ids: v.array(v.string()) },
  handler: async (ctx, { clerk_user_ids }) => {
    for (const id of clerk_user_ids) {
      const user = await userByClerkId(ctx, id);
      if (user !== null) return user.id;
    }
    return null;
  },
});

export const userIdForUsername = internalQuery({
  args: { username: v.string() },
  handler: async (ctx, { username }) =>
    (
      await ctx.db
        .query("profiles")
        .withIndex("by_username", (q) => q.eq("username", username))
        .first()
    )?.id ?? null,
});

/** Port of report_sharing_screenshot: tells the owner whose shifts were captured. */
export const reportScreenshot = mutation({
  args: { sharer_id: v.string() },
  handler: async (ctx, { sharer_id }) => {
    const { user } = await requireViewer(ctx);
    if (sharer_id === user.id) return { success: true, skipped: true };
    if ((await shareBetween(ctx, sharer_id, user.id)) === null) reject("forbidden", "No access to sharer");
    await queueScreenshot(ctx, user.id, sharer_id, undefined);
    return { success: true };
  },
});
