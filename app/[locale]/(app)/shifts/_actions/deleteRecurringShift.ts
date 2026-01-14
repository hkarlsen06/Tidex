"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { logger } from "@/lib/logger";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { verifySession } from "@/data-access/auth";
import { ERRORS } from "@/lib/errors/messages";
import {
  enqueueDirectNotification,
  generateMutationId,
  getOwnerName,
} from "@/lib/notifications/enqueue";

/**
 * Delete an entire recurring shift from the database
 * - Removes the recurring shift row
 * - Revalidates the shifts page
 */
export async function deleteRecurringShift(recurringId: string): Promise<void> {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  logger.info("deleteRecurringShift: Attempting to delete recurring shift", { recurringId, userId: user.id });

  // First, verify the recurring shift exists and is not deleted
  const { data: existingRecurring, error: fetchError } = await supabase
    .from("recurring_shifts")
    .select("id")
    .eq("id", recurringId)
    .eq("user_id", user.id)
    .is("deleted_at", null) // Only find non-deleted recurring shifts
    .single();

  if (fetchError) {
    logger.error("Failed to find recurring shift for deletion:", fetchError);
    throw new Error(ERRORS.RECURRING_NOT_FOUND);
  }

  logger.info("deleteRecurringShift: Found recurring shift, proceeding with soft delete", { existingRecurring });

  // Soft delete by setting deleted_at
  const { error, count } = await supabase
    .from("recurring_shifts")
    .update({ deleted_at: new Date().toISOString() })
    .eq("id", recurringId)
    .eq("user_id", user.id)
    .is("deleted_at", null); // Only delete if not already deleted

  if (error) {
    logger.error("Failed to delete recurring shift:", error);
    throw new Error(ERRORS.FAILED_TO_DELETE_RECURRING);
  }

  logger.info("deleteRecurringShift: Recurring shift soft deleted successfully", { recurringId, deletedCount: count });

  // Enqueue notification for recurring shift deletion
  const mutationId = generateMutationId();
  const ownerName = getOwnerName(user);

  // Get non-muted viewers for this owner
  const { data: shares } = await supabase
    .from("shift_shares")
    .select("viewer_id")
    .eq("owner_id", user.id)
    .eq("muted", false);

  if (shares && shares.length > 0) {
    const { data: prefs } = await supabase
      .from("notification_preferences")
      .select("user_id, shared_shifts_enabled")
      .in("user_id", shares.map((s) => s.viewer_id));

    const prefsMap = new Map(prefs?.map((p) => [p.user_id, p.shared_shifts_enabled]) ?? []);
    const eligibleViewers = shares
      .map((s) => s.viewer_id)
      .filter((viewerId) => prefsMap.get(viewerId) !== false);

    // Enqueue notifications for each eligible viewer
    await Promise.all(
      eligibleViewers.map((viewerId) =>
        enqueueDirectNotification({
          recipientId: viewerId,
          senderId: user.id,
          notificationType: "recurring_shift_deleted",
          title: `${ownerName} slettet en gjentagende vakt`,
          body: `Vaktmønsteret er fjernet`,
          dataPayload: {
            type: "recurring_shift_deleted",
            owner_id: user.id,
            recurring_id: recurringId,
          },
          idempotencyKey: `recurring:${recurringId}:delete:${viewerId}:${mutationId}`,
        })
      )
    );
  }

  // Invalidate cache and revalidate paths
  invalidateAndRevalidate(user.id);
}
