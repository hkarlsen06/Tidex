// Shared CORS headers for Edge Functions.
// Set CORS_ALLOWED_ORIGIN per environment when a browser client needs access.
const allowedOrigin = Deno.env.get("CORS_ALLOWED_ORIGIN") ?? "https://tidex.no";

export const corsHeaders = {
  "Access-Control-Allow-Origin": allowedOrigin,
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-send-push-secret, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS, PUT, DELETE",
  "Vary": "Origin",
};
