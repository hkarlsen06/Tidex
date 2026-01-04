"use server";

import { verifyAdmin } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";
import { revalidateTag } from "next/cache";
import type { AdminAction } from "@/lib/admin/action-labels";

type TargetAudience = "all" | "pro" | "active" | "specific";

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

interface BroadcastInput {
  title: string;
  body: string;
  deeplink?: string;
  target: TargetAudience;
  specificUserId?: string;
  includeSelf?: boolean;
}

// Validate deeplink server-side - returns error message or null if valid
function validateDeeplink(
  deeplink: string | undefined
): { valid: true; value: string | null } | { valid: false; error: string } {
  if (!deeplink || deeplink.trim() === "") {
    return { valid: true, value: null };
  }
  // Max length check
  if (deeplink.length > 200) {
    return { valid: false, error: "Deeplink too long (max 200 chars)" };
  }
  // Allow query strings: /stats?tab=week
  if (!/^\/[a-zA-Z0-9/_?=&-]*$/.test(deeplink)) {
    return {
      valid: false,
      error:
        "Invalid deeplink format. Must start with / and contain only alphanumeric, /, _, -, ?, =, &",
    };
  }
  // Block path traversal and protocol injection
  if (deeplink.includes("//") || deeplink.includes("..")) {
    return { valid: false, error: "Invalid deeplink: cannot contain // or .." };
  }
  return { valid: true, value: deeplink };
}

const BATCH_SIZE = 500; // Supabase insert limit safety

export async function sendBroadcastNotification(input: BroadcastInput) {
  // Verify admin (redirects if not)
  const { user } = await verifyAdmin();

  // Use service role client to call admin RPC functions
  const supabase = createSupabaseServiceClient();

  // Validate inputs
  if (!input.title || input.title.trim().length === 0) {
    return { success: false, message: "Title is required" };
  }
  if (input.title.length > 100) {
    return { success: false, message: "Title too long (max 100 chars)" };
  }
  if (!input.body || input.body.trim().length === 0) {
    return { success: false, message: "Body is required" };
  }
  if (input.body.length > 500) {
    return { success: false, message: "Body too long (max 500 chars)" };
  }

  // Validate deeplink - error if present but invalid
  const deeplinkResult = validateDeeplink(input.deeplink);
  if (!deeplinkResult.valid) {
    return { success: false, message: deeplinkResult.error };
  }
  const validatedDeeplink = deeplinkResult.value;

  let targetUserIds: string[] = [];

  if (input.target === "specific") {
    if (!input.specificUserId) {
      return {
        success: false,
        message: "User ID required for specific targeting",
      };
    }
    // Validate UUID format
    if (
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        input.specificUserId
      )
    ) {
      return { success: false, message: "Invalid User ID format" };
    }
    targetUserIds = [input.specificUserId];
  } else {
    // Use hardened admin RPC functions (service_role only)
    const excludeUserId = input.includeSelf ? null : user.id;

    let rpcName: string;
    let rpcParams: Record<string, unknown> = {};

    switch (input.target) {
      case "pro":
        rpcName = "admin_get_target_users_pro";
        break;
      case "active":
        rpcName = "admin_get_target_users_active";
        break;
      default: // "all"
        rpcName = "admin_get_target_users_all";
        rpcParams = { exclude_user_id: excludeUserId };
    }

    const { data, error } = await supabase.rpc(rpcName, rpcParams);
    if (error) {
      return { success: false, message: `Targeting failed: ${error.message}` };
    }
    targetUserIds = (data || []).map((r: { user_id: string }) => r.user_id);
  }

  if (targetUserIds.length === 0) {
    return { success: false, message: "No users match target criteria" };
  }

  // Create broadcast record (DB generates UUID, status defaults to 'pending')
  const { data: broadcast, error: broadcastError } = await supabase
    .schema("internal").from("admin_broadcasts")
    .insert({
      admin_id: user.id,
      title: input.title.trim(),
      body: input.body.trim(),
      deeplink: validatedDeeplink,
      target: input.target,
      target_count: targetUserIds.length,
      // status: 'pending' is default
    })
    .select("id")
    .single();

  if (broadcastError || !broadcast) {
    return {
      success: false,
      message: `Failed to create broadcast: ${broadcastError?.message}`,
    };
  }

  const broadcastId = broadcast.id;

  // Build notification rows
  const allNotifications = targetUserIds.map((userId) => ({
    type: "admin_broadcast" as const,
    recipient_id: userId,
    sender_id: user.id,
    broadcast_id: broadcastId,
    payload: {
      title: input.title.trim(),
      body: input.body.trim(),
      deeplink: validatedDeeplink,
    },
    idempotency_key: `broadcast:${broadcastId}:${userId}`,
  }));

  // Batch insert to avoid payload size limits
  let insertedCount = 0;
  for (let i = 0; i < allNotifications.length; i += BATCH_SIZE) {
    const batch = allNotifications.slice(i, i + BATCH_SIZE);
    const { error: insertError } = await supabase
      .schema("internal").from("notification_queue")
      .insert(batch);

    if (insertError) {
      // Partial failure - update broadcast status
      await supabase
        .schema("internal").from("admin_broadcasts")
        .update({ status: "partial_failure" })
        .eq("id", broadcastId);

      return {
        success: false,
        message: `Queue failed at batch ${Math.floor(i / BATCH_SIZE) + 1}: ${insertError.message}. ${insertedCount} notifications queued before failure.`,
      };
    }
    insertedCount += batch.length;
  }

  // All batches inserted successfully - update status to 'queued'
  await supabase
    .schema("internal").from("admin_broadcasts")
    .update({ status: "queued" })
    .eq("id", broadcastId);

  // Trigger edge function and await to ensure it starts
  // If it fails, notifications are still queued and will be picked up
  try {
    await supabase.functions.invoke("send-push-notifications");
  } catch (e) {
    console.error(
      "Failed to trigger push function (notifications still queued):",
      e
    );
  }

  // Log successful broadcast action
  await logAdminAction({
    adminId: user.id,
    adminEmail: user.email ?? "unknown",
    action: "broadcast_sent",
    metadata: {
      broadcast_id: broadcastId,
      title: input.title.trim(),
      target: input.target,
      target_count: targetUserIds.length,
      deeplink: validatedDeeplink,
    },
  });

  // Invalidate audit log cache
  revalidateTag("admin-auditlog", "max");

  return {
    success: true,
    message: `Notification queued for ${targetUserIds.length} user${targetUserIds.length === 1 ? "" : "s"}`,
  };
}
