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
  const jobId = searchParams.get("job") || undefined;
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
    const data = await getStatsDataForApi(session.user.id, {
      year,
      month,
      locale: localeParam as Locale,
      jobId,
    });
    return NextResponse.json(data, {
      headers: {
        // Cache for 5 minutes (300 seconds) with stale-while-revalidate
        // 'private' prevents CDN caching; browser caching is made safe via _ck (user cache key)
        // query param passed from client, ensuring different users have different cache entries
        'Cache-Control': 'private, max-age=300, stale-while-revalidate=60',
      },
    });
  } catch (error) {
    console.error("Failed to load stats data", error);
    return NextResponse.json({ error: "Failed to load stats data" }, { status: 500 });
  }
}
