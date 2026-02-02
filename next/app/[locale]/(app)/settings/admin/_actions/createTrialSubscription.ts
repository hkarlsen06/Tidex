"use server";

import { verifyAdmin } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";
import { revalidateTag } from "next/cache";
import type { AdminAction } from "@/lib/admin/action-labels";

interface CreateTrialInput {
  targetUserId: string;
  targetEmail: string;
  durationDays?: number;
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

const DEFAULT_TRIAL_DAYS = 30;

export async function createTrialSubscription(input: CreateTrialInput) {
  const { user } = await verifyAdmin();
  const supabase = createSupabaseServiceClient();
  const adminEmail = user.email ?? "unknown";

  const durationDays = input.durationDays ?? DEFAULT_TRIAL_DAYS;

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
        intended_action: "create_trial_subscription",
      },
    });
    return { success: false, message: "Ugyldig bruker-ID format" };
  }

  // Check if user already has a subscription row
  const { data: existingSub } = await supabase
    .from("subscriptions")
    .select("id, provider, status, current_period_end, stripe_customer_id")
    .eq("user_id", input.targetUserId)
    .single();

  if (existingSub) {
    // Check if current_period_end is in the future and it's a paid subscription
    const isActivePaid =
      existingSub.provider !== "admin_trial" &&
      (existingSub.status === "active" ||
        existingSub.status === "trialing" ||
        existingSub.status === "grace") &&
      (!existingSub.current_period_end ||
        new Date(existingSub.current_period_end) > new Date());

    if (isActivePaid) {
      await logAdminAction({
        adminId: user.id,
        adminEmail,
        action: "admin_action_failed",
        targetId: input.targetUserId,
        targetEmail: input.targetEmail,
        metadata: {
          error: "User already has an active paid subscription",
          intended_action: "create_trial_subscription",
          existing_subscription: {
            provider: existingSub.provider,
            status: existingSub.status,
          },
        },
      });
      return {
        success: false,
        message: "Bruker har allerede et aktivt betalt abonnement",
      };
    }
  }

  // Calculate period dates
  const now = new Date();
  const expiresAt = new Date(now);
  expiresAt.setDate(expiresAt.getDate() + durationDays);

  // Create unique subscription ID
  const subscriptionId = `admin_trial_${input.targetUserId}_${Date.now()}`;

  let dbError: { message: string } | null = null;

  if (existingSub) {
    // User has existing subscription row - update it, preserving stripe_customer_id
    const { error } = await supabase
      .from("subscriptions")
      .update({
        provider: "admin_trial",
        provider_subscription_id: subscriptionId,
        status: "active",
        product_id: "pro_monthly",
        current_period_start: now.toISOString(),
        current_period_end: expiresAt.toISOString(),
        updated_at: now.toISOString(),
        cancel_at_period_end: true,
        cancellation_reason: "Free trial only",
        // Don't update stripe_customer_id - keep existing value
      })
      .eq("user_id", input.targetUserId);
    dbError = error;
  } else {
    // No existing subscription - insert new row
    const { error } = await supabase.from("subscriptions").insert({
      user_id: input.targetUserId,
      provider: "admin_trial",
      provider_subscription_id: subscriptionId,
      status: "active",
      product_id: "pro_monthly",
      current_period_start: now.toISOString(),
      current_period_end: expiresAt.toISOString(),
      created_at: now.toISOString(),
      updated_at: now.toISOString(),
      cancel_at_period_end: true,
      cancellation_reason: "Free trial only",
      // Generate a valid stripe_customer_id for new subscriptions
      stripe_customer_id: `cus_admintrial${input.targetUserId.replace(/-/g, "").slice(0, 8)}`,
    });
    dbError = error;
  }

  if (dbError) {
    await logAdminAction({
      adminId: user.id,
      adminEmail,
      action: "admin_action_failed",
      targetId: input.targetUserId,
      targetEmail: input.targetEmail,
      metadata: {
        error: dbError.message,
        intended_action: "create_trial_subscription",
      },
    });
    return { success: false, message: "Kunne ikke opprette prøveperiode" };
  }

  // Log successful action
  await logAdminAction({
    adminId: user.id,
    adminEmail,
    action: "create_trial_subscription",
    targetId: input.targetUserId,
    targetEmail: input.targetEmail,
    metadata: {
      duration_days: durationDays,
      expires_at: expiresAt.toISOString(),
    },
  });

  // Invalidate caches
  revalidateTag(`user-${input.targetUserId}`, "max");
  revalidateTag("admin-subscribers", "max");
  revalidateTag("admin-auditlog", "max");

  return {
    success: true,
    message: `Prøveperiode opprettet (${durationDays} dager)`,
  };
}
