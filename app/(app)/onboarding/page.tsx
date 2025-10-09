import Link from "next/link";
import { redirect } from "next/navigation";

import { createSupabaseServerClient } from "@/lib/supabase/server";

export default async function OnboardingPage() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  return (
    <div className="relative flex min-h-screen items-center justify-center py-16">
      <section className="w-full max-w-md rounded-3xl border border-border bg-surface-secondary p-10 shadow-app-lg backdrop-blur text-center">
        <h1 className="mb-4 tracking-wide">Velkommen!</h1>
        <p className="mb-8 text-text-secondary">
          Onboarding kommer snart. Vi jobber med å forbedre opplevelsen din.
        </p>
        <Link
          href="/"
          className="inline-flex items-center justify-center rounded-full bg-gradient-to-r from-brand-gradientStart via-brand-gradientMid to-brand-gradientEnd px-8 py-3 text-sm font-bold uppercase tracking-wide text-text-inverse shadow-lg shadow-brand-gradientMid/40 transition hover:from-brand-gradientMid hover:via-brand-gradientMid hover:to-brand-gradientEnd focus:outline-none focus:ring-4 focus:ring-brand-highlight/60 focus:ring-offset-2 focus:ring-offset-surface-secondary"
        >
          Gå til hjem
        </Link>
      </section>
    </div>
  );
}
