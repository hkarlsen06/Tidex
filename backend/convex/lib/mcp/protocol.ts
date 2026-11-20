import type { Scope, ToolSpec } from "./registry";

// MCP over Streamable HTTP, without sessions, for both protocol eras:
// - 2026-07-28: no initialize. Every request carries its version in the
//   MCP-Protocol-Version header and in params._meta, plus Mcp-Method (and Mcp-Name for
//   tools/call) headers that must match the body.
// - 2025-06-18 and 2025-11-25: the client opens with initialize and then sends the
//   negotiated version in MCP-Protocol-Version. No Mcp-Session-Id is issued.
// Every reply is a single JSON body; the server never opens an SSE stream.
// Spec: https://modelcontextprotocol.io/specification/2026-07-28

export const MODERN_VERSION = "2026-07-28";
export const LEGACY_VERSIONS = ["2025-11-25", "2025-06-18"];
const SUPPORTED_VERSIONS = [MODERN_VERSION, ...LEGACY_VERSIONS];
const MAX_BODY_BYTES = 64 * 1024;
const META_VERSION = "io.modelcontextprotocol/protocolVersion";
const META_SERVER_INFO = "io.modelcontextprotocol/serverInfo";

export const SERVER_INFO = { name: "tidex", title: "Tidex", version: "1.0.0" };

const INSTRUCTIONS =
  "Tidex tracks the user's work shifts and what they earn. Dates are YYYY-MM-DD and times are HH:mm on the " +
  "user's local clock; a shift whose end is at or before its start ends the next day. Call list_shifts before " +
  "changing or deleting a shift, and pass the shift_id and revision it returns. Recurring shifts can only be " +
  "changed in the Tidex app. Confirm with the user before you delete a shift.";

export type ToolOutcome = { ok: true; value: unknown } | { ok: false; message: string };

/**
 * A token that checks out names a Tidex user and the OAuth scopes it grants, unless that
 * account is banned or gone.
 */
export type Authentication = { userId: string; scopes: ReadonlySet<string> } | "invalid_token" | "no_account";

/** The OAuth scopes a tool needs. A write tool's result shows the user's data, so it needs read too. */
const REQUIRED_SCOPES: Record<Scope, string[]> = { read: ["tidex:read"], write: ["tidex:read", "tidex:write"] };

const MISSING_SCOPE: Record<Scope, string> = {
  read: "Reading the user's Tidex data needs the tidex:read permission. Ask the user to connect Tidex again and allow reading.",
  write:
    "Changing the user's Tidex data needs the tidex:write permission. Ask the user to connect Tidex again and allow changes.",
};

/** What the protocol needs to know about a tool; mcp.ts passes its full McpTool entries. */
type Tool = Pick<ToolSpec, "definition" | "scope">;

export type McpDeps<T extends Tool = Tool> = {
  /** The URL of the MCP endpoint, which is the audience its tokens must carry. */
  resourceUrl: string;
  authenticate: (token: string) => Promise<Authentication>;
  tools: readonly T[];
  callTool: (userId: string, tool: T, args: Record<string, unknown>) => Promise<ToolOutcome>;
};

type Id = string | number | null;

/** The protected resource metadata URL for an MCP URL (RFC 9728 section 3.1). */
export function resourceMetadataUrl(resourceUrl: string): string {
  const url = new URL(resourceUrl);
  return `${url.origin}/.well-known/oauth-protected-resource${url.pathname === "/" ? "" : url.pathname}`;
}

export function resourceMetadata(resourceUrl: string, issuer: string) {
  return {
    resource: resourceUrl,
    authorization_servers: [issuer],
    bearer_methods_supported: ["header"],
    scopes_supported: REQUIRED_SCOPES.write,
    resource_name: "Tidex",
    resource_documentation: "https://tidex.no",
  };
}

const json = (status: number, body: unknown, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...headers },
  });

