import { NextRequest, NextResponse } from "next/server";

import { createSupabaseRouteHandlerClient } from "@/lib/supabase/server";
import type { ShiftRow, UserSettings, BonusRule } from "@/lib/payroll";
import { computeShift } from "@/lib/payroll";
import { logger } from "@/lib/logger";

const PRESET_RULES: BonusRule[] = [
  { days: [1, 2, 3, 4, 5], from: "18:00", to: "21:00", rate: 22 },
  { days: [1, 2, 3, 4, 5], from: "21:00", to: "23:59", rate: 45 },
  { days: [6], from: "13:00", to: "15:00", rate: 45 },
  { days: [6], from: "15:00", to: "18:00", rate: 55 },
  { days: [6], from: "18:00", to: "23:59", rate: 110 },
  { days: [7], from: "00:00", to: "23:59", rate: 115 },
];

const CACHE_CONTROL = { headers: { "cache-control": "no-store" } };

type ShiftRowWithMeta = ShiftRow & {
  shift_type?: number | null;
  series_id?: string | null;
};

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
    .select("id, user_id, shift_date, start_time, end_time, shift_type, series_id")
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

  const computedShifts = (shifts ?? []).map((shift) => {
    const computed = computeShift(shift as ShiftRow, settings, PRESET_RULES);
    const { shift_type, series_id, ...rest } = shift as ShiftRowWithMeta;
    return {
      id: rest.id,
      date: rest.shift_date,
      startTime: rest.start_time,
      endTime: rest.end_time,
      type: shift_type ?? 0,
      seriesId: series_id ?? null,
      calc: {
        hours: computed.paidHours,
        baseWage: computed.basePay,
        bonus: computed.bonusPay,
        total: computed.gross,
      },
    };
  });

  const response = NextResponse.json(
    {
      generatedAt: new Date().toISOString(),
      shifts: computedShifts,
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
