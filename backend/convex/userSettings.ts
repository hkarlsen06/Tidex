import { v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import { internalMutation, type MutationCtx, mutation, type QueryCtx } from "./_generated/server";
import { requireViewer } from "./lib/auth";
import { nextRevision } from "./lib/revision";
import { checkColumns } from "./lib/columns";
import { publicRow, reject, requireExpectedUser } from "./lib/syncWrite";
import schema from "./schema";

// One row per user, keyed by user_id. Same contract as lib/syncWrite.ts without remove:
// insert returns "exists" when the row is there, and update is compare-and-set on
// revision. The profile picture has its own upload path, so the app can't set it here.

const MONTH = /^[0-9]{4}-(0[1-9]|1[0-2])$/;
const mirrored = ["payroll_day", "half_tax_month", "monthly_goal", "currency"];

const all = schema.tables.user_settings.validator.omit(
  "user_id",
  "revision",
  "created_at",
  "updated_at",
  "profile_picture_storage_id",
);
const defaultable = [
  "monthly_goals_by_month",
  "theme",
  "calendar_animation_style",
  "calendar_content_color_style",
  "default_startup_tab",
  "show_dashboard_clock_buttons",
  "ai_data_sharing_enabled",
  "wagey_showcase_seen",
] as const;
const optionalFields = Object.entries(all.fields)
  .filter(([, validator]) => validator.isOptional === "optional")
  .map(([k]) => k);

/** The row as the app reads it, with profile_picture_url in place of the storage id. */
export async function settingsRow(ctx: QueryCtx, doc: Doc<"user_settings">) {
  const { profile_picture_storage_id, ...row } = publicRow(doc);
  if (profile_picture_storage_id === undefined) return row;
  return { ...row, profile_picture_url: await ctx.storage.getUrl(profile_picture_storage_id) };
}

async function ownSettings(ctx: QueryCtx, userId: string) {
  return await ctx.db
    .query("user_settings")
    .withIndex("by_user_revision", (q) => q.eq("user_id", userId))
    .unique();
}

function check(settings: Doc<"user_settings">) {
  const day = settings.payroll_day;
  if (day !== undefined && !(day >= 1 && day <= 31)) reject("invalid_row", "user_settings_payroll_day_check");
  const goals = settings.monthly_goals_by_month;
  const validGoals =
    typeof goals === "object" &&
    goals !== null &&
    !Array.isArray(goals) &&
    Object.entries(goals).every(
      ([month, goal]) =>
        MONTH.test(month) && Number.isInteger(goal) && (goal as number) >= 1 && (goal as number) <= 2147483647,
    );
  if (!validGoals) reject("invalid_row", "user_settings_monthly_goals_by_month_valid_entries");
}

// sync_legacy_settings_to_default_job: the default job takes the pay settings, and the
// settings take the default job's currency, because a job's currency never changes.
async function mirrorToDefaultJob(ctx: MutationCtx, settings: Doc<"user_settings">) {
  const job = (
    await ctx.db
      .query("jobs")
      .withIndex("by_user_revision", (q) => q.eq("user_id", settings.user_id))
      .collect()
  ).find((j) => j.is_default && j.deleted_at === undefined && j.archived_at === undefined);
  if (job === undefined) return;
  const now = new Date().toISOString();
  await ctx.db.patch(job._id, {
    payroll_day: settings.payroll_day,
    half_tax_month: settings.half_tax_month,
    monthly_goal: settings.monthly_goal,
    updated_at: now,
    revision: await nextRevision(ctx),
  });
  if (settings.currency !== job.currency) {
    await ctx.db.patch(settings._id, { currency: job.currency, updated_at: now });
  }
}

export const insert = mutation({
  args: {
    row: all
      .omit(...defaultable)
      .extend(Object.fromEntries(defaultable.map((k) => [k, v.optional(all.fields[k])]))),
    expected_user_id: v.string(),
  },
  handler: async (ctx, { row, expected_user_id }) => {
    const { user } = await requireViewer(ctx);
    requireExpectedUser(user.id, expected_user_id);
    const existing = await ownSettings(ctx, user.id);
    if (existing !== null) return { status: "exists" as const, row: await settingsRow(ctx, existing) };
    checkColumns("user_settings", row);
    const now = new Date().toISOString();
    const revision = await nextRevision(ctx);
    const doc = {
      monthly_goal: 20000,
      payroll_day: 15,
      currency: "kr",
      default_shifts_view: "calendar" as const,
      last_active: now,
      monthly_goals_by_month: {},
      theme: "dark" as const,
      calendar_animation_style: "horizontal" as const,
      calendar_content_color_style: "workplace" as const,
      default_startup_tab: "home" as const,
      show_dashboard_clock_buttons: true,
      ai_data_sharing_enabled: false,
      wagey_showcase_seen: false,
      ...row,
      user_id: user.id,
      created_at: now,
      updated_at: now,
      revision,
    };
    check(doc as Doc<"user_settings">);
    const saved = (await ctx.db.get(await ctx.db.insert("user_settings", doc)))!;
    await mirrorToDefaultJob(ctx, saved);
    return { status: "ok" as const, row: await settingsRow(ctx, (await ctx.db.get(saved._id))!) };
  },
});

export const update = mutation({
  args: {
    expected_revision: v.number(),
    set: all.partial(),
    clear: v.optional(v.array(v.union(...optionalFields.map((k) => v.literal(k))))),
  },
  handler: async (ctx, args) => {
    const { user } = await requireViewer(ctx);
    const prev = await ownSettings(ctx, user.id);
    if (prev === null) return { status: "conflict" as const, row: null };
    if (prev.revision !== args.expected_revision) {
      return { status: "conflict" as const, row: await settingsRow(ctx, prev) };
    }
    checkColumns("user_settings", args.set);
    const cleared = Object.fromEntries((args.clear ?? []).map((k) => [k, undefined]));
    const revision = await nextRevision(ctx);
    const patch = { ...args.set, ...cleared, updated_at: new Date().toISOString(), revision };
    const next = { ...prev, ...patch } as Record<string, unknown>;
    for (const k of Object.keys(cleared)) delete next[k];
    check(next as Doc<"user_settings">);
    await ctx.db.patch(prev._id, patch);
    const changed = [...Object.keys(args.set), ...Object.keys(cleared)];
    if (mirrored.some((k) => changed.includes(k))) {
      await mirrorToDefaultJob(ctx, (await ctx.db.get(prev._id))!);
    }
    return { status: "ok" as const, row: await settingsRow(ctx, (await ctx.db.get(prev._id))!) };
  },
});

/** Points the settings row at `storageId`, or clears the picture, and deletes the old file. */
async function swapProfilePicture(ctx: MutationCtx, storageId: Id<"_storage"> | undefined) {
  const { user } = await requireViewer(ctx);
  const prev = await ownSettings(ctx, user.id);
  // POST /profile-picture deletes the new file when this throws.
  if (prev === null) reject("not_found", "No settings row yet");
  await ctx.db.patch(prev._id, {
    profile_picture_storage_id: storageId,
    updated_at: new Date().toISOString(),
    revision: await nextRevision(ctx),
  });
  if (prev.profile_picture_storage_id !== undefined && prev.profile_picture_storage_id !== storageId) {
    await ctx.storage.delete(prev.profile_picture_storage_id);
  }
  return storageId === undefined ? null : await ctx.storage.getUrl(storageId);
}

/** Called by POST /profile-picture in http.ts after it stored the image. Returns the file URL. */
export const storeProfilePicture = internalMutation({
  args: { storage_id: v.id("_storage") },
  handler: async (ctx, { storage_id }) => await swapProfilePicture(ctx, storage_id),
});

export const clearProfilePicture = mutation({
  args: {},
  handler: async (ctx) => {
    await swapProfilePicture(ctx, undefined);
    return null;
  },
});
