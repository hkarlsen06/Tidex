import { redirect } from "next/navigation";

import { createSupabaseServerClient } from "@/lib/supabase/server";

export default async function Home() {
  const supabase = createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-6 bg-slate-950 px-8 py-16 text-center text-slate-100">
      <h1 className="text-3xl font-bold">Velkommen tilbake!</h1>
      <p className="max-w-xl text-base text-slate-300">
        Du er logget inn som <span className="font-semibold text-white">{user.email}</span>.
        Start byggingen ved å oppdatere <code className="rounded bg-slate-900 px-2 py-1">app/page.tsx</code> eller legge til nye ruter i <code className="rounded bg-slate-900 px-2 py-1">app</code>-mappen.
      </p>
    </main>
  );
}
