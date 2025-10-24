"use server";

import { NextRequest, NextResponse } from "next/server";

import { createSupabaseServerClient } from "@/lib/supabase/server";
import { getStatsData } from "@/app/(app)/stats/_data/getStatsData";

/**
 * API endpoint for chart data only
 * Separates heavy chart computations from critical stats data
 */
export async function GET(request: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const searchParams = request.nextUrl.searchParams;
  const yearParam = searchParams.get("year");
  const monthParam = searchParams.get("month");

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
    const data = await getStatsData(user.id, { year, month });

    // Return only chart data, excluding critical stats
    const chartData = {
      last6Months: data.last6Months,
      thisWeek: data.thisWeek,
      byDayOfWeek: data.byDayOfWeek,
      thisMonthCumulative: data.thisMonthCumulative,
      yearlyCumulative: data.yearlyCumulative,
      currentMonthBreakdown: data.currentMonthBreakdown,
      yearToDate: data.yearToDate,
    };

    return NextResponse.json(chartData);
  } catch (error) {
    console.error("Failed to load chart data", error);
    return NextResponse.json({ error: "Failed to load chart data" }, { status: 500 });
  }
}
