"use server";

import { verifyAdmin } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";
import { revalidateTag } from "next/cache";
import type { AdminAction } from "@/lib/admin/action-labels";

interface ToggleGrandfatheredInput {
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

export async function toggleGrandfathered(input: ToggleGrandfatheredInput) {
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
        intended_action: input.grant
          ? "grant_grandfathered"
          : "revoke_grandfathered",
      },
    });
    return { success: false, message: "Ugyldig bruker-ID format" };
  }

  // Get current state
  const { data: profile, error: fetchError } = await supabase
    .from("profiles")
    .select("before_paywall")
    .eq("id", input.targetUserId)
    .single();

  if (fetchError || !profile) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      targetId: input.targetUserId,
      targetEmail: input.targetEmail,
      metadata: {
        error: fetchError?.message ?? "Profile not found",
        intended_action: input.grant
          ? "grant_grandfathered"
          : "revoke_grandfathered",
      },
    });
    return { success: false, message: "Kunne ikke finne bruker" };
  }

  const oldValue = profile.before_paywall;
  const newValue = input.grant;

  // No change needed
  if (oldValue === newValue) {
    return {
      success: true,
      message: input.grant
        ? "Bruker har allerede livstidstilgang"
        : "Bruker har ikke livstidstilgang",
    };
  }

  // Update the profile
  const { error: updateError } = await supabase
    .from("profiles")
    .update({
      before_paywall: newValue,
      updated_at: new Date().toISOString(),
    })
    .eq("id", input.targetUserId);

  if (updateError) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      targetId: input.targetUserId,
      targetEmail: input.targetEmail,
      metadata: {
        error: updateError.message,
        intended_action: input.grant
          ? "grant_grandfathered"
          : "revoke_grandfathered",
        old_value: oldValue,
      },
    });
    return { success: false, message: "Kunne ikke oppdatere bruker" };
  }

  // Log successful action
  await logAdminAction({
    adminId: user.id,
    adminEmail,
    action: input.grant ? "grant_grandfathered" : "revoke_grandfathered",
    targetId: input.targetUserId,
    targetEmail: input.targetEmail,
    metadata: {
      old_value: oldValue,
      new_value: newValue,
    },
  });

  // Invalidate caches
  revalidateTag(`user-${input.targetUserId}`, "max");
  revalidateTag("admin-subscribers", "max");
  revalidateTag("admin-auditlog", "max");

  return {
    success: true,
    message: input.grant
      ? "Livstidstilgang gitt"
      : "Livstidstilgang fjernet",
  };
}
