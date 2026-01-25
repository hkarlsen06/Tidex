import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import { getSession } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";
import { logger } from "@/lib/logger";

/**
 * POST /api/sharing/screenshot
 *
 * Reports that a user took a screenshot while viewing another user's shifts.
 * Sends a push notification to the shift owner (like Snapchat).
 *
 * Authentication:
 * - iOS: Bearer token in Authorization header
 * - Web: Cookie-based session (fallback)
 *
 * Body:
 * - sharerId: string - The ID of the user whose shifts were screenshotted
 */
export async function POST(request: NextRequest) {
  // Authenticate the user
  let screenshotterId: string | null = null;
  let screenshotterName = "Someone";

  const authHeader = request.headers.get("Authorization");
  if (authHeader?.startsWith("Bearer ")) {
    const jwt = authHeader.slice(7);
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
    const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const { data, error } = await supabase.auth.getUser(jwt);
    if (error || !data.user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    screenshotterId = data.user.id;
    screenshotterName =
      (data.user.user_metadata?.full_name as string) ||
      (data.user.user_metadata?.name as string) ||
      "Someone";
  } else {
    const session = await getSession();
    if (!session) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
    screenshotterId = session.user.id;
    screenshotterName =
      (session.user.user_metadata?.full_name as string) ||
      (session.user.user_metadata?.name as string) ||
      "Someone";
  }

  // Parse request body
  let body: { sharerId: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body" }, { status: 400 });
  }

  const { sharerId } = body;
  if (!sharerId) {
    return NextResponse.json({ error: "sharerId is required" }, { status: 400 });
  }

  // Don't notify yourself
  if (sharerId === screenshotterId) {
    return NextResponse.json({ success: true, skipped: true });
  }

  const supabase = createSupabaseServiceClient();

  // Verify the screenshotter has access to view this sharer's shifts
  const { data: shareAccess } = await supabase
    .from("shift_shares")
    .select("id")
    .eq("owner_id", sharerId)
    .eq("viewer_id", screenshotterId)
    .maybeSingle();

  if (!shareAccess) {
    // User doesn't have access to this sharer's shifts
    return NextResponse.json({ error: "No access to sharer" }, { status: 403 });
  }

  // Get the sharer's locale for localization
  const { data: sharerData } = await supabase.auth.admin.getUserById(sharerId);
  const locale =
    (sharerData?.user?.user_metadata?.locale as string) || "en";

  // Build localized message
  const { title, body: notificationBody } = buildScreenshotMessage(
    screenshotterName,
    locale
  );

  // Insert notification to outbox
  const idempotencyKey = `screenshot:${screenshotterId}:${sharerId}:${Date.now()}`;

  try {
    await supabase.schema("internal").from("notifications_outbox").insert({
      owner_id: screenshotterId,
      recipient_id: sharerId,
      notification_type: "shifts_screenshotted",
      due_at: new Date().toISOString(),
      title,
      body: notificationBody,
      data_payload: {
        type: "shifts_screenshotted",
        screenshotter_id: screenshotterId,
        screenshotter_name: screenshotterName,
      },
      idempotency_key: idempotencyKey,
    });

    logger.info(
      `Screenshot notification queued: ${screenshotterId} -> ${sharerId}`
    );
    return NextResponse.json({ success: true });
  } catch (error) {
    logger.error("Failed to queue screenshot notification:", error);
    return NextResponse.json(
      { error: "Failed to send notification" },
      { status: 500 }
    );
  }
}

/**
 * Build localized notification message for screenshot event
 */
function buildScreenshotMessage(
  screenshotterName: string,
  locale: string
): { title: string; body: string } {
  if (locale === "no" || locale === "nb" || locale === "nn") {
    return {
      title: "Skjermbilde tatt",
      body: `${screenshotterName} tok et skjermbilde av vaktene dine`,
    };
  }

  // English (default)
  return {
    title: "Screenshot taken",
    body: `${screenshotterName} took a screenshot of your shifts`,
  };
}
