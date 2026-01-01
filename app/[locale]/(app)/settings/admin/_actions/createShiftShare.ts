"use server";

import { verifyAdmin } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";
import { revalidateTag } from "next/cache";
import type { AdminAction } from "@/lib/admin/action-labels";

const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const VALID_NOTIFICATION_FREQUENCIES = ["instant", "summary", "muted"] as const;
type NotificationFrequency = (typeof VALID_NOTIFICATION_FREQUENCIES)[number];

interface CreateShiftShareInput {
  ownerId: string;
  viewerId: string;
  showEarnings?: boolean;
  notificationFrequency?: NotificationFrequency;
}

interface CreateShiftShareResult {
  success: true;
  shareId: string;
}

interface CreateShiftShareError {
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

export async function createShiftShare(
  input: CreateShiftShareInput
): Promise<CreateShiftShareResult | CreateShiftShareError> {
  const { user } = await verifyAdmin();
  const supabase = createSupabaseServiceClient();
  const adminEmail = user.email ?? "unknown";

  // Validate owner_id format
  if (!UUID_REGEX.test(input.ownerId)) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      metadata: {
        error: "Invalid owner_id format",
        intended_action: "shift_share_created",
        owner_id: input.ownerId,
      },
    });
    return { success: false, message: "Ugyldig eier-ID format" };
  }

  // Validate viewer_id format
  if (!UUID_REGEX.test(input.viewerId)) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      metadata: {
        error: "Invalid viewer_id format",
        intended_action: "shift_share_created",
        viewer_id: input.viewerId,
      },
    });
    return { success: false, message: "Ugyldig seer-ID format" };
  }

  // Check owner !== viewer
  if (input.ownerId === input.viewerId) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      metadata: {
        error: "Owner and viewer cannot be the same user",
        intended_action: "shift_share_created",
        owner_id: input.ownerId,
        viewer_id: input.viewerId,
      },
    });
    return { success: false, message: "Eier og seer kan ikke være samme bruker" };
  }

  // Validate notification_frequency
  const notificationFrequency = input.notificationFrequency ?? "instant";
  if (
    !VALID_NOTIFICATION_FREQUENCIES.includes(
      notificationFrequency as NotificationFrequency
    )
  ) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      metadata: {
        error: "Invalid notification_frequency value",
        intended_action: "shift_share_created",
        notification_frequency: notificationFrequency,
      },
    });
    return { success: false, message: "Ugyldig varslingsfrekvens" };
  }

  // Check that both users exist
  const { data: ownerData, error: ownerError } =
    await supabase.auth.admin.getUserById(input.ownerId);
  if (ownerError || !ownerData?.user) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      metadata: {
        error: "Owner user not found",
        intended_action: "shift_share_created",
        owner_id: input.ownerId,
      },
    });
    return { success: false, message: "Eier-brukeren finnes ikke" };
  }

  const { data: viewerData, error: viewerError } =
    await supabase.auth.admin.getUserById(input.viewerId);
  if (viewerError || !viewerData?.user) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      metadata: {
        error: "Viewer user not found",
        intended_action: "shift_share_created",
        viewer_id: input.viewerId,
      },
    });
    return { success: false, message: "Seer-brukeren finnes ikke" };
  }

  const ownerEmail = ownerData.user.email ?? null;
  const viewerEmail = viewerData.user.email ?? null;

  // Insert the shift share
  const showEarnings = input.showEarnings ?? true;

  const { data: insertData, error: insertError } = await supabase
    .from("shift_shares")
    .insert({
      owner_id: input.ownerId,
      viewer_id: input.viewerId,
      show_earnings: showEarnings,
      notification_frequency: notificationFrequency,
    })
    .select("id")
    .single();

  if (insertError) {
    // Handle unique constraint violation
    if (insertError.code === "23505") {
      await logAdminAction({
        adminId: user.id,
        adminEmail,
        action: "admin_action_failed",
        metadata: {
          error: "Shift share already exists",
          intended_action: "shift_share_created",
          owner_id: input.ownerId,
          owner_email: ownerEmail,
          viewer_id: input.viewerId,
          viewer_email: viewerEmail,
        },
      });
      return {
        success: false,
        message: `Denne delingen finnes allerede: ${ownerEmail ?? input.ownerId.slice(0, 8)} → ${viewerEmail ?? input.viewerId.slice(0, 8)}`,
      };
    }

    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      metadata: {
        error: insertError.message,
        intended_action: "shift_share_created",
        owner_id: input.ownerId,
        viewer_id: input.viewerId,
      },
    });
    return {
      success: false,
      message: `Kunne ikke opprette deling: ${insertError.message}`,
    };
  }

  // Log successful action
  await logAdminAction({
    adminId: user.id,
    adminEmail,
    action: "shift_share_created",
    targetId: insertData.id,
    metadata: {
      share_id: insertData.id,
      owner_id: input.ownerId,
      owner_email: ownerEmail,
      viewer_id: input.viewerId,
      viewer_email: viewerEmail,
      show_earnings: showEarnings,
      notification_frequency: notificationFrequency,
    },
  });

  // Invalidate caches
  revalidateTag(`user-${input.ownerId}`, "max");
  revalidateTag(`user-${input.viewerId}`, "max");
  revalidateTag("admin-auditlog", "max");

  return { success: true, shareId: insertData.id };
}