const rpcError = (status: number, id: Id, code: number, message: string, data?: unknown) =>
  json(status, { jsonrpc: "2.0", id, error: data === undefined ? { code, message } : { code, message, data } });

/** Header values may be sent as =?base64?...?= when they aren't plain ASCII. */
function headerValue(value: string | null): string | null {
  const match = value === null ? null : /^=\?base64\?(.*)\?=$/.exec(value);
  if (match === null) return value;
  try {
    return new TextDecoder().decode(Uint8Array.from(atob(match[1]!), (c) => c.charCodeAt(0)));
  } catch {
    return null;
  }
}

/** A client without a token first asks only to read, and steps up to tidex:write on its first write. */
function unauthorized(resourceUrl: string, invalidToken: boolean) {
  const params = [
    ...(invalidToken ? ['error="invalid_token"'] : []),
    `scope="${REQUIRED_SCOPES.read.join(" ")}"`,
    `resource_metadata="${resourceMetadataUrl(resourceUrl)}"`,
  ].join(", ");
  return json(401, { error: invalidToken ? "invalid_token" : "unauthorized" }, { "WWW-Authenticate": `Bearer ${params}` });
}

/** Names every scope the tool needs, so the client asks for all of them in one new authorization. */
function insufficientScope(resourceUrl: string, id: Id, scope: Scope) {
  const params = [
    'error="insufficient_scope"',
    `scope="${REQUIRED_SCOPES[scope].join(" ")}"`,
    `resource_metadata="${resourceMetadataUrl(resourceUrl)}"`,
    `error_description="${MISSING_SCOPE[scope]}"`,
  ].join(", ");
  return json(
    403,
    { jsonrpc: "2.0", id, error: { code: -32001, message: MISSING_SCOPE[scope] } },
    { "WWW-Authenticate": `Bearer ${params}` },
  );
}

/**
 * The body as text, or null past MAX_BODY_BYTES. Reads the stream with a count, so a body
 * without Content-Length can't be buffered whole first.
 */
async function boundedText(request: Request): Promise<string | null> {
  if (Number(request.headers.get("Content-Length") ?? 0) > MAX_BODY_BYTES) return null;
  if (request.body === null) return "";
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_BODY_BYTES) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(bytes);
}

/**
 * Origins whose servers may send an Origin header when they connect. A browser page on
 * them still can't call /mcp, because the endpoint answers no CORS preflight.
 */
const ALLOWED_ORIGINS = new Set(["https://claude.ai", "https://chatgpt.com", "https://chat.openai.com"]);

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

