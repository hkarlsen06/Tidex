import { ConvexError, v } from "convex/values";
import type { Doc } from "../_generated/dataModel";
import { type MutationCtx, mutation } from "../_generated/server";
import schema from "../schema";
import { requireViewer } from "./auth";
import { checkColumns } from "./columns";
import { nextRevision } from "./revision";

// Writes for the synced tables keyed by `id`. They keep the contract the app's sync
// coordinator has with Postgres:
// - insert takes a row with an id made on the device. If that id exists, it returns
//   the server row with status "exists", which replaces the 23505 refetch.
// - update and remove are compare-and-set on `revision` and skip deleted rows. A miss
//   returns status "conflict" with the server row (null if it is gone), which replaces
//   the zero-row result and the refetch by id.
// - Broken constraints throw ConvexError({ code }), which replaces the 22/23/P0 errors.
// The server sets user_id, created_at, updated_at, revision and deleted_at.

export type IdTable =
  | "jobs"
  | "user_shifts"
  | "events"
  | "recurring_shifts"
  | "wage_snapshots"
  | "payroll_adjustments";

export type Hooks<T extends IdTable> = {
  /** Values for columns with a Postgres default, used when the insert leaves them out. */
  defaults?: (ctx: MutationCtx, userId: string) => Promise<Partial<Doc<T>>>;
  /** Throws via reject() when the row breaks a rule. `prev` is null on insert. */
  check?: (
    ctx: MutationCtx,
    row: Doc<T>,
    prev: Doc<T> | null,
    changed: ReadonlySet<string>,
  ) => Promise<void>;
  /** Runs after an insert or update. Every other row it changes needs nextRevision(). */
  afterWrite?: (ctx: MutationCtx, row: Doc<T>, changed: ReadonlySet<string>) => Promise<void>;
  beforeRemove?: (ctx: MutationCtx, row: Doc<T>) => Promise<void>;
  afterRemove?: (ctx: MutationCtx, row: Doc<T>) => Promise<void>;
  /** Extra fields a remove sets, such as is_default: false on jobs. */
  removePatch?: Partial<Doc<T>>;
};

export function reject(code: string, message?: string): never {
  throw new ConvexError(message === undefined ? { code } : { code, message });
}

/** Character count as Postgres char_length() counts it. */
export const chars = (s: string) => [...s].length;

export function publicRow<D extends { _id: unknown; _creationTime: number }>(doc: D) {
  const { _id, _creationTime, ...row } = doc;
  return row;
}

const serverFields = ["user_id", "revision", "created_at", "updated_at", "deleted_at"] as const;

export function syncedTable<T extends IdTable>(
  table: T,
  hooks: Hooks<T> = {},
  defaultable: string[] = [],
) {
  // The generic table type is too wide for the validator and index types, so this file
  // works on loose types. The argument validators still check every call at runtime.
  const all = (schema.tables[table].validator as any).omit(...serverFields);
  const insertRow = defaultable.length
    ? all
        .omit(...defaultable)
        .extend(Object.fromEntries(defaultable.map((k) => [k, v.optional(all.fields[k])])))
    : all;
  const optionalFields = Object.keys(all.fields).filter(
    (k) => all.fields[k].isOptional === "optional",
  );
  // JSON can't carry undefined, so updates list the fields to clear.
  const clearable = v.array(v.union(...optionalFields.map((k) => v.literal(k))));

  const db = (ctx: MutationCtx): any => ctx.db;
  const byUuid = async (ctx: MutationCtx, id: string): Promise<any> =>
    await db(ctx).query(table).withIndex("by_uuid", (q: any) => q.eq("id", id)).unique();

  const insert = mutation({
    args: { row: insertRow },
    handler: async (ctx, { row }: { row: Record<string, unknown> & { id: string } }) => {
      const { user } = await requireViewer(ctx);
      const existing = await byUuid(ctx, row.id);
      if (existing !== null) {
        if (existing.user_id !== user.id) reject("id_taken");
        return { status: "exists" as const, row: publicRow(existing) };
      }
      checkColumns(table, row);
      const now = new Date().toISOString();
      const revision = await nextRevision(ctx);
      const doc = {
        ...(await hooks.defaults?.(ctx, user.id)),
        ...row,
        user_id: user.id,
        created_at: now,
        updated_at: now,
        revision,
      } as unknown as Doc<T>;
      const changed = new Set(Object.keys(row));
      await hooks.check?.(ctx, doc, null, changed);
      const saved: Doc<T> = await db(ctx).get(await db(ctx).insert(table, doc));
      await hooks.afterWrite?.(ctx, saved, changed);
      return { status: "ok" as const, row: publicRow(saved as any) };
    },
  });

  const update = mutation({
    args: {
      id: v.string(),
      expected_revision: v.number(),
      set: all.omit("id").partial(),
      clear: v.optional(clearable),
    },
    handler: async (
      ctx,
      args: {
        id: string;
        expected_revision: number;
        set: Record<string, unknown>;
        clear?: string[];
      },
    ) => {
      const { user } = await requireViewer(ctx);
      const prev = await byUuid(ctx, args.id);
      if (prev === null || prev.user_id !== user.id) return { status: "conflict" as const, row: null };
      if (prev.deleted_at !== undefined || prev.revision !== args.expected_revision) {
        return { status: "conflict" as const, row: publicRow(prev) };
      }
      checkColumns(table, args.set);
      const cleared = Object.fromEntries((args.clear ?? []).map((k) => [k, undefined]));
      const revision = await nextRevision(ctx);
      const patch = { ...args.set, ...cleared, updated_at: new Date().toISOString(), revision };
      const changed = new Set([...Object.keys(args.set), ...Object.keys(cleared)]);
      const next = { ...prev, ...patch };
      for (const k of Object.keys(cleared)) delete next[k];
      await hooks.check?.(ctx, next, prev, changed);
      await db(ctx).patch(prev._id, patch);
      const saved: Doc<T> = await db(ctx).get(prev._id);
      await hooks.afterWrite?.(ctx, saved, changed);
      return { status: "ok" as const, row: publicRow(saved as any) };
    },
  });

  /** Soft delete. The purge job removes the row later. */
  const remove = mutation({
    args: { id: v.string(), expected_revision: v.number() },
    handler: async (ctx, args) => {
      const { user } = await requireViewer(ctx);
      const prev = await byUuid(ctx, args.id);
      if (prev === null || prev.user_id !== user.id) return { status: "conflict" as const, row: null };
      if (prev.deleted_at !== undefined || prev.revision !== args.expected_revision) {
        return { status: "conflict" as const, row: publicRow(prev) };
      }
      await hooks.beforeRemove?.(ctx, prev);
      const now = new Date().toISOString();
      const revision = await nextRevision(ctx);
      await db(ctx).patch(prev._id, { ...hooks.removePatch, deleted_at: now, updated_at: now, revision });
      const saved: Doc<T> = await db(ctx).get(prev._id);
      await hooks.afterRemove?.(ctx, saved);
      return { status: "ok" as const, row: publicRow(saved as any) };
    },
  });

  return { insert, update, remove };
}

/** The job a shift, recurring shift, wage snapshot or payroll adjustment points to. */
export async function requireLiveJob(ctx: MutationCtx, userId: string, jobId: string) {
  const job = await ctx.db
    .query("jobs")
    .withIndex("by_uuid", (q) => q.eq("id", jobId))
    .unique();
  if (
    job === null ||
    job.user_id !== userId ||
    job.deleted_at !== undefined ||
    job.archived_at !== undefined
  ) {
    reject("job_not_available", "job_id must belong to same user");
  }
  return job;
}
