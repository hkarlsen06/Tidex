"use server";

import { verifySession } from "@/data-access/auth";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { checkShiftLimit } from "@/app/[locale]/(app)/shifts/add/_checks/checkShiftLimit";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { isISODate, isHHMM } from "@/lib/validation/shift-validators";
import { ERRORS } from "@/lib/errors/messages";
import {
  enqueueShiftNotification,
  generateMutationId,
  getOwnerName,
} from "@/lib/notifications/enqueue";

type CreateShiftsInput = {
  dates: string[]; // ISO YYYY-MM-DD (local date)
  start: string; // HH:mm
  end: string; // HH:mm
  recurringId?: string;
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

  // First check: if trying to create shifts in multiple months at once, check limit for the first month
  // This will tell us if the user is on free tier
  const firstMonthCheck = await checkShiftLimit(targetMonths[0]);

  // If user is on free tier and trying to add to multiple months at once, reject immediately
  if (firstMonthCheck.isFreeTier && targetMonths.length > 1) {
    throw new Error(
      "Du er på gratisplanen og kan bare ha skift i én måned om gangen. Oppgrader til Pro eller slett skift i andre måneder."
    );
  }

  // If user is on free tier, verify the single target month is allowed
  if (firstMonthCheck.isFreeTier && !firstMonthCheck.allowed) {
    throw new Error(
      firstMonthCheck.reason ||
      "Du er på gratisplanen og kan bare ha skift i én måned om gangen. Oppgrader til Pro eller slett skift i andre måneder."
    );
  }

  const sid = input.recurringId && input.recurringId.trim().length > 0 ? input.recurringId : undefined;

  const rows = dates.map((shift_date) => ({
    user_id: user.id,
    shift_date,
    start_time: input.start,
    end_time: input.end,
    ...(sid ? { recurring_id: sid } : {}),
  }));

  const { data: insertedShifts, error } = await supabase
    .from("user_shifts")
    .insert(rows)
    .select('id, shift_date, start_time, end_time');

  if (error) throw new Error(error.message);

  // Enqueue notifications for each created shift
  const mutationId = generateMutationId();
  const ownerName = getOwnerName(user);

  await Promise.all(
    (insertedShifts ?? []).map((shift) =>
      enqueueShiftNotification({
        ownerId: user.id,
        ownerName,
        shiftId: shift.id,
        shiftDate: shift.shift_date,
        startTime: shift.start_time,
        endTime: shift.end_time,
        eventType: "added",
        mutationId,
      })
    )
  );

  // Invalidate cache and revalidate paths
  invalidateAndRevalidate(user.id);

  return {
    inserted: rows.length,
    shiftIds: insertedShifts?.map(s => s.id) || [],
    dates: insertedShifts?.map(s => s.shift_date) || []
  };
}
