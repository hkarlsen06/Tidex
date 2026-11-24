import { ConvexError, type Value, v } from "convex/values";
import type { JSONWebKeySet } from "jose";
import { internal } from "./_generated/api";
import { type ActionCtx, httpAction, internalMutation, internalQuery, type QueryCtx } from "./_generated/server";
import { userByClerkId } from "./lib/auth";
import { RATE_WINDOW_MS } from "./lib/mcp/db";
import { handleMcpPost, resourceMetadata, type ToolOutcome } from "./lib/mcp/protocol";
import type { McpTool } from "./lib/mcp/registry";
import { ToolError } from "./lib/mcp/shiftTimes";
import { checkKeySet, type KeySource, verifyAccessToken } from "./lib/mcp/token";
import { payTools } from "./mcpPay";
import { planTools } from "./mcpPlans";
import { shiftTools } from "./mcpShifts";
import { socialTools } from "./mcpSocial";

// The MCP server: lets a user's AI agent read and change their Tidex data. See
// docs/mcp-server.md. The HTTP action checks the OAuth token, its scopes and the
// arguments, then runs the tool for the user the token names. Each area's tools live in
// mcp<Area>.ts.

const [overviewTool, ...jobAndPayTools] = payTools;
const tools: McpTool[] = [overviewTool!, ...shiftTools, ...planTools, ...jobAndPayTools, ...socialTools];

const KEYS_FRESH_MS = 60 * 60_000;
// Clerk's keys are fetched at most this often, failed attempts included, so junk tokens
// naming unknown keys can't make every request reach Clerk.
const KEY_FETCH_COOLDOWN_MS = 60_000;
const MAX_CALLS = 120;
const MAX_WRITES = 40;


// ---------- Access ----------

const keyRow = (ctx: QueryCtx, issuer: string) =>
  ctx.db.query("mcp_signing_keys").withIndex("by_issuer", (q) => q.eq("issuer", issuer)).unique();

export const storedKeys = internalQuery({
  args: { issuer: v.string() },
  handler: async (ctx, { issuer }) => {
    const row = await keyRow(ctx, issuer);
    return row?.keys === undefined ? null : { keys: row.keys as JSONWebKeySet, fetched_at: row.fetched_at };
  },
});

/** True for the one request a minute that may fetch Clerk's keys. */
export const claimKeyFetch = internalMutation({
  args: { issuer: v.string() },
  handler: async (ctx, { issuer }) => {
    const now = Date.now();
    const row = await keyRow(ctx, issuer);
    if (row !== null && now - (row.attempted_at ?? 0) < KEY_FETCH_COOLDOWN_MS) return false;
    if (row === null) await ctx.db.insert("mcp_signing_keys", { issuer, fetched_at: 0, attempted_at: now });
    else await ctx.db.patch(row._id, { attempted_at: now });
    return true;
  },
});

export const storeKeys = internalMutation({
  args: { issuer: v.string(), keys: v.any() },
  handler: async (ctx, { issuer, keys }) => {
    const row = await keyRow(ctx, issuer);
    if (row !== null) await ctx.db.patch(row._id, { keys, fetched_at: Date.now() });
  },
});

/**
 * Clerk's keys from mcp_signing_keys, fetched again after an hour, or sooner when a token
 * names a key they lack. Stored keys stand in while a fetch fails.
 */
function clerkKeys(ctx: ActionCtx, issuer: string): KeySource {
  return async (refresh) => {
    const stored = await ctx.runQuery(internal.mcp.storedKeys, { issuer });
    const age = stored === null ? Infinity : Date.now() - stored.fetched_at;
    // Keys fetched moments ago are current, so a key they lack doesn't exist.
    if (stored !== null && age < (refresh ? KEY_FETCH_COOLDOWN_MS : KEYS_FRESH_MS)) return stored.keys;
    const fallback = refresh ? null : (stored?.keys ?? null);
    if (!(await ctx.runMutation(internal.mcp.claimKeyFetch, { issuer }))) {
      if (fallback !== null) return fallback;
      throw new Error("Clerk's keys are being fetched by another request");
    }
    try {
      const response = await fetch(`${issuer}/.well-known/jwks.json`);
      if (!response.ok) throw new Error(`Clerk JWKS answered ${response.status}`);
      // Storing a set that doesn't work would turn every valid token away for an hour.
      const keys = await checkKeySet(await response.json());
      await ctx.runMutation(internal.mcp.storeKeys, { issuer, keys });
      return keys;
    } catch (error) {
      if (fallback === null) throw error;
      console.error("Clerk JWKS fetch failed; using stored keys", error);
      return fallback;
    }
  };
}

