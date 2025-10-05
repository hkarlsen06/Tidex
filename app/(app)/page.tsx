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
      <h1>Velkommen tilbake, {user.email}!</h1>
    </main>
  );
}
