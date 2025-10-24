import "server-only";
import { cache } from "react";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  computeShift,
  type ShiftRow,
  type ShiftWithComputations,
  type UserSettings,
  PRESET_SUPPLEMENT_RULES,
} from "@/lib/payroll";
import { logger } from "@/lib/logger";

export const PRESET_RULES = PRESET_SUPPLEMENT_RULES;

export type ShiftsAggregates = {
  totalHours: number;
  totalEarnings: number;
};

export const getComputedShifts = cache(async (
  userId: string
): Promise<{
  shifts: ShiftWithComputations[],
  defaultView: string,
  settings: UserSettings,
  aggregates: ShiftsAggregates
}> => {
  const supabase = await createSupabaseServerClient();

  const { data: settingsRow, error: settingsErr } = await supabase
    .from("user_settings")
    .select("*")
    .eq("user_id", userId)
    .single();

  if (settingsErr && settingsErr.code !== "PGRST116") {
    logger.error("Failed to load user settings:", settingsErr);
    throw new Error("Kunne ikke laste brukerinnstillinger. Vennligst prøv igjen senere.");
  }
  const settings: UserSettings = settingsRow ?? {};

  const { data: shifts, error: shiftsErr } = await supabase
    .from("user_shifts")
    .select("*")
    .eq("user_id", userId)
    .order("shift_date", { ascending: false });

  if (shiftsErr) {
    logger.error("user_shifts error:", shiftsErr);
    return {
      shifts: [],
      defaultView: "calendar",
      settings,
      aggregates: { totalHours: 0, totalEarnings: 0 }
    };
  }

  const computedShifts = ((shifts ?? []) as ShiftRow[]).map((shift) => ({
    ...shift,
    computed: computeShift(shift, settings, PRESET_RULES),
  }));

  // Compute aggregates once on the server
  const aggregates: ShiftsAggregates = computedShifts.reduce(
    (acc, shift) => ({
      totalHours: acc.totalHours + shift.computed.paidHours,
      totalEarnings: acc.totalEarnings + shift.computed.gross,
    }),
    { totalHours: 0, totalEarnings: 0 }
  );

  return {
    shifts: computedShifts,
    defaultView: (settingsRow as any)?.default_shifts_view || "calendar",
    settings,
    aggregates
  };
});
