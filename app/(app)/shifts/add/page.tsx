import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import AddShiftForm from "@/components/shifts/add/AddShiftForm";

export default async function AddShiftsPage() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  // Load only the minimal data needed to highlight conflicts in the calendar
  // Avoids the heavier getComputedShifts() call which computes payroll for every shift
  const { data: rows, error } = await supabase
    .from("user_shifts")
    .select("shift_date,start_time,end_time")
    .eq("user_id", user.id)
    .order("shift_date", { ascending: false });

  if (error) {
    // In case of an error, fall back to an empty list so the page still loads quickly
    console.error("Failed to load existing shifts for add page:", error);
  }

  const existingShifts = (rows ?? []).map((s) => ({
    shift_date: s.shift_date as string,
    start_time: s.start_time as string,
    end_time: s.end_time as string,
  }));

  return <AddShiftForm existingShifts={existingShifts} />;
}
