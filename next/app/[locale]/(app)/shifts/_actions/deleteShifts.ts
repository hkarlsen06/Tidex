"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { logger } from "@/lib/logger";
import { verifySession } from "@/data-access/auth";
import { ERRORS } from "@/lib/errors/messages";
import {
  enqueueShiftNotification,
  generateMutationId,
  getOwnerName,
} from "@/lib/notifications/enqueue";

type ShiftToDelete = {
  shiftId: string;
  recurringId?: string;
  shiftDate?: string;
};

/**
 * Bulk delete multiple shifts in a single server action.
 * Handles both regular shifts and recurring shift exclusions efficiently.
 */
export async function deleteShifts(shifts: ShiftToDelete[]) {
  if (!shifts || shifts.length === 0) {
    return { deleted: 0 };
  }

  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  // Separate recurring virtual shifts from regular shifts
  const recurringShifts = shifts.filter((s) => s.recurringId && s.shiftDate);
  const regularShifts = shifts.filter((s) => !s.recurringId || !s.shiftDate);

  let deletedCount = 0;
  const errors: string[] = [];

  // Handle recurring shifts - group by recurringId to minimize DB queries
  if (recurringShifts.length > 0) {
    // Group exclusions by recurringId
    const exclusionsByRecurringId = new Map<string, string[]>();
    for (const shift of recurringShifts) {
      const existing = exclusionsByRecurringId.get(shift.recurringId!) || [];
      existing.push(shift.shiftDate!);
      exclusionsByRecurringId.set(shift.recurringId!, existing);
    }

    // Process each recurring shift pattern
    const mutationId = generateMutationId();
    const ownerName = getOwnerName(user);

    for (const [recurringId, datesToExclude] of exclusionsByRecurringId) {
      const { data: recurring, error: recurringError } = await supabase
        .from("recurring_shifts")
        .select("exclusions, start_time, end_time")
        .eq("id", recurringId)
        .eq("user_id", user.id)
        .is("deleted_at", null) // Only find non-deleted recurring shifts
        .single();

      if (recurringError || !recurring) {
        logger.error(
          "Failed to load recurring shift for bulk deletion:",
          recurringError
        );
        errors.push(`Failed to process recurring shift ${recurringId}`);
        continue;
      }

      const currentExclusions = recurring.exclusions || [];
      const newExclusions = datesToExclude.filter(
        (d) => !currentExclusions.includes(d)
      );
      const updatedExclusions = [...currentExclusions, ...newExclusions];

      const { error: updateError } = await supabase
        .from("recurring_shifts")
        .update({ exclusions: updatedExclusions })
        .eq("id", recurringId)
        .eq("user_id", user.id)
        .is("deleted_at", null); // Only update non-deleted

      if (updateError) {
        logger.error(
          "Failed to update recurring shift exclusions:",
          updateError
        );
        errors.push(`Failed to exclude dates from recurring shift ${recurringId}`);
      } else {
        deletedCount += datesToExclude.length;

        // Enqueue notifications for each deleted virtual shift
        await Promise.all(
          datesToExclude.map((shiftDate) =>
            enqueueShiftNotification({
              ownerId: user.id,
              ownerName,
              shiftId: `${recurringId}:${shiftDate}`,
              shiftDate,
              startTime: recurring.start_time,
              endTime: recurring.end_time,
              eventType: "deleted",
              mutationId,
            })
          )
        );
      }
    }
  }

  // Handle regular shifts - bulk delete in a single query
  if (regularShifts.length > 0) {
    const shiftIds = regularShifts.map((s) => s.shiftId);

    // First, fetch all shifts to get their dates and times for notifications
    const { data: shiftsToDelete, error: fetchError } = await supabase
      .from("user_shifts")
      .select("id, shift_date, start_time, end_time")
      .in("id", shiftIds)
      .eq("user_id", user.id)
      .is("deleted_at", null); // Only find non-deleted shifts

    if (fetchError) {
      logger.error("Failed to fetch shifts for bulk deletion:", fetchError);
      errors.push(ERRORS.SHIFT_NOT_FOUND);
    } else if (shiftsToDelete && shiftsToDelete.length > 0) {
      // Bulk soft delete all shifts in a single query
      const { error: deleteError, count } = await supabase
        .from("user_shifts")
        .update({ deleted_at: new Date().toISOString() })
        .in("id", shiftIds)
        .eq("user_id", user.id)
        .is("deleted_at", null); // Only delete non-deleted shifts

      if (deleteError) {
        logger.error("Failed to bulk delete shifts:", deleteError);
        errors.push(deleteError.message);
      } else {
        deletedCount += count ?? shiftsToDelete.length;

        // Enqueue notifications for each deleted shift
        const mutationId = generateMutationId();
        const ownerName = getOwnerName(user);

        await Promise.all(
          shiftsToDelete.map((shift) =>
            enqueueShiftNotification({
              ownerId: user.id,
              ownerName,
              shiftId: shift.id,
              shiftDate: shift.shift_date,
              startTime: shift.start_time,
              endTime: shift.end_time,
              eventType: "deleted",
              mutationId,
            })
          )
        );

        // Clean up recurring shift exclusions for deleted dates
        // Group by weekday for efficient processing
        const deletedDates = shiftsToDelete.map((s) => s.shift_date);
        await cleanupRecurringExclusions(supabase, user.id, deletedDates);
      }
    }
  }

  // Invalidate cache and revalidate paths (only once for all deletions)
  invalidateAndRevalidate(user.id);

  if (errors.length > 0) {
    logger.warn("Some shifts failed to delete:", errors);
  }

  return {
    deleted: deletedCount,
    errors: errors.length > 0 ? errors : undefined,
  };
}

