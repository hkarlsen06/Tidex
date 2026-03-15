"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { verifySession } from "@/data-access/auth";
import { logger } from "@/lib/logger";

export async function clearShiftSnapshots(shiftId: string) {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  const { error } = await supabase
    .from("user_shifts")
    .select("id")
    .eq("id", shiftId)
    .eq("user_id", user.id)
    .is("deleted_at", null)
    .single();

  if (error) {
    logger.error("Failed to verify shift before clearing deprecated snapshots:", error);
    throw error;
  }

  logger.info("clearShiftSnapshots is deprecated; per-shift snapshots are no longer stored", {
    userId: user.id,
    shiftId,
  });
  invalidateAndRevalidate(user.id);
  return {
    success: true,
    deprecated: true,
    message:
      "Per-shift snapshots are no longer stored. Wage is resolved from wage entries by date and workplace.",
  };
}
