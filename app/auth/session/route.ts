import { NextResponse } from "next/server";

import { createSupabaseServerClient } from "@/lib/supabase/server";

export async function GET() {
  try {
    const supabase = await createSupabaseServerClient();
    const {
      data: { session },
      error,
    } = await supabase.auth.getSession();

    if (error) {
      console.error("[AUTH SESSION] Failed to read session from cookies", error);
      return NextResponse.json(
        { session: null },
        {
          status: 401,
          headers: { "cache-control": "no-store" },
        }
      );
    }

    return NextResponse.json(
      { session },
      {
        status: 200,
        headers: { "cache-control": "no-store" },
      }
    );
  } catch (error) {
    console.error("[AUTH SESSION] Unexpected error while fetching session", error);
    return NextResponse.json(
      { session: null },
      {
        status: 500,
        headers: { "cache-control": "no-store" },
      }
    );
  }
}

export const dynamic = "force-dynamic";
