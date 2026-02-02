/**
 * Error Report API Route
 *
 * Receives client-side error reports and sends push notifications to the developer.
 * Used for tracking production issues like IAP failures.
 */

import { NextRequest, NextResponse } from "next/server"
import { createSupabaseServerClient } from "@/lib/supabase/server"
import { enqueueDirectNotification } from "@/lib/notifications/enqueue"

// Developer user ID to receive error notifications
const DEVELOPER_USER_ID = "032d8c2a-9af6-4777-99f0-24e2c4058bf3"

export async function POST(request: NextRequest) {
  try {
    const { errorType, message, context } = await request.json()

    if (!errorType || !message) {
      return NextResponse.json({ error: "Missing errorType or message" }, { status: 400 })
    }

    // Get authenticated user info (optional, for context)
    const supabase = await createSupabaseServerClient()
    const {
      data: { user },
    } = await supabase.auth.getUser()

    const userId = user?.id ?? "anonymous"
    const userEmail = user?.email ?? "unknown"

    // Build notification
    const title = `⚠️ ${errorType}`
    const body = `${message}\n\nUser: ${userEmail}\nContext: ${JSON.stringify(context ?? {})}`

    // Generate idempotency key based on error details and timestamp (allow same error to be reported multiple times but not spam)
    const timestamp = Math.floor(Date.now() / 60000) // 1-minute window for dedup
    const idempotencyKey = `error:${errorType}:${userId}:${timestamp}`

    await enqueueDirectNotification({
      recipientId: DEVELOPER_USER_ID,
      notificationType: "error_report",
      title,
      body: body.slice(0, 500), // Truncate body to avoid overly long notifications
      dataPayload: {
        type: "error_report",
        errorType,
        message,
        context,
        userId,
        userEmail,
        timestamp: new Date().toISOString(),
      },
      idempotencyKey,
    })

    return NextResponse.json({ success: true })
  } catch (error) {
    console.error("Failed to report error:", error)
    return NextResponse.json({ error: "Failed to report error" }, { status: 500 })
  }
}
