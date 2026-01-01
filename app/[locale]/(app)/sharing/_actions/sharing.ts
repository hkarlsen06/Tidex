"use server";

import { Effect } from "effect";
import { SharingService, type NotificationFrequency } from "@/lib/services/sharing";
import { SharingLive } from "@/lib/layers/app";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { logger } from "@/lib/logger";
import { verifySession } from "@/data-access/auth";

/**
 * Response type for sharing actions
 */
type ActionResult =
  | { success: true; message?: string }
  | { success: false; error: string };

/**
 * Add sharing error messages to match the project pattern
 */
const SHARING_ERRORS = {
  SHARE_LIMIT_REACHED: "Du har nådd maksimalt antall delinger for ditt abonnement",
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
} as const;

/**
 * Create a new share (add recipient by email or phone)
 *
 * Validates:
 * - User is authenticated
 * - User has not exceeded their subscription tier limit
 * - Target user exists
 * - Share doesn't already exist
 *
 * Returns generic error messages to prevent email enumeration
 */
export async function createShare(
  identifier: string,
  options?: { showEarnings?: boolean }
): Promise<ActionResult> {
  const { user } = await verifySession();

  const trimmed = identifier?.trim();
  if (!trimmed) {
    return { success: false, error: SHARING_ERRORS.INVALID_IDENTIFIER };
  }

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    const result = yield* sharing.createShare(user.id, trimmed, options);
    return result;
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    await Effect.runPromise(program);

    // Invalidate both users' caches (owner and recipient)
    invalidateAndRevalidate(user.id);

    return { success: true };
  } catch (error: any) {
    logger.error("Failed to create share:", error);

    // Map tagged errors to user-friendly messages
    if (error._tag === "ValidationError") {
      if (error.field === "limit") {
        return { success: false, error: SHARING_ERRORS.SHARE_LIMIT_REACHED };
      }
      if (error.field === "identifier") {
        if (error.message?.includes("yourself")) {
          return { success: false, error: SHARING_ERRORS.CANNOT_SHARE_SELF };
        }
        return { success: false, error: SHARING_ERRORS.INVALID_IDENTIFIER };
      }
    }

    if (error._tag === "NotFoundError") {
      // Generic message to prevent email enumeration
      return { success: false, error: SHARING_ERRORS.USER_NOT_FOUND };
    }

    if (error._tag === "ConflictError") {
      return { success: false, error: SHARING_ERRORS.ALREADY_SHARED };
    }

    return { success: false, error: SHARING_ERRORS.FAILED_TO_CREATE_SHARE };
  }
}

/**
 * Remove a share (revoke recipient access)
 *
 * Validates:
 * - User is authenticated
 * - Share exists and user is the owner
 */
export async function removeShare(recipientId: string): Promise<ActionResult> {
  const { user } = await verifySession();

  if (!recipientId) {
    return { success: false, error: SHARING_ERRORS.SHARE_NOT_FOUND };
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

    return { success: true };
  } catch (error: any) {
    logger.error("Failed to remove share:", error);
    return { success: false, error: SHARING_ERRORS.FAILED_TO_REMOVE_SHARE };
  }
}

/**
 * Toggle earnings visibility for a share recipient
 *
 * Validates:
 * - User is authenticated
 * - Share exists and user is the owner
 *
 * When showEarnings is false, recipients will only see hours data,
 * not earnings/wages (enforced server-side in DAL)
 */
export async function toggleShareEarnings(
  recipientId: string,
  showEarnings: boolean
): Promise<ActionResult> {
  const { user } = await verifySession();

  if (!recipientId) {
    return { success: false, error: SHARING_ERRORS.SHARE_NOT_FOUND };
  }

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    yield* sharing.updateShareSettings(user.id, recipientId, { showEarnings });
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    await Effect.runPromise(program);

    // Invalidate caches for both users
    // Owner needs their recipient list updated
    // Recipient needs their shared shifts updated (earnings may be hidden now)
    invalidateAndRevalidate(user.id);
    invalidateAndRevalidate(recipientId);

    return { success: true };
  } catch (error: any) {
    logger.error("Failed to update share settings:", error);
    return { success: false, error: SHARING_ERRORS.FAILED_TO_UPDATE_SETTINGS };
  }
}

/**
 * Block a sharer (hide their shifts from your list)
 *
 * Validates:
 * - User is authenticated
 * - Share relationship exists
 *
 * The share relationship is preserved, just hidden from view.
 * Can be reversed with unblockSharer.
 */
export async function blockSharer(ownerId: string): Promise<ActionResult> {
  const { user } = await verifySession();

  if (!ownerId) {
    return { success: false, error: SHARING_ERRORS.SHARE_NOT_FOUND };
  }

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    yield* sharing.blockSharer(user.id, ownerId);
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    await Effect.runPromise(program);

    // Only invalidate the viewer's cache (the person blocking)
    invalidateAndRevalidate(user.id);

    return { success: true };
  } catch (error: any) {
    logger.error("Failed to block sharer:", error);
    return { success: false, error: SHARING_ERRORS.FAILED_TO_BLOCK_SHARER };
  }
}

