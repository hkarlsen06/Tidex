"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { convertSeriesShiftToStandalone } from "./convertSeriesShiftToStandalone";
import { verifySession } from "@/data-access/auth";
import { isISODate, isHHMM, shiftTypeFromISODate } from "@/lib/validation/shift-validators";
import { ERRORS } from "@/lib/errors/messages";

export type UpdateShiftInput = {
  id: string;
  shift_date: string; // ISO YYYY-MM-DD
  start: string; // HH:mm
  end: string; // HH:mm
  series_id?: string; // Present if this is a series ghost
};

export async function updateShift(input: UpdateShiftInput) {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  if (!input.id) {
    throw new Error(ERRORS.INVALID_SHIFT_ID);
  }

  if (!isISODate(input.shift_date)) {
    throw new Error(ERRORS.INVALID_DATE);
  }

  if (!isHHMM(input.start) || !isHHMM(input.end)) {
    throw new Error(ERRORS.INVALID_TIME);
  }

  // If this is a series ghost, convert to standalone instead of updating
  if (input.series_id) {
    await convertSeriesShiftToStandalone({
      seriesId: input.series_id,
      shiftDate: input.shift_date,
      startTime: input.start,
      endTime: input.end,
    });

    // Invalidate cache and revalidate paths
    invalidateAndRevalidate(user.id);

    return { updated: 1 };
  }

  const shiftType = shiftTypeFromISODate(input.shift_date);

  const { data: existing, error: fetchError } = await supabase
    .from("user_shifts")
    .select("id")
    .eq("id", input.id)
    .eq("user_id", user.id)
    .single();

  if (fetchError || !existing) {
    throw new Error(ERRORS.SHIFT_NOT_FOUND);
  }

  const { error } = await supabase
    .from("user_shifts")
    .update({
      shift_date: input.shift_date,
      start_time: input.start,
      end_time: input.end,
      shift_type: shiftType,
    })
    .eq("id", input.id)
    .eq("user_id", user.id);

  if (error) {
    throw new Error(error.message);
  }

  // Invalidate cache and revalidate paths
  invalidateAndRevalidate(user.id);

  return { updated: 1 };
}
