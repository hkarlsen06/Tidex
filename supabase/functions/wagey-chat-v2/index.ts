// Wagey is shut down. This stub makes no OpenAI, database, or network calls.
const MESSAGE =
  "Wagey is being shut down and will be removed entirely in the next update.";

// Same headers @supabase/server's withSupabase sent by default.
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-retry-count",
  "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
};

export default {
  fetch(req: Request): Response {
    if (req.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }
    // iOS 2.7.1 and older treat any non-200 status as a generic HTTP error and
    // never read the body, so answer with the SSE stream they render as a reply.
    const body = [
      { type: "text_start" },
      { type: "text", content: MESSAGE },
      { type: "done" },
    ].map((chunk) => `data: ${JSON.stringify({ type: "chunk", chunk })}\n\n`)
      .join("");
    return new Response(body, {
      headers: { ...CORS_HEADERS, "Content-Type": "text/event-stream" },
    });
  },
};