export const userForToken = internalQuery({
  args: { clerk_user_id: v.string() },
  handler: async (ctx, { clerk_user_id }) => {
    const user = await userByClerkId(ctx, clerk_user_id);
    return user === null || user.banned_at !== undefined ? null : user.id;
  },
});

/** Counts a tool call. Returns null when allowed, else the seconds until the window resets. */
export const consume = internalMutation({
  args: { user_id: v.string(), write: v.boolean() },
  handler: async (ctx, { user_id, write }) => {
    const now = Date.now();
    const row = await ctx.db.query("mcp_rate_limits").withIndex("by_user", (q) => q.eq("user_id", user_id)).unique();
    if (row === null || now - row.window_start >= RATE_WINDOW_MS) {
      // Replacing the row also clears the sends that mcpSocial counts.
      const fresh = { user_id, window_start: now, calls: 1, writes: write ? 1 : 0 };
      if (row === null) await ctx.db.insert("mcp_rate_limits", fresh);
      else await ctx.db.replace(row._id, fresh);
      return null;
    }
    if (row.calls >= MAX_CALLS || (write && row.writes >= MAX_WRITES)) {
      return Math.ceil((row.window_start + RATE_WINDOW_MS - now) / 1000);
    }
    await ctx.db.patch(row._id, { calls: row.calls + 1, writes: row.writes + (write ? 1 : 0) });
    return null;
  },
});

// ---------- HTTP ----------

/** The MCP URL and Clerk issuer, or null while the server is off or misconfigured. */
function config() {
  const resourceUrl = process.env.MCP_RESOURCE_URL;
  const issuer = process.env.CLERK_JWT_ISSUER_DOMAIN;
  if (!resourceUrl || !issuer) return null;
  try {
    if (new URL(resourceUrl).pathname === "/mcp") return { resourceUrl, issuer };
  } catch {
    // Reported below.
  }
  console.error("MCP_RESOURCE_URL must be an absolute URL ending in /mcp", resourceUrl);
  return null;
}

const notFound = () => new Response("Not found", { status: 404 });

function errorMessage(error: ConvexError<Value>) {
  const data = error.data as { code?: string; message?: string } | string;
  if (typeof data === "string") return data;
  return data.message ?? `Tidex refused the change (${data.code ?? "error"}).`;
}

async function runTool(ctx: ActionCtx, userId: string, tool: McpTool, rawArgs: Record<string, unknown>): Promise<ToolOutcome> {
  const retryAfter = await ctx.runMutation(internal.mcp.consume, { user_id: userId, write: tool.scope === "write" });
  if (retryAfter !== null) return { ok: false, message: `Too many requests. Try again in ${retryAfter} seconds.` };
  try {
    return { ok: true, value: await tool.run(ctx, userId, tool.parse(rawArgs)) };
  } catch (error) {
    if (error instanceof ToolError) return { ok: false, message: error.message };
    if (error instanceof ConvexError) return { ok: false, message: errorMessage(error) };
    console.error("mcp tool failed", tool.definition.name, error);
    return { ok: false, message: "Tidex couldn't do that right now. Try again later." };
  }
}

/** POST /mcp. Answers 404 until MCP_RESOURCE_URL is set, so a deploy alone doesn't turn it on. */
export const endpoint = httpAction(async (ctx, request) => {
  const settings = config();
  if (settings === null) return notFound();
  const { resourceUrl, issuer } = settings;
  try {
    return await handleMcpPost(request, {
      resourceUrl,
      authenticate: async (token) => {
        const verified = await verifyAccessToken(token, issuer, resourceUrl, clerkKeys(ctx, issuer));
        if (verified === null) return "invalid_token";
        const userId = await ctx.runQuery(internal.mcp.userForToken, { clerk_user_id: verified.clerkUserId });
        return userId === null ? "no_account" : { userId, scopes: verified.scopes };
      },
      tools,
      callTool: (userId, tool, args) => runTool(ctx, userId, tool, args),
    });
  } catch (error) {
    console.error("mcp request failed", error);
    return Response.json({ error: "temporarily_unavailable" }, { status: 503, headers: { "Retry-After": "30" } });
  }
});

/** GET and DELETE /mcp. There is no SSE stream and no session to end. */
export const methodNotAllowed = httpAction(async () =>
  config() === null ? notFound() : new Response(null, { status: 405, headers: { Allow: "POST" } }),
);

/** OAuth protected resource metadata (RFC 9728), which tells clients to get a token from Clerk. */
export const protectedResource = httpAction(async () => {
  const settings = config();
  if (settings === null) return notFound();
  return Response.json(resourceMetadata(settings.resourceUrl, settings.issuer), {
    headers: { "Access-Control-Allow-Origin": "*", "Cache-Control": "public, max-age=3600" },
  });
});
