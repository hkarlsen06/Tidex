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
 * - Authenticates admin via Bearer token (admin's JWT)
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
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { corsHeaders } from "../_shared/cors.ts";
import {
  createCipheriv,
  createDecipheriv,
  randomBytes,
} from "node:crypto";

// ---------- Environment ----------
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// Encryption keys (same as Next.js, must be synced)
const IMPERSONATION_ENC_KEY = Deno.env.get("IMPERSONATION_ENC_KEY") ?? "";
const IMPERSONATION_SIGNING_KEY = Deno.env.get("IMPERSONATION_SIGNING_KEY") ?? "";

// Session configuration
const DEFAULT_SESSION_DURATION_MS = 30 * 60 * 1000; // 30 minutes
const MAX_SESSION_DURATION_MS = 60 * 60 * 1000; // 1 hour

// ---------- Supabase Clients ----------
const supabaseAdmin = SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY
  ? createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false },
    })
  : null;

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
  return `1:${CURRENT_KEY_ID}:${iv.toString("base64url")}:${encrypted.toString("base64url")}:${authTag.toString("base64url")}`;
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
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

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

  const { data, error } = await supabaseAdmin.rpc("check_impersonation_rate_limit", {
    p_admin_user_id: adminUserId,
  });

  if (error) {
    console.error("[impersonation] Rate limit check failed:", error);
    return true; // Fail open but log
  }

  return data === true;
}

async function recordAttempt(adminUserId: string, success: boolean): Promise<void> {
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

  // Check if this user is currently the target of an active impersonation session
  const now = new Date().toISOString();
  const { data } = await supabaseAdmin
    .schema("internal")
    .from("impersonation_sessions")
    .select("id")
    .eq("target_user_id", userId)
    .is("ended_at", null)
    .gt("expires_at", now)
    .limit(1)
    .maybeSingle();

  return data !== null;
}

async function getActiveSessionForAdmin(adminUserId: string): Promise<ImpersonationSession | null> {
  if (!supabaseAdmin) return null;

  const { data, error } = await supabaseAdmin
    .schema("internal")
    .from("impersonation_sessions")
    .select("*")
    .eq("admin_user_id", adminUserId)
    .is("ended_at", null)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    console.error("[impersonation] Failed to get active session:", error);
    return null;
  }

  return data;
}

async function endImpersonationSession(sessionId: string, endedByAdminUserId: string): Promise<void> {
  if (!supabaseAdmin) return;

  const { error } = await supabaseAdmin
    .schema("internal")
    .from("impersonation_sessions")
    .update({
      ended_at: new Date().toISOString(),
      ended_by_admin_user_id: endedByAdminUserId,
    })
    .eq("id", sessionId)
    .is("ended_at", null);

  if (error) {
    console.error("[impersonation] Failed to end session:", error);
  }
}

async function createImpersonationSession(params: {
  adminUserId: string;
  targetUserId: string;
  reason: string;
  adminRefreshToken: string;
  adminIp: string | null;
  adminUserAgent: string | null;
  durationMs?: number;
}): Promise<{ id: string; expiresAt: Date }> {
  if (!supabaseAdmin) {
    throw new Error("Database not configured");
  }

  const now = new Date();
  const durationMs = Math.min(
    params.durationMs ?? DEFAULT_SESSION_DURATION_MS,
    MAX_SESSION_DURATION_MS
  );
  const expiresAt = new Date(now.getTime() + durationMs);

  // Encrypt the admin refresh token
  const encryptedToken = encryptAndSerialize(params.adminRefreshToken);

  const { data, error } = await supabaseAdmin
    .schema("internal")
    .from("impersonation_sessions")
    .insert({
      admin_user_id: params.adminUserId,
      target_user_id: params.targetUserId,
      reason: params.reason,
      expires_at: expiresAt.toISOString(),
      admin_ip: params.adminIp,
      admin_user_agent: params.adminUserAgent,
      admin_refresh_token_enc: encryptedToken,
    })
    .select("id")
    .single();

  if (error) {
    if (error.code === "23505") {
      throw new Error("An active impersonation session already exists");
    }
    throw new Error(`Failed to create session: ${error.message}`);
  }

  return { id: data.id, expiresAt };
}

