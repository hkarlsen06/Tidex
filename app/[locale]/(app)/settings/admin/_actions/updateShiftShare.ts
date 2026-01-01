"use server";

import { verifyAdmin } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";
import { revalidateTag } from "next/cache";
import type { AdminAction } from "@/lib/admin/action-labels";

const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const VALID_NOTIFICATION_FREQUENCIES = ["instant", "summary", "muted"] as const;
type NotificationFrequency = (typeof VALID_NOTIFICATION_FREQUENCIES)[number];

interface UpdateShiftShareInput {
  shareId: string;
  showEarnings?: boolean;
  blocked?: boolean;
  notificationFrequency?: NotificationFrequency;
}

interface UpdateShiftShareResult {
  success: true;
}

interface UpdateShiftShareError {
  success: false;
  message: string;
}

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

export async function updateShiftShare(
  input: UpdateShiftShareInput
): Promise<UpdateShiftShareResult | UpdateShiftShareError> {
  const { user } = await verifyAdmin();
  const supabase = createSupabaseServiceClient();
  const adminEmail = user.email ?? "unknown";

  // Validate share_id format
  if (!UUID_REGEX.test(input.shareId)) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      metadata: {
        error: "Invalid share_id format",
        intended_action: "shift_share_updated",
        share_id: input.shareId,
      },
    });
    return { success: false, message: "Ugyldig delings-ID format" };
  }

  // Validate notification_frequency if provided
  if (
    input.notificationFrequency !== undefined &&
    !VALID_NOTIFICATION_FREQUENCIES.includes(
      input.notificationFrequency as NotificationFrequency
    )
  ) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      metadata: {
        error: "Invalid notification_frequency value",
        intended_action: "shift_share_updated",
        notification_frequency: input.notificationFrequency,
      },
    });
    return { success: false, message: "Ugyldig varslingsfrekvens" };
  }

  // Fetch current values for audit diff
  const { data: currentData, error: fetchError } = await supabase
    .from("shift_shares")
    .select("id, owner_id, viewer_id, show_earnings, blocked, notification_frequency")
    .eq("id", input.shareId)
    .single();

  if (fetchError || !currentData) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      metadata: {
        error: fetchError?.message ?? "Share not found",
        intended_action: "shift_share_updated",
        share_id: input.shareId,
      },
    });
    return { success: false, message: "Delingen finnes ikke" };
  }

  // Get user emails for audit context
  const { data: ownerData } = await supabase.auth.admin.getUserById(
    currentData.owner_id
  );
  const { data: viewerData } = await supabase.auth.admin.getUserById(
    currentData.viewer_id
  );
  const ownerEmail = ownerData?.user?.email ?? null;
  const viewerEmail = viewerData?.user?.email ?? null;

  // Build update object and track changes
  const updates: Record<string, unknown> = {};
  const changes: Record<string, { before: unknown; after: unknown }> = {};

  if (
    input.showEarnings !== undefined &&
    input.showEarnings !== currentData.show_earnings
  ) {
    updates.show_earnings = input.showEarnings;
    changes.show_earnings = {
      before: currentData.show_earnings,
      after: input.showEarnings,
    };
  }

  if (input.blocked !== undefined && input.blocked !== currentData.blocked) {
    updates.blocked = input.blocked;
    changes.blocked = {
      before: currentData.blocked,
      after: input.blocked,
    };
  }

  if (
    input.notificationFrequency !== undefined &&
    input.notificationFrequency !== currentData.notification_frequency
  ) {
    updates.notification_frequency = input.notificationFrequency;
    changes.notification_frequency = {
      before: currentData.notification_frequency,
      after: input.notificationFrequency,
    };
  }

  // No changes to make
  if (Object.keys(updates).length === 0) {
    return { success: true };
  }

  // Perform the update
  const { error: updateError } = await supabase
    .from("shift_shares")
    .update(updates)
    .eq("id", input.shareId);

  if (updateError) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      targetId: input.shareId,
      metadata: {
        error: updateError.message,
        intended_action: "shift_share_updated",
        share_id: input.shareId,
        owner_id: currentData.owner_id,
        viewer_id: currentData.viewer_id,
      },
    });
    return {
      success: false,
      message: `Kunne ikke oppdatere deling: ${updateError.message}`,
    };
  }

  // Log successful action with before/after diff
  await logAdminAction({
    adminId: user.id,
    adminEmail,
    action: "shift_share_updated",
    targetId: input.shareId,
    metadata: {
      share_id: input.shareId,
      owner_id: currentData.owner_id,
      owner_email: ownerEmail,
      viewer_id: currentData.viewer_id,
      viewer_email: viewerEmail,
      changes,
    },
  });

  // Invalidate caches
  revalidateTag(`user-${currentData.owner_id}`, "max");
  revalidateTag(`user-${currentData.viewer_id}`, "max");
  revalidateTag("admin-auditlog", "max");

  return { success: true };
}
