import { NextRequest, NextResponse } from "next/server";
import { createClient, SupabaseClient } from "@supabase/supabase-js";
import { getSession } from "@/data-access/auth";
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
  pro: 5,
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
 * Get admin Supabase client for database operations
 */
function getAdminClient(): SupabaseClient | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) {
    logger.error("Missing Supabase URL or service role key");
    return null;
  }

  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false },
  });
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
 * - iOS: Bearer token in Authorization header
 * - Web: Cookie-based session (fallback)
 */
export async function POST(request: NextRequest) {
  // Try to get user from Authorization header first (iOS)
  // Fall back to cookie-based session (web)
  let user: AuthenticatedUser | null = null;

  const authHeader = request.headers.get("Authorization");
  if (authHeader?.startsWith("Bearer ")) {
    const jwt = authHeader.slice(7);

    // Verify JWT and get user - uses server-side validation
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
    const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!;
    const supabase = createClient(supabaseUrl, supabaseKey);
    const {
      data: { user: supabaseUser },
      error,
    } = await supabase.auth.getUser(jwt);

    if (error || !supabaseUser) {
      logger.warn("Auth error in /api/sharing/manage:", error?.message);
      return NextResponse.json(
        { success: false, error: "Unauthorized" },
        { status: 401 }
      );
    }

    user = supabaseUser;
  } else {
    // Fall back to cookie-based session (web clients)
    const session = await getSession();
    if (!session) {
      return NextResponse.json(
        { success: false, error: "Unauthorized" },
        { status: 401 }
      );
    }
    user = session.user;
  }

  // Get admin client for database operations
  const adminClient = getAdminClient();
  if (!adminClient) {
    return NextResponse.json(
      { success: false, error: "Server configuration error" },
      { status: 500 }
    );
  }

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
  // Check for grandfathered status first
  const { data: profileData } = await adminClient
    .from("profiles")
    .select("is_grandfathered")
    .eq("id", userId)
    .maybeSingle();

  if (profileData?.is_grandfathered) {
    return SHARE_LIMITS.max;
  }

  // Check subscription tier
  const { data: subscriptionData } = await adminClient
    .from("subscriptions")
    .select("tier")
    .eq("user_id", userId)
    .eq("status", "active")
    .maybeSingle();

  const tier = (subscriptionData?.tier as keyof typeof SHARE_LIMITS) || "free";
  return SHARE_LIMITS[tier] || SHARE_LIMITS.free;
}

/**
 * Find a user by email or phone
 */
async function findUserByIdentifier(
  adminClient: SupabaseClient,
  identifier: string
): Promise<{ id: string } | null> {
  const { data: usersData } = await adminClient.auth.admin.listUsers();

  if (!usersData?.users) return null;

  // Check if identifier is email or phone
  const isEmail = identifier.includes("@");

  for (const u of usersData.users) {
    if (isEmail && u.email?.toLowerCase() === identifier.toLowerCase()) {
      return { id: u.id };
    }
    if (!isEmail && u.phone === identifier) {
      return { id: u.id };
    }
  }

  return null;
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
