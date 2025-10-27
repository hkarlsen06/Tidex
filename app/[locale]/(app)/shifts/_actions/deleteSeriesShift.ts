"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { logger } from "@/lib/logger";
import { invalidateUserCache } from "@/app/[locale]/(app)/shifts/_data/cache";

/**
 * Delete an entire series shift from the database
 * - Removes the series row
 * - Revalidates the shifts page
 */
export async function deleteSeriesShift(seriesId: string): Promise<void> {
  const supabase = await createSupabaseServerClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    logger.error("deleteSeriesShift: No user found");
    throw new Error("Unauthorized");
  }

  logger.info("deleteSeriesShift: Attempting to delete series", { seriesId, userId: user.id });

  // First, verify the series exists
  const { data: existingSeries, error: fetchError } = await supabase
    .from("series_shifts")
    .select("id")
    .eq("id", seriesId)
    .eq("user_id", user.id)
    .single();

  if (fetchError) {
    logger.error("Failed to find series for deletion:", fetchError);
    throw new Error("Series not found");
  }

  logger.info("deleteSeriesShift: Found series, proceeding with delete", { existingSeries });

  const { error, count } = await supabase
    .from("series_shifts")
    .delete({ count: "exact" })
    .eq("id", seriesId)
    .eq("user_id", user.id);

  if (error) {
    logger.error("Failed to delete series:", error);
    throw new Error("Failed to delete series");
  }

  logger.info("deleteSeriesShift: Series deleted successfully", { seriesId, deletedCount: count });

  // Invalidate all cached data for this user
  invalidateUserCache(user.id);

  revalidatePath("/[locale]/shifts", "page");
  revalidatePath("/[locale]", "page");
  revalidatePath("/[locale]/stats", "page");
}
