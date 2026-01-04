/**
 * Impersonation Utilities
 *
 * Server-side utilities for reading and managing impersonation state.
 * Used across route handlers, server actions, and middleware.
 */
import "server-only";
import { cookies } from "next/headers";
import type { NextRequest, NextResponse } from "next/server";
import {
  parseAndVerifySignedCookie,
  createSignedCookieValue,
  generateNonce,
  encryptAndSerialize,
  parseAndDecrypt,
  type ImpersonationContext,
} from "./impersonation-crypto";
import { resolveSecureFlag } from "./cookie-config";
import { createSupabaseServiceClient } from "@/lib/supabase/service";

/** Cookie name for impersonation context */
export const IMPERSONATION_COOKIE_NAME = "tidex_imp";

/** Default impersonation session duration (30 minutes) */
export const DEFAULT_SESSION_DURATION_MS = 30 * 60 * 1000;

/** Maximum impersonation session duration (1 hour) */
export const MAX_SESSION_DURATION_MS = 60 * 60 * 1000;

// Re-export types
export type { ImpersonationContext };

// ============================================================================
// COOKIE READING (for Server Components, Server Actions, Route Handlers)
// ============================================================================

/**
 * Read and verify impersonation context from cookies.
 * Use in Server Components and Server Actions.
 *
 * @returns Verified impersonation context, or null if not impersonating or invalid
 */
export async function readImpersonationContext(): Promise<ImpersonationContext | null> {
  const cookieStore = await cookies();
  const cookieValue = cookieStore.get(IMPERSONATION_COOKIE_NAME)?.value;

  if (!cookieValue) {
    return null;
  }

  return parseAndVerifySignedCookie(cookieValue);
}

/**
 * Read impersonation context from a NextRequest (for proxy/middleware).
 *
 * @param request - The Next.js request
 * @returns Verified impersonation context, or null if not impersonating or invalid
 */
export function readImpersonationContextFromRequest(
  request: NextRequest
): ImpersonationContext | null {
  const cookieValue = request.cookies.get(IMPERSONATION_COOKIE_NAME)?.value;

  if (!cookieValue) {
    return null;
  }

  return parseAndVerifySignedCookie(cookieValue);
}

/**
 * Check if the current session is impersonating.
 * Convenience wrapper for readImpersonationContext.
 */
export async function isImpersonating(): Promise<boolean> {
  const context = await readImpersonationContext();
  return context !== null;
}

/**
 * Check if impersonating from a request (for proxy/middleware).
 */
export function isImpersonatingFromRequest(request: NextRequest): boolean {
  const context = readImpersonationContextFromRequest(request);
  return context !== null;
}

// ============================================================================
// COOKIE WRITING (for Route Handlers)
// ============================================================================

export interface SetImpersonationCookieParams {
  impersonationSessionId: string;
  adminUserId: string;
  targetUserId: string;
  expiresAt: Date;
}

/**
 * Create and set the impersonation cookie on a response.
 * Use in Route Handlers only.
 */
export function setImpersonationCookie(
  response: NextResponse,
  params: SetImpersonationCookieParams,
  request: NextRequest
): void {
  const now = new Date();

  const context: ImpersonationContext = {
    impersonationSessionId: params.impersonationSessionId,
    adminUserId: params.adminUserId,
    targetUserId: params.targetUserId,
    expiresAt: params.expiresAt.toISOString(),
    iat: now.toISOString(),
    nonce: generateNonce(),
  };

  const cookieValue = createSignedCookieValue(context);

  // Calculate max-age in seconds
  const maxAge = Math.floor((params.expiresAt.getTime() - now.getTime()) / 1000);

  // Resolve secure flag based on request
  const url = new URL(request.url);
  const secure = resolveSecureFlag(url.protocol, url.hostname);

  response.cookies.set(IMPERSONATION_COOKIE_NAME, cookieValue, {
    httpOnly: true,
    secure,
    sameSite: "lax",
    path: "/",
    maxAge: Math.max(0, maxAge),
  });
}

/**
 * Clear the impersonation cookie from a response.
 * Use in Route Handlers only.
 */
export function clearImpersonationCookie(
  response: NextResponse,
  request: NextRequest
): void {
  const url = new URL(request.url);
  const secure = resolveSecureFlag(url.protocol, url.hostname);

  response.cookies.set(IMPERSONATION_COOKIE_NAME, "", {
    httpOnly: true,
    secure,
    sameSite: "lax",
    path: "/",
    maxAge: 0,
  });
}

/**
 * Clear impersonation cookie directly from cookies store.
 * Use in Server Actions when you need to clear without a response object.
 */
export async function clearImpersonationCookieFromStore(): Promise<void> {
  const cookieStore = await cookies();
  cookieStore.delete(IMPERSONATION_COOKIE_NAME);
}

// ============================================================================
// DATABASE OPERATIONS (using service role)
// ============================================================================

export interface CreateSessionParams {
  adminUserId: string;
  targetUserId: string;
  reason: string;
  adminRefreshToken: string;
  adminIp?: string | null;
  adminUserAgent?: string | null;
  durationMs?: number;
}

export interface ImpersonationSession {
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
  enc_kid: string;
  enc_alg: string;
  enc_format_ver: number;
}

/**
 * Create a new impersonation session in the database.
 * Returns the session ID and expiration.
 */
