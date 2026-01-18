import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { getSession } from "@/data-access/auth";
import { getSharedUserShiftsWithViewerId } from "@/data-access/sharing";
import { getMonthStart, getMonthEnd } from "@/lib/date-utils";
import { isTaggedError } from "@/lib/errors/tagged";

/**
 * API route for fetching shared user's shifts
 *
 * GET: Fetch shifts for a specific month from a user who has shared with the viewer
 *
 * Authentication:
 * - iOS: Bearer token in Authorization header
 * - Web: Cookie-based session (fallback)
 *
 * Query params:
 * - ownerId: string (UUID of the user whose shifts to fetch)
 * - year: number (e.g., 2025)
 * - month: number (1-12)
 */
export async function GET(request: NextRequest) {
  // Try to get user ID from Authorization header first (iOS)
  // Fall back to cookie-based session (web)
  let viewerId: string | null = null;

  const authHeader = request.headers.get("Authorization");
  if (authHeader?.startsWith("Bearer ")) {
    const jwt = authHeader.slice(7);

    // Verify JWT and get user - uses server-side validation
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
    const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!;
    const supabase = createClient(supabaseUrl, supabaseKey);
    const { data: { user }, error } = await supabase.auth.getUser(jwt);

    if (error || !user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    viewerId = user.id;
  } else {
    // Fall back to cookie-based session (web clients)
    const session = await getSession();
    if (!session) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
    viewerId = session.user.id;
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
    // getSharedUserShiftsWithViewerId verifies share access internally
    // Pass year and month to get correct payoutTaxSettings for this month
    const { shifts, settings, payoutTaxSettings } = await getSharedUserShiftsWithViewerId(
      viewerId,
      ownerId,
      {
        startDate: getMonthStart(year, month),
        endDate: getMonthEnd(year, month),
        limit: 100,
        year,
        month,
      }
    );

    return NextResponse.json(
      { shifts, settings, payoutTaxSettings },
      {
        headers: {
          // No caching - shifts can change anytime (new shifts trigger notifications)
          "Cache-Control": "private, no-cache, no-store, must-revalidate",
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
