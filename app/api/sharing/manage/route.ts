import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { Effect } from "effect";
import { SharingService, type NotificationFrequency } from "@/lib/services/sharing";
import { SharingLive } from "@/lib/layers/app";
import { getSession } from "@/data-access/auth";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { logger } from "@/lib/logger";
import {
  enqueueDirectNotification,
  generateMutationId,
  getOwnerName,
} from "@/lib/notifications/enqueue";

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
  FAILED_TO_REMOVE_SHARE: "Kunne ikke fjerne deling",
  SHARE_NOT_FOUND: "Fant ikke delingen",
  FAILED_TO_UPDATE_SETTINGS: "Kunne ikke oppdatere innstillinger",
  FAILED_TO_BLOCK_SHARER: "Kunne ikke skjule brukeren",
  FAILED_TO_UNBLOCK_SHARER: "Kunne ikke fjerne skjuling",
  FAILED_TO_SHARE_BACK: "Kunne ikke dele tilbake",
  FAILED_TO_UPDATE_FREQUENCY: "Kunne ikke oppdatere varslingsfrekvens",
  FAILED_TO_REMOVE_SHARER: "Kunne ikke fjerne personen fra vennelisten",
  INVALID_ACTION: "Ugyldig handling",
} as const;

type ActionType =
  | "createShare"
  | "removeShare"
  | "removeSharer"
  | "toggleEarnings"
  | "blockSharer"
  | "unblockSharer"
  | "shareBack"
  | "toggleMuted";

