/**
 * Supabase Edge Function: Admin Impersonation
 *
 * Provides a platform-agnostic backend primitive for admin impersonation.
 * Works for both Next.js (web) and iOS (native) clients.
 *
 * Endpoints:
 * - POST /start: Start impersonation, mint tokens for target user
 * - POST /stop: End impersonation session (for audit logging)
 *
 * Security:
 * - Authenticates admin via @supabase/server user auth
 * - Verifies admin role via app_metadata
 * - Rate limiting (10 per hour per admin)
 * - Prevents nested impersonation
 * - Audit logging in database
 *
 * Response format (iOS-compatible):
 * {
 *   "impersonated": {
 *     "access_token": "...",
 *     "refresh_token": "...",
 *     "expires_in": 3600,
 *     "token_type": "bearer",
 *     "user": { "id": "...", "email": "..." }
 *   },
 *   "session": {
 *     "id": "uuid",
 *     "expires_at": "ISO string"
 *   }
 * }
 */
import { withSupabase } from "@supabase/server";
import { createAdminClient } from "@supabase/server/core";
import type { User } from "@supabase/supabase-js";
import { Buffer } from "node:buffer";
import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";

// ---------- Environment ----------
// Site URL for redirects (the actual app URL, not Supabase project URL)
// Falls back to a placeholder since redirectTo is not actually used for impersonation
const SITE_URL = Deno.env.get("SITE_URL") ?? "https://tidex.app";
const SUPERADMIN_USER_ID = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";

// Encryption key (same as Next.js, must be synced)
const IMPERSONATION_ENC_KEY = Deno.env.get("IMPERSONATION_ENC_KEY") ?? "";

// ---------- Supabase Clients ----------
let supabaseAdmin: any = null;

function getSupabaseAdmin(): any {
  return supabaseAdmin;
}

function createRequestScopedAdminClient(): any {
  try {
    const createServerAdminClient = createAdminClient as unknown as () => any;
    return createServerAdminClient();
  } catch (error) {
    console.error(
      "[impersonation] Failed to create request-scoped admin client:",
      error,
    );
    return null;
  }
}

// ---------- Encryption Utilities ----------
const ALGORITHM = "aes-256-gcm";
const IV_LENGTH = 12;
const AUTH_TAG_LENGTH = 16;
const CURRENT_KEY_ID = "v1";

function getEncryptionKey(): Buffer {
  if (!IMPERSONATION_ENC_KEY) {
    throw new Error("Missing IMPERSONATION_ENC_KEY");
  }
  const key = Buffer.from(IMPERSONATION_ENC_KEY, "hex");
  if (key.length !== 32) {
    throw new Error("IMPERSONATION_ENC_KEY must be 64 hex characters");
  }
  return key;
}

function encryptAndSerialize(plaintext: string): string {
  const key = getEncryptionKey();
  const iv = randomBytes(IV_LENGTH);

  const cipher = createCipheriv(ALGORITHM, key, iv, {
    authTagLength: AUTH_TAG_LENGTH,
  });

  const encrypted = Buffer.concat([
    cipher.update(plaintext, "utf8"),
    cipher.final(),
  ]);

  const authTag = cipher.getAuthTag();

  // Format: ver:kid:iv:ciphertext:authTag (base64url)
  return `1:${CURRENT_KEY_ID}:${iv.toString("base64url")}:${
    encrypted.toString(
      "base64url",
    )
  }:${authTag.toString("base64url")}`;
}

