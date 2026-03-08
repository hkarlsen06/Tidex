import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/data-access/auth";
import { createSupabaseServiceClient } from "@/lib/supabase/service";
import { logger } from "@/lib/logger";

/**
 * POST /api/friends/chat/screenshot
 *
 * Reports that a user took a screenshot while viewing a direct friends chat.
 * Sends a push notification to the counterpart user.
 *
 * Body:
 * - threadId: string
 */
export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const screenshotterId = session.user.id;
  const screenshotterName =
    (session.user.user_metadata?.full_name as string) ||
    (session.user.user_metadata?.name as string) ||
    "Someone";

  let body: { threadId: string };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid request body" }, { status: 400 });
  }

  const { threadId } = body;
  if (!threadId) {
    return NextResponse.json({ error: "threadId is required" }, { status: 400 });
  }

  const supabase = createSupabaseServiceClient();

  const { data: membership } = await supabase
    .from("thread_memberships")
    .select("thread_id")
    .eq("thread_id", threadId)
    .eq("user_id", screenshotterId)
    .eq("status", "active")
    .maybeSingle();

  if (!membership) {
    return NextResponse.json({ error: "No access to thread" }, { status: 403 });
  }

  const { data: thread } = await supabase
    .from("threads")
    .select("id, kind")
    .eq("id", threadId)
    .maybeSingle();

  if (!thread || thread.kind !== "direct") {
    return NextResponse.json({ success: true, skipped: true });
  }

  const { data: counterpartMembership } = await supabase
    .from("thread_memberships")
    .select("user_id")
    .eq("thread_id", threadId)
    .eq("status", "active")
    .neq("user_id", screenshotterId)
    .maybeSingle();

  const recipientId = counterpartMembership?.user_id;
  if (!recipientId || recipientId === screenshotterId) {
    return NextResponse.json({ success: true, skipped: true });
  }

  const [{ data: recipientUser }, { data: screenshotterSettings }] =
    await Promise.all([
      supabase.auth.admin.getUserById(recipientId),
      supabase
        .from("user_settings")
        .select("profile_picture_url")
        .eq("user_id", screenshotterId)
        .maybeSingle(),
    ]);

  const locale =
    (recipientUser?.user?.user_metadata?.locale as string | undefined) || "en";
  const screenshotterAvatarUrl =
    screenshotterSettings?.profile_picture_url ||
    (session.user.user_metadata?.avatar_url as string | undefined) ||
    (session.user.user_metadata?.picture as string | undefined) ||
    null;

  const { title, body: notificationBody } = buildScreenshotMessage(
    screenshotterName,
    locale,
    "chat"
  );

  const idempotencyKey = `thread_screenshot:${screenshotterId}:${threadId}:${Date.now()}`;

  try {
    await supabase.schema("internal").from("notifications_outbox").insert({
      owner_id: screenshotterId,
      recipient_id: recipientId,
      notification_type: "thread_screenshot",
      due_at: new Date().toISOString(),
      title,
      body: notificationBody,
      data_payload: {
        type: "thread_screenshot",
        thread_id: threadId,
        screenshotter_id: screenshotterId,
        screenshotter_name: screenshotterName,
        sender_user_id: screenshotterId,
        sender_name: screenshotterName,
        sender_avatar_url: screenshotterAvatarUrl,
      },
      idempotency_key: idempotencyKey,
    });

    logger.info(
      `Chat screenshot notification queued: ${screenshotterId} -> ${recipientId} (thread ${threadId})`
    );
    return NextResponse.json({ success: true });
  } catch (error) {
    logger.error("Failed to queue chat screenshot notification:", error);
    return NextResponse.json(
      { error: "Failed to send notification" },
      { status: 500 }
    );
  }
}

function isNorwegian(locale: string | undefined): boolean {
  if (!locale) return false;
  const l = locale.toLowerCase();
  return l === "no" || l === "nb" || l === "nn" ||
    l.startsWith("no-") || l.startsWith("nb-") || l.startsWith("nn-");
}

function buildScreenshotMessage(
  screenshotterName: string,
  locale: string,
  kind: "chat" | "shifts"
): { title: string; body: string } {
  if (isNorwegian(locale)) {
    return {
      title: screenshotterName,
      body: kind === "chat"
        ? `${screenshotterName} tok et skjermbilde av chatten deres`
        : `${screenshotterName} tok et skjermbilde av vaktene dine`,
    };
  }

  return {
    title: screenshotterName,
    body: kind === "chat"
      ? `${screenshotterName} took a screenshot of your conversation`
      : `${screenshotterName} took a screenshot of your shifts`,
  };
}
