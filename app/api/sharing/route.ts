import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/data-access/auth";
import { getSharedUserShifts } from "@/data-access/sharing";
import { getMonthStart, getMonthEnd } from "@/lib/date-utils";
import { isTaggedError } from "@/lib/errors/tagged";

/**
 * API route for fetching shared user's shifts
 *
 * GET: Fetch shifts for a specific month from a user who has shared with the viewer
 *
 * Query params:
 * - ownerId: string (UUID of the user whose shifts to fetch)
 * - year: number (e.g., 2025)
 * - month: number (1-12)
 */
export async function GET(request: NextRequest) {
  // Manual auth check for API routes (redirect() not supported)
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const ownerId = searchParams.get("ownerId");
  const year = parseInt(searchParams.get("year") || "", 10);
  const month = parseInt(searchParams.get("month") || "", 10);

  if (!ownerId) {
    return NextResponse.json({ error: "ownerId is required" }, { status: 400 });
  }

  if (isNaN(year) || isNaN(month) || month < 1 || month > 12) {
    return NextResponse.json({ error: "Invalid year/month" }, { status: 400 });
  }

  try {
    // getSharedUserShifts verifies share access internally
    // Pass year and month to get correct payoutTaxSettings for this month
    const { shifts, settings, payoutTaxSettings } = await getSharedUserShifts(ownerId, {
      startDate: getMonthStart(year, month),
      endDate: getMonthEnd(year, month),
      limit: 100,
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
          "Cache-Control": "private, max-age=300, stale-while-revalidate=60",
        },
      }
    );
  } catch (error) {
    console.error("Failed to fetch shared shifts:", error);

    // Check for specific tagged error types
    if (isTaggedError(error)) {
      switch (error._tag) {
        case "AuthError":
          return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
        case "NotFoundError":
          return NextResponse.json({ error: "Share not found" }, { status: 404 });
        case "ValidationError":
          return NextResponse.json({ error: "Invalid request" }, { status: 400 });
        // DatabaseError, SupabaseError, etc. fall through to 500
      }
    }

    return NextResponse.json(
      { error: "Failed to fetch shared shifts" },
      { status: 500 }
    );
  }
}
