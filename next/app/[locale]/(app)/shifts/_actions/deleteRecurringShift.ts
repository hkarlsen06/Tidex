"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { logger } from "@/lib/logger";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { verifySession } from "@/data-access/auth";
import { ERRORS } from "@/lib/errors/messages";


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

  // Invalidate cache and revalidate paths
  invalidateAndRevalidate(user.id);
}
