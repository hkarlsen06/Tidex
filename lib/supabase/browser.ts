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
 * Note: We use getUser() (not getSession()) in supabase-listener.tsx and
 * other client components for session validation. This validates the session
 * with the Supabase Auth server and avoids the security warning about
 * potentially unauthentic data from getSession().
 */
export const supabase = createBrowserClient(supabaseUrl, supabasePublishableKey);
