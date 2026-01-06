"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { logger } from "@/lib/logger";
import { verifySession } from "@/data-access/auth";
import { ERRORS } from "@/lib/errors/messages";
import {
  enqueueShiftNotification,
  generateMutationId,
  getOwnerName,
} from "@/lib/notifications/enqueue";

type DeleteShiftInput = {
  shiftId: string;
  recurringId?: string; // Present if this is a recurring virtual shift
  shiftDate?: string; // ISO date, needed if recurring virtual shift
};

export async function deleteShift(input: string | DeleteShiftInput) {
  // Handle both legacy string input and new object input
  const shiftId = typeof input === "string" ? input : input.shiftId;
  const recurringId = typeof input === "string" ? undefined : input.recurringId;
  const shiftDate = typeof input === "string" ? undefined : input.shiftDate;

  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  if (!shiftId) throw new Error(ERRORS.INVALID_SHIFT_ID);

  // Case 1: Deleting a recurring virtual shift - add to exclusions instead
  if (recurringId && shiftDate) {
    const { data: recurring, error: recurringError } = await supabase
      .from("recurring_shifts")
      .select("exclusions, start_time, end_time")
      .eq("id", recurringId)
      .eq("user_id", user.id)
      .single();

    if (recurringError || !recurring) {
      logger.error("Failed to load recurring shift for deletion:", recurringError);
      throw new Error(ERRORS.FAILED_TO_LOAD_RECURRING);
    }

    const currentExclusions = recurring.exclusions || [];
    const updatedExclusions = currentExclusions.includes(shiftDate)
      ? currentExclusions
      : [...currentExclusions, shiftDate];

    const { error: updateError } = await supabase
      .from("recurring_shifts")
      .update({ exclusions: updatedExclusions })
      .eq("id", recurringId)
      .eq("user_id", user.id);

    if (updateError) {
      logger.error("Failed to update recurring shift exclusions:", updateError);
      throw new Error(ERRORS.FAILED_TO_UPDATE_RECURRING);
    }

    // Enqueue notification for the deleted virtual shift
    const mutationId = generateMutationId();
    const ownerName = getOwnerName(user);

    await enqueueShiftNotification({
      ownerId: user.id,
      ownerName,
      shiftId: `${recurringId}:${shiftDate}`, // Composite ID for virtual shift
      shiftDate,
      startTime: recurring.start_time,
      endTime: recurring.end_time,
      eventType: "deleted",
      mutationId,
    });

    // Invalidate cache and revalidate paths
    invalidateAndRevalidate(user.id);

    return { deleted: 1 };
  }

  // Case 2: Deleting a standalone shift
  // First get the shift to know its date and times for notification
  const { data: shift, error: fetchError } = await supabase
    .from("user_shifts")
    .select("id, shift_date, start_time, end_time")
    .eq("id", shiftId)
    .eq("user_id", user.id)
    .single();

  if (fetchError || !shift) {
    throw new Error(ERRORS.SHIFT_NOT_FOUND);
  }

  const deletedDate = shift.shift_date;

  // Delete the shift
  const { error } = await supabase
    .from("user_shifts")
    .delete()
    .eq("id", shiftId)
    .eq("user_id", user.id);

  if (error) throw new Error(error.message);

  // Enqueue notification for the deleted shift
  const mutationId = generateMutationId();
  const ownerName = getOwnerName(user);

  await enqueueShiftNotification({
    ownerId: user.id,
    ownerName,
    shiftId: shift.id,
    shiftDate: shift.shift_date,
    startTime: shift.start_time,
    endTime: shift.end_time,
    eventType: "deleted",
    mutationId,
  });

  // Check if this date should be removed from any recurring shift exclusions
  // Get the weekday of the deleted shift
  const d = new Date(`${deletedDate}T00:00:00Z`);
  const weekday = d.getUTCDay();

  // Find recurring shifts that have this date in exclusions and have an anchor for this weekday
  const { data: allRecurring, error: allRecurringError } = await supabase
    .from("recurring_shifts")
    .select("*")
    .eq("user_id", user.id);

  if (allRecurringError) {
    logger.error("Failed to load recurring shifts for exclusion cleanup:", allRecurringError);
    // Continue without cleanup
  } else if (allRecurring && allRecurring.length > 0) {
    // Find recurring shifts with this date in exclusions and matching weekday anchor
    const matchingRecurring = allRecurring.filter((s) => {
      const hasExclusion = (s.exclusions || []).includes(deletedDate);
      const hasWeekdayAnchor = s.selected_days && s.selected_days[String(weekday) as keyof typeof s.selected_days];
      return hasExclusion && hasWeekdayAnchor;
    });

    if (matchingRecurring.length > 0) {
      // Sort by earliest anchor date to pick the earliest recurring shift
      matchingRecurring.sort((a, b) => {
        const aAnchors = Object.values(a.selected_days || {});
        const bAnchors = Object.values(b.selected_days || {});
        const aEarliest = Math.min(...aAnchors.map((iso) => new Date(iso as string).getTime()));
        const bEarliest = Math.min(...bAnchors.map((iso) => new Date(iso as string).getTime()));
        return aEarliest - bEarliest;
      });

      const earliestRecurring = matchingRecurring[0];
      const updatedExclusions = (earliestRecurring.exclusions || []).filter((d: string) => d !== deletedDate);

      const { error: cleanupError } = await supabase
        .from("recurring_shifts")
        .update({ exclusions: updatedExclusions })
        .eq("id", earliestRecurring.id)
        .eq("user_id", user.id);

      if (cleanupError) {
        logger.error("Failed to cleanup recurring shift exclusions:", cleanupError);
        // Continue anyway
      }
    }
  }

  // Invalidate cache and revalidate paths
  invalidateAndRevalidate(user.id);

  return { deleted: 1 };
}

