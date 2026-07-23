import type { SupabaseContext } from "@supabase/server";
import type { SupabaseClient, User } from "@supabase/supabase-js";

export type WageyRequestContext = {
  supabase: SupabaseClient;
  supabaseAdmin: SupabaseClient;
  user: User;
  cache: Map<string, Promise<unknown>>;
};

export function invalidateWageyCache(ctx: WageyRequestContext): void {
  ctx.cache.clear();
}

export async function createWageyContext(
  supabaseContext: SupabaseContext,
): Promise<WageyRequestContext> {
  const {
    data: { user },
    error,
  } = await supabaseContext.supabase.auth.getUser();

  if (error || !user) {
    throw new Error("Unauthorized");
  }

  return {
    supabase: supabaseContext.supabase as unknown as SupabaseClient,
    supabaseAdmin: supabaseContext.supabaseAdmin as unknown as SupabaseClient,
    user,
    cache: new Map(),
  };
}