interface ManageRequest {
  action: ActionType;
  identifier?: string; // For createShare (email/phone)
  recipientId?: string; // For removeShare, toggleEarnings, shareBack
  ownerId?: string; // For removeSharer, blockSharer, unblockSharer, toggleMuted
  showEarnings?: boolean; // For createShare, toggleEarnings
  muted?: boolean; // For toggleMuted
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
 * Unified endpoint for all sharing management actions.
 * Used by the iOS app's sharing management modal.
 *
 * Authentication:
 * - iOS: Bearer token in Authorization header
 * - Web: Cookie-based session (fallback)
 *
 * Request body:
 * {
 *   action: "createShare" | "removeShare" | "removeSharer" | "toggleEarnings" |
 *           "blockSharer" | "unblockSharer" | "shareBack" | "toggleMuted",
 *   identifier?: string,      // For createShare
 *   recipientId?: string,     // For removeShare, toggleEarnings, shareBack
 *   ownerId?: string,         // For removeSharer, blockSharer, unblockSharer, toggleMuted
 *   showEarnings?: boolean,   // For createShare, toggleEarnings
 *   muted?: boolean           // For toggleMuted
 * }
 *
 * Response:
 * { success: true } or { success: false, error: string }
 */
export async function POST(request: NextRequest) {
  try {
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

    // Parse request body
    const body: ManageRequest = await request.json();
    const { action } = body;

    if (!action) {
      return NextResponse.json(
        { success: false, error: SHARING_ERRORS.INVALID_ACTION },
        { status: 400 }
      );
    }

    logger.info(`Processing sharing action: ${action} for user ${user.id}`);

    switch (action) {
      case "createShare":
        return handleCreateShare(user, body);
      case "removeShare":
        return handleRemoveShare(user, body);
      case "removeSharer":
        return handleRemoveSharer(user, body);
      case "toggleEarnings":
        return handleToggleEarnings(user, body);
      case "blockSharer":
        return handleBlockSharer(user, body);
      case "unblockSharer":
        return handleUnblockSharer(user, body);
      case "shareBack":
        return handleShareBack(user, body);
      case "toggleMuted":
        return handleToggleMuted(user, body);
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
 * Create a new share (add recipient by email or phone)
 */
async function handleCreateShare(
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

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    const result = yield* sharing.createShare(user.id, trimmed, {
      showEarnings: showEarnings ?? false,
    });
    return result;
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    const result = await Effect.runPromise(program);

    // Enqueue share_started notification to the recipient
    const mutationId = generateMutationId();
    const ownerName = getOwnerName(user);

    await enqueueDirectNotification({
      recipientId: result.recipientId,
      senderId: user.id,
      notificationType: "share_started",
      title: `${ownerName} deler nå vaktene sine med deg`,
      body: "Trykk for å se vaktene",
      dataPayload: {
        type: "share_started",
        owner_id: user.id,
      },
      idempotencyKey: `share:${user.id}:${result.recipientId}:${mutationId}`,
    });

    // Invalidate both users' caches
    invalidateAndRevalidate(user.id);

    return NextResponse.json({ success: true });
  } catch (error: any) {
    logger.error("Failed to create share:", error);

    // Map tagged errors to user-friendly messages
    if (error._tag === "ValidationError") {
      if (error.field === "limit") {
        return NextResponse.json(
          { success: false, error: SHARING_ERRORS.SHARE_LIMIT_REACHED },
          { status: 400 }
        );
      }
      if (error.field === "identifier") {
        if (error.message?.includes("yourself")) {
          return NextResponse.json(
            { success: false, error: SHARING_ERRORS.CANNOT_SHARE_SELF },
            { status: 400 }
          );
        }
        return NextResponse.json(
          { success: false, error: SHARING_ERRORS.INVALID_IDENTIFIER },
          { status: 400 }
        );
      }
    }

    if (error._tag === "NotFoundError") {
      return NextResponse.json(
        { success: false, error: SHARING_ERRORS.USER_NOT_FOUND },
        { status: 404 }
      );
    }

    if (error._tag === "ConflictError") {
      return NextResponse.json(
        { success: false, error: SHARING_ERRORS.ALREADY_SHARED },
        { status: 409 }
      );
    }

    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.FAILED_TO_CREATE_SHARE },
      { status: 500 }
    );
  }
}

/**
 * Remove a share (revoke recipient access)
 */
async function handleRemoveShare(
  user: AuthenticatedUser,
  body: ManageRequest
): Promise<NextResponse> {
  const { recipientId } = body;

  if (!recipientId) {
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.SHARE_NOT_FOUND },
      { status: 400 }
    );
  }

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    yield* sharing.removeShare(user.id, recipientId);
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    await Effect.runPromise(program);

    // Invalidate both users' caches
    invalidateAndRevalidate(user.id);
    invalidateAndRevalidate(recipientId);

    return NextResponse.json({ success: true });
  } catch (error: any) {
    logger.error("Failed to remove share:", error);
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.FAILED_TO_REMOVE_SHARE },
      { status: 500 }
    );
  }
}

/**
 * Remove a sharer from your friends list (as the viewer)
 */
async function handleRemoveSharer(
  user: AuthenticatedUser,
  body: ManageRequest
): Promise<NextResponse> {
  const { ownerId } = body;

  if (!ownerId) {
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.SHARE_NOT_FOUND },
      { status: 400 }
    );
  }

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    yield* sharing.removeSharerAsViewer(user.id, ownerId);
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    await Effect.runPromise(program);

    // Invalidate both users' caches
    invalidateAndRevalidate(user.id);
    invalidateAndRevalidate(ownerId);

    return NextResponse.json({ success: true });
  } catch (error: any) {
    logger.error("Failed to remove sharer:", error);
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.FAILED_TO_REMOVE_SHARER },
      { status: 500 }
    );
  }
}

/**
 * Toggle earnings visibility for a share recipient
 */
async function handleToggleEarnings(
  user: AuthenticatedUser,
  body: ManageRequest
): Promise<NextResponse> {
  const { recipientId, showEarnings } = body;

  if (!recipientId || showEarnings === undefined) {
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.SHARE_NOT_FOUND },
      { status: 400 }
    );
  }

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    yield* sharing.updateShareSettings(user.id, recipientId, { showEarnings });
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    await Effect.runPromise(program);

    // Invalidate both users' caches
    invalidateAndRevalidate(user.id);
    invalidateAndRevalidate(recipientId);

    return NextResponse.json({ success: true });
  } catch (error: any) {
    logger.error("Failed to update share settings:", error);
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.FAILED_TO_UPDATE_SETTINGS },
      { status: 500 }
    );
  }
}

