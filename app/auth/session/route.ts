import { NextResponse, type NextRequest } from "next/server";

import { createSupabaseRouteHandlerClient } from "@/lib/supabase/server";

function propagateCookies(from: NextResponse, to: NextResponse) {
  for (const cookie of from.cookies.getAll()) {
    to.cookies.set(cookie);
  }
}

export async function GET(request: NextRequest) {
  const baseResponse = new NextResponse(null, {
    headers: { "cache-control": "no-store" },
  });

  try {
    const supabase = createSupabaseRouteHandlerClient(request, baseResponse);
    const {
      data: { session },
      error,
    } = await supabase.auth.getSession();

    if (error) {
      console.error("[AUTH SESSION] Failed to read session from cookies", error);
      const errorResponse = NextResponse.json(
        { session: null },
        {
          status: 401,
          headers: { "cache-control": "no-store" },
        }
      );

      propagateCookies(baseResponse, errorResponse);
      return errorResponse;
    }

    const successResponse = NextResponse.json(
      { session },
      {
        status: 200,
        headers: { "cache-control": "no-store" },
      }
    );

    propagateCookies(baseResponse, successResponse);
    return successResponse;
  } catch (error) {
    console.error("[AUTH SESSION] Unexpected error while fetching session", error);
    const errorResponse = NextResponse.json(
      { session: null },
      {
        status: 500,
        headers: { "cache-control": "no-store" },
      }
    );

    propagateCookies(baseResponse, errorResponse);
    return errorResponse;
  }
}

export const dynamic = "force-dynamic";
