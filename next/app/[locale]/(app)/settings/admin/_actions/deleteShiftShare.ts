"use server";

import { verifyAdmin } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";
import { revalidateTag } from "next/cache";
import type { AdminAction } from "@/lib/admin/action-labels";

const UUID_REGEX =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface DeleteShiftShareInput {
  shareId: string;
}

interface DeleteShiftShareResult {
  success: true;
}

interface DeleteShiftShareError {
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

export async function deleteShiftShare(
  input: DeleteShiftShareInput
): Promise<DeleteShiftShareResult | DeleteShiftShareError> {
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
        intended_action: "shift_share_deleted",
        share_id: input.shareId,
      },
    });
    return { success: false, message: "Ugyldig delings-ID format" };
  }

  // Fetch share details before delete for audit
  const { data: shareData, error: fetchError } = await supabase
    .from("shift_shares")
    .select("id, owner_id, viewer_id, show_earnings, hidden, muted, created_at")
    .eq("id", input.shareId)
    .single();

  if (fetchError || !shareData) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      metadata: {
        error: fetchError?.message ?? "Share not found",
        intended_action: "shift_share_deleted",
        share_id: input.shareId,
      },
    });
    return { success: false, message: "Delingen finnes ikke" };
  }

  // Get user emails for audit context
  const { data: ownerData } = await supabase.auth.admin.getUserById(
    shareData.owner_id
  );
  const { data: viewerData } = await supabase.auth.admin.getUserById(
    shareData.viewer_id
  );
  const ownerEmail = ownerData?.user?.email ?? null;
  const viewerEmail = viewerData?.user?.email ?? null;

  // Delete the share
  const { error: deleteError } = await supabase
    .from("shift_shares")
    .delete()
    .eq("id", input.shareId);

  if (deleteError) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      targetId: input.shareId,
      metadata: {
        error: deleteError.message,
        intended_action: "shift_share_deleted",
        share_id: input.shareId,
        owner_id: shareData.owner_id,
        viewer_id: shareData.viewer_id,
      },
    });
    return {
      success: false,
      message: `Kunne ikke slette deling: ${deleteError.message}`,
    };
  }

  // Log successful action with full context
  await logAdminAction({
    adminId: user.id,
    adminEmail,
    action: "shift_share_deleted",
    targetId: input.shareId,
    metadata: {
      share_id: input.shareId,
      owner_id: shareData.owner_id,
      owner_email: ownerEmail,
      viewer_id: shareData.viewer_id,
      viewer_email: viewerEmail,
      deleted_data: {
        show_earnings: shareData.show_earnings,
        blocked: shareData.hidden,
        muted: shareData.muted,
        created_at: shareData.created_at,
      },
    },
  });

  // Invalidate caches
  revalidateTag(`user-${shareData.owner_id}`, "max");
  revalidateTag(`user-${shareData.viewer_id}`, "max");
  revalidateTag("admin-auditlog", "max");

  return { success: true };
}
