"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export type UpdateShiftInput = {
  id: string;
  shift_date: string; // ISO YYYY-MM-DD
  start: string; // HH:mm
  end: string; // HH:mm
};

function isISODate(input: string) {
  return /^\d{4}-\d{2}-\d{2}$/.test(input);
}

function isHHMM(input: string) {
  return /^\d{2}:\d{2}$/.test(input);
}

function shiftTypeFromISODate(iso: string) {
  const d = new Date(`${iso}T00:00:00Z`);
  const weekday = d.getUTCDay();
  return weekday === 6 ? 1 : weekday === 0 ? 2 : 0;
}

export async function updateShift(input: UpdateShiftInput) {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    throw new Error("Unauthorized");
  }

  if (!input.id) {
    throw new Error("Skift-ID mangler");
  }

  if (!isISODate(input.shift_date)) {
    throw new Error("Ugyldig dato");
  }

  if (!isHHMM(input.start) || !isHHMM(input.end)) {
    throw new Error("Ugyldig tid");
  }

  const shiftType = shiftTypeFromISODate(input.shift_date);

  const { data: existing, error: fetchError } = await supabase
    .from("user_shifts")
    .select("id")
    .eq("id", input.id)
    .eq("user_id", user.id)
    .single();

  if (fetchError || !existing) {
    throw new Error("Fant ikke skiftet");
  }

  const { error } = await supabase
    .from("user_shifts")
    .update({
      shift_date: input.shift_date,
      start_time: input.start,
      end_time: input.end,
      shift_type: shiftType,
    })
    .eq("id", input.id)
    .eq("user_id", user.id);

  if (error) {
    throw new Error(error.message);
  }

  revalidatePath("/shifts");

  return { updated: 1 };
}