/**
 * Clean up recurring shift exclusions when standalone shifts are deleted.
 * This restores recurring shifts that were replaced by standalone shifts.
 */
async function cleanupRecurringExclusions(
  supabase: Awaited<ReturnType<typeof createSupabaseServerClient>>,
  userId: string,
  deletedDates: string[]
) {
  if (deletedDates.length === 0) return;

  // Get all recurring shifts for this user
  const { data: allRecurring, error: allRecurringError } = await supabase
    .from("recurring_shifts")
    .select("*")
    .eq("user_id", userId)
    .is("deleted_at", null); // Only find non-deleted recurring shifts

  if (allRecurringError || !allRecurring || allRecurring.length === 0) {
    return;
  }

  // Group deleted dates by weekday for matching
  const datesByWeekday = new Map<number, string[]>();
  for (const date of deletedDates) {
    const d = new Date(`${date}T00:00:00Z`);
    const weekday = d.getUTCDay();
    const existing = datesByWeekday.get(weekday) || [];
    existing.push(date);
    datesByWeekday.set(weekday, existing);
  }

  // Find recurring shifts that need exclusion cleanup
  for (const recurring of allRecurring) {
    if (!recurring.exclusions || recurring.exclusions.length === 0) continue;
    if (!recurring.selected_days) continue;

    // Find dates in exclusions that match this recurring shift's weekdays
    const datesToRestore: string[] = [];

    for (const [weekday, dates] of datesByWeekday) {
      const hasWeekdayAnchor =
        recurring.selected_days[String(weekday) as keyof typeof recurring.selected_days];
      if (!hasWeekdayAnchor) continue;

      for (const date of dates) {
        if (recurring.exclusions.includes(date)) {
          datesToRestore.push(date);
        }
      }
    }

    if (datesToRestore.length > 0) {
      const updatedExclusions = recurring.exclusions.filter(
        (d: string) => !datesToRestore.includes(d)
      );

      const { error: cleanupError } = await supabase
        .from("recurring_shifts")
        .update({ exclusions: updatedExclusions })
        .eq("id", recurring.id)
        .eq("user_id", userId)
        .is("deleted_at", null); // Only update non-deleted

      if (cleanupError) {
        logger.error("Failed to cleanup recurring shift exclusions:", cleanupError);
      }
    }
  }
}