function parseAndDecrypt(serialized: string): string {
  const parts = serialized.split(":");
  if (parts.length !== 5) {
    throw new Error("Invalid encrypted data format");
  }

  const [, kid, ivB64, ciphertextB64, authTagB64] = parts;

  if (kid !== CURRENT_KEY_ID) {
    throw new Error(`Unsupported key ID: ${kid}`);
  }

  const key = getEncryptionKey();
  const iv = Buffer.from(ivB64, "base64url");
  const ciphertext = Buffer.from(ciphertextB64, "base64url");
  const authTag = Buffer.from(authTagB64, "base64url");

  const decipher = createDecipheriv(ALGORITHM, key, iv, {
    authTagLength: AUTH_TAG_LENGTH,
  });

  decipher.setAuthTag(authTag);

  const decrypted = Buffer.concat([
    decipher.update(ciphertext),
    decipher.final(),
  ]);

  return decrypted.toString("utf8");
}

// ---------- Validation Utilities ----------
const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isValidUUID(str: string): boolean {
  return UUID_REGEX.test(str);
}

// ---------- Database Operations ----------
interface ImpersonationSession {
  id: string;
  admin_user_id: string;
  target_user_id: string;
  reason: string;
  created_at: string;
  expires_at: string;
  ended_at: string | null;
  ended_by_admin_user_id: string | null;
  admin_ip: string | null;
  admin_user_agent: string | null;
  admin_refresh_token_enc: string;
}

async function checkRateLimit(adminUserId: string): Promise<boolean> {
  if (!supabaseAdmin) return false;

  const { data, error } = await supabaseAdmin.rpc(
    "check_impersonation_rate_limit",
    {
      p_admin_user_id: adminUserId,
    },
  );

  if (error) {
    console.error("[impersonation] Rate limit check failed:", error);
    return true; // Fail open but log
  }

  return data === true;
}

async function recordAttempt(
  adminUserId: string,
  success: boolean,
): Promise<void> {
  if (!supabaseAdmin) return;

  const { error } = await supabaseAdmin.rpc("record_impersonation_attempt", {
    p_admin_user_id: adminUserId,
    p_success: success,
  });

  if (error) {
    console.error("[impersonation] Failed to record attempt:", error);
  }
}

async function isUserBeingImpersonated(userId: string): Promise<boolean> {
  if (!supabaseAdmin) return false;

  // Use RPC function to check if user is being impersonated (SECURITY DEFINER)
  const { data, error } = await supabaseAdmin.rpc(
    "is_user_being_impersonated",
    {
      p_user_id: userId,
    },
  );

  if (error) {
    console.error(
      "[impersonation] Failed to check if user is being impersonated:",
      error,
    );
    return false;
  }

  return data === true;
}

async function getActiveSessionForAdmin(
  adminUserId: string,
): Promise<ImpersonationSession | null> {
  if (!supabaseAdmin) return null;

  // Use RPC function to get active session (SECURITY DEFINER)
  const { data, error } = await supabaseAdmin.rpc(
    "get_active_impersonation_for_admin",
    {
      p_admin_user_id: adminUserId,
    },
  );

  if (error) {
    console.error("[impersonation] Failed to get active session:", error);
    return null;
  }

  // RPC returns array, get first row
  if (!data || (Array.isArray(data) && data.length === 0)) {
    return null;
  }

  return (Array.isArray(data) ? data[0] : data) as ImpersonationSession;
}

async function endImpersonationSession(
  sessionId: string,
  endedByUserId: string,
): Promise<void> {
  if (!supabaseAdmin) return;

  // Use RPC function to end session (SECURITY DEFINER)
  // Note: The column is named ended_by_admin_user_id but we store the actual caller's ID
  // This could be the admin OR the impersonated user (target) who ended the session
  const { data, error } = await supabaseAdmin.rpc(
    "mark_impersonation_session_ended",
    {
      p_session_id: sessionId,
      p_ended_by_user_id: endedByUserId,
    },
  );

  if (error) {
    console.error("[impersonation] Failed to end session:", error);
  } else if (!data) {
    console.log(
      "[impersonation] Session was already ended or not found:",
      sessionId,
    );
  }
}

