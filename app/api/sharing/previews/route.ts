import { NextResponse } from "next/server";
import { getSession } from "@/data-access/auth";
import { getSharerShiftPreviewsWithViewerId } from "@/data-access/sharing";

// Ensure Next.js never caches this route or its fetch calls
export const dynamic = 'force-dynamic';
export const fetchCache = 'force-no-store';

/**
 * API route for fetching shift previews for all sharers
 *
 * GET: Fetch the most relevant shift (active > upcoming > past) for each sharer
 *
 * Authentication:
 * - iOS: Bearer token in Authorization header (handled by getSession)
 * - Web: Cookie-based session (handled by getSession)
 *
 * Query params:
 * - sharerIds: comma-separated list of UUIDs
 */
export async function GET(request: Request) {
  // getSession now handles both Bearer tokens (iOS) and cookies (web)
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { searchParams } = new URL(request.url);
  const sharerIdsParam = searchParams.get("sharerIds");

  if (!sharerIdsParam) {
    return NextResponse.json({ error: "sharerIds is required" }, { status: 400 });
  }

  const sharerIds = sharerIdsParam.split(",").filter(Boolean);
  if (sharerIds.length === 0) {
    return NextResponse.json({ previews: [] });
  }

  try {
    // Use the shared DAL function - auth already verified by getSession
    const previews = await getSharerShiftPreviewsWithViewerId(session.user.id, sharerIds);

    return NextResponse.json(
      { previews },
      {
        headers: {
          // No caching - previews should reflect latest shifts
          "Cache-Control": "private, no-cache, no-store, must-revalidate",
        },
      }
    );
  } catch (error) {
    console.error("Failed to fetch shift previews:", error);
    return NextResponse.json(
      { error: "Failed to fetch shift previews" },
      { status: 500 }
    );
  }
}
