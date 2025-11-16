"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { checkShiftLimit } from "@/app/[locale]/(app)/shifts/add/_checks/checkShiftLimit";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { cleanTime } from "@/lib/time-utils";
import { verifySession } from "@/data-access/auth";
import { isISODate } from "@/lib/validation/shift-validators";
import { ERRORS } from "@/lib/errors/messages";

type CopyShiftsInput = {
  shiftIds: string[];
  targetDate: string; // ISO YYYY-MM-DD (local date)
};

export async function copyShifts(input: CopyShiftsInput) {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  const shiftIds = Array.isArray(input.shiftIds) ? input.shiftIds.filter(Boolean) : [];
  if (shiftIds.length === 0) throw new Error(ERRORS.MIN_ONE_SHIFT_REQUIRED);
  if (!isISODate(input.targetDate)) throw new Error(ERRORS.INVALID_DATE);

  // Separate ghost shifts from regular shifts
  const ghostIds = shiftIds.filter((id) => id.startsWith("ghost-"));
  const regularIds = shiftIds.filter((id) => !id.startsWith("ghost-"));

  const sourceShifts: Array<{
    start_time: string;
    end_time: string;
    series_id?: string;
  }> = [];

  // Fetch regular shifts from user_shifts table
  if (regularIds.length > 0) {
    const { data: regularShifts, error: fetchError } = await supabase
      .from("user_shifts")
      .select("*")
      .eq("user_id", user.id)
      .in("id", regularIds);

    if (fetchError) throw new Error(fetchError.message);
    if (regularShifts) {
      sourceShifts.push(...regularShifts);
    }
  }

  // Handle ghost shifts - extract series information
  if (ghostIds.length > 0) {
    // Parse ghost IDs to get series IDs and their corresponding ghost IDs
    // Format: "ghost-{seriesId}-{date}"
    const ghostBySeriesId = new Map<string, string[]>();
    for (const ghostId of ghostIds) {
      const match = ghostId.match(/^ghost-([a-f0-9-]+)-(\d{4}-\d{2}-\d{2})$/);
      if (match) {
        const seriesId = match[1];
        if (!ghostBySeriesId.has(seriesId)) {
          ghostBySeriesId.set(seriesId, []);
        }
        ghostBySeriesId.get(seriesId)!.push(ghostId);
      }
    }

    if (ghostBySeriesId.size > 0) {
      const { data: seriesShifts, error: seriesError } = await supabase
        .from("series_shifts")
        .select("id, start_time, end_time")
        .eq("user_id", user.id)
        .in("id", Array.from(ghostBySeriesId.keys()));

      if (seriesError) throw new Error(seriesError.message);
      if (seriesShifts) {
        // For each ghost shift, add one entry with the series times
        for (const series of seriesShifts) {
          const ghostsForThisSeries = ghostBySeriesId.get(series.id) || [];
          // Add one entry per ghost (each ghost represents a different date from the series)
          for (const _ of ghostsForThisSeries) {
            sourceShifts.push({
              start_time: series.start_time,
              end_time: series.end_time,
              series_id: undefined, // Don't link copied shifts to the series
            });
          }
        }
      }
    }
  }

  if (sourceShifts.length === 0) {
    throw new Error(ERRORS.NO_SHIFTS_FOUND);
  }

  // Check shift limit (free tier enforcement)
  const targetMonth = input.targetDate.slice(0, 7); // Extract YYYY-MM
  const limitCheck = await checkShiftLimit(targetMonth);

  if (!limitCheck.allowed) {
    throw new Error(
      limitCheck.reason ||
      "Du er på gratisplanen og kan bare ha skift i én måned om gangen. Oppgrader til Pro eller slett skift i andre måneder."
    );
  }

  // Create new shifts based on source shifts but with the target date
  const rows = sourceShifts.map((shift) => ({
    user_id: user.id,
    shift_date: input.targetDate,
    start_time: cleanTime(shift.start_time),
    end_time: cleanTime(shift.end_time),
    ...(shift.series_id ? { series_id: shift.series_id } : {}),
  }));

  const { error } = await supabase.from("user_shifts").insert(rows);
  if (error) throw new Error(error.message);

  // Invalidate cache and revalidate paths
  invalidateAndRevalidate(user.id);

  return { copied: rows.length };
}
