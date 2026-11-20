import { afterEach, describe, expect, test } from "bun:test";
import { getFunctionName } from "convex/server";
import { getFriendSchedule, sendMessage, shareShiftsWith, updateSharing } from "../convex/lib/mcp/social";
import { friendSchedule, listFriends } from "../convex/mcpSocial";
import { shareTargetFor } from "../convex/sharing";

// The friend tools' queries run against an in-memory database. Only the database is fake;
// the share, block and pay rules are the real ones.

type Row = Record<string, unknown>;

function database(tables: Record<string, Row[]>) {
  return {
    tables,
    db: {
      query(table: string) {
        let rows = tables[table] ?? [];
        const index = {
          eq(field: string, value: unknown) {
            rows = rows.filter((r) => r[field] === value);
            return index;
          },
          gte(field: string, value: string) {
            rows = rows.filter((r) => (r[field] as string) >= value);
            return index;
          },
          lte(field: string, value: string) {
            rows = rows.filter((r) => (r[field] as string) <= value);
            return index;
          },
        };
        const query = {
          withIndex(_name: string, range?: (q: typeof index) => unknown) {
            range?.(index);
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

const share = (owner_id: string, viewer_id: string, fields: Row = {}) => ({
  id: `${owner_id}->${viewer_id}`,
  owner_id,
  viewer_id,
  show_earnings: false,
  blocked: false,
  muted: false,
  owner_muted: false,
  hidden: false,
  created_at: "2026-11-01T10:00:00Z",
  revision: 1,
  ...fields,
});

function people(shares: Row[]) {
  return database({
    users: [
      { id: "me", name: "Hjalmar", email: "me@example.com" },
      { id: "ola", name: "Ola", email: "ola@example.com" },
      { id: "kari", name: "Kari", email: "kari@example.com" },
      { id: "troll", name: "Troll", email: "troll@example.com" },
    ],
    profiles: [
      { id: "ola", username: "ola", schedule_time_zone: "Europe/London" },
      { id: "kari", username: "kari" },
    ],
    shift_shares: shares,
    user_settings: [],
    user_shifts: [
      { id: "ola-1", user_id: "ola", job_id: "ola-job", shift_date: "2026-11-16", start_time: "08:00", end_time: "16:00" },
      { id: "ola-old", user_id: "ola", job_id: "ola-job", shift_date: "2026-10-01", start_time: "08:00", end_time: "16:00" },
      { id: "ola-gone", user_id: "ola", job_id: "ola-job", shift_date: "2026-11-17", start_time: "08:00", end_time: "16:00", deleted_at: "2026-11-02T00:00:00Z" },
    ],
    recurring_shifts: [
      {
        id: "ola-weekly", user_id: "ola", job_id: "ola-job", start_time: "22:00", end_time: "06:00",
        repeat_interval_weeks: 1, selected_days: { "3": "2026-11-04" },
      },
    ],
    wage_snapshots: [
      {
        id: "ola-wage", user_id: "ola", job_id: "ola-job", hourly_wage: 200, supplements: { rules: [] },
        break_enabled: false, tax_enabled: true, tax_percentage: 30,
      },
    ],
    jobs: [{ id: "ola-job", user_id: "ola", name: "Café", currency: "kr", sort_order: 0 }],
  });
}

type Handler = { _handler: (ctx: unknown, args: unknown) => Promise<unknown> };
const run = <T>(fn: unknown, ctx: unknown, args: Row) => (fn as Handler)._handler(ctx, args) as Promise<T>;
const toolMessage = (fn: () => unknown) => {
  try {
    fn();
  } catch (error) {
    return (error as Error).message;
  }
  return null;
};

describe("MCP message arguments", () => {
  const parse = (args: Row) => sendMessage.parse({ friend_id: "ola", ...args });

  test("a message is sent trimmed, and a blank or too-long one is refused", () => {
    expect(parse({ text: "  Bytte vakt på fredag?\n" }).text).toBe("Bytte vakt på fredag?");
    expect(toolMessage(() => parse({ text: "   " }))).toBe("text is required.");
    expect(toolMessage(() => parse({}))).toBe("text is required.");
    // 5000 emoji are 10000 UTF-16 units but 5000 characters, as the server counts them.
    expect(parse({ text: "👋".repeat(5000) }).text).toHaveLength(10000);
    expect(toolMessage(() => parse({ text: "a".repeat(5001) }))).toContain("at most 5000 characters");
  });

  test("a message the app's safety filter would block is refused before it is sent", () => {
    expect(toolMessage(() => parse({ text: "send nudes" }))).toContain("safety filter");
  });

  test("a retry can pass the first attempt's client_id, which must be a UUID", () => {
    const id = "0B6C5F8E-3F4A-4D2B-9A1E-6F0C2D7E8A91";
    expect(parse({ text: "Hei", client_id: id }).client_id).toBe(id.toLowerCase());
    expect(parse({ text: "Hei", client_id: null }).client_id).toBeUndefined();
    expect(toolMessage(() => parse({ text: "Hei", client_id: "retry-1" }))).toContain("client_id must be a UUID");
  });
});

describe("MCP sharing arguments", () => {
  test("a friend's schedule can span at most 93 days", () => {
    expect(getFriendSchedule.parse({ friend_id: "ola", from: "2026-11-01", to: "2027-02-01" }).to).toBe("2027-02-01");
    expect(toolMessage(() => getFriendSchedule.parse({ friend_id: "ola", from: "2026-11-01", to: "2027-02-02" }))).toBe(
      "The range can be at most 93 days.",
    );
  });

  test("sharing needs someone to share with, and keeps earnings hidden unless asked", () => {
    expect(shareShiftsWith.parse({ username_or_email: " @Ola " })).toEqual({ identifier: "@Ola", show_earnings: false });
    expect(toolMessage(() => shareShiftsWith.parse({ username_or_email: " @ " }))).toBe("username_or_email is required.");
  });

  test("a sharing change must change something", () => {
    expect(toolMessage(() => updateSharing.parse({ friend_id: "ola" }))).toContain("Give at least one of");
    expect(updateSharing.parse({ friend_id: "ola", hidden: false }).hidden).toBe(false);
  });
});

describe("MCP share lookup", () => {
  const realFetch = globalThis.fetch;
  afterEach(() => {
    globalThis.fetch = realFetch;
  });

  function action() {
    const lookups: { fn: string; args: unknown }[] = [];
    const ctx = {
      runQuery: async (fn: unknown, args: unknown) => {
        lookups.push({ fn: getFunctionName(fn as never), args });
        return "found";
      },
    };
    return { ctx: ctx as never, lookups };
  }

  test("an identifier with @ inside is matched only against verified email addresses", async () => {
    process.env.CLERK_SECRET_KEY = "sk_test";
    globalThis.fetch = (async () =>
      Response.json([
        { id: "clerk-verified", email_addresses: [{ email_address: "Ola@Example.com", verification: { status: "verified" } }] },
        { id: "clerk-unverified", email_addresses: [{ email_address: "ola@example.com", verification: { status: "unverified" } }] },
      ])) as unknown as typeof fetch;
    const { ctx, lookups } = action();
    await shareTargetFor(ctx, "ola@example.com");
    expect(lookups).toEqual([{ fn: "sharing:userIdForClerkUsers", args: { clerk_user_ids: ["clerk-verified"] } }]);
  });

  test("anything else is a username, lowercased and without a leading @", async () => {
    globalThis.fetch = (() => {
      throw new Error("a username never reaches Clerk");
    }) as unknown as typeof fetch;
    const { ctx, lookups } = action();
    await shareTargetFor(ctx, "@Ola_Nordmann");
    expect(lookups).toEqual([{ fn: "sharing:userIdForUsername", args: { username: "ola_nordmann" } }]);
  });
});

describe("MCP friends", () => {
  test("friends show what each side shares, never an email address, and leave out blocked pairs", async () => {
    const ctx = people([
      share("ola", "me", { show_earnings: true, muted: true }),
      share("me", "ola", { owner_muted: true }),
      share("kari", "me", { hidden: true }),
      share("me", "troll", { blocked: true, blocked_by_user_id: "me" }),
    ]);
    const { friends } = await run<{ friends: Row[] }>(listFriends, ctx, { user_id: "me" });
    expect(JSON.stringify(friends)).not.toContain("@example.com");
    expect(friends).toEqual([
      {
        friend_id: "kari",
        name: "Kari",
        username: "kari",
        they_share_with_me: {
          since: "2026-11-01T10:00:00Z",
          earnings_visible_to_me: false,
          hidden: true,
          notify_me_of_their_shifts: true,
        },
        i_share_with_them: null,
      },
      {
        friend_id: "ola",
        name: "Ola",
        username: "ola",
        they_share_with_me: {
          since: "2026-11-01T10:00:00Z",
          earnings_visible_to_me: true,
          hidden: false,
          notify_me_of_their_shifts: false,
        },
        i_share_with_them: { since: "2026-11-01T10:00:00Z", show_my_earnings: false, notify_them_of_my_shifts: false },
      },
    ]);
  });

  const week = { user_id: "me", friend_id: "ola", from: "2026-11-16", to: "2026-11-22" };

  test("a friend's schedule is on their clock and includes their repeating shifts", async () => {
    const ctx = people([share("ola", "me")]);
    const schedule = await run<Row>(friendSchedule, ctx, week);
    expect(schedule.time_zone).toBe("Europe/London");
    expect(schedule.shifts).toEqual([
      { date: "2026-11-16", start: "08:00", end: "16:00", ends_next_day: false, job_name: "Café" },
      { date: "2026-11-18", start: "22:00", end: "06:00", ends_next_day: true, job_name: "Café" },
    ]);
  });

  test("a friend's pay shows only when they share their earnings with the user", async () => {
    const hidden = await run<Row>(friendSchedule, people([share("ola", "me")]), week);
    expect(hidden.earnings_shared).toBe(false);
    expect(hidden.earnings).toBeNull();

    const shared = await run<Row>(friendSchedule, people([share("ola", "me", { show_earnings: true })]), week);
    expect(shared.earnings).toEqual({
      totals: [{ currency: "kr", gross_pay: 3200, paid_hours: 16, shifts: 2 }],
      shifts_without_pay_setup: 0,
    });
  });

  test("a hidden or blocked friend's schedule, or no share at all, is refused", async () => {
    const refused = async (shares: Row[]) => {
      try {
        await run(friendSchedule, people(shares), week);
      } catch (error) {
        return ((error as { data: { message: string } }).data ?? {}).message;
      }
      return null;
    };
    expect(await refused([share("ola", "me", { hidden: true })])).toContain("hid this friend's schedule");
    expect(await refused([share("ola", "me", { blocked: true, blocked_by_user_id: "ola" })])).toContain("doesn't share");
    expect(await refused([share("me", "ola")])).toContain("doesn't share");
  });
});
