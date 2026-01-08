/**
 * Admin Impersonation Start Endpoint
 *
 * Allows admins to impersonate non-admin users for support and debugging.
 * Uses Supabase Admin API to mint a session for the target user that
 * bypasses MFA requirements.
 *
 * Security:
 * - Admin-only access
 * - Rate limited (10 per hour per admin)
 * - Single active impersonation per admin
 * - No nested impersonation
 * - Cannot impersonate self or other admins
 * - Audit trail in database
 */

import { NextRequest, NextResponse } from "next/server";
import { createServerClient } from "@supabase/ssr";
import { createSupabaseServiceClient } from "@/lib/supabase/service";
import {
  createImpersonationSession,
  endImpersonationSession,
  setImpersonationCookie,
  readImpersonationContextFromRequest,
  checkRateLimit,
  recordAttempt,
  validateTargetUser,
  getActiveSessionForAdmin,
  getImpersonationSession,
} from "@/lib/auth/impersonation";
import { ENV } from "@/lib/env";
import { invalidateUserCache } from "@/data-access/cache";

interface StartImpersonationRequest {
  targetUserId: string;
  reason: string;
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

    const { data: { user: caller }, error: authError } = await supabase.auth.getUser();

    if (authError || !caller) {
      return NextResponse.json(
        { ok: false, error: "Authentication required" },
        { status: 401 }
      );
    }

    // 3. Verify caller is an admin
    const callerIsAdmin = caller.app_metadata?.role === "admin";
    if (!callerIsAdmin) {
      return NextResponse.json(
        { ok: false, error: "Admin access required" },
        { status: 403 }
      );
    }

    // 4. Parse and validate request body
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

    if (!targetUserId || typeof targetUserId !== "string") {
      return NextResponse.json(
        { ok: false, error: "targetUserId is required" },
        { status: 400 }
      );
    }

    if (!reason || typeof reason !== "string" || reason.trim().length < 5) {
      return NextResponse.json(
        { ok: false, error: "reason is required (minimum 5 characters)" },
        { status: 400 }
      );
    }

    // Validate UUID format
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!uuidRegex.test(targetUserId)) {
      return NextResponse.json(
        { ok: false, error: "Invalid targetUserId format" },
        { status: 400 }
      );
    }

    // 5. Cannot impersonate self
    if (targetUserId === caller.id) {
      return NextResponse.json(
        { ok: false, error: "Cannot impersonate yourself" },
        { status: 400 }
      );
    }

    // 6. Check rate limit
    const withinRateLimit = await checkRateLimit(caller.id);
    if (!withinRateLimit) {
      await recordAttempt(caller.id, false);
      return NextResponse.json(
        { ok: false, error: "Rate limit exceeded. Maximum 10 impersonation attempts per hour." },
        { status: 429 }
      );
    }

    // 7. Auto-end any existing active impersonation session
    // This handles cases where the admin closed the browser without stopping
    const activeSession = await getActiveSessionForAdmin(caller.id);
    if (activeSession) {
      console.log("[Impersonation] Auto-ending previous session:", activeSession.id);
      await endImpersonationSession(activeSession.id, caller.id);
    }

    // 8. Validate target user exists and is not an admin
    const targetValidation = await validateTargetUser(targetUserId);
    if (!targetValidation.exists) {
      await recordAttempt(caller.id, false);
      return NextResponse.json(
        { ok: false, error: "Target user not found" },
        { status: 404 }
      );
    }

    if (targetValidation.isAdmin) {
      await recordAttempt(caller.id, false);
      return NextResponse.json(
        { ok: false, error: "Cannot impersonate admin users" },
        { status: 403 }
      );
    }

    // 9. Get the caller's current session (we need the refresh token)
    const { data: sessionData } = await supabase.auth.getSession();
    const adminRefreshToken = sessionData?.session?.refresh_token;

    if (!adminRefreshToken) {
      return NextResponse.json(
        { ok: false, error: "Could not retrieve current session. Please re-authenticate." },
        { status: 401 }
      );
    }

    // 10. Mint a session for the target user using Admin API
    // This bypasses MFA by using the admin generateLink and verifyOtp flow
    const serviceClient = createSupabaseServiceClient();

    // Generate a magic link for the target user (server-side only)
    const { data: linkData, error: linkError } = await serviceClient.auth.admin.generateLink({
      type: "magiclink",
      email: targetValidation.email!,
      options: {
        // Don't send the email, we just want the token
        redirectTo: `${ENV.URL}/dashboard`,
      },
    });

    if (linkError || !linkData?.properties?.hashed_token) {
      console.error("[Impersonation] Failed to generate link:", linkError);
      await recordAttempt(caller.id, false);
      return NextResponse.json(
        { ok: false, error: "Failed to create impersonation session" },
        { status: 500 }
      );
    }

    // Verify the token to create a session (this bypasses MFA)
    const { data: verifyData, error: verifyError } = await serviceClient.auth.verifyOtp({
      token_hash: linkData.properties.hashed_token,
      type: "magiclink",
    });

    if (verifyError || !verifyData.session) {
      console.error("[Impersonation] Failed to verify OTP:", verifyError);
      await recordAttempt(caller.id, false);
      return NextResponse.json(
        { ok: false, error: "Failed to create impersonation session" },
        { status: 500 }
      );
    }

    // 11. Create impersonation session record in database
    const adminIp = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
      request.headers.get("x-real-ip") ||
      null;
    const adminUserAgent = request.headers.get("user-agent") || null;

    let dbSession: { id: string; expiresAt: Date };
    try {
      dbSession = await createImpersonationSession({
        adminUserId: caller.id,
        targetUserId,
        reason: reason.trim(),
        adminRefreshToken,
        adminIp,
        adminUserAgent,
      });
    } catch (error) {
      console.error("[Impersonation] Failed to create session record:", error);
      // Try to clean up the minted session
      await serviceClient.auth.admin.signOut(verifyData.session.access_token).catch(() => {});
      await recordAttempt(caller.id, false);

      const errorMessage = error instanceof Error ? error.message : "Failed to create session record";
      return NextResponse.json(
        { ok: false, error: errorMessage },
        { status: 500 }
      );
    }

    // 12. Set the target user's session in the browser cookies
    // Create a new Supabase client that writes to the response cookies
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

    // Set the session (this writes the cookies)
    const { error: setSessionError } = await targetSupabase.auth.setSession({
      access_token: verifyData.session.access_token,
      refresh_token: verifyData.session.refresh_token,
    });

    if (setSessionError) {
      console.error("[Impersonation] Failed to set session:", setSessionError);
      // Clean up
      await serviceClient.auth.admin.signOut(verifyData.session.access_token).catch(() => {});
      await recordAttempt(caller.id, false);
      return NextResponse.json(
        { ok: false, error: "Failed to set impersonation session" },
        { status: 500 }
      );
    }

    // 13. Set the impersonation context cookie
    setImpersonationCookie(response, {
      impersonationSessionId: dbSession.id,
      adminUserId: caller.id,
      targetUserId,
      expiresAt: dbSession.expiresAt,
    }, request);

    // 14. Record successful attempt
    await recordAttempt(caller.id, true);

    // 15. Invalidate caches for both admin and target user
    // This ensures fresh data is loaded after session switch
    invalidateUserCache(caller.id);
    invalidateUserCache(targetUserId);

    console.log("[Impersonation] Started:", {
      adminId: caller.id,
      targetId: targetUserId,
      sessionId: dbSession.id,
      expiresAt: dbSession.expiresAt.toISOString(),
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
