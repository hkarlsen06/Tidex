// Edge runtime router (the "main" function) for the self-hosted Supabase stack.
//
// Deployed by copying this directory to
// /srv/tidex/tidex-sb/volumes/functions/main/ on mdr and running
// `docker compose restart functions` in /srv/tidex/tidex-sb.
// It lives outside supabase/functions so `supabase functions serve` does not
// treat it as a user function.
//
// Every function requires a valid JWT unless it is listed in PUBLIC_FUNCTIONS.
// The router does not read the VERIFY_JWT env var or verify_jwt in config.toml.
import { bearerToken, createJwtVerifier } from "./auth.ts";

// deno-lint-ignore no-explicit-any
declare const EdgeRuntime: any;

const FUNCTIONS_ROOT = "/home/deno/functions";

// Functions that authenticate their callers some other way (Apple signature,
// Standard Webhooks signature, calendar token) or are public stubs. Keep in
// sync with the verify_jwt = false entries in supabase/config.toml.
const PUBLIC_FUNCTIONS = new Set([
  "apple-server-notifications",
  "before-user-created",
  "calendar-feed",
  "wagey-chat-v2",
]);

// UptimeBot polls GET /functions/v1/send-push-notifications with only the
// publishable key. The function answers GET with a static status and checks
// credentials itself on POST, so the router lets that GET through.
const PUBLIC_GET_FUNCTIONS = new Set(["send-push-notifications"]);

// Lowercase letters, digits and hyphens. This rules out _shared, node_modules,
// deno.json and path tricks. main is the router itself.
const FUNCTION_NAME = /^[a-z0-9][a-z0-9-]*$/;

const verifyJwt = createJwtVerifier({
  secret: Deno.env.get("JWT_SECRET"),
  jwks: Deno.env.get("SUPABASE_JWKS"),
});

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function isDeployedFunction(name: string): Promise<boolean> {
  if (!FUNCTION_NAME.test(name) || name === "main") return false;
  try {
    return (await Deno.stat(`${FUNCTIONS_ROOT}/${name}/index.ts`)).isFile;
  } catch {
    return false;
  }
}

Deno.serve(async (req: Request) => {
  const name = new URL(req.url).pathname.split("/")[1] ?? "";
  if (!name) {
    return json(400, { msg: "missing function name in request" });
  }

  if (!(await isDeployedFunction(name))) {
    return json(404, { msg: "function not found" });
  }

  // CORS preflights carry no credentials.
  const isPublic = PUBLIC_FUNCTIONS.has(name) ||
    (req.method === "GET" && PUBLIC_GET_FUNCTIONS.has(name));
  if (req.method !== "OPTIONS" && !isPublic) {
    const token = bearerToken(req);
    if (!token) {
      return json(401, { code: 401, message: "Missing authorization header" });
    }
    if (!(await verifyJwt(token))) {
      return json(401, { code: 401, message: "Invalid JWT" });
    }
  }

  try {
    const envVars = Object.entries(Deno.env.toObject());
    const worker = await EdgeRuntime.userWorkers.create({
      servicePath: `${FUNCTIONS_ROOT}/${name}`,
      memoryLimitMb: 150,
      workerTimeoutMs: 60 * 1000,
      noModuleCache: false,
      importMapPath: null,
      envVars,
    });
    return await worker.fetch(req);
  } catch (e) {
    console.error(`[router] ${name} failed:`, e);
    return json(500, { msg: "function failed" });
  }
});
