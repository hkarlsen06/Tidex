"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { verifySession } from "@/data-access/auth";
import { logger } from "@/lib/logger";
import { getCurrentSnapshots } from "@/data-access/snapshots";

export async function bulkClearSnapshots(
  startDate: string,
  endDate: string
): Promise<{ success: boolean; count: number }> {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  // Get current snapshots based on user settings
  const snapshots = await getCurrentSnapshots();

  const { data, error } = await supabase
    .from("user_shifts")
    .update({
      hourly_wage_snapshot: snapshots.hourly_wage_snapshot,
      supplement_rules_snapshot: snapshots.supplement_rules_snapshot,
    })
    .eq("user_id", user.id)
    .gte("shift_date", startDate)
    .lte("shift_date", endDate)
    .select();

  if (error) {
    logger.error("Failed to bulk update shift snapshots:", error);
    throw error;
  }

  const count = data?.length ?? 0;

  // Invalidate cache and revalidate paths
  invalidateAndRevalidate(user.id);

  return { success: true, count };
}
