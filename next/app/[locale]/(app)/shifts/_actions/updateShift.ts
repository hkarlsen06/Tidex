"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { convertRecurringShiftToStandalone } from "./convertRecurringShiftToStandalone";
import { verifySession } from "@/data-access/auth";
import { isISODate, isHHMM } from "@/lib/validation/shift-validators";
import { ERRORS } from "@/lib/errors/messages";


export type UpdateShiftInput = {
  id: string;
  shift_date: string; // ISO YYYY-MM-DD
  start: string; // HH:mm
  end: string; // HH:mm
  recurring_id?: string; // Present if this is a recurring virtual shift
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

  // If this is a recurring virtual shift, convert to standalone instead of updating
  if (input.recurring_id) {
    await convertRecurringShiftToStandalone({
      recurringId: input.recurring_id,
      shiftDate: input.shift_date,
      startTime: input.start,
      endTime: input.end,
    });

    // Invalidate cache and revalidate paths
    invalidateAndRevalidate(user.id);

    return { updated: 1 };
  }

  // Fetch current shift to compare if date/time changed
  const { data: oldShift, error: fetchError } = await supabase
    .from("user_shifts")
    .select("id, shift_date, start_time, end_time")
    .eq("id", input.id)
    .eq("user_id", user.id)
    .is("deleted_at", null) // Only find non-deleted shifts
    .single();

  if (fetchError || !oldShift) {
    throw new Error(ERRORS.SHIFT_NOT_FOUND);
  }

  const { error } = await supabase
    .from("user_shifts")
    .update({
      shift_date: input.shift_date,
      start_time: input.start,
      end_time: input.end,
    })
    .eq("id", input.id)
    .eq("user_id", user.id)
    .is("deleted_at", null) // Only update non-deleted shifts
    .select("id")
    .single();

  if (error) {
    throw new Error(error.message);
  }

  // Invalidate cache and revalidate paths
  invalidateAndRevalidate(user.id);

  return { updated: 1 };
}
