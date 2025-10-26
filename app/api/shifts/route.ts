import { NextRequest, NextResponse } from "next/server";
import { getComputedShifts } from "@/app/[locale]/(app)/shifts/_data/getShifts";
import { getMonthStart, getMonthEnd } from "@/lib/date-utils";
import { createSupabaseServerClient } from "@/lib/supabase/server";

/**
 * API route for fetching shifts for a specific month
 * Used for dynamic month navigation when user navigates to different years
 *
 * Query params:
 * - year: number (e.g., 2025)
 * - month: number (1-12)
 */
export async function GET(request: NextRequest) {
  const supabase = await createSupabaseServerClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const year = parseInt(searchParams.get('year') || '');
  const month = parseInt(searchParams.get('month') || '');

  if (!year || !month || month < 1 || month > 12) {
    return NextResponse.json({ error: 'Invalid year/month' }, { status: 400 });
  }

  try {
    const { shifts, settings } = await getComputedShifts(user.id, {
      startDate: getMonthStart(year, month),
      endDate: getMonthEnd(year, month),
      limit: 100
    });

    return NextResponse.json(
      { shifts, settings },
      {
        headers: {
          // Cache for 5 minutes (300 seconds)
          // 'private' ensures cache is user-specific, not shared across users
          'Cache-Control': 'private, max-age=300, stale-while-revalidate=60',
        },
      }
    );
  } catch (error) {
    console.error('Failed to fetch shifts:', error);
    return NextResponse.json(
      { error: 'Failed to fetch shifts' },
      { status: 500 }
    );
  }
}
