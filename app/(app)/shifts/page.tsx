import { getComputedShifts, PRESET_RULES } from "./_data/getShifts";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { ShiftsView } from "@components//shifts/ShiftsView";

export default async function ShiftsPage() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    throw new Error("Expected authenticated user in shifts page; middleware should handle redirects.");
  }

  const { shifts, defaultView, aggregates, settings } = await getComputedShifts(user.id);

  return <ShiftsView shifts={shifts} defaultView={defaultView} aggregates={aggregates} userSettings={settings} presetRules={PRESET_RULES} />;
}
