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

export const supabase = createBrowserClient(supabaseUrl, supabasePublishableKey);
