import { expect, test } from "bun:test";
import { record } from "../convex/appActivity";
import { backfill, setMine } from "../convex/scheduleTimeZone";
import { friendsBootstrap, sharedMonth } from "../convex/sharing";
import { isScheduleTimeZone } from "../convex/lib/scheduleTimeZone";

// Run the real handlers, replacing only Convex's database and identity boundary.
function context() {
  const tables = new Map();
  let subject = "clerk-viewer";
  function rows(table) {
    if (!tables.has(table)) tables.set(table, []);
    return tables.get(table);
  }
  function seed(table, data) {
    const row = { _id: `${table}:${rows(table).length}`, ...data };
    rows(table).push(row);
    return row;
  }
  const db = {
    query(table) {
      let predicates = [];
      const selected = () => rows(table).filter(row => predicates.every(p => p(row)));
      const index = {
        eq(field, value) { predicates.push(row => row[field] === value); return index; },
        gte(field, value) { predicates.push(row => row[field] >= value); return index; },
        lte(field, value) { predicates.push(row => row[field] <= value); return index; },
      };
      const query = {
        withIndex(_name, build) { build(index); return query; },
        order() { return query; },
        filter() { return query; },
        unique: async () => selected()[0] ?? null,
        first: async () => selected()[0] ?? null,
        collect: async () => selected(),
        paginate: async () => ({ page: selected(), isDone: true, continueCursor: "done" }),
      };
      return query;
    },
    insert: async (table, data) => seed(table, data)._id,
    patch: async (id, patch) => {
      const row = [...tables.values()].flat().find(r => r._id === id);
      if (!row) throw new Error("Missing row");
      for (const [key, value] of Object.entries(patch)) {
        if (value === undefined) delete row[key]; else row[key] = value;
      }
    },
  };
  seed("users", { id: "viewer", clerk_user_id: subject, role: "user" });
  return { db, seed, rows, auth: { getUserIdentity: async () => subject === null ? null : ({ subject, sid: "session" }) },
    signIn: id => { subject = id; } };
}

test("accept named zones supported by both clients, reject offsets, abbreviations and invalid names", () => {
  for (const zone of ["Europe/Oslo", "Europe/London", "America/New_York", "Asia/Kolkata", "UTC"]) {
    expect(isScheduleTimeZone(zone)).toBe(true);
  }
  for (const zone of [undefined, "", "+01:00", "PST", "GMT+0100", "europe/oslo", "Europe/oslo", "Fake/City"]) {
    expect(isScheduleTimeZone(zone)).toBe(false);
  }
});

test("backfill is previewable and repeatable, and leaves explicit owner choices in place", async () => {
  const ctx = context();
  ctx.seed("user_app_activity", { user_id: "viewer", time_zone: "Europe/London" });
  ctx.seed("user_app_activity", { user_id: "invalid", time_zone: "PST" });
  ctx.seed("user_app_activity", { user_id: "chosen", time_zone: "America/New_York" });
  const chosen = ctx.seed("profiles", { id: "chosen", schedule_time_zone: "Asia/Tokyo" });
  const preview = await backfill._handler(ctx, { cursor: null, apply: false });
  expect(preview.eligible).toBe(1);
  expect(ctx.rows("profiles").length).toBe(1);
  await backfill._handler(ctx, { cursor: null, apply: true });
  expect(ctx.rows("profiles").find(p => p.id === "viewer").schedule_time_zone).toBe("Europe/London");
  expect(chosen.schedule_time_zone).toBe("Asia/Tokyo");
  expect((await backfill._handler(ctx, { cursor: null, apply: true })).eligible).toBe(0);
});

test("travel, a second device and an old client cannot move the shared schedule", async () => {
  const ctx = context();
  await record._handler(ctx, { time_zone: "Europe/London" });
  const profile = ctx.rows("profiles")[0];
  await record._handler(ctx, { time_zone: "America/New_York" });
  await record._handler(ctx, { time_zone: "Asia/Tokyo" });
  await record._handler(ctx, {});
  expect(profile.schedule_time_zone).toBe("Europe/London");
  await setMine._handler(ctx, { time_zone: "Europe/Oslo", expected_user_id: "viewer" });
  await record._handler(ctx, { time_zone: "Europe/London" });
  expect(profile.schedule_time_zone).toBe("Europe/Oslo");
});

test("only the owner can change the zone and impersonation cannot initialize it", async () => {
  const ctx = context();
  await expect(setMine._handler(ctx, { time_zone: "UTC", expected_user_id: "someone-else" })).rejects.toThrow("wrong_user");
  await expect(setMine._handler(ctx, { time_zone: "+01:00", expected_user_id: "viewer" })).rejects.toThrow("invalid_time_zone");
  ctx.signIn(null);
  await expect(setMine._handler(ctx, { time_zone: "UTC", expected_user_id: "viewer" })).rejects.toThrow("not_authorized");
  ctx.seed("users", { id: "admin", clerk_user_id: "clerk-admin", role: "admin" });
  ctx.seed("impersonation_sessions", { id: "imp", admin_user_id: "admin", target_user_id: "viewer",
    clerk_session_id: "session", expires_at: new Date(Date.now() + 60_000).toISOString() });
  ctx.signIn("clerk-admin");
  await record._handler(ctx, { time_zone: "Asia/Tokyo" });
  expect(ctx.rows("profiles").length).toBe(0);
  await expect(setMine._handler(ctx, { time_zone: "UTC", expected_user_id: "viewer" })).rejects.toThrow("not_authorized");
});

test("only authorized incoming schedules disclose their fixed zone", async () => {
  const ctx = context();
  for (const id of ["incoming", "outgoing", "blocked"]) {
    ctx.seed("users", { id, clerk_user_id: `clerk-${id}`, role: "user" });
    ctx.seed("profiles", { id, schedule_time_zone: "Europe/London" });
  }
  const share = { created_at: "2026-11-10T00:00:00Z", hidden: false, show_earnings: false };
  ctx.seed("shift_shares", { ...share, owner_id: "incoming", viewer_id: "viewer" });
  ctx.seed("shift_shares", { ...share, owner_id: "viewer", viewer_id: "outgoing" });
  ctx.seed("shift_shares", { ...share, owner_id: "blocked", viewer_id: "viewer", blocked_by_user_id: "viewer" });
  const bootstrap = await friendsBootstrap._handler(ctx, {});
  expect(bootstrap.previewPayloads.map(p => [p.sharer_id, p.owner_time_zone])).toEqual([["incoming", "Europe/London"]]);
  for (const friend of [...bootstrap.friends, ...bootstrap.blockedFriends]) {
    expect(friend).not.toHaveProperty("owner_time_zone");
    expect(friend).not.toHaveProperty("schedule_time_zone");
  }
  expect(await sharedMonth._handler(ctx, { owner_id: "outgoing", year: 2026, month: 11 })).toBeNull();
  expect(await sharedMonth._handler(ctx, { owner_id: "blocked", year: 2026, month: 11 })).toBeNull();
  expect((await sharedMonth._handler(ctx, { owner_id: "incoming", year: 2026, month: 11 })).owner_time_zone).toBe("Europe/London");
});
