import "server-only";
import { cookies } from "next/headers";
import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { ENV } from "@/lib/env";

export async function createSupabaseServerClient() {
  const store = await cookies();
  return createServerClient(ENV.URL!, ENV.PUBLISHABLE!, {
    cookies: {
      get: (name: string) => store.get(name)?.value,
      set: (_n: string, _v: string, _o?: CookieOptions) => {},
      remove: (_n: string, _o?: CookieOptions) => {},
    },
  });
}