async function createImpersonationSession(params: {
  adminUserId: string;
  targetUserId: string;
  reason: string;
  adminRefreshToken?: string;
  adminIp: string | null;
  adminUserAgent: string | null;
  adminEmail?: string | null;
  targetEmail?: string | null;
}): Promise<{ id: string; expiresAt: Date }> {
  if (!supabaseAdmin) {
    throw new Error("Database not configured");
  }

  // Only encrypt and store admin refresh token if provided (web flow)
  // iOS flow doesn't send this - they store admin session locally in Keychain
  const encryptedToken =
    params.adminRefreshToken && params.adminRefreshToken.length > 0
      ? encryptAndSerialize(params.adminRefreshToken)
      : "";

  // Use RPC function to create session (SECURITY DEFINER)
  // The RPC function handles session creation, audit logging, and rate limit recording
  // Returns table with (session_id, expires_at) to avoid clock skew issues
  const { data, error } = await supabaseAdmin.rpc(
    "create_impersonation_session",
    {
      p_admin_user_id: params.adminUserId,
      p_target_user_id: params.targetUserId,
      p_admin_refresh_token_enc: encryptedToken,
      p_reason: params.reason,
      p_admin_ip: params.adminIp,
      p_admin_user_agent: params.adminUserAgent,
      p_admin_email: params.adminEmail,
      p_target_email: params.targetEmail,
    },
  );

  if (error) {
    if (error.code === "23505") {
      throw new Error("An active impersonation session already exists");
    }
    throw new Error(`Failed to create session: ${error.message}`);
  }

  // RPC returns a table row with session_id and expires_at
  // Handle both array format (from some Supabase clients) and single object
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || !row.session_id) {
    throw new Error("Failed to create session: no session ID returned");
  }

  // Use the database-calculated expires_at to avoid clock skew
  const expiresAt = new Date(row.expires_at);

  return { id: row.session_id, expiresAt };
}

async function getImpersonationSession(
  sessionId: string,
): Promise<ImpersonationSession | null> {
  if (!supabaseAdmin) return null;

  // Use RPC function to get session (SECURITY DEFINER)
  const { data, error } = await supabaseAdmin.rpc(
    "get_impersonation_session_full",
    {
      p_session_id: sessionId,
    },
  );

  if (error) {
    console.error("[impersonation] Failed to get session:", error);
    return null;
  }

  // RPC returns array, get first row
  if (!data || (Array.isArray(data) && data.length === 0)) {
    return null;
  }

  return (Array.isArray(data) ? data[0] : data) as ImpersonationSession;
}

async function validateTargetUser(targetUserId: string): Promise<{
  exists: boolean;
  isAdmin: boolean;
  email: string | null;
  displayName: string | null;
}> {
  if (!supabaseAdmin) {
    return { exists: false, isAdmin: false, email: null, displayName: null };
  }

  const { data, error } = await supabaseAdmin.auth.admin.getUserById(
    targetUserId,
  );

  if (error || !data.user) {
    return { exists: false, isAdmin: false, email: null, displayName: null };
  }

  const user = data.user;
  const isAdmin = user.app_metadata?.role === "admin";
  const displayName = user.user_metadata?.full_name ||
    user.user_metadata?.name || null;

  return {
    exists: true,
    isAdmin,
    email: user.email || null,
    displayName,
  };
}

async function insertAuditLog(params: {
  sessionId: string;
  adminUserId: string;
  targetUserId: string;
  action: "start" | "stop";
  reason?: string;
  adminIp?: string | null;
  adminUserAgent?: string | null;
  metadata?: Record<string, unknown>;
}): Promise<void> {
  if (!supabaseAdmin) return;

  // Use RPC function to insert audit log (SECURITY DEFINER)
  const { error } = await supabaseAdmin.rpc("insert_impersonation_audit_log", {
    p_session_id: params.sessionId,
    p_admin_user_id: params.adminUserId,
    p_target_user_id: params.targetUserId,
    p_action: params.action,
    p_reason: params.reason ?? null,
    p_admin_ip: params.adminIp ?? null,
    p_admin_user_agent: params.adminUserAgent ?? null,
    p_metadata: params.metadata ? JSON.stringify(params.metadata) : null,
  });

  if (error) {
    console.error("[impersonation] Failed to insert audit log:", error);
    // Non-fatal
  }
}

