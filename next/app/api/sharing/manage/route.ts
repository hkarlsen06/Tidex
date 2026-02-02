import { NextRequest, NextResponse } from "next/server";
import { SupabaseClient } from "@supabase/supabase-js";
import { getSession } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { logger } from "@/lib/logger";
import {
  enqueueDirectNotification,
  generateMutationId,
  getOwnerName,
} from "@/lib/notifications/enqueue";

// Share limits per subscription tier
const SHARE_LIMITS = {
  free: 1,
  pro: 10,
  max: 20,
} as const;

/**
 * Sharing error messages (Norwegian)
 */
const SHARING_ERRORS = {
  SHARE_LIMIT_REACHED:
    "Du har nådd maksimalt antall delinger for ditt abonnement",
  USER_NOT_FOUND: "Fant ingen bruker med denne e-posten eller telefonnummeret",
  ALREADY_SHARED: "Du deler allerede vaktene dine med denne brukeren",
  CANNOT_SHARE_SELF: "Du kan ikke dele med deg selv",
  INVALID_IDENTIFIER: "Vennligst oppgi en gyldig e-post eller telefonnummer",
  FAILED_TO_CREATE_SHARE: "Kunne ikke opprette deling",
  FAILED_TO_SHARE_BACK: "Kunne ikke dele tilbake",
  INVALID_ACTION: "Ugyldig handling",
} as const;

// Only actions that require server-side logic (user lookup, notifications)
// Other actions (toggleEarnings, block/unblock, muted, remove) are handled
// directly via Supabase from the iOS app using RLS policies
type ActionType = "createShare" | "shareBack";

interface ManageRequest {
  action: ActionType;
  identifier?: string; // For createShare (email/phone)
  recipientId?: string; // For shareBack
  showEarnings?: boolean; // For createShare
}

// User type for handlers - includes optional fields for notification handling
interface AuthenticatedUser {
  id: string;
  email?: string;
  user_metadata?: Record<string, unknown>;
}

/**
 * POST /api/sharing/manage
 *
 * Handles sharing actions that require server-side logic:
 * - createShare: User lookup by email/phone, limit checks, notifications
 * - shareBack: Limit checks, notifications
 *
 * Other actions (toggleEarnings, block/unblock, muted, remove) are handled
 * directly via Supabase from the iOS app using RLS policies.
 *
 * Authentication:
 * - Bearer token in Authorization header (native iOS app) - handled by getSession
 * - Cookie-based session (web app) - handled by getSession
 */
export async function POST(request: NextRequest) {
  // getSession handles both Bearer tokens (iOS) and cookies (web)
  const session = await getSession();
  if (!session) {
    return NextResponse.json(
      { success: false, error: "Unauthorized" },
      { status: 401 }
    );
  }

  const user: AuthenticatedUser = session.user;

  // Get service client for database operations
  const adminClient = createSupabaseServiceClient();

  // Parse request body
  let body: ManageRequest;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.INVALID_ACTION },
      { status: 400 }
    );
  }

  const { action } = body;

  if (!action) {
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.INVALID_ACTION },
      { status: 400 }
    );
  }

  logger.info(`Processing sharing action: ${action} for user ${user.id}`);

  try {
    switch (action) {
      case "createShare":
        return await handleCreateShare(adminClient, user, body);
      case "shareBack":
        return await handleShareBack(adminClient, user, body);
      default:
        return NextResponse.json(
          { success: false, error: SHARING_ERRORS.INVALID_ACTION },
          { status: 400 }
        );
    }
  } catch (error: any) {
    logger.error("Error in /api/sharing/manage:", error);
    return NextResponse.json(
      { success: false, error: "Internal server error" },
      { status: 500 }
    );
  }
}

/**
 * Get user's share limit based on subscription tier
 */
async function getUserShareLimit(
  adminClient: SupabaseClient,
  userId: string
): Promise<number> {
  // Use user_entitlements view (single source of truth for tier)
  const { data: entitlementData } = await adminClient
    .from("user_entitlements")
    .select("tier")
    .eq("user_id", userId)
    .maybeSingle();

  const tier = (entitlementData?.tier as keyof typeof SHARE_LIMITS) || "free";
  return SHARE_LIMITS[tier] || SHARE_LIMITS.free;
}

/**
 * Normalize phone number to E.164 format (47xxxxxxxx for Norwegian numbers)
 */
function normalizePhoneNumber(phone: string): string {
  // Remove all non-digit characters
  const digits = phone.replace(/\D/g, "");

  // If 8 digits, assume Norwegian and add country code
  if (digits.length === 8) {
    return `47${digits}`;
  }

  // If starts with + and has country code, just return digits
  if (phone.startsWith("+")) {
    return digits;
  }

  // If starts with 00 (international prefix), remove it
  if (digits.startsWith("00")) {
    return digits.slice(2);
  }

  return digits;
}

/**
 * Find a user by email or phone using direct database queries
 */
