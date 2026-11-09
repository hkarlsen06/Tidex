import { afterEach, expect, setSystemTime, test } from "bun:test";
import { recordAuthEvent } from "../convex/diagnostics";

afterEach(() => setSystemTime());

// Run the diagnostic mutation and real outbox enqueue together, replacing storage
// and the scheduler so no test can send a push.
function context() {
  const tables = {
    users: [{ id: "user-a", clerk_user_id: "clerk-a", role: "user" }],
    auth_diagnostic_events: [],
    notifications_outbox: [],
  };
  return {
    tables,
    auth: { getUserIdentity: async () => ({ subject: "clerk-a" }) },
    scheduler: { runAt: async () => {} },
    db: {
      query(table) {
        let rows = tables[table] ?? [];
        const index = {
          eq(field, value) { rows = rows.filter((row) => row[field] === value); return index; },
        };
        const query = {
          withIndex(_name, range) { range(index); return query; },
          unique: async () => rows[0] ?? null,
          first: async () => rows[0] ?? null,
        };
        return query;
      },
      async insert(table, row) {
        const _id = `${table}-${tables[table].length}`;
        tables[table].push({ ...row, _id });
        return _id;
      },
      async get(id) {
        return Object.values(tables).flat().find((row) => row._id === id) ?? null;
      },
    },
  };
}

const warning = {
  event_type: "session_fetch_failed",
  severity: "warning",
  error_kind: "AuthSessionManagerError",
  error_message: "Session retrieval timed out",
};

test("seven session timeouts retain all diagnostics but send one developer alert", async () => {
  setSystemTime(new Date("2026-11-09T13:06:35Z"));
  const ctx = context();
  for (let i = 0; i < 7; i++) await recordAuthEvent._handler(ctx, warning);
  expect(ctx.tables.auth_diagnostic_events).toHaveLength(7);
  expect(ctx.tables.notifications_outbox).toHaveLength(1);
  expect(ctx.tables.notifications_outbox[0].data_payload.diagnostic_event_id)
    .toBe(ctx.tables.auth_diagnostic_events[0].id);
});

test("cooldown crosses quarter-hour boundaries and alerts again after 15 minutes", async () => {
  const ctx = context();
  setSystemTime(new Date("2026-11-09T13:14:59Z"));
  await recordAuthEvent._handler(ctx, warning);
  ctx.tables.notifications_outbox[0].status = "sent";
  setSystemTime(new Date("2026-11-09T13:15:01Z"));
  await recordAuthEvent._handler(ctx, warning);
  setSystemTime(new Date("2026-11-09T13:29:58Z"));
  await recordAuthEvent._handler(ctx, warning);
  expect(ctx.tables.notifications_outbox).toHaveLength(1);
  setSystemTime(new Date("2026-11-09T13:29:59Z"));
  await recordAuthEvent._handler(ctx, warning);
  expect(ctx.tables.notifications_outbox).toHaveLength(2);
});

test("escalations, different failures and other users still alert during cooldown", async () => {
  const ctx = context();
  await recordAuthEvent._handler(ctx, warning);
  await recordAuthEvent._handler(ctx, { ...warning, severity: "error" });
  await recordAuthEvent._handler(ctx, { ...warning, error_kind: "ClerkAPIError" });
  await recordAuthEvent._handler(ctx, { ...warning, event_type: "foreground_session_failed" });
  ctx.tables.users[0].id = "user-b";
  await recordAuthEvent._handler(ctx, warning);
  expect(ctx.tables.notifications_outbox).toHaveLength(5);
});

test("debug and expected sign-out events remain quiet", async () => {
  const ctx = context();
  await recordAuthEvent._handler(ctx, { ...warning, severity: "debug" });
  await recordAuthEvent._handler(ctx, { ...warning, event_type: "signed_out_received" });
  expect(ctx.tables.auth_diagnostic_events).toHaveLength(2);
  expect(ctx.tables.notifications_outbox).toHaveLength(0);
});
