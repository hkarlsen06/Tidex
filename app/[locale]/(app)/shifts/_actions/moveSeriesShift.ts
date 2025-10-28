"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { logger } from "@/lib/logger";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { cleanTime } from "@/lib/time-utils";
import { verifySession } from "@/data-access/auth";
import { getUserSettings } from "@/data-access/settings";
import { prepareShiftSnapshots } from "@/lib/payroll/snapshot";
import { isISODate, isHHMM, shiftTypeFromISODate } from "@/lib/validation/shift-validators";
import { ERRORS } from "@/lib/errors/messages";

type MoveSeriesShiftInput = {
  seriesId: string;
  sourceDate: string; // ISO date to exclude
  targetDate: string; // ISO date for new standalone shift
  startTime: string; // HH:mm
  endTime: string; // HH:mm
};

/**
 * Move a series shift to a new date
 * - Adds the source date to series exclusions
 * - Creates a new standalone shift at the target date
 * - Revalidates the shifts page
 */
export async function moveSeriesShift({
  seriesId,
  sourceDate,
  targetDate,
  startTime,
  endTime,
}: MoveSeriesShiftInput): Promise<void> {
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

  // Load the series to get current exclusions
  const { data: series, error: seriesError } = await supabase
    .from("series_shifts")
    .select("exclusions")
    .eq("id", seriesId)
    .eq("user_id", user.id)
    .single();

  if (seriesError || !series) {
    logger.error("Failed to load series for move:", seriesError);
    throw new Error(ERRORS.SERIES_NOT_FOUND);
  }

  // Add source date to exclusions
  const currentExclusions = series.exclusions || [];
  const updatedExclusions = currentExclusions.includes(sourceDate)
    ? currentExclusions
    : [...currentExclusions, sourceDate];

  // Update series exclusions
  const { error: updateError } = await supabase
    .from("series_shifts")
    .update({ exclusions: updatedExclusions })
    .eq("id", seriesId)
    .eq("user_id", user.id);

  if (updateError) {
    logger.error("Failed to update series exclusions:", updateError);
    throw new Error("Kunne ikke oppdatere serien");
  }

  // Get current settings and prepare snapshots
  const settings = await getUserSettings();
  const snapshots = settings ? prepareShiftSnapshots(settings) : { hourly_wage_snapshot: null, supplement_rules_snapshot: null };

  // Create standalone shift at target date
  const shiftType = shiftTypeFromISODate(targetDate);

  const { error: insertError } = await supabase
    .from("user_shifts")
    .insert({
      user_id: user.id,
      shift_date: targetDate,
      start_time: cleanedStartTime,
      end_time: cleanedEndTime,
      shift_type: shiftType,
      hourly_wage_snapshot: snapshots.hourly_wage_snapshot,
      supplement_rules_snapshot: snapshots.supplement_rules_snapshot,
    });

  if (insertError) {
    logger.error("Failed to create standalone shift:", insertError);
    throw new Error("Kunne ikke opprette skift");
  }

  // Invalidate cache and revalidate paths
  invalidateAndRevalidate(user.id);
}
