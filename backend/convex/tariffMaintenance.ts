import { v, ConvexError } from "convex/values";
import { internalQuery } from "./_generated/server";
import { CATALOGUE_REVISION, tariffCatalogue } from "./lib/tariffCatalogue";
import { publicRow } from "./lib/syncWrite";

function requireDate(value: string) {
  if (
    !/^\d{4}-\d{2}-\d{2}$/.test(value) ||
    !Number.isFinite(Date.parse(value)) ||
    new Date(value).toISOString().slice(0, 10) !== value
  )
    throw new ConvexError("Invalid date");
}
function requireExclusions(ids: string[]) {
  if (
    ids.length === 0 ||
    ids.some(
      (id) =>
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
          id,
        ),
    )
  )
    throw new ConvexError(
      "Explicitly exclude the App Review account before inspecting user wage setups",
    );
}

// Internal queries require the deployment admin key. App sessions cannot read the inventory or proposals.
export const inventory = internalQuery({
  args: {},
  handler: async (ctx) => ({
    types: await ctx.db.query("tariff_types").collect(),
    versions: await ctx.db.query("tariff_versions").collect(),
  }),
});

export const impact = internalQuery({
  args: {
    as_of: v.string(),
    exclude_user_ids: v.array(v.string()),
    cursor: v.union(v.string(), v.null()),
  },
  handler: async (ctx, { as_of, exclude_user_ids, cursor }) => {
    requireDate(as_of);
    requireExclusions(exclude_user_ids);
    const page = await ctx.db.query("jobs").paginate({ cursor, numItems: 100 });
    const counts: Record<
      string,
      {
        jobs: number;
        below_catalogue: number;
        at_catalogue: number;
        above_catalogue: number;
        unknown_category: number;
      }
    > = {};
    for (const job of page.page) {
      if (
        job.archived_at ||
        job.deleted_at ||
        exclude_user_ids.includes(job.user_id)
      )
        continue;
      const snapshots = await ctx.db
        .query("wage_snapshots")
        .withIndex("by_job", (q) => q.eq("job_id", job.id))
        .collect();
      const snapshot = snapshots
        .filter((s) => !s.deleted_at && (!s.from_date || s.from_date <= as_of))
        .sort((a, b) =>
          (b.from_date ?? "").localeCompare(a.from_date ?? ""),
        )[0];
      if (!snapshot?.tariff_type_id) continue;
      const entry = tariffCatalogue.find(
        (candidate) => candidate.type.id === snapshot.tariff_type_id,
      );
      const rate =
        snapshot.wage_level === undefined || snapshot.wage_level === null
          ? undefined
          : entry?.version.rates[String(snapshot.wage_level)];
      const bucket = (counts[snapshot.tariff_type_id] ??= {
        jobs: 0,
        below_catalogue: 0,
        at_catalogue: 0,
        above_catalogue: 0,
        unknown_category: 0,
      });
      bucket.jobs++;
      if (rate === undefined) bucket.unknown_category++;
      else if (snapshot.hourly_wage < rate - 0.005) bucket.below_catalogue++;
      else if (snapshot.hourly_wage > rate + 0.005) bucket.above_catalogue++;
      else bucket.at_catalogue++;
    }
    return { counts, cursor: page.continueCursor, done: page.isDone };
  },
});

export const correctionProposal = internalQuery({
  args: {
    job_id: v.string(),
    expected_snapshot_id: v.string(),
    expected_revision: v.number(),
    from_date: v.string(),
    exclude_user_ids: v.array(v.string()),
  },
  handler: async (ctx, args) => {
    requireDate(args.from_date);
    requireExclusions(args.exclude_user_ids);
    const job = await ctx.db
      .query("jobs")
      .withIndex("by_uuid", (q) => q.eq("id", args.job_id))
      .unique();
    if (
      !job ||
      job.archived_at ||
      job.deleted_at ||
      args.exclude_user_ids.includes(job.user_id)
    )
      throw new ConvexError("Job is unavailable or excluded");
    const rows = await ctx.db
      .query("wage_snapshots")
      .withIndex("by_job", (q) => q.eq("job_id", job.id))
      .collect();
    const source = rows
      .filter(
        (r) => !r.deleted_at && (!r.from_date || r.from_date <= args.from_date),
      )
      .sort((a, b) => (b.from_date ?? "").localeCompare(a.from_date ?? ""))[0];
    if (
      !source ||
      source.id !== args.expected_snapshot_id ||
      source.revision !== args.expected_revision
    )
      throw new ConvexError("Wage setup changed; regenerate the proposal");
    if (rows.some((r) => !r.deleted_at && r.from_date === args.from_date))
      throw new ConvexError("A snapshot already exists on the proposed date");
    const entry = tariffCatalogue.find(
      (e) => e.type.id === source.tariff_type_id,
    );
    if (!entry || source.wage_level === undefined || source.wage_level === null)
      throw new ConvexError(
        "No verified category; choose qualification and schedule in the app",
      );
    const rate = entry.version.rates[String(source.wage_level)];
    if (
      rate === undefined ||
      args.from_date < entry.version.effective_date ||
      args.from_date > entry.version.valid_through
    )
      throw new ConvexError("Category or date is outside verified coverage");
    const proposedWage = Math.max(source.hourly_wage, rate);
    return {
      revision: CATALOGUE_REVISION,
      writes: 0,
      job_id: job.id,
      source_snapshot_id: source.id,
      expected_revision: source.revision,
      original: publicRow(source),
      proposed: {
        ...publicRow(source),
        id: null,
        from_date: args.from_date,
        hourly_wage: proposedWage,
        supplements: entry.version.supplements,
        overtime: entry.version.overtime,
      },
      changes: {
        hourly_wage: { before: source.hourly_wage, after: proposedWage },
        supplements: {
          before: source.supplements,
          after: entry.version.supplements,
        },
        overtime: { before: source.overtime, after: entry.version.overtime },
      },
      requires_review: [
        "Confirm employment agreement, category and schedule",
        "Reconcile custom supplements rather than replacing them",
        "Release compatible clients before applying rich payroll rules",
        "Historical compensation is a separate reviewed operation",
      ],
    };
  },
});
