/**
 * Notification Enqueue Module
 *
 * Provides direct notification enqueueing for non-trigger notification types
 * (e.g., error_report, feedback_submitted).
 *
 * Trigger-owned notifications (feedback_responded, share_started) are handled
 * by DB triggers and should NOT be enqueued from app code.
 */

import "server-only"
import { createSupabaseServiceClient } from "@/lib/supabase/service"

/**
 * Enqueue a direct notification to the outbox for immediate delivery.
 *
 * Use this for notification types that are NOT handled by DB triggers.
 */
export async function enqueueDirectNotification(params: {
  recipientId: string
  senderId?: string
  notificationType: string
  title: string
  body: string
  dataPayload: Record<string, unknown>
  idempotencyKey: string
}) {
  const supabase = createSupabaseServiceClient()

  await supabase.schema("internal").from("notifications_outbox").upsert(
    {
      owner_id: params.senderId ?? null,
      recipient_id: params.recipientId,
      notification_type: params.notificationType,
      due_at: new Date().toISOString(),
      title: params.title,
      body: params.body,
      data_payload: params.dataPayload,
      idempotency_key: params.idempotencyKey,
    },
    { onConflict: "idempotency_key", ignoreDuplicates: true }
  )
}
