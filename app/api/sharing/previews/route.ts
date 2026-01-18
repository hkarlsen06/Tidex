import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { getSession } from "@/data-access/auth";
import { getSharedUserShiftsWithViewerId } from "@/data-access/sharing";
import type { ShiftWithComputations } from "@/lib/payroll";

/**
 * Parse shift times into Date objects, handling cross-midnight shifts
 */
function parseShiftTimes(
  shiftDate: string,
  startTime: string,
  endTime: string
): { start: Date; end: Date } {
  const [startH, startM] = startTime.split(":").map(Number);
  const [endH, endM] = endTime.split(":").map(Number);

  const start = new Date(shiftDate + "T00:00:00");
  start.setHours(startH, startM, 0, 0);

  const end = new Date(shiftDate + "T00:00:00");
  end.setHours(endH, endM, 0, 0);

  // Handle cross-midnight: if end <= start, end is next day
  if (end <= start) {
    end.setDate(end.getDate() + 1);
  }

  return { start, end };
}

type ShiftPreviewStatus = "active" | "upcoming" | "past";

interface SharerPreview {
  sharerId: string;
  shift: ShiftWithComputations | null;
  status: ShiftPreviewStatus | null;
  showEarnings: boolean;
}

/**
 * API route for fetching shift previews for all sharers
 *
 * GET: Fetch the most relevant shift (active > upcoming > past) for each sharer
 *
 * Authentication:
 * - iOS: Bearer token in Authorization header
 * - Web: Cookie-based session (fallback)
 *
 * Query params:
 * - sharerIds: comma-separated list of UUIDs
 */
export async function GET(request: NextRequest) {
  // Try to get user ID from Authorization header first (iOS)
  // Fall back to cookie-based session (web)
  let viewerId: string | null = null;

  const authHeader = request.headers.get("Authorization");
  if (authHeader?.startsWith("Bearer ")) {
    const jwt = authHeader.slice(7);

    // Verify JWT and get user
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
  const sharerIdsParam = searchParams.get("sharerIds");

  if (!sharerIdsParam) {
    return NextResponse.json({ error: "sharerIds is required" }, { status: 400 });
  }

  const sharerIds = sharerIdsParam.split(",").filter(Boolean);
  if (sharerIds.length === 0) {
    return NextResponse.json({ previews: [] });
  }

  const now = new Date();

  // Fetch a ±30 day window
  const monthAgo = new Date(now);
  monthAgo.setDate(monthAgo.getDate() - 30);
  const monthFromNow = new Date(now);
  monthFromNow.setDate(monthFromNow.getDate() + 30);

  const startDate = monthAgo.toISOString().slice(0, 10);
  const endDate = monthFromNow.toISOString().slice(0, 10);

  try {
    const previews = await Promise.all(
      sharerIds.map(async (sharerId): Promise<SharerPreview> => {
        try {
          const { shifts, showEarnings } = await getSharedUserShiftsWithViewerId(
            viewerId,
            sharerId,
            { startDate, endDate, limit: 100 }
          );

          if (!shifts || shifts.length === 0) {
            return { sharerId, shift: null, status: null, showEarnings };
          }

          // Sort shifts by date and time
          const sortedShifts = [...shifts].sort((a, b) => {
            const dateCompare = a.shift_date.localeCompare(b.shift_date);
            if (dateCompare !== 0) return dateCompare;
            return a.start_time.localeCompare(b.start_time);
          });

          // Find active shift
          for (const shift of sortedShifts) {
            const { start, end } = parseShiftTimes(shift.shift_date, shift.start_time, shift.end_time);
            if (now >= start && now <= end) {
              return { sharerId, shift, status: "active", showEarnings };
            }
          }

          // Find next upcoming shift
          for (const shift of sortedShifts) {
            const [hours, minutes] = shift.start_time.split(":").map(Number);
            const shiftDateTime = new Date(shift.shift_date + "T00:00:00");
            shiftDateTime.setHours(hours, minutes, 0, 0);

            if (shiftDateTime > now) {
              return { sharerId, shift, status: "upcoming", showEarnings };
            }
          }

          // Find most recent past shift
          const pastShifts = sortedShifts.filter((shift) => {
            const { end } = parseShiftTimes(shift.shift_date, shift.start_time, shift.end_time);
            return end < now;
          });

          if (pastShifts.length > 0) {
            return { sharerId, shift: pastShifts[pastShifts.length - 1], status: "past", showEarnings };
          }

          return { sharerId, shift: null, status: null, showEarnings };
        } catch (error) {
          console.error(`Failed to fetch shift preview for sharer ${sharerId}:`, error);
          return { sharerId, shift: null, status: null, showEarnings: false };
        }
      })
    );

    // Sort by shift proximity: active first, then upcoming (soonest), then past (most recent), then no shifts
    const sortedPreviews = previews.sort((a, b) => {
      const statusPriority: Record<string, number> = { active: 0, upcoming: 1, past: 2, null: 3 };
      const aPriority = statusPriority[a.status ?? "null"];
      const bPriority = statusPriority[b.status ?? "null"];

      if (aPriority !== bPriority) {
        return aPriority - bPriority;
      }

      if (!a.shift || !b.shift) return 0;

      const aStart = new Date(a.shift.shift_date + "T" + a.shift.start_time).getTime();
      const bStart = new Date(b.shift.shift_date + "T" + b.shift.start_time).getTime();

      if (a.status === "upcoming") {
        return aStart - bStart; // Upcoming: soonest first
      } else if (a.status === "past") {
        return bStart - aStart; // Past: most recent first
      }

      return 0;
    });

    return NextResponse.json(
      { previews: sortedPreviews },
      {
        headers: {
          // No caching - previews should reflect latest shifts (notifications)
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
