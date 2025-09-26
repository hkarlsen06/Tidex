import { createBrowserClient } from "@supabase/ssr";

const missingEnvError = (name: string) =>
  new Error(`Missing required environment variable: ${name}`);

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

if (!supabaseUrl) {
  throw missingEnvError("NEXT_PUBLIC_SUPABASE_URL");
}

if (!supabaseAnonKey) {
  throw missingEnvError("NEXT_PUBLIC_SUPABASE_ANON_KEY");
}

export const createSupabaseBrowserClient = () =>
  createBrowserClient(supabaseUrl, supabaseAnonKey);
