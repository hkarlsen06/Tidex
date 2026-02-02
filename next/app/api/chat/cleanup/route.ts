/**
 * Chat Cleanup API
 *
 * No-op endpoint for backward compatibility
 * (Redis functionality removed)
 */

import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/data-access/auth";

/**
 * POST /api/chat/cleanup
 * Body: { streamRunId: string }
 */
export async function POST(request: NextRequest) {
  try {
    // Verify authentication
    const session = await getSession();
    if (!session) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const body = await request.json();
    const { streamRunId } = body;

    if (!streamRunId || typeof streamRunId !== "string") {
      return NextResponse.json(
        { error: "streamRunId is required" },
        { status: 400 }
      );
    }

    // No-op: Redis functionality removed
    return NextResponse.json({ success: true });
  } catch (error) {
    console.error("Chat cleanup error:", error);
    return NextResponse.json(
      {
        error:
          error instanceof Error ? error.message : "Internal server error",
      },
      { status: 500 }
    );
  }
}
