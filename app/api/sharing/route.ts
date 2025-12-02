import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/data-access/auth";
import { getSharedUserShifts } from "@/data-access/sharing";
import { getMonthStart, getMonthEnd } from "@/lib/date-utils";

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
    const { shifts, settings } = await getSharedUserShifts(ownerId, {
      startDate: getMonthStart(year, month),
      endDate: getMonthEnd(year, month),
      limit: 100,
    });

    return NextResponse.json(
      { shifts, settings },
      {
        headers: {
          // Cache for 5 minutes (300 seconds)
          // 'private' ensures cache is user-specific, not shared across users
          "Cache-Control": "private, max-age=300, stale-while-revalidate=60",
        },
      }
    );
  } catch (error) {
    console.error("Failed to fetch shared shifts:", error);

    // Check for specific error types
    const errorMessage =
      error instanceof Error ? error.message : "Failed to fetch shared shifts";

    // If access denied or not found, return 403/404
    if (
      errorMessage.includes("permission") ||
      errorMessage.includes("access")
    ) {
      return NextResponse.json(
        { error: "Access denied" },
        { status: 403 }
      );
    }

    return NextResponse.json(
      { error: "Failed to fetch shared shifts" },
      { status: 500 }
    );
  }
}
