"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { invalidateUserCache } from "@/data-access/cache";
import { verifySession } from "@/data-access/auth";
import { logger } from "@/lib/logger";
import { prepareShiftSnapshots } from "@/lib/payroll/snapshot";

export async function bulkClearSnapshots(
  startDate: string,
  endDate: string
): Promise<{ success: boolean; count: number }> {
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

  // Invalidate cache
  invalidateUserCache(user.id);

  // Revalidate paths
  revalidatePath("/[locale]/shifts", "page");
  revalidatePath("/[locale]", "page");
  revalidatePath("/[locale]/stats", "page");

  return { success: true, count };
}
