"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { logger } from "@/lib/logger";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { cleanTime } from "@/lib/time-utils";
import { verifySession } from "@/data-access/auth";
import { isISODate, isHHMM } from "@/lib/validation/shift-validators";
import { ERRORS } from "@/lib/errors/messages";

type MoveRecurringShiftInput = {
  recurringId: string;
  sourceDate: string; // ISO date to exclude
  targetDate: string; // ISO date for new standalone shift
  startTime: string; // HH:mm
  endTime: string; // HH:mm
};

/**
 * Move a recurring shift to a new date
 * - Adds the source date to recurring shift exclusions
 * - Creates a new standalone shift at the target date
 * - Revalidates the shifts page
 */
export async function moveRecurringShift({
  recurringId,
  sourceDate,
  targetDate,
  startTime,
  endTime,
}: MoveRecurringShiftInput): Promise<void> {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  if (!isISODate(sourceDate) || !isISODate(targetDate)) {
    throw new Error(ERRORS.INVALID_DATE);
  }

  // Clean time strings to HH:mm format (removes timezone and seconds)
  const cleanedStartTime = cleanTime(startTime);
  const cleanedEndTime = cleanTime(endTime);

  if (!isHHMM(cleanedStartTime) || !isHHMM(cleanedEndTime)) {
    throw new Error(ERRORS.INVALID_TIME);
  }

  // Load the recurring shift to get current exclusions
  const { data: recurring, error: recurringError } = await supabase
    .from("recurring_shifts")
    .select("exclusions")
    .eq("id", recurringId)
    .eq("user_id", user.id)
    .single();

  if (recurringError || !recurring) {
    logger.error("Failed to load recurring shift for move:", recurringError);
    throw new Error(ERRORS.RECURRING_NOT_FOUND);
  }

  // Add source date to exclusions
  const currentExclusions = recurring.exclusions || [];
  const updatedExclusions = currentExclusions.includes(sourceDate)
    ? currentExclusions
    : [...currentExclusions, sourceDate];

  // Update recurring shift exclusions
  const { error: updateError } = await supabase
    .from("recurring_shifts")
    .update({ exclusions: updatedExclusions })
    .eq("id", recurringId)
    .eq("user_id", user.id);

  if (updateError) {
    logger.error("Failed to update recurring shift exclusions:", updateError);
    throw new Error(ERRORS.FAILED_TO_UPDATE_RECURRING);
  }

  // Create standalone shift at target date
  const { error: insertError } = await supabase
    .from("user_shifts")
    .insert({
      user_id: user.id,
      shift_date: targetDate,
      start_time: cleanedStartTime,
      end_time: cleanedEndTime,
    });

  if (insertError) {
    logger.error("Failed to create standalone shift:", insertError);
    throw new Error(ERRORS.FAILED_TO_CREATE_SHIFT);
  }

  // Invalidate cache and revalidate paths
  invalidateAndRevalidate(user.id);
}
