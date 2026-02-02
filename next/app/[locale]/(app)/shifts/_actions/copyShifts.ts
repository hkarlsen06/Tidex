"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { checkShiftLimit } from "@/app/[locale]/(app)/shifts/add/_checks/checkShiftLimit";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { cleanTime } from "@/lib/time-utils";
import { verifySession } from "@/data-access/auth";
import { isISODate } from "@/lib/validation/shift-validators";
import { ERRORS } from "@/lib/errors/messages";
import {
  enqueueShiftNotification,
  generateMutationId,
  getOwnerName,
} from "@/lib/notifications/enqueue";

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

  // Separate virtual shifts from regular shifts
  const virtualIds = shiftIds.filter((id) => id.startsWith("virtual-"));
  const regularIds = shiftIds.filter((id) => !id.startsWith("virtual-"));

  const sourceShifts: Array<{
    start_time: string;
    end_time: string;
    recurring_id?: string;
  }> = [];

  // Fetch regular shifts from user_shifts table
  if (regularIds.length > 0) {
    const { data: regularShifts, error: fetchError } = await supabase
      .from("user_shifts")
      .select("*")
      .eq("user_id", user.id)
      .is("deleted_at", null) // Exclude soft-deleted shifts
      .in("id", regularIds);

    if (fetchError) throw new Error(fetchError.message);
    if (regularShifts) {
      sourceShifts.push(...regularShifts);
    }
  }

  // Handle virtual shifts - extract recurring shift information
  if (virtualIds.length > 0) {
    // Parse virtual shift IDs to get recurring shift IDs and their corresponding virtual IDs
    // Format: "virtual-{recurringId}-{date}"
    const virtualByRecurringId = new Map<string, string[]>();
    for (const virtualId of virtualIds) {
      const match = virtualId.match(/^virtual-([a-f0-9-]+)-(\d{4}-\d{2}-\d{2})$/);
      if (match) {
        const recurringId = match[1];
        if (!virtualByRecurringId.has(recurringId)) {
          virtualByRecurringId.set(recurringId, []);
        }
        virtualByRecurringId.get(recurringId)!.push(virtualId);
      }
    }

    if (virtualByRecurringId.size > 0) {
      const { data: recurringShifts, error: recurringError } = await supabase
        .from("recurring_shifts")
        .select("id, start_time, end_time")
        .eq("user_id", user.id)
        .is("deleted_at", null) // Exclude soft-deleted recurring shifts
        .in("id", Array.from(virtualByRecurringId.keys()));

      if (recurringError) throw new Error(recurringError.message);
      if (recurringShifts) {
        // For each virtual shift, add one entry with the recurring shift times
        for (const recurring of recurringShifts) {
          const virtualShiftsForThisRecurring = virtualByRecurringId.get(recurring.id) || [];
          // Add one entry per virtual shift (each represents a different date from the recurring shift)
          for (const _ of virtualShiftsForThisRecurring) {
            sourceShifts.push({
              start_time: recurring.start_time,
              end_time: recurring.end_time,
              recurring_id: undefined, // Don't link copied shifts to the recurring shift
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
    ...(shift.recurring_id ? { recurring_id: shift.recurring_id } : {}),
  }));

  const { data: insertedShifts, error } = await supabase
    .from("user_shifts")
    .insert(rows)
    .select("id, shift_date, start_time, end_time");
  if (error) throw new Error(error.message);

  // Enqueue notifications for each copied shift
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

  return { copied: rows.length };
}
