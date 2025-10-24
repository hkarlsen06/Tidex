"use server";

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { invalidateUserCache } from "@/app/(app)/shifts/_data/cache";

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

  // Invalidate all cached data for this user
  invalidateUserCache(user.id);

  revalidatePath("/shifts");
  revalidatePath("/");
  revalidatePath("/stats");

  return { deleted: 1 };
}

