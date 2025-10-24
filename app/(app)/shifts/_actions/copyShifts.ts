"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getUserSubscriptionData } from "@/app/(app)/settings/subscription/_data/getSubscription";
import { hasProAccess, getUniqueShiftMonths } from "@/lib/subscription/hasProAccess";
import { invalidateUserCache } from "@/app/(app)/shifts/_data/cache";

type CopyShiftsInput = {
  shiftIds: string[];
  targetDate: string; // ISO YYYY-MM-DD (local date)
};

function isISODate(s: string) {
  return /^\d{4}-\d{2}-\d{2}$/.test(s);
}

function shiftTypeFromISODate(iso: string) {
  const d = new Date(iso + "T00:00:00Z");
  const wd = d.getUTCDay(); // 0..6
  return wd === 6 ? 1 : wd === 0 ? 2 : 0; // 0=weekday,1=Sat,2=Sun
}

export async function copyShifts(input: CopyShiftsInput) {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) throw new Error("Unauthorized");

  const shiftIds = Array.isArray(input.shiftIds) ? input.shiftIds.filter(Boolean) : [];
  if (shiftIds.length === 0) throw new Error("Minst én vakt er påkrevd");
  if (!isISODate(input.targetDate)) throw new Error("Ugyldig datoformat");

  // Fetch the source shifts
  const { data: sourceShifts, error: fetchError } = await supabase
    .from("user_shifts")
    .select("*")
    .eq("user_id", user.id)
    .in("id", shiftIds);

  if (fetchError) throw new Error(fetchError.message);
  if (!sourceShifts || sourceShifts.length === 0) {
    throw new Error("Ingen vakter funnet");
  }

  // Server-side validation: Check free tier limitation
  const { subscription, profile } = await getUserSubscriptionData(user.id);

  if (!hasProAccess(subscription, profile)) {
    // User is on free tier - enforce single month limitation
    const { data: existingShifts } = await supabase
      .from("user_shifts")
      .select("shift_date")
      .eq("user_id", user.id);

    const existingMonths = existingShifts
      ? getUniqueShiftMonths(existingShifts)
      : new Set<string>();
    const newMonths = getUniqueShiftMonths([
      { shift_date: input.targetDate },
    ]);
    const allMonths = new Set([
      ...Array.from(existingMonths),
      ...Array.from(newMonths),
    ]);

    if (allMonths.size > 1) {
      throw new Error(
        "Du er på gratisplanen og kan bare ha skift i én måned om gangen. Oppgrader til Pro eller slett skift i andre måneder."
      );
    }
  }

  // Create new shifts based on source shifts but with the target date
  const rows = sourceShifts.map((shift) => ({
    user_id: user.id,
    shift_date: input.targetDate,
    start_time: shift.start_time,
    end_time: shift.end_time,
    shift_type: shiftTypeFromISODate(input.targetDate),
    ...(shift.series_id ? { series_id: shift.series_id } : {}),
  }));

  const { error } = await supabase.from("user_shifts").insert(rows);
  if (error) throw new Error(error.message);

  // Invalidate all cached data for this user
  invalidateUserCache(user.id);

  // Ensure any cached data is fresh on next view
  revalidatePath("/shifts");
  revalidatePath("/");
  revalidatePath("/stats");

  return { copied: rows.length };
}
