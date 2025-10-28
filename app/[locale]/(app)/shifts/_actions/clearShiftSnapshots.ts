"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { verifySession } from "@/data-access/auth";
import { logger } from "@/lib/logger";
import { prepareShiftSnapshots } from "@/lib/payroll/snapshot";

export async function clearShiftSnapshots(shiftId: string) {
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  // Fetch current user settings
  const { data: settings, error: settingsError } = await supabase
    .from("user_settings")
    .select("use_preset, current_wage_level, custom_wage, custom_supplements")
    .eq("user_id", user.id)
    .single();

  if (settingsError) {
    logger.error("Failed to fetch user settings:", settingsError);
    throw settingsError;
  }

  // Prepare snapshots with current values
  const snapshots = prepareShiftSnapshots(settings);

  const { error } = await supabase
    .from("user_shifts")
    .update({
      hourly_wage_snapshot: snapshots.hourly_wage_snapshot,
      supplement_rules_snapshot: snapshots.supplement_rules_snapshot,
    })
    .eq("id", shiftId)
    .eq("user_id", user.id);

  if (error) {
    logger.error("Failed to update shift snapshots:", error);
    throw error;
  }

  // Invalidate cache and revalidate paths
  invalidateAndRevalidate(user.id);

  return { success: true };
}
