"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { logger } from "@/lib/logger";
import { invalidateUserCache } from "@/data-access/cache";
import { cleanTime } from "@/lib/time-utils";
import { verifySession } from "@/data-access/auth";

type MoveSeriesShiftInput = {
  seriesId: string;
  sourceDate: string; // ISO date to exclude
  targetDate: string; // ISO date for new standalone shift
  startTime: string; // HH:mm
  endTime: string; // HH:mm
};

function isISODate(input: string) {
  return /^\d{4}-\d{2}-\d{2}$/.test(input);
}

function isHHMM(input: string) {
  return /^\d{2}:\d{2}$/.test(input);
}

function shiftTypeFromISODate(iso: string) {
  const d = new Date(`${iso}T00:00:00Z`);
  const weekday = d.getUTCDay();
  return weekday === 6 ? 1 : weekday === 0 ? 2 : 0;
}

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
    throw new Error("Ugyldig dato");
  }

  // Clean time strings to HH:mm format (removes timezone and seconds)
  const cleanedStartTime = cleanTime(startTime);
  const cleanedEndTime = cleanTime(endTime);

  if (!isHHMM(cleanedStartTime) || !isHHMM(cleanedEndTime)) {
    throw new Error("Ugyldig tid");
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
    throw new Error("Fant ikke serien");
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
    });

  if (insertError) {
    logger.error("Failed to create standalone shift:", insertError);
    throw new Error("Kunne ikke opprette skift");
  }

  // Invalidate all cached data for this user
  invalidateUserCache(user.id);

  revalidatePath("/[locale]/shifts", "page");
  revalidatePath("/[locale]", "page");
  revalidatePath("/[locale]/stats", "page");
}
