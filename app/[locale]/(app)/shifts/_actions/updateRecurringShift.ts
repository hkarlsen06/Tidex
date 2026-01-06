"use server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { logger } from "@/lib/logger";
import type { SelectedDays, EndCondition } from "@/lib/recurring/types";
import { invalidateAndRevalidate } from "@/lib/revalidation/paths";
import { verifySession } from "@/data-access/auth";
import { ERRORS } from "@/lib/errors/messages";
import {
  enqueueDirectNotification,
  generateMutationId,
  getOwnerName,
} from "@/lib/notifications/enqueue";

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

  // Enqueue notification for recurring shift update
  const mutationId = generateMutationId();
  const ownerName = getOwnerName(user);

  // Get non-muted viewers for this owner
  const { data: shares } = await supabase
    .from("shift_shares")
    .select("viewer_id")
    .eq("owner_id", user.id)
    .eq("muted", false);

  if (shares && shares.length > 0) {
    const { data: prefs } = await supabase
      .from("notification_preferences")
      .select("user_id, shared_shifts_enabled")
      .in("user_id", shares.map((s) => s.viewer_id));

    const prefsMap = new Map(prefs?.map((p) => [p.user_id, p.shared_shifts_enabled]) ?? []);
    const eligibleViewers = shares
      .map((s) => s.viewer_id)
      .filter((viewerId) => prefsMap.get(viewerId) !== false);

    // Enqueue notifications for each eligible viewer
    await Promise.all(
      eligibleViewers.map((viewerId) =>
        enqueueDirectNotification({
          recipientId: viewerId,
          senderId: user.id,
          notificationType: "recurring_shift_updated",
          title: `${ownerName} endret en gjentagende vakt`,
          body: `Trykk for å se endringene`,
          dataPayload: {
            type: "recurring_shift_updated",
            owner_id: user.id,
            recurring_id: id,
          },
          idempotencyKey: `recurring:${id}:update:${viewerId}:${mutationId}`,
        })
      )
    );
  }

  // Invalidate cache and revalidate paths
  invalidateAndRevalidate(user.id);
}
