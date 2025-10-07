import { redirect } from "next/navigation";

import { getComputedShifts } from "./_data/getShifts";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { ShiftsView } from "@components//shifts/ShiftsView";

export default async function ShiftsPage() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const shifts = await getComputedShifts(user.id);

  return <ShiftsView shifts={shifts} />;
}
