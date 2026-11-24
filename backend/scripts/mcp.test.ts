import { describe, expect, test } from "bun:test";
import { exportJWK, generateKeyPair, SignJWT } from "jose";
import {
  computeAdjustmentWithPay,
  computeShiftsWithPay,
  type JobPayMeta,
  payoutEarningsReport,
  workedEarningsReport,
} from "../convex/lib/mcp/earnings";
import { getOverview } from "../convex/lib/mcp/pay";
import { payWindowForDate, payWindowsPaidInMonth } from "../convex/lib/mcp/payPeriod";
import { handleMcpPost, type McpDeps, MODERN_VERSION } from "../convex/lib/mcp/protocol";
import { addShifts, deleteShifts, getEarnings, getSchedule, updateShift } from "../convex/lib/mcp/shifts";
import { movedTimes, parseRange, parseShiftId, recurringOccurrenceId, shiftTimes } from "../convex/lib/mcp/shiftTimes";
import { checkKeySet, verifyAccessToken } from "../convex/lib/mcp/token";
import type { LiveActivityRegularShift } from "../convex/lib/shared/liveActivityScheduling";
import type { WageSnapshot } from "../convex/lib/shared/payroll/types";
import { getOverview as getOverviewHandler } from "../convex/mcpPay";
import { getEarnings as getEarningsHandler, getSchedule as getScheduleHandler } from "../convex/mcpShifts";

const RESOURCE = "https://actions.tidex.no/mcp";
const calls: { userId: string; name: string; args: unknown }[] = [];
const deps: McpDeps = {
  resourceUrl: RESOURCE,
  authenticate: async (token) => {
    const scopes = { good: ["tidex:read", "tidex:write"], reader: ["tidex:read"], profile: ["profile", "email"] }[token];
    if (scopes !== undefined) return { userId: "user-1", scopes: new Set(scopes) };
    return token === "banned" ? "no_account" : "invalid_token";
  },
  tools: [getOverview, addShifts, deleteShifts],
  callTool: async (userId, tool, args) => {
    const name = tool.definition.name;
    calls.push({ userId, name, args });
    return { ok: true, value: { echoed: name } };
  },
};

function post(body: unknown, headers: Record<string, string> = {}) {
  return new Request(RESOURCE, {
    method: "POST",
    headers: { Authorization: "Bearer good", "Content-Type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

const modernHeaders = (method: string, name?: string) => ({
  "MCP-Protocol-Version": MODERN_VERSION,
  "Mcp-Method": method,
  ...(name === undefined ? {} : { "Mcp-Name": name }),
});
const modernMeta = { "io.modelcontextprotocol/protocolVersion": MODERN_VERSION, "io.modelcontextprotocol/clientCapabilities": {} };

describe("MCP authorization", () => {
  test("a request without a token is told where to get one", async () => {
    const response = await handleMcpPost(post({ jsonrpc: "2.0", id: 1, method: "tools/list" }, { Authorization: "" }), deps);
    expect(response.status).toBe(401);
    expect(response.headers.get("WWW-Authenticate")).toBe(
      'Bearer scope="tidex:read", resource_metadata="https://actions.tidex.no/.well-known/oauth-protected-resource/mcp"',
    );
  });

  test("a read-only token can list and read, but a write asks for tidex:write too", async () => {
    calls.length = 0;
    const reader = { Authorization: "Bearer reader" };
    const list = await handleMcpPost(post({ jsonrpc: "2.0", id: 1, method: "tools/list" }, reader), deps);
    expect((await list.json()).result.tools.map((t: { name: string }) => t.name)).toContain("add_shifts");
    const read = await handleMcpPost(post({ jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "get_overview" } }, reader), deps);
    expect((await read.json()).result.structuredContent).toEqual({ echoed: "get_overview" });

    const write = await handleMcpPost(
      post({ jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "add_shifts", arguments: {} } }, reader),
      deps,
    );
    expect(write.status).toBe(403);
    const challenge = write.headers.get("WWW-Authenticate");
    expect(challenge).toStartWith('Bearer error="insufficient_scope", scope="tidex:read tidex:write"');
    expect(challenge).toContain('resource_metadata="https://actions.tidex.no/.well-known/oauth-protected-resource/mcp"');
    const body = await write.json();
    expect(body.id).toBe(3);
    expect(body.error.message).toContain("tidex:write");
    expect(calls.map((c) => c.name)).toEqual(["get_overview"]);
  });

  test("a token without Tidex scopes can't read", async () => {
    calls.length = 0;
    const response = await handleMcpPost(
      post({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "get_overview" } }, { Authorization: "Bearer profile" }),
      deps,
    );
    expect(response.status).toBe(403);
    expect(response.headers.get("WWW-Authenticate")).toStartWith('Bearer error="insufficient_scope", scope="tidex:read",');
    expect((await response.json()).error.message).toContain("tidex:read");
    expect(calls).toHaveLength(0);
  });

  test("a rejected token gets invalid_token and never reaches a tool", async () => {
    calls.length = 0;
    const response = await handleMcpPost(
      post({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "get_overview" } }, { Authorization: "Bearer stolen" }),
      deps,
    );
    expect(response.status).toBe(401);
    expect(response.headers.get("WWW-Authenticate")).toContain('error="invalid_token"');
    expect(calls).toHaveLength(0);
  });

  test("a browser page can't use a token", async () => {
    const response = await handleMcpPost(post({ jsonrpc: "2.0", id: 1, method: "tools/list" }, { Origin: "https://evil.example" }), deps);
    expect(response.status).toBe(403);
    const fromClaude = await handleMcpPost(post({ jsonrpc: "2.0", id: 1, method: "tools/list" }, { Origin: "https://claude.ai" }), deps);
    expect(fromClaude.status).toBe(200);
  });

  test("a valid token for a banned or missing account is refused without asking to sign in again", async () => {
    const response = await handleMcpPost(post({ jsonrpc: "2.0", id: 1, method: "tools/list" }, { Authorization: "Bearer banned" }), deps);
    expect(response.status).toBe(403);
    expect(response.headers.get("WWW-Authenticate")).toBeNull();
  });

  test("a body over 64 KB is refused even without Content-Length", async () => {
    const big = new TextEncoder().encode(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "ping", params: { pad: "x".repeat(70_000) } }));
    const stream = new ReadableStream({
      start(controller) {
        for (let i = 0; i < big.length; i += 8192) controller.enqueue(big.slice(i, i + 8192));
        controller.close();
      },
    });
    const request = new Request(RESOURCE, { method: "POST", headers: { Authorization: "Bearer good" }, body: stream, duplex: "half" } as RequestInit);
    expect((await handleMcpPost(request, deps)).status).toBe(413);
  });
});

