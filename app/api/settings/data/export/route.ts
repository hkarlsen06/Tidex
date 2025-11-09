import { NextRequest, NextResponse } from "next/server";

import { createSupabaseRouteHandlerClient } from "@/lib/supabase/server";
import {
  computeShift,
  PRESET_SUPPLEMENT_RULES,
  type ShiftRow,
  type UserSettings,
  type WageSnapshot,
} from "@/lib/payroll";
import { logger } from "@/lib/logger";
import { generateGhostsForMonth } from "@/lib/series/utils";
import type { SeriesShiftRow } from "@/lib/series/types";
import { cleanTime } from "@/lib/time-utils";

const CACHE_CONTROL = { headers: { "cache-control": "no-store" } };

/**
 * Calculate shift type based on date
 * 0 = weekday (Mon-Fri), 1 = Saturday, 2 = Sunday/holiday
 */
function getShiftType(dateISO: string): number {
  const date = new Date(dateISO + 'T00:00:00Z');
  const dayOfWeek = date.getUTCDay();

  if (dayOfWeek === 0) return 2; // Sunday
  if (dayOfWeek === 6) return 1; // Saturday
  return 0; // Weekday (Mon-Fri)
}

export async function GET(request: NextRequest) {
  const baseResponse = new NextResponse(null, CACHE_CONTROL);
  const supabase = createSupabaseRouteHandlerClient(request, baseResponse);
  const searchParams = request.nextUrl.searchParams;
  const fromParam = searchParams.get("from");
  const toParam = searchParams.get("to");

  if ((fromParam && !toParam) || (!fromParam && toParam)) {
    const response = NextResponse.json(
      { error: "Både fra- og tildato må være satt." },
      { status: 400, ...CACHE_CONTROL }
    );
    propagateCookies(baseResponse, response);
    return response;
  }

  if (fromParam && toParam) {
    const fromDate = new Date(`${fromParam}T00:00:00`);
    const toDate = new Date(`${toParam}T00:00:00`);

    if (Number.isNaN(fromDate.getTime()) || Number.isNaN(toDate.getTime())) {
      const response = NextResponse.json(
        { error: "Ugyldige datoer oppgitt." },
        { status: 400, ...CACHE_CONTROL }
      );
      propagateCookies(baseResponse, response);
      return response;
    }

    if (fromDate > toDate) {
      const response = NextResponse.json(
        { error: "Fradato kan ikke være etter tildato." },
        { status: 400, ...CACHE_CONTROL }
      );
      propagateCookies(baseResponse, response);
      return response;
    }
  }

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError) {
    logger.error("[data export] Failed to fetch user:", userError);
    const response = NextResponse.json(
      { error: "Kunne ikke bekrefte innlogging." },
      { status: 401, ...CACHE_CONTROL }
    );
    propagateCookies(baseResponse, response);
    return response;
  }

  if (!user) {
    const response = NextResponse.json(
      { error: "Ikke autentisert." },
      { status: 401, ...CACHE_CONTROL }
    );
    propagateCookies(baseResponse, response);
    return response;
  }

  const { data: settingsRow, error: settingsError } = await supabase
    .from("user_settings")
    .select("*")
    .eq("user_id", user.id)
    .single();

  if (settingsError && settingsError.code !== "PGRST116") {
    logger.error("[data export] Failed to load user settings:", settingsError);
    const response = NextResponse.json(
      { error: "Kunne ikke laste brukerinnstillinger." },
      { status: 500, ...CACHE_CONTROL }
    );
    propagateCookies(baseResponse, response);
    return response;
  }

  const settings: UserSettings = settingsRow ?? {};

  let query = supabase
    .from("user_shifts")
    .select("*")
    .eq("user_id", user.id)
    .order("shift_date", { ascending: true })
    .order("start_time", { ascending: true });

  if (fromParam) {
    query = query.gte("shift_date", fromParam);
  }

  if (toParam) {
    query = query.lte("shift_date", toParam);
  }

  const { data: shifts, error: shiftsError } = await query;

  if (shiftsError) {
    logger.error("[data export] Failed to load shifts:", shiftsError);
    const response = NextResponse.json(
      { error: "Kunne ikke hente vakter." },
      { status: 500, ...CACHE_CONTROL }
    );
    propagateCookies(baseResponse, response);
    return response;
  }

  // Fetch series shifts
  const { data: seriesShifts, error: seriesError } = await supabase
    .from("series_shifts")
    .select("*")
    .eq("user_id", user.id);

  if (seriesError) {
    logger.error("[data export] Failed to load series shifts:", seriesError);
    const response = NextResponse.json(
      { error: "Kunne ikke hente serieskift." },
      { status: 500, ...CACHE_CONTROL }
    );
    propagateCookies(baseResponse, response);
    return response;
  }

  // Fetch wage snapshots for all shift dates
  const { data: allSnapshots, error: snapshotsError } = await supabase
    .from('wage_snapshots')
    .select('*')
    .eq('user_id', user.id)
    .order('from_date', { ascending: false, nullsFirst: false });

  if (snapshotsError) {
    logger.error("[data export] Failed to load wage snapshots:", snapshotsError);
  }

  const snapshots = (allSnapshots ?? []) as WageSnapshot[];
  const baselineSnapshot = snapshots.find((snapshot) => snapshot.from_date === null);

  // Create a function to get the applicable snapshot for a shift date
  const getSnapshotForDate = (shiftDate: string): WageSnapshot | null => {
    // Find the first dated snapshot where from_date <= shiftDate
    const applicableSnapshot = snapshots.find(
      (snapshot) => snapshot.from_date !== null && snapshot.from_date <= shiftDate
    );

    // Use dated snapshot if found, otherwise fall back to baseline
    return applicableSnapshot || baselineSnapshot || null;
  };

  // Compute regular shifts
  const computedShifts = (shifts ?? []).map((shift) => {
    const snapshot = getSnapshotForDate(shift.shift_date);
    const computed = computeShift(shift as ShiftRow, settings, PRESET_SUPPLEMENT_RULES, snapshot);
    return {
      id: shift.id,
      date: shift.shift_date,
      startTime: shift.start_time,
      endTime: shift.end_time,
      type: getShiftType(shift.shift_date),
      seriesId: null,
      calc: {
        hours: computed.paidHours,
        baseWage: computed.basePay,
        supplement: computed.supplementPay,
        total: computed.gross,
      },
    };
  });

  // Generate and compute ghost shifts from series
  const ghostShifts = [];

  if (seriesShifts && seriesShifts.length > 0) {
    // Determine date range for ghost generation
    let startDate: Date;
    let endDate: Date;

    if (fromParam && toParam) {
      startDate = new Date(fromParam + 'T00:00:00Z');
      endDate = new Date(toParam + 'T00:00:00Z');
    } else {
      // If no date range specified, generate for all time
      // Use a reasonable default range (e.g., past 2 years to future 1 year)
      const now = new Date();
      startDate = new Date(now.getFullYear() - 2, 0, 1);
      endDate = new Date(now.getFullYear() + 1, 11, 31);
    }

    const startYear = startDate.getUTCFullYear();
    const startMonth = startDate.getUTCMonth() + 1;
    const endYear = endDate.getUTCFullYear();
    const endMonth = endDate.getUTCMonth() + 1;

    // Generate ghosts for each series
    for (const series of seriesShifts as SeriesShiftRow[]) {
      let currentYear = startYear;
      let currentMonth = startMonth;

      while (
        currentYear < endYear ||
        (currentYear === endYear && currentMonth <= endMonth)
      ) {
        const ghosts = generateGhostsForMonth({ year: currentYear, month: currentMonth }, {
          start_time: cleanTime(series.start_time),
          end_time: cleanTime(series.end_time),
          repeat_interval_weeks: series.repeat_interval_weeks as 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8,
          selected_days: series.selected_days,
          end_condition: series.end_condition,
          exclusions: series.exclusions || []
        });

        // Compute each ghost
        for (const ghost of ghosts) {
          try {
            const snapshot = getSnapshotForDate(ghost.date);
            const ghostShiftRow: ShiftRow = {
              id: `ghost-${series.id}-${ghost.date}`,
              user_id: user.id,
              shift_date: ghost.date,
              start_time: cleanTime(series.start_time),
              end_time: cleanTime(series.end_time),
              series_id: series.id,
              series_anchor_weekday: ghost.weekday
            };

            const computed = computeShift(
              ghostShiftRow,
              settings,
              PRESET_SUPPLEMENT_RULES,
              snapshot
            );

            ghostShifts.push({
              id: ghostShiftRow.id,
              date: ghost.date,
              startTime: cleanTime(series.start_time),
              endTime: cleanTime(series.end_time),
              type: getShiftType(ghost.date),
              seriesId: series.id,
              calc: {
                hours: computed.paidHours,
                baseWage: computed.basePay,
                supplement: computed.supplementPay,
                total: computed.gross,
              },
            });
          } catch (err) {
            logger.error(`[data export] Failed to compute ghost for series ${series.id} on ${ghost.date}:`, err);
          }
        }

        // Move to next month
        currentMonth++;
        if (currentMonth > 12) {
          currentMonth = 1;
          currentYear++;
        }
      }
    }
  }

  // Merge regular shifts and ghost shifts, then sort by date and time
  const allShifts = [...computedShifts, ...ghostShifts].sort((a, b) => {
    const dateCompare = a.date.localeCompare(b.date);
    if (dateCompare !== 0) return dateCompare;
    return a.startTime.localeCompare(b.startTime);
  });

  const response = NextResponse.json(
    {
      generatedAt: new Date().toISOString(),
      shifts: allShifts,
    },
    { status: 200, ...CACHE_CONTROL }
  );

  propagateCookies(baseResponse, response);
  return response;
}

function propagateCookies(from: NextResponse, to: NextResponse) {
  for (const cookie of from.cookies.getAll()) {
    to.cookies.set(cookie);
  }
}
