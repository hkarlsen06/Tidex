/**
 * Serialize concurrent token refresh attempts to prevent race conditions.
 *
 * When multiple components or effects try to call getUser() simultaneously
 * during app boot or rehydration, this can trigger concurrent refresh requests
 * that race with each other, potentially causing "Refresh Token Not Found" errors.
 *
 * Usage:
 *   import { supabase } from "@/lib/supabase/browser";
 *   const { data } = await withRefreshLock(() => supabase.auth.getUser());
 */

let inflight: Promise<any> | null = null;

export async function withRefreshLock<T>(fn: () => Promise<T>): Promise<T> {
  // Wait for any in-flight refresh to complete
  if (inflight) {
    await inflight.catch(() => {
      // Ignore errors from previous refresh attempts
    });
  }

  // If another refresh started while we were waiting, return that one
  if (inflight) {
    return inflight as Promise<T>;
  }

  // Execute the refresh operation atomically
  const promise = fn();
  inflight = promise;

  try {
    return await promise;
  } finally {
    // Only clear if we're still the active promise
    if (inflight === promise) {
      inflight = null;
    }
  }
}