// ---------- Request Handlers ----------
async function handleStart(req: Request, caller: User): Promise<Response> {
  // Initialize long-lived DB/RPC client (lazy initialization)
  const dbClient = getSupabaseAdmin();
  if (!dbClient) {
    return json({ ok: false, error: "Service not configured" }, 503);
  }

  // Use a separate request-scoped client for auth flows that can mutate session
  // (e.g. verifyOtp), so DB RPCs always run as service_role.
  const authClient = createRequestScopedAdminClient();
  if (!authClient) {
    return json({ ok: false, error: "Service not configured" }, 503);
  }

  // 1. Verify caller is an admin
  const callerIsAdmin = caller.app_metadata?.role === "admin";
  if (!callerIsAdmin) {
    return json({ ok: false, error: "Admin access required" }, 403);
  }

  // 2. Check if caller is currently being impersonated (prevent nested impersonation)
  const isBeingImpersonated = await isUserBeingImpersonated(caller.id);
  if (isBeingImpersonated) {
    return json(
      { ok: false, error: "Nested impersonation is not allowed" },
      400,
    );
  }

  // 3. Parse and validate request body
  // Note: adminRefreshToken is NOT accepted here for security reasons.
  // The Next.js wrapper stores it server-side after this call returns.
  // iOS clients store admin session locally in Keychain.
  let body: { targetUserId: string; reason: string };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "Invalid JSON body" }, 400);
  }

  const { targetUserId, reason } = body;

  if (!targetUserId || typeof targetUserId !== "string") {
    return json({ ok: false, error: "targetUserId is required" }, 400);
  }

  if (!isValidUUID(targetUserId)) {
    return json({ ok: false, error: "Invalid targetUserId format" }, 400);
  }

  if (!reason || typeof reason !== "string" || reason.trim().length < 5) {
    return json(
      {
        ok: false,
        error: "reason is required (minimum 5 characters)",
      },
      400,
    );
  }

  // 4. Cannot impersonate self
  if (targetUserId === caller.id) {
    return json({ ok: false, error: "Cannot impersonate yourself" }, 400);
  }

  // 5. Check rate limit
  const withinRateLimit = await checkRateLimit(caller.id);
  if (!withinRateLimit) {
    await recordAttempt(caller.id, false);
    return json(
      {
        ok: false,
        error:
          "Rate limit exceeded. Maximum 10 impersonation attempts per hour.",
      },
      429,
    );
  }

  // 6. Auto-end any existing active impersonation session
  const activeSession = await getActiveSessionForAdmin(caller.id);
  if (activeSession) {
    console.log(
      "[impersonation] Auto-ending previous session:",
      activeSession.id,
    );
    await endImpersonationSession(activeSession.id, caller.id);
  }

  // 7. Validate target user exists and only superadmin can impersonate admins
  const targetValidation = await validateTargetUser(targetUserId);
  if (!targetValidation.exists) {
    await recordAttempt(caller.id, false);
    return json({ ok: false, error: "Target user not found" }, 404);
  }

  if (targetValidation.isAdmin && caller.id !== SUPERADMIN_USER_ID) {
    await recordAttempt(caller.id, false);
    return json({ ok: false, error: "Cannot impersonate admin users" }, 403);
  }

  // 8. Verify target user has an email (required for generateLink)
  if (!targetValidation.email) {
    await recordAttempt(caller.id, false);
    return json(
      {
        ok: false,
        error: "Target user does not have an email address",
      },
      400,
    );
  }

  // 9. Mint a session for the target user using Admin API
  // Generate a magic link (server-side only, email not sent)
  const { data: linkData, error: linkError } = await authClient.auth.admin
    .generateLink({
      type: "magiclink",
      email: targetValidation.email,
      options: {
        // Use the actual site URL, not the Supabase project URL
        // This must be in the allowed redirect URLs in Supabase Auth settings
        redirectTo: `${SITE_URL}/dashboard`,
      },
    });

  if (linkError || !linkData?.properties?.hashed_token) {
    console.error("[impersonation] Failed to generate link:", linkError);
    await recordAttempt(caller.id, false);
    return json(
      { ok: false, error: "Failed to create impersonation session" },
      500,
    );
  }

  // Verify the token to create a session (bypasses MFA)
  const { data: verifyData, error: verifyError } = await authClient.auth
    .verifyOtp({
      token_hash: linkData.properties.hashed_token,
      type: "magiclink",
    });

  if (verifyError || !verifyData.session) {
    console.error("[impersonation] Failed to verify OTP:", verifyError);
    await recordAttempt(caller.id, false);
    return json(
      { ok: false, error: "Failed to create impersonation session" },
      500,
    );
  }

  // 10. Create impersonation session record in database
  const adminIp = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    req.headers.get("x-real-ip") ||
    null;
  const adminUserAgent = req.headers.get("user-agent") || null;

  // Note: adminRefreshToken is NOT stored here - the Next.js wrapper stores it
  // server-side after this call returns. iOS stores admin session in Keychain.
  // The RPC function handles session creation, audit logging, and rate limit recording.
  let dbSession: { id: string; expiresAt: Date };
  try {
    dbSession = await createImpersonationSession({
      adminUserId: caller.id,
      targetUserId,
      reason: reason.trim(),
      // adminRefreshToken intentionally omitted - stored by Next.js wrapper
      adminIp,
      adminUserAgent,
      adminEmail: caller.email,
      targetEmail: targetValidation.email,
    });
  } catch (error) {
    console.error("[impersonation] Failed to create session record:", error);
    // Clean up the minted session
    await authClient.auth.admin
      .signOut(verifyData.session.access_token)
      .catch(() => {});

    const errorMessage = error instanceof Error
      ? error.message
      : "Failed to create session record";
    return json({ ok: false, error: errorMessage }, 500);
  }

  // Note: Audit log and rate limit recording are now handled by the RPC function

  console.log("[impersonation] Started:", {
    adminId: caller.id,
    targetId: targetUserId,
    sessionId: dbSession.id,
    expiresAt: dbSession.expiresAt.toISOString(),
  });

  // 11. Return tokens in iOS-compatible format
  return json({
    ok: true,
    impersonated: {
      access_token: verifyData.session.access_token,
      refresh_token: verifyData.session.refresh_token,
      expires_in: verifyData.session.expires_in ?? 3600,
      token_type: "bearer",
      user: {
        id: verifyData.session.user.id,
        email: verifyData.session.user.email,
        user_metadata: verifyData.session.user.user_metadata,
      },
    },
    session: {
      id: dbSession.id,
      admin_user_id: caller.id,
      target_user_id: targetUserId,
      expires_at: dbSession.expiresAt.toISOString(),
    },
  });
}

