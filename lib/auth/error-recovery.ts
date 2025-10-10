import "server-only";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { withRefreshLock } from "./refresh-lock";

/**
 * Error recovery policy for 401 authentication failures.
 *
 * When a Supabase call returns 401:
 * 1. Attempt exactly ONE session refresh behind refresh lock
 * 2. If still 401 after refresh → sign out server-side and redirect to /login
 * 3. Never retry more than once to avoid infinite loops
 *
 * Usage in Server Components/Actions:
 *   try {
 *     const { data, error } = await supabase.from('table').select();
 *     if (error) throw error;
 *     return data;
 *   } catch (error) {
 *     await handleAuthError(error);
 *     // Will not reach here - handleAuthError redirects or re-throws
 *   }
 */

let refreshAttempted = false; // Global flag to prevent infinite retry loops

/**
 * Handle authentication errors with refresh-then-signout policy.
 *
 * @param error - Error from Supabase operation
 * @throws Redirects to /login on auth failure, re-throws other errors
 */
export async function handleAuthError(error: any): Promise<never> {
  // Check if error is 401 Unauthorized
  const is401 =
    error?.status === 401 ||
    error?.code === "PGRST301" || // PostgREST 401
    error?.message?.includes("JWT") ||
    error?.message?.includes("expired") ||
    error?.message?.includes("Invalid Refresh Token");

  if (!is401) {
    // Not an auth error - re-throw for caller to handle
    throw error;
  }

  console.warn("[AUTH ERROR] 401 detected:", error.message);

  // If we already attempted refresh, give up and sign out
  if (refreshAttempted) {
    console.error("[AUTH ERROR] Refresh failed, signing out");
    refreshAttempted = false; // Reset for next session
    await signOutAndRedirect();
  }

  // Attempt exactly one refresh behind the lock
  refreshAttempted = true;

  try {
    console.log("[AUTH ERROR] Attempting session refresh");
    const supabase = await createSupabaseServerClient();

    // Use refresh lock to prevent concurrent refresh attempts
    const { data, error: refreshError } = await withRefreshLock(() =>
      supabase.auth.getSession()
    );

    if (refreshError || !data.session) {
      console.error("[AUTH ERROR] Refresh failed:", refreshError?.message);
      await signOutAndRedirect();
    }

    console.log("[AUTH ERROR] Refresh succeeded, resetting flag");
    refreshAttempted = false; // Reset flag on success

    // Refresh succeeded but the original operation still failed
    // Redirect to trigger re-render with fresh session
    redirect(getCurrentPath());
  } catch (refreshError) {
    console.error("[AUTH ERROR] Refresh threw exception:", refreshError);
    await signOutAndRedirect();
  }

  // TypeScript needs this for exhaustiveness checking, but code never reaches here
  // because all paths above either throw or redirect
  throw new Error("Unreachable");
}

/**
 * Sign out server-side and redirect to login.
 * Never returns - always redirects.
 */
async function signOutAndRedirect(): Promise<never> {
  try {
    const supabase = await createSupabaseServerClient();
    await supabase.auth.signOut();
  } catch (signOutError) {
    console.error("[AUTH ERROR] Sign out failed:", signOutError);
    // Continue to redirect even if sign out fails
  }

  redirect("/login");
}

/**
 * Get current path for redirect after refresh.
 * Falls back to root if headers not available.
 */
function getCurrentPath(): string {
  try {
    // In Server Components, we can't reliably get the current path
    // Redirect to root and let the app router handle it
    return "/";
  } catch {
    return "/";
  }
}

/**
 * Reset the refresh attempt flag.
 * Call this at the start of new requests to ensure clean state.
 *
 * Note: This is automatically reset on successful refresh or sign-out.
 * Only call manually if you need to force-reset state in edge cases.
 */
export function resetRefreshFlag(): void {
  refreshAttempted = false;
}
