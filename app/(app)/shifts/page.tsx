import { Suspense } from "react";
import { redirect } from "next/navigation";
import type { Metadata } from "next";
import { getComputedShifts, PRESET_RULES } from "./_data/getShifts";
import { createSupabaseServerClient } from "@/lib/supabase/server";
import { ShiftsView } from "@components//shifts/ShiftsView";
import { ShiftsSkeleton } from "@/components/app/skeletons/ShiftsSkeleton";

export const metadata: Metadata = {
  title: "Vakter",
};

export default async function ShiftsPage() {
  // Layout guarantees user is authenticated
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // This should never happen (layout redirects), but TypeScript needs the guard
  if (!user) {
    redirect("/login");
  }

  return (
    <Suspense fallback={<ShiftsSkeleton />}>
      <ShiftsDataLoader userId={user.id} />
    </Suspense>
  );
}

async function ShiftsDataLoader({ userId }: { userId: string }) {
  const { shifts, defaultView, settings } = await getComputedShifts(userId);
  return <ShiftsView shifts={shifts} defaultView={defaultView} userSettings={settings} presetRules={PRESET_RULES} />;
}
