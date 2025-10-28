"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getUserSubscriptionData } from "@/data-access/subscription";
import { hasProAccess, getUniqueShiftMonths } from "@/lib/subscription/hasProAccess";
import { invalidateUserCache } from "@/data-access/cache";
import { cleanTime } from "@/lib/time-utils";
import { verifySession } from "@/data-access/auth";
import { getUserSettings } from "@/data-access/settings";
import { prepareShiftSnapshots } from "@/lib/payroll/snapshot";

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
  const { user } = await verifySession();
  const supabase = await createSupabaseServerClient();

  const shiftIds = Array.isArray(input.shiftIds) ? input.shiftIds.filter(Boolean) : [];
  if (shiftIds.length === 0) throw new Error("Minst én vakt er påkrevd");
  if (!isISODate(input.targetDate)) throw new Error("Ugyldig datoformat");

  // Separate ghost shifts from regular shifts
  const ghostIds = shiftIds.filter((id) => id.startsWith("ghost-"));
  const regularIds = shiftIds.filter((id) => !id.startsWith("ghost-"));

  const sourceShifts: Array<{
    start_time: string;
    end_time: string;
    series_id?: string;
  }> = [];

  // Fetch regular shifts from user_shifts table
  if (regularIds.length > 0) {
    const { data: regularShifts, error: fetchError } = await supabase
      .from("user_shifts")
      .select("*")
      .eq("user_id", user.id)
      .in("id", regularIds);

    if (fetchError) throw new Error(fetchError.message);
    if (regularShifts) {
      sourceShifts.push(...regularShifts);
    }
  }

  // Handle ghost shifts - extract series information
  if (ghostIds.length > 0) {
    // Parse ghost IDs to get series IDs and their corresponding ghost IDs
    // Format: "ghost-{seriesId}-{date}"
    const ghostBySeriesId = new Map<string, string[]>();
    for (const ghostId of ghostIds) {
      const match = ghostId.match(/^ghost-([a-f0-9-]+)-(\d{4}-\d{2}-\d{2})$/);
      if (match) {
        const seriesId = match[1];
        if (!ghostBySeriesId.has(seriesId)) {
          ghostBySeriesId.set(seriesId, []);
        }
        ghostBySeriesId.get(seriesId)!.push(ghostId);
      }
    }

    if (ghostBySeriesId.size > 0) {
      const { data: seriesShifts, error: seriesError } = await supabase
        .from("series_shifts")
        .select("id, start_time, end_time")
        .eq("user_id", user.id)
        .in("id", Array.from(ghostBySeriesId.keys()));

      if (seriesError) throw new Error(seriesError.message);
      if (seriesShifts) {
        // For each ghost shift, add one entry with the series times
        for (const series of seriesShifts) {
          const ghostsForThisSeries = ghostBySeriesId.get(series.id) || [];
          // Add one entry per ghost (each ghost represents a different date from the series)
          for (const _ of ghostsForThisSeries) {
            sourceShifts.push({
              start_time: series.start_time,
              end_time: series.end_time,
              series_id: undefined, // Don't link copied shifts to the series
            });
          }
        }
      }
    }
  }

  if (sourceShifts.length === 0) {
    throw new Error("Ingen vakter funnet");
  }

  // Server-side validation: Check free tier limitation
  const { subscription, profile } = await getUserSubscriptionData();

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

  // Get current settings and prepare snapshots for copied shifts
  const settings = await getUserSettings();
  const snapshots = settings ? prepareShiftSnapshots(settings) : { hourly_wage_snapshot: null, supplement_rules_snapshot: null };

  // Create new shifts based on source shifts but with the target date
  const rows = sourceShifts.map((shift) => ({
    user_id: user.id,
    shift_date: input.targetDate,
    start_time: cleanTime(shift.start_time),
    end_time: cleanTime(shift.end_time),
    shift_type: shiftTypeFromISODate(input.targetDate),
    hourly_wage_snapshot: snapshots.hourly_wage_snapshot,
    supplement_rules_snapshot: snapshots.supplement_rules_snapshot,
    ...(shift.series_id ? { series_id: shift.series_id } : {}),
  }));

  const { error } = await supabase.from("user_shifts").insert(rows);
  if (error) throw new Error(error.message);

  // Invalidate all cached data for this user
  invalidateUserCache(user.id);

  // Ensure any cached data is fresh on next view
  revalidatePath("/[locale]/shifts", "page");
  revalidatePath("/[locale]", "page");
  revalidatePath("/[locale]/stats", "page");

  return { copied: rows.length };
}
