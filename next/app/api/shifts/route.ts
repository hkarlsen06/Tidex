import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/data-access/auth";
import { getComputedShiftsForApi } from "@/data-access/shifts";
import { getMonthStart, getMonthEnd } from "@/lib/date-utils";
import { createShifts } from "@/app/[locale]/(app)/shifts/add/actions";

/**
 * API route for shift operations
 *
 * GET: Fetch shifts for a specific month
 * POST: Create new shift(s)
 */

/**
 * GET /api/shifts
 * Fetch shifts for a specific month
 *
 * Query params:
 * - year: number (e.g., 2025)
 * - month: number (1-12)
 * - job: optional job ID filter
 */
export async function GET(request: NextRequest) {
  // Manual auth check for API routes (redirect() not supported)
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const year = parseInt(searchParams.get('year') || '', 10);
  const month = parseInt(searchParams.get('month') || '', 10);
  const jobId = searchParams.get('job') || undefined;

  if (isNaN(year) || isNaN(month) || month < 1 || month > 12) {
    return NextResponse.json({ error: 'Invalid year/month' }, { status: 400 });
  }

  try {
    // getComputedShifts already includes recurring virtual shifts, so no need to generate them again
    const { shifts, settings, payoutTaxSettings } = await getComputedShiftsForApi(session.user.id, {
      startDate: getMonthStart(year, month),
      endDate: getMonthEnd(year, month),
      limit: 100,
      jobId,
      year,
      month,
    });

    return NextResponse.json(
      { shifts, settings, payoutTaxSettings },
      {
        headers: {
          // Cache for 5 minutes (300 seconds) with stale-while-revalidate
          // 'private' prevents CDN caching; browser caching is made safe via _ck (user cache key)
          // query param passed from client, ensuring different users have different cache entries
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

/**
 * POST /api/shifts
 * Create new shift(s)
 *
 * Body:
 * {
 *   dates: string[], // Array of ISO dates (YYYY-MM-DD)
 *   start: string,   // Start time (HH:mm)
 *   end: string,     // End time (HH:mm)
 *   recurringId?: string, // Optional recurring ID
 *   jobId?: string // Optional job ID
 * }
 */
export async function POST(request: NextRequest) {
  // Manual auth check for API routes
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    let body;
    try {
      body = await request.json();
    } catch {
      return NextResponse.json(
        { error: 'Invalid JSON in request body' },
        { status: 400 }
      );
    }

    // Validate required fields
    if (!body.dates || !Array.isArray(body.dates) || body.dates.length === 0) {
      return NextResponse.json(
        { error: 'dates array is required' },
        { status: 400 }
      );
    }

    if (!body.start || !body.end) {
      return NextResponse.json(
        { error: 'start and end times are required' },
        { status: 400 }
      );
    }

    // Call the existing server action
    const result = await createShifts({
      dates: body.dates,
      start: body.start,
      end: body.end,
      recurringId: body.recurringId,
      jobId: body.jobId,
    });

    return NextResponse.json(result, { status: 201 });
  } catch (error) {
    console.error('Failed to create shifts:', error);

    const errorMessage = error instanceof Error ? error.message : 'Failed to create shifts';
    const statusCode = errorMessage.includes('Unauthorized') ? 401
                     : errorMessage.includes('limit') || errorMessage.includes('gratisplan') ? 402
                     : 500;

    return NextResponse.json(
      { error: errorMessage },
      { status: statusCode }
    );
  }
}