/**
 * Block a sharer (hide their shifts from your list)
 */
async function handleBlockSharer(
  user: AuthenticatedUser,
  body: ManageRequest
): Promise<NextResponse> {
  const { ownerId } = body;

  if (!ownerId) {
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.SHARE_NOT_FOUND },
      { status: 400 }
    );
  }

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    yield* sharing.blockSharer(user.id, ownerId);
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    await Effect.runPromise(program);

    // Only invalidate the viewer's cache
    invalidateAndRevalidate(user.id);

    return NextResponse.json({ success: true });
  } catch (error: any) {
    logger.error("Failed to block sharer:", error);
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.FAILED_TO_BLOCK_SHARER },
      { status: 500 }
    );
  }
}

/**
 * Unblock a sharer (restore their shifts to your list)
 */
async function handleUnblockSharer(
  user: AuthenticatedUser,
  body: ManageRequest
): Promise<NextResponse> {
  const { ownerId } = body;

  if (!ownerId) {
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.SHARE_NOT_FOUND },
      { status: 400 }
    );
  }

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    yield* sharing.unblockSharer(user.id, ownerId);
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    await Effect.runPromise(program);

    // Only invalidate the viewer's cache
    invalidateAndRevalidate(user.id);

    return NextResponse.json({ success: true });
  } catch (error: any) {
    logger.error("Failed to unblock sharer:", error);
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.FAILED_TO_UNBLOCK_SHARER },
      { status: 500 }
    );
  }
}

/**
 * Share back with someone who has shared with you
 */
async function handleShareBack(
  user: AuthenticatedUser,
  body: ManageRequest
): Promise<NextResponse> {
  const { recipientId } = body;

  if (!recipientId) {
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.SHARE_NOT_FOUND },
      { status: 400 }
    );
  }

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    yield* sharing.createShareById(user.id, recipientId, {
      showEarnings: false,
    });
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    await Effect.runPromise(program);

    // Enqueue share_started notification to the recipient
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

    // Invalidate both users' caches
    invalidateAndRevalidate(user.id);
    invalidateAndRevalidate(recipientId);

    return NextResponse.json({ success: true });
  } catch (error: any) {
    logger.error("Failed to share back:", error);

    // Map tagged errors
    if (error._tag === "ValidationError" && error.field === "limit") {
      return NextResponse.json(
        { success: false, error: SHARING_ERRORS.SHARE_LIMIT_REACHED },
        { status: 400 }
      );
    }

    if (error._tag === "ConflictError") {
      return NextResponse.json(
        { success: false, error: SHARING_ERRORS.ALREADY_SHARED },
        { status: 409 }
      );
    }

    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.FAILED_TO_SHARE_BACK },
      { status: 500 }
    );
  }
}

/**
 * Toggle muted status for a specific sharer
 */
async function handleToggleMuted(
  user: AuthenticatedUser,
  body: ManageRequest
): Promise<NextResponse> {
  const { ownerId, muted } = body;

  if (!ownerId || muted === undefined) {
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.SHARE_NOT_FOUND },
      { status: 400 }
    );
  }

  // Convert boolean to frequency
  const frequency: NotificationFrequency = muted ? "muted" : "instant";

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    yield* sharing.updateNotificationFrequency(user.id, ownerId, frequency);
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    await Effect.runPromise(program);

    // Invalidate the viewer's cache
    invalidateAndRevalidate(user.id);

    return NextResponse.json({ success: true });
  } catch (error: any) {
    logger.error("Failed to toggle sharer muted status:", error);
    return NextResponse.json(
      { success: false, error: SHARING_ERRORS.FAILED_TO_UPDATE_FREQUENCY },
      { status: 500 }
    );
  }
}
