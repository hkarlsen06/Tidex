/**
 * Serialize concurrent token refresh attempts to prevent race conditions.
 *
 * When multiple components or effects try to call getSession() simultaneously
 * during app boot or rehydration, this can trigger concurrent refresh requests
 * that race with each other, potentially causing "Refresh Token Not Found" errors.
 *
 * Usage:
 *   import { supabase } from "@/lib/supabase/browser";
 *   const { data } = await withRefreshLock(() => supabase.auth.getSession());
 */

let inflight: Promise<any> | null = null;

export async function withRefreshLock<T>(fn: () => Promise<T>): Promise<T> {
  // Wait for any in-flight refresh to complete
  while (inflight) {
    await inflight.catch(() => {
      // Ignore errors from previous refresh attempts
    });
  }

  // Execute the refresh operation
  inflight = fn();

  try {
    return await inflight;
  } finally {
    inflight = null;
  }
}
