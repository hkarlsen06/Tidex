import "server-only";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { computeShift, ShiftRow, UserSettings, BonusRule } from "@/lib/payroll";

const PRESET_RULES: BonusRule[] = [
  { days: [1,2,3,4,5], from: "18:00", to: "21:00", rate: 22 },
  { days: [1,2,3,4,5], from: "21:00", to: "23:59", rate: 45 },
  { days: [6], from: "13:00", to: "15:00", rate: 45 },
  { days: [6], from: "15:00", to: "18:00", rate: 55 },
  { days: [6], from: "18:00", to: "23:59", rate: 110 },
  { days: [7], from: "00:00", to: "23:59", rate: 115 },
];

export async function getComputedShifts(userId: string) {
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
    { cookies: cookies() }
  );

  const { data: settingsRow } = await supabase
    .from("user_settings")
    .select("*")
    .eq("user_id", userId)
    .single();

  const settings: UserSettings = settingsRow ?? {};

  const { data: shifts } = await supabase
    .from("user_shifts")
    .select("*")
    .eq("user_id", userId)
    .order("shift_date", { ascending: false });

  const computed = (shifts ?? []).map((s: ShiftRow) =>
    computeShift(s, settings, PRESET_RULES)
  );

  return computed;
}
