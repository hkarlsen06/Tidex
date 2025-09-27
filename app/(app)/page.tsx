import { redirect } from "next/navigation";

import { createSupabaseServerClient } from "@/lib/supabase/server";

export default async function Home() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  return (
    <main className="flex min-h-[60vh] flex-col items-center justify-center gap-6 text-center text-text-primary">
      <h1 className="text-3xl font-semibold">Velkommen tilbake, {user.email}!</h1>
      <p className="max-w-xl text-sm text-text-secondary">
        Naviger til skiftoversikten for å se dine registrerte skift med full lønnsberegning.
      </p>
    </main>
  );
}
