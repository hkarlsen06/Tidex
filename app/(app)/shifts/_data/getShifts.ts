import "server-only";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import {
  computeShift,
  type BonusRule,
  type ShiftRow,
  type ShiftWithComputations,
  type UserSettings,
} from "@/lib/payroll";

const PRESET_RULES: BonusRule[] = [
  { days: [1,2,3,4,5], from: "18:00", to: "21:00", rate: 22 },
  { days: [1,2,3,4,5], from: "21:00", to: "23:59", rate: 45 },
  { days: [6], from: "13:00", to: "15:00", rate: 45 },
  { days: [6], from: "15:00", to: "18:00", rate: 55 },
  { days: [6], from: "18:00", to: "23:59", rate: 110 },
  { days: [7], from: "00:00", to: "23:59", rate: 115 },
];

export async function getComputedShifts(
  userId: string
): Promise<ShiftWithComputations[]> {
  const supabase = await createSupabaseServerClient();

  const { data: settingsRow, error: settingsErr } = await supabase
    .from("user_settings")
    .select("*")
    .eq("user_id", userId)
    .single();

  if (settingsErr && settingsErr.code !== "PGRST116") {
    console.error("user_settings error:", settingsErr);
  }
  const settings: UserSettings = settingsRow ?? {};

  const { data: shifts, error: shiftsErr } = await supabase
    .from("user_shifts")
    .select("*")
    .eq("user_id", userId)
    .order("shift_date", { ascending: false });

  if (shiftsErr) {
    console.error("user_shifts error:", shiftsErr);
    return [];
  }

  return ((shifts ?? []) as ShiftRow[]).map((shift) => ({
    ...shift,
    computed: computeShift(shift, settings, PRESET_RULES),
  }));
}
