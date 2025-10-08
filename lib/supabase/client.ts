import { createBrowserClient } from "@supabase/ssr";

import { SUPABASE_AUTH_COOKIE_NAME } from "./constants";

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

// Singleton instance to ensure only one browser client exists
let browserClient: ReturnType<typeof createBrowserClient> | null = null;

export const createSupabaseBrowserClient = () => {
  if (browserClient) return browserClient;

  browserClient = createBrowserClient(supabaseUrl, supabasePublishableKey, {
    cookieOptions: {
      name: SUPABASE_AUTH_COOKIE_NAME,
    },
    auth: {
      persistSession: true,
      autoRefreshToken: true,
    },
  });

  return browserClient;
};