describe("MCP token verification", async () => {
  const { privateKey, publicKey } = await generateKeyPair("RS256");
  const jwk = { ...(await exportJWK(publicKey)), kid: "k1", alg: "RS256", use: "sig" };
  const issuer = "https://clerk.test.invalid";
  let fetches = 0;
  const keys = async () => {
    fetches += 1;
    return { keys: [jwk] };
  };
  const verifyAt = (token: string, audience = RESOURCE) => verifyAccessToken(token, issuer, audience, keys);

  const sign = (claims: Record<string, unknown>, typ = "at+jwt") =>
    new SignJWT({ sub: "user_clerk", ...claims })
      .setProtectedHeader({ alg: "RS256", kid: "k1", typ })
      .setIssuer(issuer)
      .setIssuedAt()
      .setExpirationTime("1h")
      .sign(privateKey);

  test("an OAuth token for the MCP endpoint names its Clerk user and the scopes in its scope claim", async () => {
    expect(await verifyAt(await sign({ aud: RESOURCE, client_id: "client", scope: "profile tidex:read" }))).toEqual({
      clerkUserId: "user_clerk",
      scopes: new Set(["profile", "tidex:read"]),
    });
    expect((await verifyAt(await sign({ aud: RESOURCE, client_id: "client" })))?.scopes).toEqual(new Set());
  });

  test("the app's own session token is refused", async () => {
    expect(await verifyAt(await sign({ aud: "convex" }))).toBeNull();
    expect(await verifyAt(await sign({ aud: RESOURCE }))).toBeNull();
    expect(await verifyAt(await sign({ aud: RESOURCE, client_id: "client" }, "JWT"))).toBeNull();
  });

  test("a token signed with an unknown key asks once for fresh keys, then is refused", async () => {
    const other = await generateKeyPair("RS256");
    const forged = await new SignJWT({ sub: "user_clerk", aud: RESOURCE, client_id: "c" })
      .setProtectedHeader({ alg: "RS256", kid: "unknown", typ: "at+jwt" })
      .setIssuer(issuer)
      .setExpirationTime("1h")
      .sign(other.privateKey);
    fetches = 0;
    expect(await verifyAt(forged)).toBeNull();
    expect(fetches).toBe(2);
  });

  test("a token with a critical header the server doesn't know is a bad token, not an outage", async () => {
    const enc = (o: object) => Buffer.from(JSON.stringify(o)).toString("base64url");
    const header = enc({ alg: "RS256", kid: "k1", typ: "at+jwt", crit: ["x-unknown"], "x-unknown": true });
    const body = enc({ sub: "user_clerk", aud: RESOURCE, client_id: "c", iss: issuer, exp: Math.floor(Date.now() / 1000) + 3600 });
    const signature = Buffer.from(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", privateKey, new TextEncoder().encode(`${header}.${body}`))).toString("base64url");
    expect(await verifyAt(`${header}.${body}.${signature}`)).toBeNull();
  });

  test("a broken key set from Clerk is an outage, not a bad token", async () => {
    const token = await sign({ aud: RESOURCE, client_id: "client" });
    await expect(verifyAccessToken(token, issuer, RESOURCE, async () => ({ keys: "none" }) as never)).rejects.toThrow();
  });

  test("only RS256 public keys that import replace the stored ones", async () => {
    expect(await checkKeySet({ keys: [jwk] })).toEqual({ keys: [jwk] });
    await expect(checkKeySet({ keys: [] })).rejects.toThrow();
    await expect(checkKeySet({ keys: [{ kty: "RSA", kid: "current" }] })).rejects.toThrow();
    await expect(checkKeySet({ keys: [{ ...jwk, n: "AQAB-not-a-modulus!" }] })).rejects.toThrow();
    await expect(checkKeySet({ keys: [jwk, jwk] })).rejects.toThrow();
    await expect(checkKeySet({ keys: [{ ...jwk, alg: "RS512" }] })).rejects.toThrow();
    await expect(checkKeySet({ keys: [{ ...jwk, use: "enc" }] })).rejects.toThrow();
  });

  test("a token without a kid is a bad token, even while Clerk publishes two keys", async () => {
    const second = { ...(await exportJWK((await generateKeyPair("RS256")).publicKey)), kid: "k2", alg: "RS256", use: "sig" };
    const token = await new SignJWT({ sub: "user_clerk", aud: RESOURCE, client_id: "c" })
      .setProtectedHeader({ alg: "RS256", typ: "at+jwt" })
      .setIssuer(issuer)
      .setExpirationTime("1h")
      .sign(privateKey);
    expect(await verifyAccessToken(token, issuer, RESOURCE, async () => ({ keys: [jwk, second] }))).toBeNull();
  });

  test("Clerk's key endpoint failing is not reported as a bad token", async () => {
    const token = await sign({ aud: RESOURCE, client_id: "client" });
    await expect(verifyAccessToken(token, issuer, RESOURCE, async () => { throw new Error("Clerk JWKS answered 503"); })).rejects.toThrow("503");
  });

  test("a token for another resource or without an audience is refused", async () => {
    expect(await verifyAt(await sign({ aud: "https://other.example/mcp", client_id: "c" }))).toBeNull();
    expect(await verifyAt(await sign({ client_id: "c" }))).toBeNull();
    expect(await verifyAt(await sign({ aud: [RESOURCE, "https://other.example"], client_id: "c" }))).toBeNull();
  });
});

describe("MCP protocol", () => {
  test("2025 clients initialize without a session and see the tools", async () => {
    const init = await handleMcpPost(
      post({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-06-18", capabilities: {} } }),
      deps,
    );
    expect(init.headers.get("Mcp-Session-Id")).toBeNull();
    const body = await init.json();
    expect(body.result.protocolVersion).toBe("2025-06-18");
    expect(body.result.capabilities.tools).toBeDefined();

    const notified = await handleMcpPost(post({ jsonrpc: "2.0", method: "notifications/initialized" }), deps);
    expect(notified.status).toBe(202);

    const list = await (
      await handleMcpPost(post({ jsonrpc: "2.0", id: 2, method: "tools/list" }, { "MCP-Protocol-Version": "2025-06-18" }), deps)
    ).json();
    expect(list.result.tools.map((t: { name: string }) => t.name)).toContain("add_shifts");
    expect(list.result.resultType).toBeUndefined();
  });

  test("2026-07-28 clients discover the server and call a tool", async () => {
    const discover = await (
      await handleMcpPost(
        post({ jsonrpc: "2.0", id: 1, method: "server/discover", params: { _meta: modernMeta } }, modernHeaders("server/discover")),
        deps,
      )
    ).json();
    expect(discover.result.supportedVersions).toContain(MODERN_VERSION);
    expect(discover.result.resultType).toBe("complete");

    calls.length = 0;
    const call = await (
      await handleMcpPost(
        post(
          { jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "get_overview", arguments: {}, _meta: modernMeta } },
          modernHeaders("tools/call", "get_overview"),
        ),
        deps,
      )
    ).json();
    expect(call.result.structuredContent).toEqual({ echoed: "get_overview" });
    expect(calls).toEqual([{ userId: "user-1", name: "get_overview", args: {} }]);
  });

  test("a 2026-07-28 header that disagrees with the body is refused", async () => {
    const response = await handleMcpPost(
      post(
        { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "delete_shifts", arguments: {}, _meta: modernMeta } },
        modernHeaders("tools/call", "get_overview"),
      ),
      deps,
    );
    expect(response.status).toBe(400);
    expect((await response.json()).error.code).toBe(-32020);
  });

  test("a body that declares 2026-07-28 can't skip that era's header checks", async () => {
    const response = await handleMcpPost(
      post({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "delete_shifts", arguments: {}, _meta: modernMeta } }),
      deps,
    );
    expect(response.status).toBe(400);
    expect((await response.json()).error.code).toBe(-32020);
  });

  test("a 2026-07-28 request can't open with initialize", async () => {
    const response = await handleMcpPost(
      post(
        { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: MODERN_VERSION, _meta: modernMeta } },
        modernHeaders("initialize"),
      ),
      deps,
    );
    expect(response.status).toBe(404);
    expect((await response.json()).error.code).toBe(-32601);
  });

  test("an unsupported version lists the supported ones", async () => {
    const response = await handleMcpPost(
      post({ jsonrpc: "2.0", id: 1, method: "tools/list" }, { "MCP-Protocol-Version": "2024-11-05" }),
      deps,
    );
    expect(response.status).toBe(400);
    const body = await response.json();
    expect(body.error.code).toBe(-32022);
    expect(body.error.data.supported).toContain(MODERN_VERSION);
  });

  test("an unknown tool is a protocol error, not a tool call", async () => {
    calls.length = 0;
    const body = await (
      await handleMcpPost(post({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "delete_account" } }), deps)
    ).json();
    expect(body.error.code).toBe(-32602);
    expect(calls).toHaveLength(0);
  });
});

