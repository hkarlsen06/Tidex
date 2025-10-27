"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { invalidateUserCache } from "@/app/[locale]/(app)/shifts/_data/cache";
import { logger } from "@/lib/logger";

type DeleteShiftInput = {
  shiftId: string;
  seriesId?: string; // Present if this is a series ghost
  shiftDate?: string; // ISO date, needed if series ghost
};

export async function deleteShift(input: string | DeleteShiftInput) {
  // Handle both legacy string input and new object input
  const shiftId = typeof input === "string" ? input : input.shiftId;
  const seriesId = typeof input === "string" ? undefined : input.seriesId;
  const shiftDate = typeof input === "string" ? undefined : input.shiftDate;

  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) throw new Error("Unauthorized");
  if (!shiftId) throw new Error("Ugyldig skift-ID");

  // Case 1: Deleting a series ghost - add to exclusions instead
  if (seriesId && shiftDate) {
    const { data: series, error: seriesError } = await supabase
      .from("series_shifts")
      .select("exclusions")
      .eq("id", seriesId)
      .eq("user_id", user.id)
      .single();

    if (seriesError || !series) {
      logger.error("Failed to load series for deletion:", seriesError);
      throw new Error("Failed to load series");
    }

    const currentExclusions = series.exclusions || [];
    const updatedExclusions = currentExclusions.includes(shiftDate)
      ? currentExclusions
      : [...currentExclusions, shiftDate];

    const { error: updateError } = await supabase
      .from("series_shifts")
      .update({ exclusions: updatedExclusions })
      .eq("id", seriesId)
      .eq("user_id", user.id);

    if (updateError) {
      logger.error("Failed to update series exclusions:", updateError);
      throw new Error("Failed to update series");
    }

    // Invalidate all cached data for this user
    invalidateUserCache(user.id);

    revalidatePath("/[locale]/shifts", "page");
    revalidatePath("/[locale]", "page");
    revalidatePath("/[locale]/stats", "page");

    return { deleted: 1 };
  }

  // Case 2: Deleting a standalone shift
  // First get the shift to know its date
  const { data: shift, error: fetchError } = await supabase
    .from("user_shifts")
    .select("shift_date")
    .eq("id", shiftId)
    .eq("user_id", user.id)
    .single();

  if (fetchError || !shift) {
    throw new Error("Fant ikke skiftet");
  }

  const deletedDate = shift.shift_date;

  // Delete the shift
  const { error } = await supabase
    .from("user_shifts")
    .delete()
    .eq("id", shiftId)
    .eq("user_id", user.id);

  if (error) throw new Error(error.message);

  // Check if this date should be removed from any series exclusions
  // Get the weekday of the deleted shift
  const d = new Date(`${deletedDate}T00:00:00Z`);
  const weekday = d.getUTCDay();

  // Find series that have this date in exclusions and have an anchor for this weekday
  const { data: allSeries, error: allSeriesError } = await supabase
    .from("series_shifts")
    .select("*")
    .eq("user_id", user.id);

  if (allSeriesError) {
    logger.error("Failed to load series for exclusion cleanup:", allSeriesError);
    // Continue without cleanup
  } else if (allSeries && allSeries.length > 0) {
    // Find series with this date in exclusions and matching weekday anchor
    const matchingSeries = allSeries.filter((s) => {
      const hasExclusion = (s.exclusions || []).includes(deletedDate);
      const hasWeekdayAnchor = s.selected_days && s.selected_days[String(weekday) as keyof typeof s.selected_days];
      return hasExclusion && hasWeekdayAnchor;
    });

    if (matchingSeries.length > 0) {
      // Sort by earliest anchor date to pick the earliest series
      matchingSeries.sort((a, b) => {
        const aAnchors = Object.values(a.selected_days || {});
        const bAnchors = Object.values(b.selected_days || {});
        const aEarliest = Math.min(...aAnchors.map((iso) => new Date(iso as string).getTime()));
        const bEarliest = Math.min(...bAnchors.map((iso) => new Date(iso as string).getTime()));
        return aEarliest - bEarliest;
      });

      const earliestSeries = matchingSeries[0];
      const updatedExclusions = (earliestSeries.exclusions || []).filter((d: string) => d !== deletedDate);

      const { error: cleanupError } = await supabase
        .from("series_shifts")
        .update({ exclusions: updatedExclusions })
        .eq("id", earliestSeries.id)
        .eq("user_id", user.id);

      if (cleanupError) {
        logger.error("Failed to cleanup series exclusions:", cleanupError);
        // Continue anyway
      }
    }
  }

  // Invalidate all cached data for this user
  invalidateUserCache(user.id);

  revalidatePath("/[locale]/shifts", "page");
  revalidatePath("/[locale]", "page");
  revalidatePath("/[locale]/stats", "page");

  return { deleted: 1 };
}

