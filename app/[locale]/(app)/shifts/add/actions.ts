"use server";

import { verifySession } from "@/data-access/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { checkShiftLimit } from "@/app/[locale]/(app)/shifts/add/_checks/checkShiftLimit";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { getCurrentSnapshots } from "@/data-access/snapshots";
import { isISODate, isHHMM, shiftTypeFromISODate } from "@/lib/validation/shift-validators";
import { ERRORS } from "@/lib/errors/messages";

type CreateShiftsInput = {
  dates: string[]; // ISO YYYY-MM-DD (local date)
  start: string; // HH:mm
  end: string; // HH:mm
  seriesId?: string;
};

export async function createShifts(input: CreateShiftsInput) {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  const dates = Array.isArray(input.dates) ? input.dates.filter(Boolean) : [];
  if (dates.length === 0) throw new Error("Minst én dato er påkrevd");
  if (!isHHMM(input.start) || !isHHMM(input.end)) throw new Error(ERRORS.INVALID_TIME);
  if (!dates.every(isISODate)) throw new Error(ERRORS.INVALID_DATE);

  // Check shift limit (free tier enforcement) for all target months
  const targetMonths = Array.from(new Set(dates.map(date => date.slice(0, 7)))); // Extract unique YYYY-MM

  for (const targetMonth of targetMonths) {
    const limitCheck = await checkShiftLimit(targetMonth);

    if (!limitCheck.allowed) {
      throw new Error(
        limitCheck.reason ||
        "Du er på gratisplanen og kan bare ha skift i én måned om gangen. Oppgrader til Pro eller slett skift i andre måneder."
      );
    }
  }

  const sid = input.seriesId && input.seriesId.trim().length > 0 ? input.seriesId : undefined;

  // Get current snapshots
  const snapshots = await getCurrentSnapshots();

  const rows = dates.map((shift_date) => ({
    user_id: user.id,
    shift_date,
    start_time: input.start,
    end_time: input.end,
    shift_type: shiftTypeFromISODate(shift_date),
    hourly_wage_snapshot: snapshots.hourly_wage_snapshot,
    supplement_rules_snapshot: snapshots.supplement_rules_snapshot,
    ...(sid ? { series_id: sid } : {}),
  }));

  const { error } = await supabase.from("user_shifts").insert(rows);
  if (error) throw new Error(error.message);

  // Invalidate cache and revalidate paths
  invalidateAndRevalidate(user.id);

  return { inserted: rows.length };
}
