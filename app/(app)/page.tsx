import { redirect } from "next/navigation";

import ShiftCard from "@/components/ShiftCard";
import { getComputedShifts } from "@/app/(app)/shifts/_data/getShifts";
import { createSupabaseServerClient } from "@/lib/supabase/server";

export default async function Home() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const shifts = await getComputedShifts(user.id);
  const highlightedShift = shifts[0];

  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-8 bg-slate-950 px-6 py-16 text-slate-100">
      <div className="flex flex-col items-center gap-2 text-center">
        <h1 className="text-3xl font-semibold">Velkommen tilbake, {user.email}!</h1>
        <p className="max-w-2xl text-sm text-slate-300">
          Her er et forhåndsvist skiftkort basert på dine siste registrerte timer. Gi gjerne tilbakemelding på layout og innhold før vi ruller det ut.
        </p>
      </div>
      {highlightedShift ? (
        <ShiftCard shift={highlightedShift} />
      ) : (
        <div className="rounded-3xl border border-slate-800 bg-slate-900/60 px-8 py-12 text-center text-slate-300">
          <p className="text-lg font-medium">Ingen skift funnet ennå</p>
          <p className="mt-2 text-sm text-slate-400">
            Legg inn et skift for å se hvordan kortet presenterer lønnsberegningene dine.
          </p>
        </div>
      )}
    </main>
  );
}
