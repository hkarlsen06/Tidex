"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function deleteShift(shiftId: string) {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) throw new Error("Unauthorized");
  if (!shiftId) throw new Error("Ugyldig skift-ID");

  const { error } = await supabase
    .from("user_shifts")
    .delete()
    .eq("id", shiftId)
    .eq("user_id", user.id);

  if (error) throw new Error(error.message);

  revalidatePath("/shifts");
  return { deleted: 1 };
}