/**
 * Unblock a sharer (restore their shifts to your list)
 *
 * Validates:
 * - User is authenticated
 * - Share relationship exists
 *
 * Reverses a previous block action.
 */
export async function unblockSharer(ownerId: string): Promise<ActionResult> {
  const { user } = await verifySession();

  if (!ownerId) {
    return { success: false, error: SHARING_ERRORS.SHARE_NOT_FOUND };
  }

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    yield* sharing.unblockSharer(user.id, ownerId);
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    await Effect.runPromise(program);

    // Only invalidate the viewer's cache (the person unblocking)
    invalidateAndRevalidate(user.id);

    return { success: true };
  } catch (error: any) {
    logger.error("Failed to unblock sharer:", error);
    return { success: false, error: SHARING_ERRORS.FAILED_TO_UNBLOCK_SHARER };
  }
}

/**
 * Share back with someone who has shared with you
 *
 * Validates:
 * - User is authenticated
 * - User has not exceeded their subscription tier limit
 * - Not already sharing with this person
 *
 * Creates a share directly by user ID (no email/phone lookup needed)
 * Defaults earnings visibility to OFF
 */
export async function shareBack(recipientId: string): Promise<ActionResult> {
  const { user } = await verifySession();

  if (!recipientId) {
    return { success: false, error: SHARING_ERRORS.SHARE_NOT_FOUND };
  }

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    yield* sharing.createShareById(user.id, recipientId, { showEarnings: false });
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    await Effect.runPromise(program);

    // Invalidate both users' caches
    invalidateAndRevalidate(user.id);
    invalidateAndRevalidate(recipientId);

    return { success: true };
  } catch (error: any) {
    logger.error("Failed to share back:", error);

    // Map tagged errors to user-friendly messages
    if (error._tag === "ValidationError") {
      if (error.field === "limit") {
        return { success: false, error: SHARING_ERRORS.SHARE_LIMIT_REACHED };
      }
    }

    if (error._tag === "ConflictError") {
      return { success: false, error: SHARING_ERRORS.ALREADY_SHARED };
    }

    return { success: false, error: SHARING_ERRORS.FAILED_TO_SHARE_BACK };
  }
}

/**
 * Refresh the sharing page data
 *
 * Invalidates all cached sharing data for the current user and triggers
 * a revalidation. Use this when manual refresh is needed to see updates
 * (e.g., blocked/unblocked sharers, new shares).
 */
export async function refreshSharingData(): Promise<ActionResult> {
  const { user } = await verifySession();

  try {
    invalidateAndRevalidate(user.id);
    return { success: true };
  } catch (error: any) {
    logger.error("Failed to refresh sharing data:", error);
    return { success: false, error: "Kunne ikke oppdatere data" };
  }
}

/**
 * Update notification frequency for a specific sharer
 *
 * Controls how often you receive notifications about this sharer's shifts:
 * - instant: Notifications sent immediately (within 1-2 minutes)
 * - summary: Daily digest at your configured time (default 18:00)
 * - muted: No notifications from this sender
 */
export async function updateNotificationFrequency(
  ownerId: string,
  frequency: NotificationFrequency
): Promise<ActionResult> {
  const { user } = await verifySession();

  if (!ownerId) {
    return { success: false, error: SHARING_ERRORS.SHARE_NOT_FOUND };
  }

  // Validate frequency value
  if (!["instant", "summary", "muted"].includes(frequency)) {
    return { success: false, error: SHARING_ERRORS.FAILED_TO_UPDATE_FREQUENCY };
  }

  const program = Effect.gen(function* () {
    const sharing = yield* SharingService;
    yield* sharing.updateNotificationFrequency(user.id, ownerId, frequency);
  }).pipe(Effect.provide(SharingLive), Effect.scoped);

  try {
    await Effect.runPromise(program);

    // Invalidate the viewer's cache to update their friends list
    invalidateAndRevalidate(user.id);

    return { success: true };
  } catch (error: any) {
    logger.error("Failed to update notification frequency:", error);
    return { success: false, error: SHARING_ERRORS.FAILED_TO_UPDATE_FREQUENCY };
  }
}

/**
 * Remove a sharer from your friends list (as the viewer)
 *
 * Use this when someone shares with you but you don't want them in your friends list.
 * This deletes the share row entirely, meaning you will no longer see their shifts.
 *
 * Note: This is different from blocking - blocking just hides them from view but
 * preserves the relationship. This removes the relationship entirely.
 *
 * Validates:
 * - User is authenticated
 * - Share relationship exists where user is the viewer
 */
export async function removeSharer(ownerId: string): Promise<ActionResult> {
  const { user } = await verifySession();

  if (!ownerId) {
    return { success: false, error: SHARING_ERRORS.SHARE_NOT_FOUND };
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

    return { success: true };
  } catch (error: any) {
    logger.error("Failed to remove sharer:", error);
    return { success: false, error: SHARING_ERRORS.FAILED_TO_REMOVE_SHARER };
  }
}
