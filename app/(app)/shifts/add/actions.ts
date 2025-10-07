"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";

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

  // Ensure any cached data is fresh on next view
  revalidatePath("/shifts");

  return { inserted: rows.length };
}

