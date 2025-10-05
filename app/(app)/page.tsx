import { redirect } from "next/navigation";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { Card, CardHeader, CardTitle } from "@/components/app/Card";

export default async function Home() {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  return (
    <main className="flex min-h-[60vh] flex-col items-center justify-center gap-6 text-center">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle>Velkommen tilbake, {user.email}!</CardTitle>
        </CardHeader>
      </Card>
    </main>
  );
}