async function handleStop(req: Request, caller: User): Promise<Response> {
  // Initialize Supabase client (lazy initialization)
  const adminClient = getSupabaseAdmin();
  if (!adminClient) {
    return json({ ok: false, error: "Service not configured" }, 503);
  }

  // 1. Parse request body
  let body: { sessionId: string };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "Invalid JSON body" }, 400);
  }

  const { sessionId } = body;

  if (!sessionId || !isValidUUID(sessionId)) {
    return json({ ok: false, error: "Valid sessionId is required" }, 400);
  }

  // 2. Load the session
  const dbSession = await getImpersonationSession(sessionId);
  if (!dbSession) {
    return json({ ok: false, error: "Session not found" }, 404);
  }

  // 3. Verify the caller is the admin who started the session
  // Note: caller could be the admin (using their restored session) or
  // the impersonated user (ending from their context)
  // We allow either the admin or the target user to end the session
  if (
    dbSession.admin_user_id !== caller.id &&
    dbSession.target_user_id !== caller.id
  ) {
    return json(
      { ok: false, error: "Not authorized to end this session" },
      403,
    );
  }

  // 4. Check if already ended
  if (dbSession.ended_at) {
    return json({ ok: false, error: "Session already ended" }, 400);
  }

  // 5. End the session - record the actual caller who ended it (admin or target user)
  await endImpersonationSession(sessionId, caller.id);

  // 6. Insert audit log
  const adminIp = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    req.headers.get("x-real-ip") ||
    null;
  const adminUserAgent = req.headers.get("user-agent") || null;

  await insertAuditLog({
    sessionId,
    adminUserId: dbSession.admin_user_id,
    targetUserId: dbSession.target_user_id,
    action: "stop",
    adminIp,
    adminUserAgent,
    metadata: {
      ended_by_user_id: caller.id,
      ended_by_type: caller.id === dbSession.admin_user_id
        ? "admin"
        : "impersonated_user",
    },
  });

  console.log("[impersonation] Stopped:", {
    adminId: dbSession.admin_user_id,
    targetId: dbSession.target_user_id,
    sessionId,
    endedBy: caller.id,
  });

  // 7. Return admin refresh token only to the original admin context.
  let adminRefreshToken: string | null = null;
  if (
    caller.id === dbSession.admin_user_id &&
    dbSession.admin_refresh_token_enc &&
    dbSession.admin_refresh_token_enc.length > 0
  ) {
    try {
      adminRefreshToken = parseAndDecrypt(dbSession.admin_refresh_token_enc);
    } catch (error) {
      console.error(
        "[impersonation] Failed to decrypt admin refresh token:",
        error,
      );
      // Non-fatal - iOS doesn't need this
    }
  }

  return json({
    ok: true,
    session: {
      id: sessionId,
      ended_at: new Date().toISOString(),
    },
    // Only include if we have a stored token (web flow)
    ...(adminRefreshToken ? { admin_refresh_token: adminRefreshToken } : {}),
  });
}

