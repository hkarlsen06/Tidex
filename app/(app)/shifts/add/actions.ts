"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getUserSubscriptionData } from "@/app/(app)/settings/subscription/_data/getSubscription";
import { hasProAccess, getUniqueShiftMonths } from "@/lib/subscription/hasProAccess";
import { invalidateUserCache } from "@/app/(app)/shifts/_data/cache";

type CreateShiftsInput = {
  dates: string[]; // ISO YYYY-MM-DD (local date)
  start: string; // HH:mm
  end: string; // HH:mm
  seriesId?: string;
};

function isISODate(s: string) {
  return /^\d{4}-\d{2}-\d{2}$/.test(s);
}

function isHHMM(s: string) {
  return /^\d{2}:\d{2}$/.test(s);
}

function shiftTypeFromISODate(iso: string) {
  const d = new Date(iso + "T00:00:00Z");
  const wd = d.getUTCDay(); // 0..6
  return wd === 6 ? 1 : wd === 0 ? 2 : 0; // 0=weekday,1=Sat,2=Sun
}

export async function createShifts(input: CreateShiftsInput) {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) throw new Error("Unauthorized");

  const dates = Array.isArray(input.dates) ? input.dates.filter(Boolean) : [];
  if (dates.length === 0) throw new Error("Minst én dato er påkrevd");
  if (!isHHMM(input.start) || !isHHMM(input.end)) throw new Error("Ugyldig tid");
  if (!dates.every(isISODate)) throw new Error("Ugyldig datoformat");

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
    const newMonths = getUniqueShiftMonths(
      dates.map((shift_date) => ({ shift_date }))
    );
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

  const sid = input.seriesId && input.seriesId.trim().length > 0 ? input.seriesId : undefined;

  const rows = dates.map((shift_date) => ({
    user_id: user.id,
    shift_date,
    start_time: input.start,
    end_time: input.end,
    shift_type: shiftTypeFromISODate(shift_date),
    ...(sid ? { series_id: sid } : {}),
  }));

  const { error } = await supabase.from("user_shifts").insert(rows);
  if (error) throw new Error(error.message);

  // Invalidate all cached data for this user
  invalidateUserCache(user.id);

  // Ensure any cached data is fresh on next view
  revalidatePath("/shifts");
  revalidatePath("/");
  revalidatePath("/stats");

  return { inserted: rows.length };
}
