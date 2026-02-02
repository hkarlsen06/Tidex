"use server";

import { verifyAdmin } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";
import { revalidateTag } from "next/cache";
import type { AdminAction } from "@/lib/admin/action-labels";

interface RevokeTrialInput {
  targetUserId: string;
  targetEmail: string;
}

/**
 * Log an admin action to the audit log
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

export async function revokeTrialSubscription(input: RevokeTrialInput) {
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
        intended_action: "revoke_trial_subscription",
      },
    });
    return { success: false, message: "Ugyldig bruker-ID format" };
  }

  // Find the active admin trial subscription
  const { data: trial, error: fetchError } = await supabase
    .from("subscriptions")
    .select("id, status, current_period_end")
    .eq("user_id", input.targetUserId)
    .eq("provider", "admin_trial")
    .eq("status", "active")
    .single();

  if (fetchError || !trial) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      targetId: input.targetUserId,
      targetEmail: input.targetEmail,
      metadata: {
        error: fetchError?.message ?? "No active admin trial found",
        intended_action: "revoke_trial_subscription",
      },
    });
    return { success: false, message: "Ingen aktiv prøveperiode funnet" };
  }

  const now = new Date().toISOString();

  // Revoke the trial
  const { error: updateError } = await supabase
    .from("subscriptions")
    .update({
      status: "canceled",
      canceled_at: now,
      updated_at: now,
    })
    .eq("id", trial.id);

  if (updateError) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      targetId: input.targetUserId,
      targetEmail: input.targetEmail,
      metadata: {
        error: updateError.message,
        intended_action: "revoke_trial_subscription",
        subscription_id: trial.id,
      },
    });
    return { success: false, message: "Kunne ikke avslutte prøveperiode" };
  }

  // Log successful action
  await logAdminAction({
    adminId: user.id,
    adminEmail,
    action: "revoke_trial_subscription",
    targetId: input.targetUserId,
    targetEmail: input.targetEmail,
    metadata: {
      old_value: {
        status: trial.status,
        current_period_end: trial.current_period_end,
      },
      new_value: {
        status: "canceled",
        canceled_at: now,
      },
    },
  });

  // Invalidate caches
  revalidateTag(`user-${input.targetUserId}`, "max");
  revalidateTag("admin-subscribers", "max");
  revalidateTag("admin-auditlog", "max");

  return {
    success: true,
    message: "Prøveperiode avsluttet",
  };
}
