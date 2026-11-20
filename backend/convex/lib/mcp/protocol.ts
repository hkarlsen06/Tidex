import { isToolName, TOOLS, type ToolName } from "./tools";

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

export type McpDeps = {
  /** The URL of the MCP endpoint, which is the audience its tokens must carry. */
  resourceUrl: string;
  /** The Tidex user ID the bearer token is valid for, or null. */
  authenticate: (token: string) => Promise<string | null>;
  callTool: (userId: string, name: ToolName, args: Record<string, unknown>) => Promise<ToolOutcome>;
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

function unauthorized(deps: McpDeps, invalidToken: boolean) {
  const params = [
    ...(invalidToken ? ['error="invalid_token"'] : []),
    `resource_metadata="${resourceMetadataUrl(deps.resourceUrl)}"`,
  ].join(", ");
  return json(401, { error: invalidToken ? "invalid_token" : "unauthorized" }, { "WWW-Authenticate": `Bearer ${params}` });
}

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

export async function handleMcpPost(request: Request, deps: McpDeps): Promise<Response> {
  // Agents connect from servers and apps, which send no Origin. A browser page does, and
  // must not be able to use a token it got hold of.
  if (request.headers.get("Origin") !== null) {
    return rpcError(403, null, -32600, "Requests from web pages are not allowed");
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const token = /^Bearer (\S+)$/i.exec(authorization)?.[1];
  if (token === undefined) return unauthorized(deps, false);
  const userId = await deps.authenticate(token);
  if (userId === null) return unauthorized(deps, true);

  if (Number(request.headers.get("Content-Length") ?? 0) > MAX_BODY_BYTES) {
    return rpcError(413, null, -32600, "Request body is too large");
  }
  const text = await request.text();
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) return rpcError(413, null, -32600, "Request body is too large");

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

  if (method === "initialize") {
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

  const version = request.headers.get("MCP-Protocol-Version");
  const modern = version === MODERN_VERSION;
  if (version !== null && !SUPPORTED_VERSIONS.includes(version)) {
    return rpcError(400, id, -32022, "Unsupported protocol version", { supported: SUPPORTED_VERSIONS, requested: version });
  }
  if (modern) {
    const mismatch = (header: string, value: string | null, expected: unknown) =>
      rpcError(400, id, -32020, `Header mismatch: ${header} header value '${value ?? ""}' does not match body value '${String(expected)}'`);
    const meta = isObject(params._meta) ? params._meta : {};
    if (meta[META_VERSION] !== MODERN_VERSION) return mismatch("MCP-Protocol-Version", version, meta[META_VERSION]);
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
      return reply({ tools: TOOLS, ...cacheable });
    case "tools/call": {
      if (!isToolName(params.name)) return rpcError(200, id, -32602, `Unknown tool: ${String(params.name)}`);
      const args = params.arguments ?? {};
      if (!isObject(args)) return rpcError(200, id, -32602, "arguments must be an object");
      const outcome = await deps.callTool(userId, params.name, args);
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
