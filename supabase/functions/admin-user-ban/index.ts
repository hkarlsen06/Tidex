import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, type User } from "npm:@supabase/supabase-js@2.45.4";
import { corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const BAN_DURATION = "876000h";

interface BanRequestBody {
  targetUserId?: string;
  targetEmail?: string;
  ban?: boolean;
}

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function getAuthHeader(request: Request) {
  return request.headers.get("Authorization") ?? "";
}

function isAdmin(user: User) {
  return user.app_metadata?.role === "admin";
}

async function logAction(
  userClient: any,
  action: string,
  targetId: string | null,
  targetEmail: string | null,
  metadata: Record<string, unknown>,
) {
  const { error } = await userClient.rpc("admin_log_action_rpc", {
    p_action: action,
    p_target_id: targetId,
    p_target_email: targetEmail,
    p_metadata: metadata,
  });

  if (error) {
    console.error("[admin-user-ban] admin_log_action_rpc failed", error);
  }
}

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse(405, { success: false, error: "Method not allowed" });
  }

  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
    return jsonResponse(500, { success: false, error: "Missing Supabase configuration" });
  }

  const authHeader = getAuthHeader(request);
  if (!authHeader.startsWith("Bearer ")) {
    return jsonResponse(401, { success: false, error: "Missing bearer token" });
  }

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false },
    global: { headers: { Authorization: authHeader } },
  });
  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  const {
    data: { user: adminUser },
    error: adminError,
  } = await userClient.auth.getUser();

  if (adminError || !adminUser) {
    return jsonResponse(401, { success: false, error: "Not authenticated" });
  }

  if (!isAdmin(adminUser)) {
    return jsonResponse(403, { success: false, error: "Admin access required" });
  }

  let body: BanRequestBody;
  try {
    body = await request.json();
  } catch {
    return jsonResponse(400, { success: false, error: "Invalid JSON body" });
  }

  const targetUserId = body.targetUserId?.trim();
  const targetEmail = body.targetEmail?.trim() || null;
  const ban = body.ban;

  if (!targetUserId) {
    return jsonResponse(400, { success: false, error: "Missing targetUserId" });
  }

  if (typeof ban !== "boolean") {
    return jsonResponse(400, { success: false, error: "Missing or invalid ban field" });
  }

  if (targetUserId === adminUser.id) {
    await logAction(userClient, "admin_action_failed", targetUserId, targetEmail, {
      error: "Cannot ban yourself",
      intended_action: ban ? "user_ban" : "user_unban",
    });
    return jsonResponse(403, { success: false, error: "Cannot ban yourself" });
  }

  const { data: targetUserData, error: targetUserError } =
    await adminClient.auth.admin.getUserById(targetUserId);

  if (targetUserError || !targetUserData.user) {
    await logAction(userClient, "admin_action_failed", targetUserId, targetEmail, {
      error: targetUserError?.message ?? "User not found",
      intended_action: ban ? "user_ban" : "user_unban",
    });
    return jsonResponse(404, { success: false, error: "User not found" });
  }

  const targetUser = targetUserData.user;
  const targetIsAdmin = targetUser.app_metadata?.role === "admin";
  const targetUserBannedUntil =
    ((targetUser as unknown as { banned_until?: string | null }).banned_until) ?? null;
  const wasBanned = !!targetUserBannedUntil;

  if (ban && targetIsAdmin) {
    await logAction(userClient, "admin_action_failed", targetUserId, targetEmail, {
      error: "Cannot ban another admin",
      intended_action: "user_ban",
    });
    return jsonResponse(403, { success: false, error: "Cannot ban another admin" });
  }

  if (wasBanned === ban) {
    return jsonResponse(200, {
      success: true,
      message: ban ? "User is already banned" : "User is not banned",
    });
  }

  const { error: updateError } = await adminClient.auth.admin.updateUserById(targetUserId, {
    ban_duration: ban ? BAN_DURATION : "none",
  });

  if (updateError) {
    await logAction(userClient, "admin_action_failed", targetUserId, targetEmail, {
      error: updateError.message,
      intended_action: ban ? "user_ban" : "user_unban",
      old_value: { banned: wasBanned, banned_until: targetUserBannedUntil },
    });
    return jsonResponse(500, {
      success: false,
      error: ban ? "Failed to ban user" : "Failed to unban user",
    });
  }

  await logAction(userClient, ban ? "user_ban" : "user_unban", targetUserId, targetEmail, {
    old_value: { banned: wasBanned, banned_until: targetUserBannedUntil },
    new_value: { banned: ban },
    ban_duration: ban ? BAN_DURATION : null,
  });

  return jsonResponse(200, {
    success: true,
    message: ban ? "User banned successfully" : "User unbanned successfully",
  });
});