async function findUserByIdentifier(
  adminClient: SupabaseClient,
  identifier: string
): Promise<{ id: string } | null> {
  const isEmail = identifier.includes("@");

  if (isEmail) {
    // Direct lookup by email (case-insensitive)
    const { data, error } = await adminClient.rpc("find_user_by_email", {
      search_email: identifier.toLowerCase(),
    });

    if (error) {
      logger.error("Error finding user by email:", error);
      return null;
    }

    return data ? { id: data } : null;
  } else {
    // Normalize phone and lookup directly
    const normalizedPhone = normalizePhoneNumber(identifier);

    const { data, error } = await adminClient.rpc("find_user_by_phone", {
      search_phone: normalizedPhone,
    });

    if (error) {
      logger.error("Error finding user by phone:", error);
      return null;
    }

    return data ? { id: data } : null;
  }
}

/**
 * Create a new share (add recipient by email or phone)
 */
async function handleCreateShare(
  adminClient: SupabaseClient,
  user: AuthenticatedUser,
  body: ManageRequest
): Promise<NextResponse> {
  const { identifier, showEarnings } = body;

  const trimmed = identifier?.trim();
  if (!trimmed) {
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.INVALID_IDENTIFIER },
      { status: 400 }
    );
  }

  // Find recipient user
  const recipientUser = await findUserByIdentifier(adminClient, trimmed);
  if (!recipientUser) {
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.USER_NOT_FOUND },
      { status: 404 }
    );
  }

  // Can't share with yourself
  if (recipientUser.id === user.id) {
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.CANNOT_SHARE_SELF },
      { status: 400 }
    );
  }

  // Check share limit
  const limit = await getUserShareLimit(adminClient, user.id);
  const { count } = await adminClient
    .from("shift_shares")
    .select("*", { count: "exact", head: true })
    .eq("owner_id", user.id);

  if ((count || 0) >= limit) {
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.SHARE_LIMIT_REACHED },
      { status: 400 }
    );
  }

  // Check if already shared
  const { data: existingShare } = await adminClient
    .from("shift_shares")
    .select("id")
    .eq("owner_id", user.id)
    .eq("viewer_id", recipientUser.id)
    .maybeSingle();

  if (existingShare) {
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.ALREADY_SHARED },
      { status: 409 }
    );
  }

  // Create the share
  const { error: insertError } = await adminClient.from("shift_shares").insert({
    owner_id: user.id,
    viewer_id: recipientUser.id,
    show_earnings: showEarnings ?? false,
  });

  if (insertError) {
    logger.error("Failed to create share:", insertError);
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.FAILED_TO_CREATE_SHARE },
      { status: 500 }
    );
  }

  // Enqueue share_started notification to the recipient
  try {
    const mutationId = generateMutationId();
    const ownerName = getOwnerName(user);

    await enqueueDirectNotification({
      recipientId: recipientUser.id,
      senderId: user.id,
      notificationType: "share_started",
      title: `${ownerName} deler nå vaktene sine med deg`,
      body: "Trykk for å se vaktene",
      dataPayload: {
        type: "share_started",
        owner_id: user.id,
      },
      idempotencyKey: `share:${user.id}:${recipientUser.id}:${mutationId}`,
    });
  } catch (notifError) {
    // Don't fail the share creation if notification fails
    logger.warn("Failed to enqueue share notification:", notifError);
  }

  // Invalidate caches
  invalidateAndRevalidate(user.id);

  return NextResponse.json({ success: true });
}

/**
 * Share back with someone who has shared with you
 */
async function handleShareBack(
  adminClient: SupabaseClient,
  user: AuthenticatedUser,
  body: ManageRequest
): Promise<NextResponse> {
  const { recipientId } = body;

  if (!recipientId) {
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.INVALID_ACTION },
      { status: 400 }
    );
  }

  // Check share limit
  const limit = await getUserShareLimit(adminClient, user.id);
  const { count } = await adminClient
    .from("shift_shares")
    .select("*", { count: "exact", head: true })
    .eq("owner_id", user.id);

  if ((count || 0) >= limit) {
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.SHARE_LIMIT_REACHED },
      { status: 400 }
    );
  }

  // Check if already shared
  const { data: existingShare } = await adminClient
    .from("shift_shares")
    .select("id")
    .eq("owner_id", user.id)
    .eq("viewer_id", recipientId)
    .maybeSingle();

  if (existingShare) {
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.ALREADY_SHARED },
      { status: 409 }
    );
  }

  // Create the share
  const { error: insertError } = await adminClient.from("shift_shares").insert({
    owner_id: user.id,
    viewer_id: recipientId,
    show_earnings: false,
  });

  if (insertError) {
    logger.error("Failed to share back:", insertError);
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.FAILED_TO_SHARE_BACK },
      { status: 500 }
    );
  }

  // Enqueue share_started notification to the recipient
  try {
    const mutationId = generateMutationId();
    const ownerName = getOwnerName(user);

    await enqueueDirectNotification({
      recipientId,
      senderId: user.id,
      notificationType: "share_started",
      title: `${ownerName} deler nå vaktene sine med deg`,
      body: "Trykk for å se vaktene",
      dataPayload: {
        type: "share_started",
        owner_id: user.id,
      },
      idempotencyKey: `share:${user.id}:${recipientId}:${mutationId}`,
    });
  } catch (notifError) {
    // Don't fail the share creation if notification fails
    logger.warn("Failed to enqueue share notification:", notifError);
  }

  // Invalidate caches
  invalidateAndRevalidate(user.id);
  invalidateAndRevalidate(recipientId);

  return NextResponse.json({ success: true });
}
