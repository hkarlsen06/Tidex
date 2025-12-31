"use server";

import { verifyAdmin } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";
import { revalidateTag } from "next/cache";
import type { AdminAction } from "@/lib/admin/action-labels";

interface ToggleUserBanInput {
  targetUserId: string;
  targetEmail: string;
  ban: boolean;
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

// Ban duration: 100 years in hours
const BAN_DURATION_HOURS = "876000h";

export async function toggleUserBan(input: ToggleUserBanInput) {
  const { user } = await verifyAdmin();
  const supabase = createSupabaseServiceClient();
  const adminEmail = user.email ?? "unknown";

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
        intended_action: input.ban ? "user_ban" : "user_unban",
      },
    });
    return { success: false, message: "Ugyldig bruker-ID format" };
  }

  // GUARDRAIL: Cannot ban self
  if (input.targetUserId === user.id) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      targetId: input.targetUserId,
      targetEmail: input.targetEmail,
      metadata: {
        error: "Cannot ban self",
        intended_action: "user_ban",
      },
    });
    return { success: false, message: "Du kan ikke utestenge deg selv" };
  }

  // Get target user to check if they're an admin
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
        intended_action: input.ban ? "user_ban" : "user_unban",
      },
    });
    return { success: false, message: "Kunne ikke finne bruker" };
  }

  const targetUser = targetUserData.user;
  const isTargetAdmin =
    (targetUser.app_metadata?.role as string | undefined) === "admin";

  // GUARDRAIL: Cannot ban other admins
  if (input.ban && isTargetAdmin) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      targetId: input.targetUserId,
      targetEmail: input.targetEmail,
      metadata: {
        error: "Cannot ban another admin",
        intended_action: "user_ban",
      },
    });
    return { success: false, message: "Du kan ikke utestenge en annen admin" };
  }

  // Cast to access banned_until which may not be in the type
  const targetUserBannedUntil = (targetUser as unknown as { banned_until?: string | null }).banned_until;
  const wasBanned = !!targetUserBannedUntil;

  // No change needed
  if (wasBanned === input.ban) {
    return {
      success: true,
      message: input.ban
        ? "Bruker er allerede utestengt"
        : "Bruker er ikke utestengt",
    };
  }

  // Perform the ban/unban
  const { error: updateError } = await supabase.auth.admin.updateUserById(
    input.targetUserId,
    {
      ban_duration: input.ban ? BAN_DURATION_HOURS : "none",
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
        intended_action: input.ban ? "user_ban" : "user_unban",
        old_value: { banned: wasBanned },
      },
    });
    return {
      success: false,
      message: input.ban
        ? "Kunne ikke utestenge bruker"
        : "Kunne ikke fjerne utestengelse",
    };
  }

  // Log successful action
  await logAdminAction({
    adminId: user.id,
    adminEmail,
    action: input.ban ? "user_ban" : "user_unban",
    targetId: input.targetUserId,
    targetEmail: input.targetEmail,
    metadata: {
      old_value: { banned: wasBanned, banned_until: targetUserBannedUntil },
      new_value: { banned: input.ban },
      ban_duration: input.ban ? BAN_DURATION_HOURS : null,
    },
  });

  // Invalidate caches
  revalidateTag(`user-${input.targetUserId}`, "max");
  revalidateTag("admin-users", "max");
  revalidateTag("admin-auditlog", "max");

  return {
    success: true,
    message: input.ban ? "Bruker utestengt" : "Utestengelse fjernet",
  };
}
