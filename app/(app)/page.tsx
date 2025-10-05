import { redirect } from "next/navigation";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getComputedShifts } from "@/app/(app)/shifts/_data/getShifts";
import { HomeContent } from "./_components/HomeContent";

export default async function Home() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const shifts = await getComputedShifts(user.id);

  return (
    <main className="flex min-h-[60vh] flex-col gap-6 px-4">
      <HomeContent shifts={shifts} />
    </main>
  );
}
