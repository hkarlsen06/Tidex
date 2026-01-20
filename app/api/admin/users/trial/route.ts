import { NextRequest, NextResponse } from 'next/server';
import { createSupabaseServiceClient } from '@/lib/supabase/service';
import { revalidateTag } from 'next/cache';
import { verifyAdminFromRequest, isValidUUID } from '../../_lib/verify-admin';
import { logAdminAction } from '../../_lib/audit-log';

/**
 * POST /api/admin/users/trial
 *
 * Create or revoke a trial subscription for a user.
 *
 * Authentication:
 * - Cookie-based session (web app)
 * - Bearer token in Authorization header (native iOS app)
 * - Requires admin role (app_metadata.role === "admin")
 *
 * Body:
 * - targetUserId: string - The UUID of the target user
 * - targetEmail: string - The email of the target user (for logging)
 * - action: "create" | "revoke" - The action to perform
 * - durationDays?: number - Trial duration in days (default: 7, only for "create")
 *
 * Response:
 * - 200: { success: true, message: string }
 * - 400: { success: false, message: string } - Invalid input or validation error
 * - 401: { error: string } - Not authenticated
 * - 500: { success: false, message: string } - Server error
 */

const DEFAULT_TRIAL_DAYS = 7;

interface TrialRequestBody {
  targetUserId: string;
  targetEmail: string;
  action: 'create' | 'revoke';
  durationDays?: number;
}

export async function POST(request: NextRequest) {
  try {
    // Verify admin authentication
    const adminResult = await verifyAdminFromRequest(request);

    if (!adminResult) {
      return NextResponse.json(
        { error: 'Not authenticated or not an admin' },
        { status: 401 }
      );
    }

    const { user: admin } = adminResult;
    const adminEmail = admin.email ?? 'unknown';

    // Parse request body
    let body: TrialRequestBody;
    try {
      body = await request.json();
    } catch {
      return NextResponse.json(
        { success: false, message: 'Invalid JSON body' },
        { status: 400 }
      );
    }

    const { targetUserId, targetEmail, action, durationDays } = body;

    // Validate required fields
    if (!targetUserId || typeof targetUserId !== 'string') {
      return NextResponse.json(
        { success: false, message: 'Missing or invalid targetUserId' },
        { status: 400 }
      );
    }

    if (!targetEmail || typeof targetEmail !== 'string') {
      return NextResponse.json(
        { success: false, message: 'Missing or invalid targetEmail' },
        { status: 400 }
      );
    }

    if (!action || !['create', 'revoke'].includes(action)) {
      return NextResponse.json(
        { success: false, message: 'Invalid action. Must be "create" or "revoke"' },
        { status: 400 }
      );
    }

    // Validate UUID format
    if (!isValidUUID(targetUserId)) {
      await logAdminAction({
        adminId: admin.id,
        adminEmail,
        action: 'admin_action_failed',
        targetId: undefined,
        targetEmail,
        metadata: {
          error: 'Invalid User ID format',
          intended_action: action === 'create' ? 'create_trial_subscription' : 'revoke_trial_subscription',
        },
      });
      return NextResponse.json(
        { success: false, message: 'Invalid user ID format' },
        { status: 400 }
      );
    }

    if (action === 'create') {
      return handleCreateTrial(admin.id, adminEmail, targetUserId, targetEmail, durationDays);
    } else {
      return handleRevokeTrial(admin.id, adminEmail, targetUserId, targetEmail);
    }
  } catch (error) {
    console.error('[admin/users/trial] Exception:', error);
    return NextResponse.json(
      { success: false, message: 'Internal server error' },
      { status: 500 }
    );
  }
}

