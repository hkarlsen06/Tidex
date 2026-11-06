import { expect, test } from "bun:test";
import { friendsBootstrap, sharedMonth } from "../convex/sharing";

// Only the database and authenticated identity are replaced. Both public query
// handlers run their real authorization, schedule shaping and compatibility checks.
function context() {
  const tables = {
    users: [{ id: "viewer", clerk_user_id: "clerk-viewer", role: "user" }],
    shift_shares: ["reviewed", "legacy"].map((owner_id) => ({
      owner_id, viewer_id: "viewer", show_earnings: true, hidden: false,
      created_at: "2026-11-01",
    })),
    user_shifts: ["reviewed", "legacy"].map((user_id) => ({
      id: `${user_id}-shift`, user_id, job_id: `${user_id}-job`,
      shift_date: "2026-11-06", start_time: "08:00", end_time: "16:00",
    })),
    recurring_shifts: [],
    wage_snapshots: ["reviewed", "legacy"].map((user_id) => ({
      id: `${user_id}-wage`, user_id, job_id: `${user_id}-job`, hourly_wage: 200,
      supplements: { rules: user_id === "reviewed"
        ? [{ dates: ["2026-12-25"], rate: 100 }]
        : [{ days: [1], from: "18:00", to: "21:00", rate: 20 }] },
    })),
    jobs: ["reviewed", "legacy"].map((user_id) => ({
      id: `${user_id}-job`, user_id, name: user_id, sort_order: 0,
    })),
  };
  return {
    tables,
    auth: { getUserIdentity: async () => ({ subject: "clerk-viewer" }) },
    db: {
      query(table) {
        let rows = tables[table] ?? [];
        const index = {
          eq(field, value) { rows = rows.filter((r) => r[field] === value); return index; },
          gte(field, value) { rows = rows.filter((r) => r[field] >= value); return index; },
          lte(field, value) { rows = rows.filter((r) => r[field] <= value); return index; },
        };
        const query = {
          withIndex(_name, range) { range(index); return query; },
          order() { return query; },
          filter(predicate) {
            rows = rows.filter((r) => predicate({ field: (key) => r[key], eq: (a, b) => a === b }));
            return query;
          },
          collect: async () => rows,
          unique: async () => rows[0] ?? null,
          first: async () => rows[0] ?? null,
        };
        return query;
      },
    },
  };
}

test("older apps keep every friend and schedule when one friend uses reviewed pay rules", async () => {
  const response = await friendsBootstrap._handler(context(), {});
  expect(response.friends).toHaveLength(2);
  expect(response.sharers).toHaveLength(2);
  expect(response.sharers.find((s) => s.id === "reviewed").showEarnings).toBe(false);
  expect(response.sharers.find((s) => s.id === "legacy").showEarnings).toBe(true);
  const reviewed = response.previewPayloads.find((p) => p.sharer_id === "reviewed");
  expect(reviewed.show_earnings).toBe(false);
  expect(reviewed.shifts[0].id).toBe("reviewed-shift");
  expect(reviewed.jobs[0].id).toBe("reviewed-job");
  expect(reviewed.snapshots[0].hourly_wage).toBe(0);
  expect(reviewed.snapshots[0].supplements.rules).toEqual([]);
  const legacy = response.previewPayloads.find((p) => p.sharer_id === "legacy");
  expect(legacy.show_earnings).toBe(true);
  expect(legacy.snapshots[0].hourly_wage).toBe(200);
});

test("older apps can open the reviewed friend's month without an incorrect earnings amount", async () => {
  const response = await sharedMonth._handler(context(), { owner_id: "reviewed", year: 2026, month: 11 });
  expect(response.show_earnings).toBe(false);
  expect(response.shifts[0].id).toBe("reviewed-shift");
  expect(response.snapshots[0].hourly_wage).toBe(0);
});

test("current apps keep reviewed earnings and sharing permissions still hide them", async () => {
  const ctx = context();
  const args = { owner_id: "reviewed", year: 2026, month: 11, payroll_revision: "2026-11" };
  const visible = await sharedMonth._handler(ctx, args);
  expect(visible.show_earnings).toBe(true);
  expect(visible.snapshots[0].hourly_wage).toBe(200);
  expect(visible.snapshots[0].supplements.rules[0].rate).toBe(100);
  const bootstrap = await friendsBootstrap._handler(ctx, { payroll_revision: "2026-11" });
  expect(bootstrap.sharers.find((s) => s.id === "reviewed").showEarnings).toBe(true);
  ctx.tables.shift_shares[0].show_earnings = false;
  const hidden = await sharedMonth._handler(ctx, args);
  expect(hidden.show_earnings).toBe(false);
  expect(hidden.snapshots[0].hourly_wage).toBe(0);
  expect(hidden.snapshots[0].supplements.rules).toEqual([]);
});

for (const source of ["shift", "recurring shift"]) {
  test(`older apps also hide unsupported ${source} supplement overrides`, async () => {
    const ctx = context();
    ctx.tables.wage_snapshots[0].supplements.rules = [];
    const rich = { rules: [{ dates: ["2026-11-06"], rate: 100 }] };
    if (source === "shift") {
      ctx.tables.user_shifts[0].custom_supplements = rich;
    } else {
      ctx.tables.recurring_shifts.push({
        id: "recurring", user_id: "reviewed", job_id: "reviewed-job",
        start_time: "08:00", end_time: "16:00", repeat_interval_weeks: 1,
        selected_days: [5], date_specific_supplements: { "2026-11-06": rich },
      });
    }
    const response = await friendsBootstrap._handler(ctx, {});
    const reviewed = response.previewPayloads.find((p) => p.sharer_id === "reviewed");
    expect(reviewed.show_earnings).toBe(false);
    expect(reviewed.shifts[0].custom_supplements).toBeNull();
    if (source === "recurring shift") {
      expect(reviewed.recurring_shifts[0].id).toBe("recurring");
      expect(reviewed.recurring_shifts[0].date_specific_supplements).toBeNull();
    }
    const current = await friendsBootstrap._handler(ctx, { payroll_revision: "2026-11" });
    const visible = current.previewPayloads.find((p) => p.sharer_id === "reviewed");
    expect(visible.show_earnings).toBe(true);
    expect(source === "shift"
      ? visible.shifts[0].custom_supplements
      : visible.recurring_shifts[0].date_specific_supplements["2026-11-06"]
    ).toEqual(rich);
  });
}

test("an override outside the preview range still hides earnings in the friend's calendar", async () => {
  const ctx = context();
  ctx.tables.wage_snapshots[0].supplements.rules = [];
  ctx.tables.user_shifts.push({
    ...ctx.tables.user_shifts[0], id: "future-shift", shift_date: "2026-12-25",
    custom_supplements: { rules: [{ dates: ["2026-12-25"], rate: 100 }] },
  });
  const response = await friendsBootstrap._handler(ctx, {
    preview_start_date: "2026-11-02", preview_end_date: "2026-11-08",
  });
  expect(response.sharers.find((s) => s.id === "reviewed").showEarnings).toBe(false);
  const reviewed = response.previewPayloads.find((p) => p.sharer_id === "reviewed");
  expect(reviewed.show_earnings).toBe(false);
  expect(reviewed.shifts.map((s) => s.id)).toEqual(["reviewed-shift"]);
});
