/**
 * Admin Impersonation Start Endpoint (Web Wrapper)
 *
 * This route is the web-specific wrapper that:
 * 1. Calls the shared Supabase Edge Function to mint impersonated tokens
 * 2. Sets session cookies for the web browser
 * 3. Sets the impersonation context cookie for tracking
 *
 * For iOS/native clients, call the Edge Function directly:
 * POST /functions/v1/impersonation/start
 *
 * Security:
 * - Admin-only access (enforced by Edge Function)
 * - Rate limited (10 per hour per admin)
 * - Single active impersonation per admin
 * - No nested impersonation
 * - Cannot impersonate self or other admins
 * - Audit trail in database
 */

import { NextRequest, NextResponse } from "next/server";
import { createServerClient } from "@supabase/ssr";
import {
  setImpersonationCookie,
  readImpersonationContextFromRequest,
  getImpersonationSession,
} from "@/lib/auth/impersonation";
import { ENV } from "@/lib/env";
import { invalidateUserCache } from "@/data-access/cache";

interface StartImpersonationRequest {
  targetUserId: string;
  reason: string;
}

interface EdgeFunctionResponse {
  ok: boolean;
  error?: string;
  impersonated?: {
    access_token: string;
    refresh_token: string;
    expires_in: number;
    token_type: string;
    user: {
      id: string;
      email?: string;
      user_metadata?: Record<string, unknown>;
    };
  };
  session?: {
    id: string;
    admin_user_id: string;
    target_user_id: string;
    expires_at: string;
  };
}

export async function POST(request: NextRequest) {
  // Create response object for cookie setting
  const response = NextResponse.json({ ok: true });

  try {
    // 1. Check if already impersonating (no nested impersonation)
    // We also validate against the database to handle stale cookies
    const existingContext = readImpersonationContextFromRequest(request);
    if (existingContext) {
      // Verify the session is still active in the database
      const existingSession = await getImpersonationSession(existingContext.impersonationSessionId);
      const now = new Date();

      if (
        existingSession &&
        existingSession.ended_at === null &&
        new Date(existingSession.expires_at) > now
      ) {
        // Session is truly active - block nested impersonation
        return NextResponse.json(
          { ok: false, error: "Nested impersonation is not allowed. Stop current impersonation first." },
          { status: 400 }
        );
      }
      // Session is invalid/expired - we'll clear the stale cookie later in the response
    }

    // 2. Authenticate the caller using Supabase SSR
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

    const { data: { session: adminSession }, error: sessionError } = await supabase.auth.getSession();

    if (sessionError || !adminSession) {
      return NextResponse.json(
        { ok: false, error: "Authentication required" },
        { status: 401 }
      );
    }

    // 3. Parse request body
    let body: StartImpersonationRequest;
    try {
      body = await request.json();
    } catch {
      return NextResponse.json(
        { ok: false, error: "Invalid JSON body" },
        { status: 400 }
      );
    }

    const { targetUserId, reason } = body;

    // 4. Call the Edge Function
    // The Edge Function handles all validation, rate limiting, and token minting
    const edgeFunctionUrl = `${ENV.URL}/functions/v1/impersonation/start`;

    const edgeResponse = await fetch(edgeFunctionUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${adminSession.access_token}`,
        "x-forwarded-for": request.headers.get("x-forwarded-for") || "",
        "x-real-ip": request.headers.get("x-real-ip") || "",
        "user-agent": request.headers.get("user-agent") || "",
      },
      body: JSON.stringify({
        targetUserId,
        reason,
        // Send admin refresh token for server-side storage (web flow)
        adminRefreshToken: adminSession.refresh_token,
      }),
    });

    const edgeResult: EdgeFunctionResponse = await edgeResponse.json();

    // 5. Handle Edge Function errors
    if (!edgeResult.ok || !edgeResult.impersonated || !edgeResult.session) {
      return NextResponse.json(
        { ok: false, error: edgeResult.error || "Failed to start impersonation" },
        { status: edgeResponse.status }
      );
    }

    // 6. Set the target user's session in the browser cookies
    const targetSupabase = createServerClient(ENV.URL!, ENV.PUBLISHABLE!, {
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

    const { error: setSessionError } = await targetSupabase.auth.setSession({
      access_token: edgeResult.impersonated.access_token,
      refresh_token: edgeResult.impersonated.refresh_token,
    });

    if (setSessionError) {
      console.error("[Impersonation] Failed to set session:", setSessionError);
      return NextResponse.json(
        { ok: false, error: "Failed to set impersonation session" },
        { status: 500 }
      );
    }

    // 7. Set the impersonation context cookie
    setImpersonationCookie(response, {
      impersonationSessionId: edgeResult.session.id,
      adminUserId: edgeResult.session.admin_user_id,
      targetUserId: edgeResult.session.target_user_id,
      expiresAt: new Date(edgeResult.session.expires_at),
    }, request);

    // 8. Invalidate caches for both admin and target user
    invalidateUserCache(edgeResult.session.admin_user_id);
    invalidateUserCache(edgeResult.session.target_user_id);

    console.log("[Impersonation] Started via Edge Function:", {
      adminId: edgeResult.session.admin_user_id,
      targetId: edgeResult.session.target_user_id,
      sessionId: edgeResult.session.id,
      expiresAt: edgeResult.session.expires_at,
    });

    return response;
  } catch (error) {
    console.error("[Impersonation] Unexpected error:", error);
    return NextResponse.json(
      { ok: false, error: "An unexpected error occurred" },
      { status: 500 }
    );
  }
}
