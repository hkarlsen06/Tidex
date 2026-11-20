import { describe, expect, test } from "bun:test";
import { exportJWK, generateKeyPair, SignJWT } from "jose";
import { shiftEarnings } from "../convex/lib/mcp/earnings";
import { handleMcpPost, type McpDeps, MODERN_VERSION } from "../convex/lib/mcp/protocol";
import { movedTimes, parseRange, shiftTimes } from "../convex/lib/mcp/shiftTimes";
import { checkKeySet, verifyAccessToken } from "../convex/lib/mcp/token";
import { parseArgs } from "../convex/lib/mcp/tools";
import type { LiveActivityRegularShift } from "../convex/lib/shared/liveActivityScheduling";
import type { WageSnapshot } from "../convex/lib/shared/payroll/types";

const RESOURCE = "https://actions.tidex.no/mcp";
const calls: { userId: string; name: string; args: unknown }[] = [];
const deps: McpDeps = {
  resourceUrl: RESOURCE,
  authenticate: async (token) => (token === "good" ? { userId: "user-1" } : token === "banned" ? "no_account" : "invalid_token"),
  callTool: async (userId, name, args) => {
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
      'Bearer resource_metadata="https://actions.tidex.no/.well-known/oauth-protected-resource/mcp"',
    );
  });

  test("a rejected token gets invalid_token and never reaches a tool", async () => {
    calls.length = 0;
    const response = await handleMcpPost(
      post({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "list_jobs" } }, { Authorization: "Bearer stolen" }),
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

  test("an OAuth token for the MCP endpoint names its Clerk user", async () => {
    expect(await verifyAt(await sign({ aud: RESOURCE, client_id: "client" }))).toBe("user_clerk");
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
    expect(list.result.tools.map((t: { name: string }) => t.name)).toContain("add_shift");
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
          { jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "list_jobs", arguments: {}, _meta: modernMeta } },
          modernHeaders("tools/call", "list_jobs"),
        ),
        deps,
      )
    ).json();
    expect(call.result.structuredContent).toEqual({ echoed: "list_jobs" });
    expect(calls).toEqual([{ userId: "user-1", name: "list_jobs", args: {} }]);
  });

  test("a 2026-07-28 header that disagrees with the body is refused", async () => {
    const response = await handleMcpPost(
      post(
        { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "delete_shift", arguments: {}, _meta: modernMeta } },
        modernHeaders("tools/call", "list_jobs"),
      ),
      deps,
    );
    expect(response.status).toBe(400);
    expect((await response.json()).error.code).toBe(-32020);
  });

  test("a body that declares 2026-07-28 can't skip that era's header checks", async () => {
    const response = await handleMcpPost(
      post({ jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: "delete_shift", arguments: {}, _meta: modernMeta } }),
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

describe("MCP shift times", () => {
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

  test("bad dates, times and ranges are refused", () => {
    expect(() => parseArgs.add_shift({ date: "2026-02-30", start: "08:00", end: "16:00" })).toThrow("date");
    expect(() => parseArgs.add_shift({ date: "2026-02-03", start: "24:00", end: "08:00" })).toThrow("start");
    expect(() => parseArgs.add_shift({ date: "2026-02-03", start: "8:00", end: "16:00" })).toThrow("start");
    expect(() => parseArgs.update_shift({ shift_id: "s", revision: 4 })).toThrow("at least one");
    expect(() => parseRange("2026-01-01", "2026-06-01", 93)).toThrow("93");
    expect(() => shiftTimes("08:00", "08:00")).toThrow("same time");
    expect(() => parseArgs.add_shift({ date: "2206-02-03", start: "08:00", end: "16:00" })).toThrow("five years");
  });

  test("null stands for a left-out optional argument, as strict clients send it", () => {
    expect(parseArgs.update_shift({ shift_id: "s", revision: 4, date: null, start: "09:00", end: null, job_id: null, note: null })).toEqual({
      shift_id: "s", revision: 4, date: undefined, start: "09:00", end: undefined, job_id: undefined, note: undefined,
    });
  });
});

describe("MCP earnings", () => {
  const snapshot = (hourly: number, threshold: number | null): WageSnapshot =>
    ({
      id: "wage", user_id: "user", job_id: "job", from_date: null,
      hourly_wage: hourly, wage_level: null, tariff_type_id: null,
      supplements: { rules: [] },
      overtime: threshold === null ? null : {
        enabled: true,
        weeklyThresholdHours: threshold,
        rules: [false, true].map((appliesOnHolidays) => ({
          days: [1, 2, 3, 4, 5, 6, 7], from: "00:00", to: "24:00", percent: 50, appliesOnHolidays,
        })),
      },
      tax_enabled: false, tax_percentage: 0,
      break_enabled: false, break_method: "none", break_threshold_hours: 0, break_deduction_minutes: 0,
    }) as WageSnapshot;
  const shift = (id: string, shift_date: string, start_time: string, end_time: string): LiveActivityRegularShift => ({
    id, user_id: "user", job_id: "job", shift_date, start_time, end_time, custom_pause_windows: null, custom_supplements: null,
  });
  const earn = (from: string, to: string, regular: LiveActivityRegularShift[], wage: WageSnapshot | null) =>
    shiftEarnings({ from, to, regular, recurring: [], snapshotFor: () => wage, currencyFor: () => "NOK" });

  test("gross pay and paid hours add up over the range", () => {
    const result = earn("2026-02-02", "2026-02-08", [shift("a", "2026-02-02", "08:00", "16:00"), shift("b", "2026-02-03", "22:00", "02:00")], snapshot(200, null));
    expect(result.totals).toEqual([{ currency: "NOK", gross_pay: 2400, paid_hours: 12, shifts: 2 }]);
  });

  test("overtime from earlier in the week counts for a range that starts mid-week", () => {
    // 2026-02-02 is a Monday. Ten hours before the range use up the 10-hour threshold.
    const result = earn(
      "2026-02-04",
      "2026-02-04",
      [shift("mon", "2026-02-02", "08:00", "18:00"), shift("wed", "2026-02-04", "08:00", "10:00")],
      snapshot(200, 10),
    );
    expect(result.totals).toEqual([{ currency: "NOK", gross_pay: 600, paid_hours: 2, shifts: 1 }]);
  });

  test("overlapping shifts on a date count once, as in the app", () => {
    const result = earn("2026-02-02", "2026-02-02", [shift("a", "2026-02-02", "08:00", "12:00"), shift("b", "2026-02-02", "10:00", "14:00")], snapshot(200, null));
    expect(result.totals[0]!.shifts).toBe(1);
  });

  test("a shift without pay can't push an overlapping paid shift out of the total", () => {
    const paid = snapshot(300, null);
    const result = shiftEarnings({
      from: "2026-02-02", to: "2026-02-02", recurring: [], currencyFor: () => "NOK",
      regular: [shift("paid", "2026-02-02", "08:00", "12:00"), { ...shift("unpaid", "2026-02-02", "10:00", "14:00"), job_id: "other" }],
      snapshotFor: (s) => (s.job_id === "job" ? paid : null),
    });
    expect(result.totals).toEqual([{ currency: "NOK", gross_pay: 1200, paid_hours: 4, shifts: 1 }]);
    expect(result.shifts_without_pay_setup).toBe(1);
  });

  test("shifts on a job without pay are reported, not priced with a guessed wage", () => {
    const result = earn("2026-02-02", "2026-02-02", [shift("a", "2026-02-02", "08:00", "12:00")], null);
    expect(result.totals).toEqual([]);
    expect(result.shifts_without_pay_setup).toBe(1);
  });
});
