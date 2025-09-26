import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

import { createSupabaseRouteHandlerClient } from "@/lib/supabase/server";

export async function GET(request: NextRequest) {
  const response = NextResponse.redirect(new URL("/login", request.url));
  const supabase = createSupabaseRouteHandlerClient(request, response);

  await supabase.auth.signOut();

  return response;
}

export const dynamic = "force-dynamic";