async function getImpersonationSession(sessionId: string): Promise<ImpersonationSession | null> {
  if (!supabaseAdmin) return null;

  const { data, error } = await supabaseAdmin
    .schema("internal")
    .from("impersonation_sessions")
    .select("*")
    .eq("id", sessionId)
    .single();

  if (error) {
    if (error.code === "PGRST116") return null;
    console.error("[impersonation] Failed to get session:", error);
    return null;
  }

  return data;
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

  const { data, error } = await supabaseAdmin.auth.admin.getUserById(targetUserId);

  if (error || !data.user) {
    return { exists: false, isAdmin: false, email: null, displayName: null };
  }

  const user = data.user;
  const isAdmin = user.app_metadata?.role === "admin";
  const displayName = user.user_metadata?.full_name || user.user_metadata?.name || null;

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

  const { error } = await supabaseAdmin
    .schema("internal")
    .from("impersonation_audit_log")
    .insert({
      session_id: params.sessionId,
      admin_user_id: params.adminUserId,
      target_user_id: params.targetUserId,
      action: params.action,
      reason: params.reason,
      admin_ip: params.adminIp,
      admin_user_agent: params.adminUserAgent,
      metadata: params.metadata,
    });

  if (error) {
    console.error("[impersonation] Failed to insert audit log:", error);
    // Non-fatal
  }
}

// ---------- Request Handlers ----------
async function handleStart(req: Request): Promise<Response> {
  if (!supabaseAdmin) {
    return json({ ok: false, error: "Service not configured" }, 503);
  }

  // 1. Authenticate the admin caller
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return json({ ok: false, error: "Missing authorization header" }, 401);
  }

  const token = authHeader.replace("Bearer ", "");
  const { data: { user: caller }, error: authError } = await supabaseAdmin.auth.getUser(token);

  if (authError || !caller) {
    return json({ ok: false, error: "Invalid or expired token" }, 401);
  }

  // 2. Verify caller is an admin
  const callerIsAdmin = caller.app_metadata?.role === "admin";
  if (!callerIsAdmin) {
    return json({ ok: false, error: "Admin access required" }, 403);
  }

  // 3. Check if caller is currently being impersonated (prevent nested impersonation)
  const isBeingImpersonated = await isUserBeingImpersonated(caller.id);
  if (isBeingImpersonated) {
    return json({ ok: false, error: "Nested impersonation is not allowed" }, 400);
  }

  // 4. Parse and validate request body
  let body: { targetUserId: string; reason: string; adminRefreshToken?: string };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "Invalid JSON body" }, 400);
  }

  const { targetUserId, reason, adminRefreshToken } = body;

  if (!targetUserId || typeof targetUserId !== "string") {
    return json({ ok: false, error: "targetUserId is required" }, 400);
  }

  if (!isValidUUID(targetUserId)) {
    return json({ ok: false, error: "Invalid targetUserId format" }, 400);
  }

  if (!reason || typeof reason !== "string" || reason.trim().length < 5) {
    return json({ ok: false, error: "reason is required (minimum 5 characters)" }, 400);
  }

  // 5. Cannot impersonate self
  if (targetUserId === caller.id) {
    return json({ ok: false, error: "Cannot impersonate yourself" }, 400);
  }

  // 6. Check rate limit
  const withinRateLimit = await checkRateLimit(caller.id);
  if (!withinRateLimit) {
    await recordAttempt(caller.id, false);
    return json({ ok: false, error: "Rate limit exceeded. Maximum 10 impersonation attempts per hour." }, 429);
  }

  // 7. Auto-end any existing active impersonation session
  const activeSession = await getActiveSessionForAdmin(caller.id);
  if (activeSession) {
    console.log("[impersonation] Auto-ending previous session:", activeSession.id);
    await endImpersonationSession(activeSession.id, caller.id);
  }

  // 8. Validate target user exists and is not an admin
  const targetValidation = await validateTargetUser(targetUserId);
  if (!targetValidation.exists) {
    await recordAttempt(caller.id, false);
    return json({ ok: false, error: "Target user not found" }, 404);
  }

  if (targetValidation.isAdmin) {
    await recordAttempt(caller.id, false);
    return json({ ok: false, error: "Cannot impersonate admin users" }, 403);
  }

  // 9. Mint a session for the target user using Admin API
  // Generate a magic link (server-side only, email not sent)
  const { data: linkData, error: linkError } = await supabaseAdmin.auth.admin.generateLink({
    type: "magiclink",
    email: targetValidation.email!,
    options: {
      redirectTo: `${SUPABASE_URL}/dashboard`, // Not used, just required
    },
  });

  if (linkError || !linkData?.properties?.hashed_token) {
    console.error("[impersonation] Failed to generate link:", linkError);
    await recordAttempt(caller.id, false);
    return json({ ok: false, error: "Failed to create impersonation session" }, 500);
  }

  // Verify the token to create a session (bypasses MFA)
  const { data: verifyData, error: verifyError } = await supabaseAdmin.auth.verifyOtp({
    token_hash: linkData.properties.hashed_token,
    type: "magiclink",
  });

  if (verifyError || !verifyData.session) {
    console.error("[impersonation] Failed to verify OTP:", verifyError);
    await recordAttempt(caller.id, false);
    return json({ ok: false, error: "Failed to create impersonation session" }, 500);
  }

  // 10. Create impersonation session record in database
  const adminIp = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    req.headers.get("x-real-ip") ||
    null;
  const adminUserAgent = req.headers.get("user-agent") || null;

  // Note: adminRefreshToken is optional - iOS won't send it (stores locally in Keychain)
  // Web will send it for server-side storage
  const adminRefreshTokenToStore = adminRefreshToken || "";

  let dbSession: { id: string; expiresAt: Date };
  try {
    dbSession = await createImpersonationSession({
      adminUserId: caller.id,
      targetUserId,
      reason: reason.trim(),
      adminRefreshToken: adminRefreshTokenToStore,
      adminIp,
      adminUserAgent,
    });
  } catch (error) {
    console.error("[impersonation] Failed to create session record:", error);
    // Clean up the minted session
    await supabaseAdmin.auth.admin.signOut(verifyData.session.access_token).catch(() => {});
    await recordAttempt(caller.id, false);

    const errorMessage = error instanceof Error ? error.message : "Failed to create session record";
    return json({ ok: false, error: errorMessage }, 500);
  }

  // 11. Insert audit log
  await insertAuditLog({
    sessionId: dbSession.id,
    adminUserId: caller.id,
    targetUserId,
    action: "start",
    reason: reason.trim(),
    adminIp,
    adminUserAgent,
    metadata: {
      caller_email: caller.email,
      target_email: targetValidation.email,
      target_display_name: targetValidation.displayName,
    },
  });

  // 12. Record successful attempt
  await recordAttempt(caller.id, true);

  console.log("[impersonation] Started:", {
    adminId: caller.id,
    targetId: targetUserId,
    sessionId: dbSession.id,
    expiresAt: dbSession.expiresAt.toISOString(),
  });

  // 13. Return tokens in iOS-compatible format
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

