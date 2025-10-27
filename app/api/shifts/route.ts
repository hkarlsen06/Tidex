import { NextRequest, NextResponse } from "next/server";
import { getComputedShifts } from "@/app/[locale]/(app)/shifts/_data/getShifts";
import { getMonthStart, getMonthEnd } from "@/lib/date-utils";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { generateGhostsForMonth } from "@/lib/series/utils";
import { computeShift, PRESET_SUPPLEMENT_RULES, type ShiftWithComputations } from "@/lib/payroll";
import type { SeriesShiftRow } from "@/lib/series/types";

/**
 * API route for fetching shifts for a specific month
 * Used for dynamic month navigation when user navigates to different years
 *
 * Query params:
 * - year: number (e.g., 2025)
 * - month: number (1-12)
 */
export async function GET(request: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const year = parseInt(searchParams.get('year') || '');
  const month = parseInt(searchParams.get('month') || '');

  if (!year || !month || month < 1 || month > 12) {
    return NextResponse.json({ error: 'Invalid year/month' }, { status: 400 });
  }

  try {
    const { shifts, settings } = await getComputedShifts(user.id, {
      startDate: getMonthStart(year, month),
      endDate: getMonthEnd(year, month),
      limit: 100
    });

    // Load series shifts and generate ghosts for the month
    const { data: seriesShifts, error: seriesError } = await supabase
      .from("series_shifts")
      .select("*")
      .eq("user_id", user.id);

    if (seriesError) {
      console.error('Failed to load series shifts:', seriesError);
      // Continue without series shifts
    }

    const seriesGhosts: ShiftWithComputations[] = [];
    if (seriesShifts && seriesShifts.length > 0) {
      for (const series of seriesShifts as SeriesShiftRow[]) {
        const ghosts = generateGhostsForMonth({ year, month }, {
          start_time: series.start_time.split('+')[0] || series.start_time, // Strip timezone
          end_time: series.end_time.split('+')[0] || series.end_time, // Strip timezone
          repeat_interval_weeks: series.repeat_interval_weeks as 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8,
          selected_days: series.selected_days,
          end_condition: series.end_condition,
          exclusions: series.exclusions || []
        });

        // Compute each ghost
        for (const ghost of ghosts) {
          try {
            const computed = computeShift(
              {
                id: `ghost-${series.id}-${ghost.date}`,
                user_id: user.id,
                shift_date: ghost.date,
                start_time: series.start_time.split('+')[0] || series.start_time,
                end_time: series.end_time.split('+')[0] || series.end_time,
                series_id: series.id,
                series_anchor_weekday: ghost.weekday
              },
              settings,
              PRESET_SUPPLEMENT_RULES
            );

            seriesGhosts.push({
              id: `ghost-${series.id}-${ghost.date}`,
              user_id: user.id,
              shift_date: ghost.date,
              start_time: series.start_time.split('+')[0] || series.start_time,
              end_time: series.end_time.split('+')[0] || series.end_time,
              series_id: series.id,
              series_anchor_weekday: ghost.weekday,
              computed
            });
          } catch (err) {
            console.error(`Failed to compute ghost for series ${series.id} on ${ghost.date}:`, err);
          }
        }
      }
    }

    // Merge shifts and series ghosts
    const allShifts = [...shifts, ...seriesGhosts];

    return NextResponse.json(
      { shifts: allShifts, settings },
      {
        headers: {
          // Cache for 5 minutes (300 seconds)
          // 'private' ensures cache is user-specific, not shared across users
          'Cache-Control': 'private, max-age=300, stale-while-revalidate=60',
        },
      }
    );
  } catch (error) {
    console.error('Failed to fetch shifts:', error);
    return NextResponse.json(
      { error: 'Failed to fetch shifts' },
      { status: 500 }
    );
  }
}
