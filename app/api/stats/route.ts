"use server";

import { NextRequest, NextResponse } from "next/server";

import { getSession } from "@/data-access/auth";
import { getStatsDataForApi } from "@/data-access/stats";
import type { Locale } from "@/lib/i18n/config";

export async function GET(request: NextRequest) {
  // Manual auth check for API routes (redirect() not supported)
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const searchParams = request.nextUrl.searchParams;
  const yearParam = searchParams.get("year");
  const monthParam = searchParams.get("month");
  const localeParam = searchParams.get("locale") || 'no';

  let year: number | undefined;
  let month: number | undefined;

  if (yearParam != null) {
    year = Number.parseInt(yearParam, 10);
    if (!Number.isFinite(year)) {
      return NextResponse.json({ error: "Invalid year parameter" }, { status: 400 });
    }
  }

  if (monthParam != null) {
    month = Number.parseInt(monthParam, 10);
    if (!Number.isFinite(month) || month < 1 || month > 12) {
      return NextResponse.json({ error: "Invalid month parameter" }, { status: 400 });
    }
  }

  try {
    const data = await getStatsDataForApi(session.user.id, { year, month, locale: localeParam as Locale });
    return NextResponse.json(data, {
      headers: {
        // SECURITY: Disable browser HTTP caching for user-specific data
        // Browser cache doesn't differentiate by user on same device, causing data
        // leaks when users logout/login. Server-side caching via cacheTag() is sufficient.
        'Cache-Control': 'no-store',
      },
    });
  } catch (error) {
    console.error("Failed to load stats data", error);
    return NextResponse.json({ error: "Failed to load stats data" }, { status: 500 });
  }
}
