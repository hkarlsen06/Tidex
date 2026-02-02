import { createBrowserClient } from "@supabase/ssr";

const missingEnvError = (name: string) =>
  new Error(`Missing required environment variable: ${name}`);

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabasePublishableKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;

if (!supabaseUrl) {
  throw missingEnvError("NEXT_PUBLIC_SUPABASE_URL");
}

if (!supabasePublishableKey) {
  throw missingEnvError("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY");
}

/**
 * Browser client for Supabase
 *
 * IMPORTANT: Browser clients should NOT use cookieOptions parameter.
 * The @supabase/ssr library handles browser cookies automatically using
 * the document.cookie API with appropriate defaults.
 *
 * Only server-side clients (proxy, server) should configure cookie options.
 *
 * Note: We use getClaims() for JWT validation (local, fast) and only use
 * getSession() when we need the raw access_token string. Auth is verified
 * server-side via getClaims() in the DAL.
 */
const client = createBrowserClient(supabaseUrl, supabasePublishableKey);

// Suppress getSession warning - we use getClaims() for auth validation
// @ts-expect-error: suppressGetSessionWarning is not in types but works
client.auth.suppressGetSessionWarning = true;

export const supabase = client;