describe("MCP shift times and shift tools", () => {
  test("a shift ending at midnight stays on its day, as in the app", () => {
    expect(shiftTimes("18:00", "00:00")).toEqual({ start_time: "18:00", end_time: "24:00" });
    expect(shiftTimes("00:00", "08:00")).toEqual({ start_time: "00:00", end_time: "08:00" });
  });

  test("a new start without a new end keeps the length across midnight", () => {
    expect(movedTimes({ start: "22:00:00", end: "06:00:00" }, "23:00")).toEqual({ start_time: "23:00", end_time: "07:00" });
    expect(movedTimes({ start: "16:00", end: "24:00" }, "17:00")).toEqual({ start_time: "17:00", end_time: "01:00" });
    expect(movedTimes({ start: "16:00", end: "24:00" }, undefined, "00:00")).toEqual({ start_time: "16:00", end_time: "24:00" });
    expect(movedTimes({ start: "08:00", end: "08:00" }, "09:00")).toEqual({ start_time: "09:00", end_time: "09:00" });
    expect(movedTimes({ start: "00:00", end: "24:00" }, "00:00")).toEqual({ start_time: "00:00", end_time: "24:00" });
    expect(movedTimes({ start: "08:00", end: "08:00" }, undefined, "08:00")).toEqual({ start_time: "08:00", end_time: "08:00" });
  });

  test("unified shift ids distinguish one-off shifts and recurring occurrences", () => {
    const id = recurringOccurrenceId("series-uuid-1", "2026-11-25");
    expect(id).toBe("recurring:series-uuid-1:2026-11-25");
    expect(parseShiftId(id)).toEqual({ kind: "recurring", recurringId: "series-uuid-1", date: "2026-11-25" });
    expect(parseShiftId("shift-uuid-1")).toEqual({ kind: "one_off", shiftId: "shift-uuid-1" });
    expect(() => parseShiftId("recurring:broken")).toThrow("Invalid recurring shift id");
  });

  test("bad dates, times, ranges and empty batches are refused", () => {
    expect(() => addShifts.parse({ shifts: [] })).toThrow("at least one");
    expect(() => addShifts.parse({ shifts: [{ date: "2026-02-30", start: "08:00", end: "16:00" }] })).toThrow("date");
    expect(() => addShifts.parse({ shifts: [{ date: "2026-02-03", start: "24:00", end: "08:00" }] })).toThrow("start");
    expect(() => addShifts.parse({ shifts: [{ date: "2026-02-03", start: "8:00", end: "16:00" }] })).toThrow("start");
    expect(() => addShifts.parse({ shifts: [{ date: "2206-02-03", start: "08:00", end: "16:00" }] })).toThrow("five years");
    expect(() => updateShift.parse({ id: "s" })).toThrow("at least one");
    expect(() => parseRange("2026-01-01", "2027-01-05", 366)).toThrow("366");
    expect(() => shiftTimes("08:00", "08:00")).toThrow("same time");
    expect(() => getSchedule.parse({ month: "2026-11", from: "2026-11-01" })).toThrow("not both");
    expect(() => getEarnings.parse({ by: "payout", from: "2026-11-01", to: "2026-11-30" })).toThrow("month");
  });

  test("null stands for a left-out optional argument, as strict clients send it", () => {
    expect(updateShift.parse({ id: "s", date: null, start: "09:00", end: null, job: null, note: null })).toEqual({
      id: "s",
      date: undefined,
      start: "09:00",
      end: undefined,
      job: undefined,
      note: undefined,
    });
  });
});