async function handleStop(req: Request): Promise<Response> {
  if (!supabaseAdmin) {
    return json({ ok: false, error: "Service not configured" }, 503);
  }

  // 1. Authenticate the caller
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return json({ ok: false, error: "Missing authorization header" }, 401);
  }

  const token = authHeader.replace("Bearer ", "");
  const { data: { user: caller }, error: authError } = await supabaseAdmin.auth.getUser(token);

  if (authError || !caller) {
    return json({ ok: false, error: "Invalid or expired token" }, 401);
  }

  // 2. Parse request body
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

  // 3. Load the session
  const dbSession = await getImpersonationSession(sessionId);
  if (!dbSession) {
    return json({ ok: false, error: "Session not found" }, 404);
  }

  // 4. Verify the caller is the admin who started the session
  // Note: caller could be the admin (using their restored session) or
  // the impersonated user (ending from their context)
  // We allow either the admin or the target user to end the session
  if (dbSession.admin_user_id !== caller.id && dbSession.target_user_id !== caller.id) {
    return json({ ok: false, error: "Not authorized to end this session" }, 403);
  }

  // 5. Check if already ended
  if (dbSession.ended_at) {
    return json({ ok: false, error: "Session already ended" }, 400);
  }

  // 6. End the session
  await endImpersonationSession(sessionId, dbSession.admin_user_id);

  // 7. Insert audit log
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
      ended_by_type: caller.id === dbSession.admin_user_id ? "admin" : "impersonated_user",
    },
  });

  console.log("[impersonation] Stopped:", {
    adminId: dbSession.admin_user_id,
    targetId: dbSession.target_user_id,
    sessionId,
    endedBy: caller.id,
  });

  // 8. Return admin refresh token if stored (for web to restore session)
  let adminRefreshToken: string | null = null;
  if (dbSession.admin_refresh_token_enc && dbSession.admin_refresh_token_enc.length > 0) {
    try {
      adminRefreshToken = parseAndDecrypt(dbSession.admin_refresh_token_enc);
    } catch (error) {
      console.error("[impersonation] Failed to decrypt admin refresh token:", error);
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
serve(async (req) => {
  console.log("[impersonation] Request received:", req.method, req.url);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return json({ ok: false, error: "Method not allowed" }, 405);
    }

    // Parse action from URL path
    const url = new URL(req.url);
    const pathParts = url.pathname.split("/").filter(Boolean);
    const action = pathParts[pathParts.length - 1]; // Last segment: "start" or "stop"

    switch (action) {
      case "start":
        return await handleStart(req);
      case "stop":
        return await handleStop(req);
      default:
        // If no action specified, try parsing from body
        // This supports calling just /impersonation with { action: "start", ... }
        try {
          const body = await req.clone().json();
          if (body.action === "start") {
            return await handleStart(req);
          } else if (body.action === "stop") {
            return await handleStop(req);
          }
        } catch {
          // Ignore parse errors
        }
        return json({ ok: false, error: "Invalid action. Use /start or /stop" }, 400);
    }
  } catch (error) {
    console.error("[impersonation] Unexpected error:", error);
    return json({ ok: false, error: "Internal server error" }, 500);
  }
});

// ---------- Response Helpers ----------
function json(obj: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}
