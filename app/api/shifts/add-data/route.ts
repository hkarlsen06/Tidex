import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/data-access/auth";
import { getUserSettings } from "@/data-access/settings";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { PRESET_RULES } from "@/data-access/shifts";
import { generateGhostsForMonth } from "@/lib/series/utils";
import type { SeriesShiftRow } from "@/lib/series/types";
import { cleanTime } from "@/lib/time-utils";
import { logger } from "@/lib/logger";
import { getUserWageSnapshots } from "@/data-access/wage-snapshots";

/**
 * GET /api/shifts/add-data
 * Fetch data needed for the add shift form
 *
 * Returns:
 * - existingShifts: Array of existing shifts (for conflict detection)
 * - userSettings: User's pay/display settings
 * - presetRules: Preset wage rules
 * - wageSnapshots: Historical wage snapshots
 */
export async function GET(request: NextRequest) {
  // Manual auth check for API routes
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const userId = session.user.id;

    // Load user settings
    const userSettings = (await getUserSettings(userId)) ?? {};

    const supabase = await createSupabaseServerClient();

    // Load existing shifts (minimal data for conflict detection)
    const { data: rows, error } = await supabase
      .from("user_shifts")
      .select("shift_date,start_time,end_time")
      .eq("user_id", userId)
      .order("shift_date", { ascending: false });

    if (error) {
      console.error("Failed to load existing shifts:", error);
    }

    const existingShifts = (rows ?? []).map((s) => ({
      shift_date: s.shift_date as string,
      start_time: s.start_time as string,
      end_time: s.end_time as string,
    }));

    // Load series shifts and generate ghosts for next 6 months
    const { data: seriesShifts, error: seriesError } = await supabase
      .from("series_shifts")
      .select("*")
      .eq("user_id", userId);

    if (seriesError) {
      logger.error("Failed to load series shifts:", seriesError);
    }

    const seriesGhosts: Array<{ shift_date: string; start_time: string; end_time: string }> = [];
    if (seriesShifts && seriesShifts.length > 0) {
      const now = new Date();
      const currentYear = now.getFullYear();
      const currentMonth = now.getMonth() + 1;

      for (const series of seriesShifts as SeriesShiftRow[]) {
        for (let i = 0; i < 6; i++) {
          let targetMonth = currentMonth + i;
          let targetYear = currentYear;

          while (targetMonth > 12) {
            targetMonth -= 12;
            targetYear++;
          }

          const ghosts = generateGhostsForMonth(
            { year: targetYear, month: targetMonth },
            {
              start_time: cleanTime(series.start_time),
              end_time: cleanTime(series.end_time),
              repeat_interval_weeks: series.repeat_interval_weeks as 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8,
              selected_days: series.selected_days,
              end_condition: series.end_condition,
              exclusions: series.exclusions || []
            }
          );

          for (const ghost of ghosts) {
            seriesGhosts.push({
              shift_date: ghost.date,
              start_time: cleanTime(series.start_time),
              end_time: cleanTime(series.end_time)
            });
          }
        }
      }
    }

    // Combine regular shifts and series ghosts
    const allExistingShifts = [...existingShifts, ...seriesGhosts];

    // Load wage snapshots
    const wageSnapshots = await getUserWageSnapshots();

    return NextResponse.json(
      {
        existingShifts: allExistingShifts,
        userSettings,
        presetRules: PRESET_RULES,
        wageSnapshots,
      },
      {
        headers: {
          // Cache for 5 minutes
          'Cache-Control': 'private, max-age=300, stale-while-revalidate=60',
        },
      }
    );
  } catch (error) {
    console.error('Failed to fetch add shift data:', error);
    return NextResponse.json(
      { error: 'Failed to fetch add shift data' },
      { status: 500 }
    );
  }
}