describe("MCP pay periods, tax and earnings", () => {
  const snapshot = (
    hourly: number,
    options: { threshold?: number | null; taxEnabled?: boolean; taxPercent?: number } = {},
  ): WageSnapshot =>
    ({
      id: "wage",
      user_id: "user",
      job_id: "job",
      from_date: null,
      hourly_wage: hourly,
      wage_level: null,
      tariff_type_id: null,
      supplements: { rules: [] },
      overtime:
        options.threshold == null
          ? null
          : {
              enabled: true,
              weeklyThresholdHours: options.threshold,
              rules: [false, true].map((appliesOnHolidays) => ({
                days: [1, 2, 3, 4, 5, 6, 7],
                from: "00:00",
                to: "24:00",
                percent: 50,
                appliesOnHolidays,
              })),
            },
      tax_enabled: options.taxEnabled ?? false,
      tax_percentage: options.taxPercent ?? 0,
      break_enabled: false,
      break_method: "none",
      break_threshold_hours: 0,
      break_deduction_minutes: 0,
    }) as WageSnapshot;

  const shift = (id: string, shift_date: string, start_time: string, end_time: string, job_id = "job"): LiveActivityRegularShift => ({
    id,
    user_id: "user",
    job_id,
    shift_date,
    start_time,
    end_time,
    custom_pause_windows: null,
    custom_supplements: null,
  });

  const job: JobPayMeta = { id: "job", name: "Café", currency: "kr", payroll_day: 15, is_default: true };

  test("gross pay, net pay after tax, tax deducted and paid hours add up over a range", () => {
    const result = workedEarningsReport({
      from: "2026-02-02",
      to: "2026-02-08",
      regular: [shift("a", "2026-02-02", "08:00", "16:00"), shift("b", "2026-02-03", "22:00", "02:00")],
      recurring: [],
      jobs: [job],
      adjustments: [],
      snapshotFor: () => snapshot(200, { taxEnabled: true, taxPercent: 30 }),
      snapshotForJobDate: () => snapshot(200, { taxEnabled: true, taxPercent: 30 }),
    });
    expect(result.totals).toEqual([
      {
        currency: "kr",
        gross_pay: 2400,
        net_pay: 1680,
        tax_deducted: 720,
        effective_tax_percent: 30,
        base_pay: 2400,
        supplement_pay: 0,
        paid_hours: 12,
        shifts: 2,
      },
    ]);
  });

  test("half-tax month halves tax on shifts paid out in that month", () => {
    // Calendar month job paid on the 15th of the next month with half-tax in December:
    // November shifts are paid December 15 at half tax (15%), December shifts are paid January 15 at full tax (30%).
    const halfTaxJob: JobPayMeta = { ...job, half_tax_month: 12 };
    const wage = snapshot(200, { taxEnabled: true, taxPercent: 30 });
    const computed = computeShiftsWithPay({
      from: "2026-11-25",
      to: "2026-12-05",
      regular: [shift("nov", "2026-11-25", "08:00", "16:00"), shift("dec", "2026-12-02", "08:00", "16:00")],
      recurring: [],
      jobs: [halfTaxJob],
      snapshotFor: () => wage,
    });
    const nov = computed.shifts.find((s) => s.id === "nov")!;
    const dec = computed.shifts.find((s) => s.id === "dec")!;
    expect(nov.payout_date).toBe("2026-12-15");
    expect(nov.half_tax_applied).toBe(true);
    expect(nov.effective_tax_percent).toBe(15);
    expect(nov.gross_pay).toBe(1600);
    expect(nov.net_pay).toBe(1360);
    expect(nov.tax_deducted).toBe(240);

    expect(dec.payout_date).toBe("2027-01-15");
    expect(dec.half_tax_applied).toBe(false);
    expect(dec.effective_tax_percent).toBe(30);
    expect(dec.net_pay).toBe(1120);
  });

  test("payout mode calculates exact December paycheck from November work window plus adjustments", () => {
    const halfTaxJob: JobPayMeta = { ...job, half_tax_month: 12 };
    const wage = snapshot(200, { taxEnabled: true, taxPercent: 30 });
    const report = payoutEarningsReport({
      monthKey: "2026-12",
      year: 2026,
      month: 12,
      monthFrom: "2026-12-01",
      monthTo: "2026-12-31",
      regular: [
        shift("nov", "2026-11-20", "08:00", "16:00"), // in Nov work window -> paid Dec 15 (1600 gross, 15% tax -> 1360 net)
        shift("dec", "2026-12-05", "08:00", "16:00"), // in Dec work window -> paid Jan 15 (excluded from Dec payout)
      ],
      recurring: [],
      jobs: [halfTaxJob],
      adjustments: [
        {
          id: "adj-1",
          job_id: "job",
          amount: 1000,
          currency: "kr",
          category: "bonus",
          tax_treatment: "gross_taxable",
          description: "Christmas bonus",
          payout_date: "2026-12-15",
        },
        {
          id: "adj-2",
          job_id: "job",
          amount: 500,
          currency: "kr",
          category: "correction",
          tax_treatment: "net_manual",
          description: "Meal allowance",
          payout_date: "2026-12-15",
        },
      ],
      snapshotFor: () => wage,
      snapshotForJobDate: () => wage,
    });

    // Shift: 1600 gross, 1360 net (15% half tax)
    // Bonus (gross_taxable in Dec half-tax): 1000 gross, 850 net
    // Allowance (net_manual): 500 gross, 500 net
    // Total: 3100 gross, 2710 net, 390 tax
    expect(report.totals).toHaveLength(1);
    expect(report.totals[0]).toMatchObject({
      currency: "kr",
      gross_pay: 3100,
      net_pay: 2710,
      tax_deducted: 390,
      shifts_gross: 1600,
      shifts_net: 1360,
      adjustments_gross: 1500,
      adjustments_net: 1350,
      half_tax_applied: true,
      shifts: 1,
    });
    expect(report.payouts).toHaveLength(1);
    expect(report.payouts[0]).toMatchObject({
      work_from: "2026-11-01",
      work_to: "2026-11-30",
      payout_date: "2026-12-15",
      net_pay: 2710,
    });
  });

  test("biweekly and custom monthly pay periods match PayPeriod.swift", () => {
    const customMonthly = { type: "monthly" as const, startDay: 16, payoutMonthOffset: 0 as const };
    expect(payWindowForDate(customMonthly, 20, "2026-12-10")).toEqual({
      start: "2026-11-16",
      end: "2026-12-15",
      payoutDate: "2026-12-20",
      payoutMonth: 12,
    });
    expect(payWindowsPaidInMonth(customMonthly, 20, 2026, 12)).toEqual([
      { start: "2026-11-16", end: "2026-12-15", payoutDate: "2026-12-20", payoutMonth: 12 },
    ]);

    const biweekly = { type: "biweekly" as const, anchorEnd: "2026-11-08", payoutDelayDays: 5 };
    expect(payWindowsPaidInMonth(biweekly, 15, 2026, 11)).toEqual([
      { start: "2026-10-26", end: "2026-11-08", payoutDate: "2026-11-13", payoutMonth: 11 },
      { start: "2026-11-09", end: "2026-11-22", payoutDate: "2026-11-27", payoutMonth: 11 },
    ]);
  });

  test("overtime from earlier in the week counts for a range that starts mid-week", () => {
    const result = workedEarningsReport({
      from: "2026-02-04",
      to: "2026-02-04",
      regular: [shift("mon", "2026-02-02", "08:00", "18:00"), shift("wed", "2026-02-04", "08:00", "10:00")],
      recurring: [],
      jobs: [job],
      adjustments: [],
      snapshotFor: () => snapshot(200, { threshold: 10 }),
      snapshotForJobDate: () => snapshot(200, { threshold: 10 }),
    });
    expect(result.totals[0]).toMatchObject({ gross_pay: 600, net_pay: 600, paid_hours: 2, overtime_hours: 2, shifts: 1 });
  });

  test("overlapping shifts on a date count once, as in the app", () => {
    const result = workedEarningsReport({
      from: "2026-02-02",
      to: "2026-02-02",
      regular: [shift("a", "2026-02-02", "08:00", "12:00"), shift("b", "2026-02-02", "10:00", "14:00")],
      recurring: [],
      jobs: [job],
      adjustments: [],
      snapshotFor: () => snapshot(200),
      snapshotForJobDate: () => snapshot(200),
    });
    expect(result.totals[0]!.shifts).toBe(1);
  });

  test("a shift without pay can't push an overlapping paid shift out of the total", () => {
    const paid = snapshot(300);
    const result = workedEarningsReport({
      from: "2026-02-02",
      to: "2026-02-02",
      recurring: [],
      jobs: [job, { id: "other", name: "Other", currency: "kr" }],
      adjustments: [],
      regular: [shift("paid", "2026-02-02", "08:00", "12:00"), shift("unpaid", "2026-02-02", "10:00", "14:00", "other")],
      snapshotFor: (s) => (s.job_id === "job" ? paid : null),
      snapshotForJobDate: (id) => (id === "job" ? paid : null),
    });
    expect(result.totals[0]).toMatchObject({ gross_pay: 1200, paid_hours: 4, shifts: 1 });
    expect(result.shifts_without_pay_setup).toBe(1);
  });

  test("adjustments compute net pay based on tax_treatment", () => {
    const wage = snapshot(200, { taxEnabled: true, taxPercent: 25 });
    const taxable = computeAdjustmentWithPay(
      {
        id: "a1",
        job_id: "job",
        amount: 2000,
        currency: "kr",
        category: "bonus",
        tax_treatment: "gross_taxable",
        description: "Bonus",
        payout_date: "2026-05-15",
      },
      [job],
      () => wage,
    );
    expect(taxable).toMatchObject({ amount: 2000, net_amount: 1500, tax_deducted: 500, effective_tax_percent: 25 });

    const manual = computeAdjustmentWithPay(
      {
        id: "a2",
        job_id: "job",
        amount: 2000,
        currency: "kr",
        category: "correction",
        tax_treatment: "net_manual",
        description: "Reimbursement",
        payout_date: "2026-05-15",
      },
      [job],
      () => wage,
    );
    expect(manual).toMatchObject({ amount: 2000, net_amount: 2000, tax_deducted: 0, effective_tax_percent: 0 });
  });
});

