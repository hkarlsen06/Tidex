import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, type User } from "npm:@supabase/supabase-js@2.45.4";
import { corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SUPERADMIN_USER_ID = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";

interface RoleRequestBody {
  targetUserId?: string;
  targetEmail?: string;
  grant?: boolean;
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
    console.error("[admin-user-role] admin_log_action_rpc failed", error);
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

  if (adminUser.id !== SUPERADMIN_USER_ID) {
    return jsonResponse(403, { success: false, error: "Superadmin access required" });
  }

  let body: RoleRequestBody;
  try {
    body = await request.json();
  } catch {
    return jsonResponse(400, { success: false, error: "Invalid JSON body" });
  }

  const targetUserId = body.targetUserId?.trim();
  const targetEmail = body.targetEmail?.trim() || null;
  const grant = body.grant;

  if (!targetUserId) {
    return jsonResponse(400, { success: false, error: "Missing targetUserId" });
  }

  if (typeof grant !== "boolean") {
    return jsonResponse(400, { success: false, error: "Missing or invalid grant field" });
  }

  if (targetUserId === adminUser.id) {
    await logAction(userClient, "admin_action_failed", targetUserId, targetEmail, {
      error: "Cannot modify your own admin status",
      intended_action: grant ? "grant_admin" : "revoke_admin",
    });
    return jsonResponse(403, { success: false, error: "Cannot modify your own admin status" });
  }

  const { data: targetUserData, error: targetUserError } =
    await adminClient.auth.admin.getUserById(targetUserId);

  if (targetUserError || !targetUserData.user) {
    await logAction(userClient, "admin_action_failed", targetUserId, targetEmail, {
      error: targetUserError?.message ?? "User not found",
      intended_action: grant ? "grant_admin" : "revoke_admin",
    });
    return jsonResponse(404, { success: false, error: "User not found" });
  }

  const targetUser = targetUserData.user;
  const currentRole = targetUser.app_metadata?.role as string | undefined;
  const isCurrentlyAdmin = currentRole === "admin";

  if (isCurrentlyAdmin === grant) {
    return jsonResponse(200, {
      success: true,
      message: grant ? "User is already an admin" : "User is not an admin",
    });
  }

  const nextAppMetadata = { ...targetUser.app_metadata };
  if (grant) {
    nextAppMetadata.role = "admin";
  } else {
    delete nextAppMetadata.role;
  }

  const { error: updateError } = await adminClient.auth.admin.updateUserById(targetUserId, {
    app_metadata: nextAppMetadata,
  });

  if (updateError) {
    await logAction(userClient, "admin_action_failed", targetUserId, targetEmail, {
      error: updateError.message,
      intended_action: grant ? "grant_admin" : "revoke_admin",
      old_value: { role: currentRole ?? null },
    });
    return jsonResponse(500, {
      success: false,
      error: grant ? "Failed to grant admin privileges" : "Failed to revoke admin privileges",
    });
  }

  await logAction(userClient, grant ? "grant_admin" : "revoke_admin", targetUserId, targetEmail, {
    old_value: { role: currentRole ?? null },
    new_value: { role: grant ? "admin" : null },
  });

  return jsonResponse(200, {
    success: true,
    message: grant ? "Admin privileges granted" : "Admin privileges revoked",
  });
});
