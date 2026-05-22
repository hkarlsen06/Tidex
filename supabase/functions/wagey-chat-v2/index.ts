import { withSupabase } from "npm:@supabase/server@1.0.0";
import { corsHeaders } from "../_shared/cors.ts";
import { createWageyContext } from "../_shared/wagey/context.ts";
import { handleWageyRequest } from "../_shared/wagey/router.ts";

const REQUEST_ID_HEADER = "x-wagey-request-id";

function json(
  body: Record<string, unknown>,
  status: number,
  extraHeaders: HeadersInit = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...corsHeaders,
      ...extraHeaders,
    },
  });
}

function log(
  level: "info" | "warn" | "error",
  requestId: string,
  message: string,
  metadata: Record<string, unknown> = {},
): void {
  const payload = {
    scope: "wagey-chat-v2",
    requestId,
    message,
    ...metadata,
  };

  if (level === "error") {
    console.error(JSON.stringify(payload));
    return;
  }
  if (level === "warn") {
    console.warn(JSON.stringify(payload));
    return;
  }
  console.log(JSON.stringify(payload));
}

export default {
  fetch: withSupabase<any>(
    { auth: "user", cors: corsHeaders },
    async (req, supabaseContext) => {
      const requestId =
        req.headers.get(REQUEST_ID_HEADER) ?? crypto.randomUUID();

      if (req.method !== "POST") {
        return json({ error: "Method not allowed" }, 405, {
          [REQUEST_ID_HEADER]: requestId,
        });
      }

      try {
        const requestHeaders = new Headers(req.headers);
        requestHeaders.set(REQUEST_ID_HEADER, requestId);
        const requestWithId = new Request(req, { headers: requestHeaders });

        const response = await handleWageyRequest(requestWithId, async () => {
          return await createWageyContext(supabaseContext);
        });

        const responseHeaders = new Headers(response.headers);
        for (const [key, value] of Object.entries(corsHeaders)) {
          responseHeaders.set(key, value);
        }
        responseHeaders.set(REQUEST_ID_HEADER, requestId);

        return new Response(response.body, {
          status: response.status,
          statusText: response.statusText,
          headers: responseHeaders,
        });
      } catch (error) {
        const message =
          error instanceof Error ? error.message : "Failed to initialize Wagey";
        log("error", requestId, "Initialization failed", {
          error: message,
        });
        if (
          message === "Missing authorization header" ||
          message === "Unauthorized"
        ) {
          return json({ error: message }, 401, {
            [REQUEST_ID_HEADER]: requestId,
          });
        }
        return json({ error: message }, 500, {
          [REQUEST_ID_HEADER]: requestId,
        });
      }
    },
  ),
};
