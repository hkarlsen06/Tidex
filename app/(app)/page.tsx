import { redirect } from "next/navigation";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getComputedShifts } from "@/app/(app)/shifts/_data/getShifts";
import { HomeContent } from "../../components/app/HomeContent";

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
    <div className="grid min-h-full place-items-center w-full">
      <HomeContent shifts={shifts} />
    </div>
  );
}
