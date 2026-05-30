import { withSupabase } from "npm:@supabase/server@1.0.0";
import type { User } from "npm:@supabase/supabase-js@2.45.4";
import { corsHeaders } from "../_shared/cors.ts";

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

export default {
  fetch: withSupabase<any>(
    { auth: "user", cors: corsHeaders },
    async (request, ctx) => {
      if (request.method !== "POST") {
        return jsonResponse(405, {
          success: false,
          error: "Method not allowed",
        });
      }

      const {
        data: { user: adminUser },
        error: adminError,
      } = await ctx.supabase.auth.getUser();

      if (adminError || !adminUser) {
        return jsonResponse(401, {
          success: false,
          error: "Not authenticated",
        });
      }

      if (!isAdmin(adminUser)) {
        return jsonResponse(403, {
          success: false,
          error: "Admin access required",
        });
      }

      if (adminUser.id !== SUPERADMIN_USER_ID) {
        return jsonResponse(403, {
          success: false,
          error: "Superadmin access required",
        });
      }

      let body: RoleRequestBody;
      try {
        body = await request.json();
      } catch {
        return jsonResponse(400, {
          success: false,
          error: "Invalid JSON body",
        });
      }

      const targetUserId = body.targetUserId?.trim();
      const targetEmail = body.targetEmail?.trim() || null;
      const grant = body.grant;

      if (!targetUserId) {
        return jsonResponse(400, {
          success: false,
          error: "Missing targetUserId",
        });
      }

      if (typeof grant !== "boolean") {
        return jsonResponse(400, {
          success: false,
          error: "Missing or invalid grant field",
        });
      }

      if (targetUserId === adminUser.id) {
        await logAction(
          ctx.supabase,
          "admin_action_failed",
          targetUserId,
          targetEmail,
          {
            error: "Cannot modify your own admin status",
            intended_action: grant ? "grant_admin" : "revoke_admin",
          },
        );
        return jsonResponse(403, {
          success: false,
          error: "Cannot modify your own admin status",
        });
      }

      const { data: targetUserData, error: targetUserError } = await ctx
        .supabaseAdmin.auth.admin.getUserById(targetUserId);

      if (targetUserError || !targetUserData.user) {
        await logAction(
          ctx.supabase,
          "admin_action_failed",
          targetUserId,
          targetEmail,
          {
            error: targetUserError?.message ?? "User not found",
            intended_action: grant ? "grant_admin" : "revoke_admin",
          },
        );
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
        // Supabase Auth merges app_metadata updates, so omitting `role` does not
        // remove an existing admin role. Store JSON null to clear the claim.
        nextAppMetadata.role = null;
      }

      const { error: updateError } = await ctx.supabaseAdmin.auth.admin
        .updateUserById(targetUserId, {
          app_metadata: nextAppMetadata,
        });

      const { data: verifiedUserData, error: verifyError } = updateError
        ? { data: null, error: updateError }
        : await ctx.supabaseAdmin.auth.admin.getUserById(targetUserId);

      const verifiedRole = verifiedUserData?.user?.app_metadata?.role;
      const updateSucceeded = grant
        ? verifiedRole === "admin"
        : verifiedRole !== "admin";

      if (updateError || verifyError || !updateSucceeded) {
        await logAction(
          ctx.supabase,
          "admin_action_failed",
          targetUserId,
          targetEmail,
          {
            error: updateError?.message ?? verifyError?.message ??
              "Role update verification failed",
            intended_action: grant ? "grant_admin" : "revoke_admin",
            old_value: { role: currentRole ?? null },
            observed_value: { role: verifiedRole ?? null },
          },
        );
        return jsonResponse(500, {
          success: false,
          error: grant
            ? "Failed to grant admin privileges"
            : "Failed to revoke admin privileges",
        });
      }

      await logAction(
        ctx.supabase,
        grant ? "grant_admin" : "revoke_admin",
        targetUserId,
        targetEmail,
        {
          old_value: { role: currentRole ?? null },
          new_value: { role: grant ? "admin" : null },
        },
      );

      return jsonResponse(200, {
        success: true,
        message: grant
          ? "Admin privileges granted"
          : "Admin privileges revoked",
      });
    },
  ),
};
