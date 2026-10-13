// Uptime Robot polls GET /functions/v1/health to check that the edge runtime
// can start a worker. It has no imports so a cold start stays near 100 ms.
export default {
  fetch(req: Request): Response {
    if (req.method !== "GET" && req.method !== "HEAD") {
      return new Response("Method Not Allowed", { status: 405 });
    }
    return new Response(
      req.method === "HEAD" ? null : JSON.stringify({ ok: true }),
      {
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "no-store",
        },
      },
    );
  },
};