export async function handleMcpPost<T extends Tool>(request: Request, deps: McpDeps<T>): Promise<Response> {
  // Agents connect from servers and apps. A web page sends its Origin, and must not be
  // able to use a token it got hold of.
  const origin = request.headers.get("Origin");
  if (origin !== null && !ALLOWED_ORIGINS.has(origin)) {
    return rpcError(403, null, -32600, "Requests from web pages are not allowed");
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const token = /^Bearer (\S+)$/i.exec(authorization)?.[1];
  if (token === undefined) return unauthorized(deps.resourceUrl, false);
  const auth = await deps.authenticate(token);
  if (auth === "invalid_token") return unauthorized(deps.resourceUrl, true);
  // Signing in again would give the same answer, so this is not a 401.
  if (auth === "no_account") return json(403, { error: "This Tidex account is not available." });
  const { userId, scopes } = auth;

  const text = await boundedText(request);
  if (text === null) return rpcError(413, null, -32600, "Request body is too large");

  let message: unknown;
  try {
    message = JSON.parse(text);
  } catch {
    return rpcError(400, null, -32700, "Parse error");
  }
  if (Array.isArray(message)) return rpcError(400, null, -32600, "Batches are not supported");
  if (!isObject(message) || message.jsonrpc !== "2.0") return rpcError(400, null, -32600, "Invalid request");
  // Responses and notifications need no reply.
  if (typeof message.method !== "string" || !("id" in message)) {
    return typeof message.method === "string" || "result" in message || "error" in message
      ? new Response(null, { status: 202 })
      : rpcError(400, null, -32600, "Invalid request");
  }
  const id = message.id as Id;
  if (typeof id !== "string" && typeof id !== "number") return rpcError(400, null, -32600, "Invalid request id");
  const method = message.method;
  const params = isObject(message.params) ? message.params : {};

  const version = request.headers.get("MCP-Protocol-Version");
  const meta = isObject(params._meta) ? params._meta : {};
  // A body that declares 2026-07-28 gets that era's header checks even without the header.
  const modern = version === MODERN_VERSION || meta[META_VERSION] === MODERN_VERSION;
  // initialize belongs to the 2025 era; a 2026-07-28 request never opens with it.
  if (method === "initialize" && !modern) {
    const requested = typeof params.protocolVersion === "string" ? params.protocolVersion : "";
    return json(200, {
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion: LEGACY_VERSIONS.includes(requested) ? requested : LEGACY_VERSIONS[0],
        capabilities: { tools: { listChanged: false } },
        serverInfo: SERVER_INFO,
        instructions: INSTRUCTIONS,
      },
    });
  }

  if (version !== null && !SUPPORTED_VERSIONS.includes(version) && !modern) {
    return rpcError(400, id, -32022, "Unsupported protocol version", { supported: SUPPORTED_VERSIONS, requested: version });
  }
  if (modern) {
    const mismatch = (header: string, value: string | null, expected: unknown) =>
      rpcError(400, id, -32020, `Header mismatch: ${header} header value '${value ?? ""}' does not match body value '${String(expected)}'`);
    if (version !== MODERN_VERSION || meta[META_VERSION] !== MODERN_VERSION) {
      return mismatch("MCP-Protocol-Version", version, meta[META_VERSION]);
    }
    const methodHeader = headerValue(request.headers.get("Mcp-Method"));
    if (methodHeader !== method) return mismatch("Mcp-Method", methodHeader, method);
    if (method === "tools/call") {
      const nameHeader = headerValue(request.headers.get("Mcp-Name"));
      if (nameHeader !== params.name) return mismatch("Mcp-Name", nameHeader, params.name);
    }
  }

  // 2026-07-28 results carry resultType and the server's identity.
  const reply = (result: Record<string, unknown>) =>
    json(200, {
      jsonrpc: "2.0",
      id,
      result: modern ? { resultType: "complete", ...result, _meta: { [META_SERVER_INFO]: SERVER_INFO } } : result,
    });
  const cacheable = modern ? { ttlMs: 3_600_000, cacheScope: "public" } : {};

  switch (method) {
    case "ping":
      return reply({});
    case "server/discover":
      return reply({
        supportedVersions: SUPPORTED_VERSIONS,
        capabilities: { tools: { listChanged: false } },
        instructions: INSTRUCTIONS,
        ...cacheable,
      });
    case "tools/list":
      return reply({ tools: deps.tools.map((tool) => tool.definition), ...cacheable });
    case "tools/call": {
      const tool = deps.tools.find((t) => t.definition.name === params.name);
      if (tool === undefined) return rpcError(200, id, -32602, `Unknown tool: ${String(params.name)}`);
      if (!REQUIRED_SCOPES[tool.scope].every((needed) => scopes.has(needed))) {
        return insufficientScope(deps.resourceUrl, id, tool.scope);
      }
      const args = params.arguments ?? {};
      if (!isObject(args)) return rpcError(200, id, -32602, "arguments must be an object");
      const outcome = await deps.callTool(userId, tool, args);
      return reply(
        outcome.ok
          ? {
              content: [{ type: "text", text: JSON.stringify(outcome.value) }],
              structuredContent: outcome.value,
              isError: false,
            }
          : { content: [{ type: "text", text: outcome.message }], isError: true },
      );
    }
    default:
      return rpcError(modern ? 404 : 200, id, -32601, `Method not found: ${method}`);
  }
}
