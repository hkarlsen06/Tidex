"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { logger } from "@/lib/logger";
import type { SelectedDays, EndCondition } from "@/lib/series/types";
import { invalidateUserCache } from "@/data-access/cache";
import { verifySession } from "@/data-access/auth";

type UpdateSeriesInput = {
  id: string;
  start_time: string; // HH:mm
  end_time: string; // HH:mm
  repeat_interval_weeks: 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8;
  selected_days: SelectedDays;
  end_condition: EndCondition;
  exclusions: string[];
};

/**
 * Update a series shift in the database
 * - Updates all parameters of the series
 * - Revalidates the shifts page
 */
export async function updateSeriesShift({
  id,
  start_time,
  end_time,
  repeat_interval_weeks,
  selected_days,
  end_condition,
  exclusions,
}: UpdateSeriesInput): Promise<void> {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  // Update the series
  const { error } = await supabase
    .from("series_shifts")
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
    logger.error("Failed to update series:", error);
    throw new Error("Failed to update series");
  }

  // Invalidate cache to ensure changes appear immediately
  invalidateUserCache(user.id);
  revalidatePath("/[locale]/shifts", "page");
}
