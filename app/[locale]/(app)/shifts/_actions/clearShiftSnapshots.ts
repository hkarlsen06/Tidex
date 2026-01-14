"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { verifySession } from "@/data-access/auth";
import { logger } from "@/lib/logger";
import { getCurrentSnapshots } from "@/data-access/snapshots";

export async function clearShiftSnapshots(shiftId: string) {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  // Get current snapshots based on user settings
  const snapshots = await getCurrentSnapshots();

  const { error } = await supabase
    .from("user_shifts")
    .update({
      hourly_wage_snapshot: snapshots.hourly_wage_snapshot,
      supplement_rules_snapshot: snapshots.supplement_rules_snapshot,
    })
    .eq("id", shiftId)
    .eq("user_id", user.id)
    .is("deleted_at", null); // Only update non-deleted shifts

  if (error) {
    logger.error("Failed to update shift snapshots:", error);
    throw error;
  }

  // Invalidate cache and revalidate paths
  invalidateAndRevalidate(user.id);

  return { success: true };
}
