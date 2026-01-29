/**
 * Admin Impersonation Stop Endpoint (Web Wrapper)
 *
 * This route is the web-specific wrapper that:
 * 1. Calls the shared Supabase Edge Function to end the impersonation session
 * 2. Restores admin session using the decrypted refresh token
 * 3. Clears the impersonation context cookie
 *
 * For iOS/native clients, call the Edge Function directly:
 * POST /functions/v1/impersonation/stop
 *
 * Security:
 * - Verifies impersonation context cookie
 * - Validates session in database (via Edge Function)
 * - Clears impersonation state on success or failure
 */

import { NextRequest, NextResponse } from "next/server";
import { createServerClient } from "@supabase/ssr";
import {
  readImpersonationContextFromRequest,
  clearImpersonationCookie,
} from "@/lib/auth/impersonation";
import { ENV } from "@/lib/env";
import { invalidateUserCache } from "@/data-access/cache";

interface EdgeFunctionStopResponse {
  ok: boolean;
  error?: string;
  session?: {
    id: string;
    ended_at: string;
  };
  admin_refresh_token?: string;
}

export async function POST(request: NextRequest) {
  // Create response object
  const response = NextResponse.json({ ok: true });

  try {
    // 1. Read impersonation context cookie
    const context = readImpersonationContextFromRequest(request);

    if (!context) {
      // No valid impersonation context - nothing to stop
      clearImpersonationCookie(response, request);
      return NextResponse.json(
        { ok: false, error: "No active impersonation session" },
        { status: 400 }
      );
    }

    // 2. Get current session (the impersonated user's session)
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

    const { data: { session: currentSession } } = await supabase.auth.getSession();

    // 3. Call the Edge Function to end the session and get admin refresh token
    const edgeFunctionUrl = `${ENV.URL}/functions/v1/impersonation/stop`;

    const edgeResponse = await fetch(edgeFunctionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        // Use the impersonated user's token - Edge Function allows target user to end session
        Authorization: `Bearer ${currentSession?.access_token || ""}`,
        "x-forwarded-for": request.headers.get("x-forwarded-for") || "",
        "x-real-ip": request.headers.get("x-real-ip") || "",
        "user-agent": request.headers.get("user-agent") || "",
      },
      body: JSON.stringify({
        sessionId: context.impersonationSessionId,
      }),
    });

    const edgeResult: EdgeFunctionStopResponse = await edgeResponse.json();

    // 4. Handle Edge Function errors
    if (!edgeResult.ok) {
      console.error("[Impersonation Stop] Edge Function error:", edgeResult.error);
      clearImpersonationCookie(response, request);
      return NextResponse.json(
        { ok: false, error: edgeResult.error || "Failed to end impersonation", redirectHint: "/login" },
        { status: edgeResponse.status }
      );
    }

    // 5. Restore admin session using the decrypted refresh token
    if (!edgeResult.admin_refresh_token) {
      console.error("[Impersonation Stop] No admin refresh token returned");
      clearImpersonationCookie(response, request);
      // Sign out the impersonated session
      await supabase.auth.signOut().catch(() => {});
      return NextResponse.json(
        { ok: false, error: "Admin session could not be restored. Please log in again.", redirectHint: "/login" },
        { status: 401 }
      );
    }

    // Refresh the admin session
    const { data: refreshData, error: refreshError } = await supabase.auth.refreshSession({
      refresh_token: edgeResult.admin_refresh_token,
    });

    if (refreshError || !refreshData.session) {
      console.error("[Impersonation Stop] Failed to refresh admin session:", refreshError);
      clearImpersonationCookie(response, request);
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
      return NextResponse.json(
        { ok: false, error: "Failed to restore admin session", redirectHint: "/login" },
        { status: 500 }
      );
    }

    // 6. Clear impersonation context cookie
    clearImpersonationCookie(response, request);

    // 7. Invalidate caches for both admin and target user
    invalidateUserCache(context.adminUserId);
    invalidateUserCache(context.targetUserId);

    console.log("[Impersonation Stop] Completed via Edge Function:", {
      adminId: context.adminUserId,
      targetId: context.targetUserId,
      sessionId: context.impersonationSessionId,
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