describe("MCP query handlers end-to-end", () => {
  type Row = Record<string, unknown>;
  type Handler = { _handler: (ctx: unknown, args: unknown) => Promise<unknown> };
  const run = <T>(fn: unknown, ctx: unknown, args: Row) => (fn as Handler)._handler(ctx, args) as Promise<T>;

  function makeDb() {
    const tables: Record<string, Row[]> = {
      users: [{ id: "u1", name: "Hjalmar" }],
      profiles: [{ id: "u1", username: "hjalmar", schedule_time_zone: "Europe/Oslo" }],
      user_settings: [
        {
          user_id: "u1",
          theme: "dark",
          calendar_content_color_style: "workplace",
          show_dashboard_clock_buttons: true,
          default_startup_tab: "home",
          payroll_day: 15,
          revision: 1,
        },
      ],
      notification_preferences: [],
      jobs: [
        {
          id: "job-1",
          user_id: "u1",
          name: "Rema 1000",
          color: "#3B82F6",
          currency: "kr",
          is_default: true,
          sort_order: 0,
          payroll_day: 15,
          half_tax_month: 12,
          revision: 1,
        },
      ],
      wage_snapshots: [
        {
          id: "snap-1",
          user_id: "u1",
          job_id: "job-1",
          hourly_wage: 200,
          supplements: { rules: [] },
          overtime: { enabled: false, retainSupplements: false, rules: [], weeklyThresholdHours: 40 },
          tax_enabled: true,
          tax_percentage: 30,
          break_enabled: true,
          break_method: "proportional",
          break_threshold_hours: 5.5,
          break_deduction_minutes: 30,
          revision: 1,
        },
      ],
      user_shifts: [
        { id: "shift-1", user_id: "u1", job_id: "job-1", shift_date: "2026-11-10", start_time: "08:00", end_time: "16:00", note: "Opening", revision: 1 },
      ],
      recurring_shifts: [
        {
          id: "rec-1",
          user_id: "u1",
          job_id: "job-1",
          start_time: "12:00",
          end_time: "16:00",
          repeat_interval_weeks: 0,
          selected_days: { "5": "2026-11-06" },
          exclusions: [],
          date_specific_notes: { "2026-11-13": "Friday team" },
          revision: 1,
        },
      ],
      events: [
        { id: "evt-1", user_id: "u1", start_date: "2026-11-12", end_date: "2026-11-12", is_all_day: false, start_time: "18:00", end_time: "19:00", note: "Dentist", revision: 1 },
      ],
      payroll_adjustments: [
        {
          id: "adj-1",
          user_id: "u1",
          job_id: "job-1",
          amount: 1000,
          currency: "kr",
          category: "bonus",
          tax_treatment: "gross_taxable",
          description: "Holiday bonus",
          payout_date: "2026-12-15",
          revision: 1,
        },
      ],
      shift_shares: [],
      thread_memberships: [],
      thread_user_state: [],
      threads: [],
    };
    return {
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

  test("get_overview returns jobs with current_pay, recurring shifts, settings and time_zone", async () => {
    const overview = await run<Row>(getOverviewHandler, makeDb(), {
      user_id: "u1",
      include_archived: false,
      include_pay_history: false,
    });
    expect(overview.time_zone).toBe("Europe/Oslo");
    expect((overview.jobs as Row[])[0]).toMatchObject({
      id: "job-1",
      name: "Rema 1000",
      half_tax_month: "december",
      current_pay: { type: "custom", hourly_wage: 200, tax_enabled: true, tax_percent: 30, break_enabled: true, break_minutes: 30 },
    });
    expect((overview.recurring_shifts as Row[])[0]).toMatchObject({ id: "rec-1", job_name: "Rema 1000", every_weeks: 1 });
  });

  test("get_schedule returns shifts with unified ids, net pay after half-tax, events and summary", async () => {
    const sched = await run<Row>(getScheduleHandler, makeDb(), {
      user_id: "u1",
      from: "2026-11-10",
      to: "2026-11-14",
      include_events: true,
    });
    const shifts = sched.shifts as Row[];
    expect(shifts).toHaveLength(2);
    // One-off shift: 8h - 30m break = 7.5h * 200 = 1500 gross; paid Dec 15 (half tax 15%) -> 1275 net.
    expect(shifts[0]).toMatchObject({
      id: "shift-1",
      date: "2026-11-10",
      weekday: "Tuesday",
      note: "Opening",
      paid_hours: 7.5,
      break_minutes: 30,
      gross_pay: 1500,
      net_pay: 1275,
      tax_deducted: 225,
      effective_tax_percent: 15,
      half_tax_applied: true,
      payout_date: "2026-12-15",
    });
    // Recurring occurrence: unified id, 4h (under 5.5h break threshold) * 200 = 800 gross -> 680 net.
    expect(shifts[1]).toMatchObject({
      id: "recurring:rec-1:2026-11-13",
      recurring_id: "rec-1",
      note: "Friday team",
      paid_hours: 4,
      gross_pay: 800,
      net_pay: 680,
    });
    expect(sched.summary).toEqual([
      { currency: "kr", shifts: 2, paid_hours: 11.5, gross_pay: 2300, net_pay: 1955, tax_deducted: 345 },
    ]);
    expect(sched.events).toEqual([
      { id: "evt-1", date: "2026-11-12", all_day: false, start: "18:00", end: "19:00", note: "Dentist" },
    ]);
  });

  test("get_earnings supports job filter by name and payout month with adjustments", async () => {
    const payout = await run<Row>(getEarningsHandler, makeDb(), {
      user_id: "u1",
      by: "payout",
      month: "2026-12",
      job: "rema 1000",
    });
    // Nov 2026 shifts: shift-1 (1500) + 4 Fridays (6, 13, 20, 27 -> 4 * 800 = 3200) = 4700 shifts gross
    // + 1000 bonus = 5700 gross; all at 15% December half-tax -> 4845 net, 855 tax.
    expect((payout.totals as Row[])[0]).toMatchObject({
      currency: "kr",
      shifts: 5,
      shifts_gross: 4700,
      adjustments_gross: 1000,
      gross_pay: 5700,
      net_pay: 4845,
      tax_deducted: 855,
      half_tax_applied: true,
    });
  });
});
