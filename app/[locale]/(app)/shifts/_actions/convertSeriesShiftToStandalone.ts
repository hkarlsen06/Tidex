"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { logger } from "@/lib/logger";
import { invalidateUserCache } from "@/data-access/cache";
import { verifySession } from "@/data-access/auth";
import { getUserSettings } from "@/data-access/settings";
import { prepareShiftSnapshots } from "@/lib/payroll/snapshot";

type ConvertInput = {
  seriesId: string;
  shiftDate: string; // ISO date
  startTime: string; // HH:mm
  endTime: string; // HH:mm
};

/**
 * Convert a series ghost shift to a standalone shift
 * - Creates a new standalone shift with the given parameters
 * - Adds the date to the series exclusions array
 * - Revalidates the shifts page
 */
export async function convertSeriesShiftToStandalone({
  seriesId,
  shiftDate,
  startTime,
  endTime,
}: ConvertInput): Promise<void> {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  // Load the series to get current exclusions
  const { data: series, error: seriesError } = await supabase
    .from("series_shifts")
    .select("exclusions")
    .eq("id", seriesId)
    .eq("user_id", user.id)
    .single();

  if (seriesError || !series) {
    logger.error("Failed to load series for conversion:", seriesError);
    throw new Error("Failed to load series");
  }

  // Add date to exclusions
  const currentExclusions = series.exclusions || [];
  const updatedExclusions = currentExclusions.includes(shiftDate)
    ? currentExclusions
    : [...currentExclusions, shiftDate];

  // Update series exclusions
  const { error: updateError } = await supabase
    .from("series_shifts")
    .update({ exclusions: updatedExclusions })
    .eq("id", seriesId)
    .eq("user_id", user.id);

  if (updateError) {
    logger.error("Failed to update series exclusions:", updateError);
    throw new Error("Failed to update series");
  }

  // Get current settings and prepare snapshots
  const settings = await getUserSettings();
  const snapshots = settings ? prepareShiftSnapshots(settings) : { hourly_wage_snapshot: null, supplement_rules_snapshot: null };

  // Create standalone shift
  const { error: insertError } = await supabase
    .from("user_shifts")
    .insert({
      user_id: user.id,
      shift_date: shiftDate,
      start_time: startTime,
      end_time: endTime,
      hourly_wage_snapshot: snapshots.hourly_wage_snapshot,
      supplement_rules_snapshot: snapshots.supplement_rules_snapshot,
    });

  if (insertError) {
    logger.error("Failed to create standalone shift:", insertError);
    throw new Error("Failed to create shift");
  }

  // Invalidate all cached data for this user
  invalidateUserCache(user.id);

  revalidatePath("/[locale]/shifts", "page");
  revalidatePath("/[locale]", "page");
  revalidatePath("/[locale]/stats", "page");
}
