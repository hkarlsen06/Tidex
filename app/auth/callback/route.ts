import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

import { createSupabaseRouteHandlerClient } from "@/lib/supabase/server";

export async function GET(request: NextRequest) {
  const requestUrl = new URL(request.url);
  const code = requestUrl.searchParams.get("code");
  const next = requestUrl.searchParams.get("next") ?? "/";
  const redirectUrl = new URL(next, requestUrl.origin);
  const response = NextResponse.redirect(redirectUrl);

  if (code) {
    const supabase = createSupabaseRouteHandlerClient(request, response);
    await supabase.auth.exchangeCodeForSession(code);
  }

  return response;
}

export const dynamic = "force-dynamic";