export async function createImpersonationSession(
  params: CreateSessionParams
): Promise<{ id: string; expiresAt: Date }> {
  const supabase = createSupabaseServiceClient();

  const now = new Date();
  const durationMs = Math.min(
    params.durationMs ?? DEFAULT_SESSION_DURATION_MS,
    MAX_SESSION_DURATION_MS
  );
  const expiresAt = new Date(now.getTime() + durationMs);

  // Encrypt the admin refresh token
  const encryptedToken = encryptAndSerialize(params.adminRefreshToken);

  const { data, error } = await supabase
    .schema("internal").from("impersonation_sessions")
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
    // Check for unique constraint violation (active session exists)
    if (error.code === "23505") {
      throw new Error("An active impersonation session already exists");
    }
    throw new Error(`Failed to create impersonation session: ${error.message}`);
  }

  return { id: data.id, expiresAt };
}

/**
 * Get an impersonation session by ID.
 */
export async function getImpersonationSession(
  sessionId: string
): Promise<ImpersonationSession | null> {
  const supabase = createSupabaseServiceClient();

  const { data, error } = await supabase
    .schema("internal").from("impersonation_sessions")
    .select("*")
    .eq("id", sessionId)
    .single();

  if (error) {
    if (error.code === "PGRST116") {
      return null; // Not found
    }
    throw new Error(`Failed to get impersonation session: ${error.message}`);
  }

  return data;
}

/**
 * End an impersonation session.
 */
export async function endImpersonationSession(
  sessionId: string,
  endedByAdminUserId: string
): Promise<void> {
  const supabase = createSupabaseServiceClient();

  const { error } = await supabase
    .schema("internal").from("impersonation_sessions")
    .update({
      ended_at: new Date().toISOString(),
      ended_by_admin_user_id: endedByAdminUserId,
    })
    .eq("id", sessionId)
    .is("ended_at", null);

  if (error) {
    throw new Error(`Failed to end impersonation session: ${error.message}`);
  }
}

/**
 * Get the active impersonation session for an admin.
 */
export async function getActiveSessionForAdmin(
  adminUserId: string
): Promise<ImpersonationSession | null> {
  const supabase = createSupabaseServiceClient();

  const { data, error } = await supabase
    .schema("internal").from("impersonation_sessions")
    .select("*")
    .eq("admin_user_id", adminUserId)
    .is("ended_at", null)
    .gt("expires_at", new Date().toISOString())
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error) {
    throw new Error(`Failed to get active session: ${error.message}`);
  }

  return data;
}

/**
 * Decrypt the admin refresh token from a session.
 */
export function decryptAdminRefreshToken(session: ImpersonationSession): string {
  return parseAndDecrypt(session.admin_refresh_token_enc);
}

// ============================================================================
// RATE LIMITING
// ============================================================================

/**
 * Check if admin is within rate limits for impersonation.
 * Returns true if under limit.
 */
export async function checkRateLimit(adminUserId: string): Promise<boolean> {
  const supabase = createSupabaseServiceClient();

  const { data, error } = await supabase.rpc("check_impersonation_rate_limit", {
    p_admin_user_id: adminUserId,
  });

  if (error) {
    console.error("[Impersonation] Rate limit check failed:", error);
    // Fail open but log - we'll rely on other checks
    return true;
  }

  return data === true;
}

/**
 * Record an impersonation attempt for rate limiting.
 */
export async function recordAttempt(
  adminUserId: string,
  success: boolean
): Promise<void> {
  const supabase = createSupabaseServiceClient();

  const { error } = await supabase.rpc("record_impersonation_attempt", {
    p_admin_user_id: adminUserId,
    p_success: success,
  });

  if (error) {
    console.error("[Impersonation] Failed to record attempt:", error);
    // Non-fatal - don't throw
  }
}

// ============================================================================
// ADMIN VALIDATION
// ============================================================================

/**
 * Check if a user ID belongs to an admin.
 * Uses service role to fetch app_metadata.
 */
export async function isUserAdmin(userId: string): Promise<boolean> {
  const supabase = createSupabaseServiceClient();

  const { data, error } = await supabase.auth.admin.getUserById(userId);

  if (error || !data.user) {
    return false;
  }

  return data.user.app_metadata?.role === "admin";
}

/**
 * Check if target user exists and is not an admin.
 * Returns { exists: boolean, isAdmin: boolean, email: string | null }
 */
export async function validateTargetUser(targetUserId: string): Promise<{
  exists: boolean;
  isAdmin: boolean;
  email: string | null;
  displayName: string | null;
}> {
  const supabase = createSupabaseServiceClient();

  const { data, error } = await supabase.auth.admin.getUserById(targetUserId);

  if (error || !data.user) {
    return { exists: false, isAdmin: false, email: null, displayName: null };
  }

  const user = data.user;
  const isAdmin = user.app_metadata?.role === "admin";
  const displayName =
    user.user_metadata?.full_name ||
    user.user_metadata?.name ||
    null;

  return {
    exists: true,
    isAdmin,
    email: user.email || null,
    displayName,
  };
}

// ============================================================================
// SENSITIVE ACTION RESTRICTIONS
// ============================================================================

/** Actions that are blocked while impersonating */
export const RESTRICTED_ACTIONS = [
  "change_email",
  "change_password",
  "enable_mfa",
  "disable_mfa",
  "delete_account",
  "update_subscription",
  "cancel_subscription",
  "manage_billing",
] as const;

export type RestrictedAction = (typeof RESTRICTED_ACTIONS)[number];

/**
 * Check if an action is restricted while impersonating.
 */
export function isRestrictedAction(action: string): boolean {
  return RESTRICTED_ACTIONS.includes(action as RestrictedAction);
}

/**
 * Throw an error if currently impersonating and trying to perform a restricted action.
 * Use at the start of sensitive server actions.
 */
export async function enforceNotImpersonating(action: RestrictedAction): Promise<void> {
  const context = await readImpersonationContext();
  if (context) {
    throw new Error(
      `Action "${action}" is not allowed while impersonating another user`
    );
  }
}
