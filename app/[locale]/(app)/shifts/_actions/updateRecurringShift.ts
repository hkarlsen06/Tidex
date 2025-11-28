"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { logger } from "@/lib/logger";
import type { SelectedDays, EndCondition } from "@/lib/recurring/types";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { verifySession } from "@/data-access/auth";
import { ERRORS } from "@/lib/errors/messages";

type UpdateRecurringInput = {
  id: string;
  start_time: string; // HH:mm
  end_time: string; // HH:mm
  repeat_interval_weeks: 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8;
  selected_days: SelectedDays;
  end_condition: EndCondition;
  exclusions: string[];
};

/**
 * Update a recurring shift in the database
 * - Updates all parameters of the recurring shift
 * - Revalidates the shifts page
 */
export async function updateRecurringShift({
  id,
  start_time,
  end_time,
  repeat_interval_weeks,
  selected_days,
  end_condition,
  exclusions,
}: UpdateRecurringInput): Promise<void> {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  // Update the recurring shift
  const { error } = await supabase
    .from("recurring_shifts")
    .update({
      start_time,
      end_time,
      repeat_interval_weeks,
      selected_days,
      end_condition,
      exclusions,
    })
    .eq("id", id)
    .eq("user_id", user.id);

  if (error) {
    logger.error("Failed to update recurring shift:", error);
    throw new Error(ERRORS.FAILED_TO_UPDATE_RECURRING);
  }

  // Invalidate cache and revalidate paths
  invalidateAndRevalidate(user.id);
}
