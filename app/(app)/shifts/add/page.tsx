import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import AddShiftForm from "./AddShiftForm";
import { getComputedShifts } from "@/app/(app)/shifts/_data/getShifts";

export default async function AddShiftsPage() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  // Load existing shifts to support conflict highlighting in the calendar
  const shifts = await getComputedShifts(user.id);
  const existingShifts = shifts.map((s) => ({
    shift_date: s.shift_date,
    start_time: s.start_time,
    end_time: s.end_time,
  }));

  return <AddShiftForm existingShifts={existingShifts} />;
}
