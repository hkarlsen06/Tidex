"use server";

import { verifyAdmin } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";
import { revalidateTag } from "next/cache";
import type { AdminAction } from "@/lib/admin/action-labels";

/**
 * Superadmin user ID - only this user can grant/revoke admin privileges
 * This is Hjalmar's account (primary developer)
 */
const SUPERADMIN_USER_ID = "032d8c2a-9af6-4777-99f0-24e2c4058bf3";

interface ToggleAdminInput {
  targetUserId: string;
  targetEmail: string;
  grant: boolean;
}

/**
 * Log an admin action to the audit log
 * Uses service role to bypass RLS
 */
async function logAdminAction(params: {
  adminId: string;
  adminEmail: string;
  action: AdminAction;
  targetId?: string;
  targetEmail?: string;
  metadata?: Record<string, unknown>;
}) {
  const supabase = createSupabaseServiceClient();

  const { error } = await supabase.rpc("admin_log_action", {
    p_admin_id: params.adminId,
    p_admin_email: params.adminEmail,
    p_action: params.action,
    p_target_id: params.targetId ?? null,
    p_target_email: params.targetEmail ?? null,
    p_metadata: params.metadata ?? {},
  });

  if (error) {
    console.error("Failed to log admin action:", error);
  }
}

export async function toggleAdmin(input: ToggleAdminInput) {
  const { user } = await verifyAdmin();
  const supabase = createSupabaseServiceClient();
  const adminEmail = user.email ?? "unknown";

  // GUARDRAIL: Only superadmin can grant/revoke admin privileges
  if (user.id !== SUPERADMIN_USER_ID) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      targetId: input.targetUserId,
      targetEmail: input.targetEmail,
      metadata: {
        error: "Not authorized - only superadmin can manage admin privileges",
        intended_action: input.grant ? "grant_admin" : "revoke_admin",
      },
    });
    return {
      success: false,
      message: "Kun superadmin kan administrere admin-tilganger",
    };
  }

  // Validate UUID format
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      input.targetUserId
    )
  ) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      targetId: undefined,
      targetEmail: input.targetEmail,
      metadata: {
        error: "Invalid User ID format",
        intended_action: input.grant ? "grant_admin" : "revoke_admin",
      },
    });
    return { success: false, message: "Ugyldig bruker-ID format" };
  }

  // GUARDRAIL: Cannot modify own admin status
  if (input.targetUserId === user.id) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      targetId: input.targetUserId,
      targetEmail: input.targetEmail,
      metadata: {
        error: "Cannot modify own admin status",
        intended_action: input.grant ? "grant_admin" : "revoke_admin",
      },
    });
    return {
      success: false,
      message: "Du kan ikke endre din egen admin-status",
    };
  }

  // Get target user to check current status
  const { data: targetUserData, error: getUserError } =
    await supabase.auth.admin.getUserById(input.targetUserId);

  if (getUserError || !targetUserData?.user) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      targetId: input.targetUserId,
      targetEmail: input.targetEmail,
      metadata: {
        error: getUserError?.message ?? "User not found",
        intended_action: input.grant ? "grant_admin" : "revoke_admin",
      },
    });
    return { success: false, message: "Kunne ikke finne bruker" };
  }

  const targetUser = targetUserData.user;
  const currentRole = targetUser.app_metadata?.role as string | undefined;
  const isCurrentlyAdmin = currentRole === "admin";

  // No change needed
  if (isCurrentlyAdmin === input.grant) {
    return {
      success: true,
      message: input.grant
        ? "Bruker er allerede admin"
        : "Bruker er ikke admin",
    };
  }

  // Update the user's app_metadata
  const newAppMetadata = { ...targetUser.app_metadata };
  if (input.grant) {
    newAppMetadata.role = "admin";
  } else {
    delete newAppMetadata.role;
  }

  const { error: updateError } = await supabase.auth.admin.updateUserById(
    input.targetUserId,
    {
      app_metadata: newAppMetadata,
    }
  );

  if (updateError) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      targetId: input.targetUserId,
      targetEmail: input.targetEmail,
      metadata: {
        error: updateError.message,
        intended_action: input.grant ? "grant_admin" : "revoke_admin",
        old_value: { role: currentRole },
      },
    });
    return {
      success: false,
      message: input.grant
        ? "Kunne ikke gi admin-tilgang"
        : "Kunne ikke fjerne admin-tilgang",
    };
  }

  // Log successful action
  await logAdminAction({
    adminId: user.id,
    adminEmail,
    action: input.grant ? "grant_admin" : "revoke_admin",
    targetId: input.targetUserId,
    targetEmail: input.targetEmail,
    metadata: {
      old_value: { role: currentRole },
      new_value: { role: input.grant ? "admin" : null },
    },
  });

  // Invalidate caches
  revalidateTag(`user-${input.targetUserId}`, "max");
  revalidateTag("admin-users", "max");
  revalidateTag("admin-auditlog", "max");

  return {
    success: true,
    message: input.grant ? "Admin-tilgang gitt" : "Admin-tilgang fjernet",
  };
}

/**
 * Check if the current user is the superadmin
 */
export async function checkIsSuperAdmin(): Promise<boolean> {
  try {
    const { user } = await verifyAdmin();
    return user.id === SUPERADMIN_USER_ID;
  } catch {
    return false;
  }
}