// ---------- Main Handler ----------
export default {
  fetch: withSupabase<any>(
    { auth: "user" },
    async (req, ctx) => {
      console.log("[impersonation] Request received:", req.method, req.url);
      supabaseAdmin = ctx.supabaseAdmin;

      try {
        if (req.method !== "POST") {
          return json({ ok: false, error: "Method not allowed" }, 405);
        }

        const {
          data: { user: caller },
          error: authError,
        } = await ctx.supabase.auth.getUser();
        if (authError || !caller) {
          return json({ ok: false, error: "Invalid or expired token" }, 401);
        }

        // Parse action from URL path
        const url = new URL(req.url);
        const pathParts = url.pathname.split("/").filter(Boolean);
        const action = pathParts[pathParts.length - 1]; // Last segment: "start" or "stop"

        switch (action) {
          case "start":
            return await handleStart(req, caller);
          case "stop":
            return await handleStop(req, caller);
          default:
            // If no action specified, try parsing from body
            // This supports calling just /impersonation with { action: "start", ... }
            try {
              const body = await req.clone().json();
              if (body.action === "start") {
                return await handleStart(req, caller);
              } else if (body.action === "stop") {
                return await handleStop(req, caller);
              }
            } catch {
              // Ignore parse errors
            }
            return json(
              { ok: false, error: "Invalid action. Use /start or /stop" },
              400,
            );
        }
      } catch (error) {
        console.error("[impersonation] Unexpected error:", error);
        return json({ ok: false, error: "Internal server error" }, 500);
      }
    },
  ),
};

// ---------- Response Helpers ----------
function json(obj: Record<string, unknown>, status = 200): Response {
  return Response.json(obj, { status });
}
