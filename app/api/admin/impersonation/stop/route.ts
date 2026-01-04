/**
 * Admin Impersonation Stop Endpoint
 *
 * Allows admins to stop impersonating and restore their original session.
 * Decrypts the stored admin refresh token and restores the admin's session.
 *
 * Security:
 * - Verifies impersonation context cookie
 * - Validates session in database
 * - Clears impersonation state on success or failure
 */

import { NextRequest, NextResponse } from "next/server";
import { createServerClient } from "@supabase/ssr";
import {
  readImpersonationContextFromRequest,
  clearImpersonationCookie,
  getImpersonationSession,
  endImpersonationSession,
  decryptAdminRefreshToken,
} from "@/lib/auth/impersonation";
import { ENV } from "@/lib/env";
import { invalidateUserCache } from "@/data-access/cache";

export async function POST(request: NextRequest) {
  // Create response object
  const response = NextResponse.json({ ok: true });

  try {
    // 1. Read and verify impersonation context cookie
    const context = readImpersonationContextFromRequest(request);

    if (!context) {
      // No valid impersonation context - nothing to stop
      // Still clear the cookie in case it's malformed
      clearImpersonationCookie(response, request);
      return NextResponse.json(
        { ok: false, error: "No active impersonation session" },
        { status: 400 }
      );
    }

    // 2. Load impersonation session from database
    let dbSession;
    try {
      dbSession = await getImpersonationSession(context.impersonationSessionId);
    } catch (error) {
      console.error("[Impersonation Stop] Failed to load session:", error);
      // Clear cookie and fail gracefully
      clearImpersonationCookie(response, request);
      return NextResponse.json(
        { ok: false, error: "Failed to load impersonation session", redirectHint: "/login" },
        { status: 500 }
      );
    }

    // 3. Validate session
    if (!dbSession) {
      console.warn("[Impersonation Stop] Session not found:", context.impersonationSessionId);
      clearImpersonationCookie(response, request);
      return NextResponse.json(
        { ok: false, error: "Impersonation session not found", redirectHint: "/login" },
        { status: 404 }
      );
    }

    if (dbSession.ended_at) {
      console.warn("[Impersonation Stop] Session already ended:", context.impersonationSessionId);
      clearImpersonationCookie(response, request);
      return NextResponse.json(
        { ok: false, error: "Impersonation session already ended", redirectHint: "/login" },
        { status: 400 }
      );
    }

    const now = new Date();
    const expiresAt = new Date(dbSession.expires_at);
    if (expiresAt <= now) {
      console.warn("[Impersonation Stop] Session expired:", context.impersonationSessionId);
      clearImpersonationCookie(response, request);
      // Mark as ended in DB
      await endImpersonationSession(dbSession.id, dbSession.admin_user_id).catch(() => {});
      return NextResponse.json(
        { ok: false, error: "Impersonation session expired", redirectHint: "/login" },
        { status: 400 }
      );
    }

    // Verify admin user ID matches
    if (dbSession.admin_user_id !== context.adminUserId) {
      console.error("[Impersonation Stop] Admin ID mismatch:", {
        cookie: context.adminUserId,
        db: dbSession.admin_user_id,
      });
      clearImpersonationCookie(response, request);
      return NextResponse.json(
        { ok: false, error: "Session validation failed", redirectHint: "/login" },
        { status: 400 }
      );
    }

    // 4. Decrypt the admin refresh token
    let adminRefreshToken: string;
    try {
      adminRefreshToken = decryptAdminRefreshToken(dbSession);
    } catch (error) {
      console.error("[Impersonation Stop] Failed to decrypt refresh token:", error);
      clearImpersonationCookie(response, request);
      // Mark session as ended even though restoration failed
      await endImpersonationSession(dbSession.id, dbSession.admin_user_id).catch(() => {});
      return NextResponse.json(
        { ok: false, error: "Failed to restore admin session", redirectHint: "/login" },
        { status: 500 }
      );
    }

    // 5. Create Supabase client and refresh the admin session
    const supabase = createServerClient(ENV.URL!, ENV.PUBLISHABLE!, {
      cookies: {
        getAll() {
          return request.cookies.getAll().map(({ name, value }) => ({ name, value }));
        },
        setAll(cookiesToSet) {
          for (const { name, value, options } of cookiesToSet) {
            response.cookies.set(name, value, options);
          }
        },
      },
    });

    // Refresh the session using the stored admin refresh token
    const { data: refreshData, error: refreshError } = await supabase.auth.refreshSession({
      refresh_token: adminRefreshToken,
    });

    if (refreshError || !refreshData.session) {
      console.error("[Impersonation Stop] Failed to refresh admin session:", refreshError);
      clearImpersonationCookie(response, request);
      // Mark session as ended
      await endImpersonationSession(dbSession.id, dbSession.admin_user_id).catch(() => {});

      // If refresh fails, we need to sign out and redirect to login
      // Try to clear the current (impersonated) session
      await supabase.auth.signOut().catch(() => {});

      return NextResponse.json(
        { ok: false, error: "Admin session expired. Please log in again.", redirectHint: "/login" },
        { status: 401 }
      );
    }

    // Set the restored admin session
    const { error: setSessionError } = await supabase.auth.setSession({
      access_token: refreshData.session.access_token,
      refresh_token: refreshData.session.refresh_token,
    });

    if (setSessionError) {
      console.error("[Impersonation Stop] Failed to set admin session:", setSessionError);
      clearImpersonationCookie(response, request);
      await endImpersonationSession(dbSession.id, dbSession.admin_user_id).catch(() => {});
      return NextResponse.json(
        { ok: false, error: "Failed to restore admin session", redirectHint: "/login" },
        { status: 500 }
      );
    }

    // 6. Clear impersonation context cookie
    clearImpersonationCookie(response, request);

    // 7. Update database to mark session as ended
    try {
      await endImpersonationSession(dbSession.id, dbSession.admin_user_id);
    } catch (error) {
      // Non-fatal - session is still effectively ended since cookie is cleared
      console.error("[Impersonation Stop] Failed to update session record:", error);
    }

    // 8. Invalidate caches for both admin and target user
    // This ensures fresh data is loaded after session restoration
    invalidateUserCache(dbSession.admin_user_id);
    invalidateUserCache(dbSession.target_user_id);

    console.log("[Impersonation Stop] Completed:", {
      adminId: dbSession.admin_user_id,
      targetId: dbSession.target_user_id,
      sessionId: dbSession.id,
    });

    return response;
  } catch (error) {
    console.error("[Impersonation Stop] Unexpected error:", error);

    // Always try to clear the cookie on error
    try {
      clearImpersonationCookie(response, request);
    } catch {
      // Best effort
    }

    return NextResponse.json(
      { ok: false, error: "An unexpected error occurred", redirectHint: "/login" },
      { status: 500 }
    );
  }
}
