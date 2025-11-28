"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { logger } from "@/lib/logger";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { verifySession } from "@/data-access/auth";
import { ERRORS } from "@/lib/errors/messages";

type ConvertInput = {
  recurringId: string;
  shiftDate: string; // ISO date
  startTime: string; // HH:mm
  endTime: string; // HH:mm
};

/**
 * Convert a recurring ghost shift to a standalone shift
 * - Creates a new standalone shift with the given parameters
 * - Adds the date to the recurring shift exclusions array
 * - Revalidates the shifts page
 */
export async function convertRecurringShiftToStandalone({
  recurringId,
  shiftDate,
  startTime,
  endTime,
}: ConvertInput): Promise<void> {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  // Load the recurring shift to get current exclusions
  const { data: recurring, error: recurringError } = await supabase
    .from("recurring_shifts")
    .select("exclusions")
    .eq("id", recurringId)
    .eq("user_id", user.id)
    .single();

  if (recurringError || !recurring) {
    logger.error("Failed to load recurring shift for conversion:", recurringError);
    throw new Error(ERRORS.FAILED_TO_LOAD_RECURRING);
  }

  // Add date to exclusions
  const currentExclusions = recurring.exclusions || [];
  const updatedExclusions = currentExclusions.includes(shiftDate)
    ? currentExclusions
    : [...currentExclusions, shiftDate];

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

  // Create standalone shift
  const { error: insertError } = await supabase
    .from("user_shifts")
    .insert({
      user_id: user.id,
      shift_date: shiftDate,
      start_time: startTime,
      end_time: endTime,
    });

  if (insertError) {
    logger.error("Failed to create standalone shift:", insertError);
    throw new Error(ERRORS.FAILED_TO_CREATE_SHIFT);
  }

  // Invalidate cache and revalidate paths
  invalidateAndRevalidate(user.id);
}