async function handleCreateTrial(
  adminId: string,
  adminEmail: string,
  targetUserId: string,
  targetEmail: string,
  durationDays?: number
): Promise<NextResponse> {
  const supabase = createSupabaseServiceClient();
  const trialDays = durationDays ?? DEFAULT_TRIAL_DAYS;

  // Check if user already has a subscription row
  const { data: existingSub } = await supabase
    .from('subscriptions')
    .select('id, provider, status, current_period_end, stripe_customer_id')
    .eq('user_id', targetUserId)
    .single();

  if (existingSub) {
    // Check if current_period_end is in the future and it's a paid subscription
    const isActivePaid =
      existingSub.provider !== 'admin_trial' &&
      (existingSub.status === 'active' ||
        existingSub.status === 'trialing' ||
        existingSub.status === 'grace') &&
      (!existingSub.current_period_end ||
        new Date(existingSub.current_period_end) > new Date());

    if (isActivePaid) {
      await logAdminAction({
        adminId,
        adminEmail,
        action: 'admin_action_failed',
        targetId: targetUserId,
        targetEmail,
        metadata: {
          error: 'User already has an active paid subscription',
          intended_action: 'create_trial_subscription',
          existing_subscription: {
            provider: existingSub.provider,
            status: existingSub.status,
          },
        },
      });
      return NextResponse.json({
        success: false,
        message: 'User already has an active paid subscription',
      });
    }
  }

  // Calculate period dates
  const now = new Date();
  const expiresAt = new Date(now);
  expiresAt.setDate(expiresAt.getDate() + trialDays);

  // Create unique subscription ID
  const subscriptionId = `admin_trial_${targetUserId}_${Date.now()}`;

  // Product ID based on duration
  const productId = `admin_trial_${trialDays}d`;

  let dbError: { message: string } | null = null;

  if (existingSub) {
    // User has existing subscription row - update it, preserving stripe_customer_id
    const { error } = await supabase
      .from('subscriptions')
      .update({
        provider: 'admin_trial',
        provider_subscription_id: subscriptionId,
        status: 'active',
        product_id: productId,
        current_period_start: now.toISOString(),
        current_period_end: expiresAt.toISOString(),
        updated_at: now.toISOString(),
        cancel_at_period_end: true,
        cancellation_reason: 'Free trial only',
        // Don't update stripe_customer_id - keep existing value
      })
      .eq('user_id', targetUserId);
    dbError = error;
  } else {
    // No existing subscription - insert new row
    const { error } = await supabase.from('subscriptions').insert({
      user_id: targetUserId,
      provider: 'admin_trial',
      provider_subscription_id: subscriptionId,
      status: 'active',
      product_id: productId,
      current_period_start: now.toISOString(),
      current_period_end: expiresAt.toISOString(),
      created_at: now.toISOString(),
      updated_at: now.toISOString(),
      cancel_at_period_end: true,
      cancellation_reason: 'Free trial only',
      // Generate a valid stripe_customer_id for new subscriptions
      stripe_customer_id: `cus_admintrial${targetUserId.replace(/-/g, '').slice(0, 8)}`,
    });
    dbError = error;
  }

  if (dbError) {
    await logAdminAction({
      adminId,
      adminEmail,
      action: 'admin_action_failed',
      targetId: targetUserId,
      targetEmail,
      metadata: {
        error: dbError.message,
        intended_action: 'create_trial_subscription',
      },
    });
    return NextResponse.json(
      { success: false, message: 'Failed to create trial subscription' },
      { status: 500 }
    );
  }

  // Log successful action
  await logAdminAction({
    adminId,
    adminEmail,
    action: 'create_trial_subscription',
    targetId: targetUserId,
    targetEmail,
    metadata: {
      duration_days: trialDays,
      expires_at: expiresAt.toISOString(),
      product_id: productId,
    },
  });

  // Invalidate caches
  revalidateTag(`user-${targetUserId}`, 'max');
  revalidateTag('admin-subscribers', 'max');
  revalidateTag('admin-auditlog', 'max');

  return NextResponse.json({
    success: true,
    message: `Trial subscription created (${trialDays} days)`,
  });
}

async function handleRevokeTrial(
  adminId: string,
  adminEmail: string,
  targetUserId: string,
  targetEmail: string
): Promise<NextResponse> {
  const supabase = createSupabaseServiceClient();

  // Find the active admin trial subscription
  const { data: trial, error: fetchError } = await supabase
    .from('subscriptions')
    .select('id, status, current_period_end')
    .eq('user_id', targetUserId)
    .eq('provider', 'admin_trial')
    .eq('status', 'active')
    .single();

  if (fetchError || !trial) {
    await logAdminAction({
      adminId,
      adminEmail,
      action: 'admin_action_failed',
      targetId: targetUserId,
      targetEmail,
      metadata: {
        error: fetchError?.message ?? 'No active admin trial found',
        intended_action: 'revoke_trial_subscription',
      },
    });
    return NextResponse.json({
      success: false,
      message: 'No active trial subscription found',
    });
  }

  const now = new Date().toISOString();

  // Revoke the trial by setting status to canceled
  const { error: updateError } = await supabase
    .from('subscriptions')
    .update({
      status: 'canceled',
      canceled_at: now,
      updated_at: now,
    })
    .eq('id', trial.id);

  if (updateError) {
    await logAdminAction({
      adminId,
      adminEmail,
      action: 'admin_action_failed',
      targetId: targetUserId,
      targetEmail,
      metadata: {
        error: updateError.message,
        intended_action: 'revoke_trial_subscription',
        subscription_id: trial.id,
      },
    });
    return NextResponse.json(
      { success: false, message: 'Failed to revoke trial subscription' },
      { status: 500 }
    );
  }

  // Log successful action
  await logAdminAction({
    adminId,
    adminEmail,
    action: 'revoke_trial_subscription',
    targetId: targetUserId,
    targetEmail,
    metadata: {
      old_value: {
        status: trial.status,
        current_period_end: trial.current_period_end,
      },
      new_value: {
        status: 'canceled',
        canceled_at: now,
      },
    },
  });

  // Invalidate caches
  revalidateTag(`user-${targetUserId}`, 'max');
  revalidateTag('admin-subscribers', 'max');
  revalidateTag('admin-auditlog', 'max');

  return NextResponse.json({
    success: true,
    message: 'Trial subscription revoked',
  });
}
