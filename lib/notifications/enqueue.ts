/**
 * Notification Enqueue Module
 *
 * All notification enqueueing happens in app/server code. NO database triggers.
 *
 * Core Rules:
 * 1. Same-day shifts = immediate delivery (insert to outbox with due_at = now())
 * 2. Non-today shifts = 15-minute window batching (aggregate in notification_time_windows)
 * 3. Pre-computed Norwegian messages stored in outbox
 */

import "server-only"
import { createSupabaseServerClient } from "@/lib/supabase/server"

// Types
export type ShiftEventType = "added" | "updated" | "deleted"

export interface ShiftNotificationParams {
  ownerId: string
  ownerName: string
  shiftId: string
  shiftDate: string // ISO date string YYYY-MM-DD
  startTime: string // HH:MM or HH:MM:SS
  endTime: string // HH:MM or HH:MM:SS
  eventType: ShiftEventType
  mutationId: string // Server-generated unique ID for this mutation request
}

interface WindowUpsertParams {
  ownerId: string
  shiftDate: string
  eventType: ShiftEventType
}

// ============================================================================
// Helper Functions
// ============================================================================

/**
 * Get today's date in Oslo timezone as ISO string (YYYY-MM-DD)
 */
function getTodayOslo(): string {
  return new Date().toLocaleDateString("sv-SE", { timeZone: "Europe/Oslo" })
}

/**
 * Calculate Oslo's UTC offset in minutes for a given date
 */
function getOsloOffsetMinutes(date: Date): number {
  const utcDate = new Date(date.toLocaleString("en-US", { timeZone: "UTC" }))
  const osloDate = new Date(date.toLocaleString("en-US", { timeZone: "Europe/Oslo" }))
  return (osloDate.getTime() - utcDate.getTime()) / 60000
}

/**
 * Get the start of the current 15-minute window in Oslo timezone as ISO string
 * Windows are clock-aligned: :00, :15, :30, :45
 */
function getWindowStart(): string {
  const now = new Date()
  const osloFormatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Oslo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  })
  const parts = osloFormatter.formatToParts(now)
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? "0"

  const year = parseInt(get("year"))
  const month = parseInt(get("month")) - 1
  const day = parseInt(get("day"))
  const hour = parseInt(get("hour"))
  const minute = parseInt(get("minute"))

  // Align to 15-minute window
  const windowMinute = Math.floor(minute / 15) * 15

  // Build date in UTC, then adjust for Oslo offset
  const windowDate = new Date(Date.UTC(year, month, day, hour, windowMinute, 0))

  // Adjust for Oslo offset (CET/CEST)
  const osloOffset = getOsloOffsetMinutes(now)
  windowDate.setMinutes(windowDate.getMinutes() - osloOffset)

  return windowDate.toISOString()
}

/**
 * Format a date string to Norwegian locale
 * Example: "2026-01-15" -> "onsdag 15. januar"
 */
function formatDateNorwegian(dateStr: string): string {
  const date = new Date(dateStr + "T12:00:00")
  return date.toLocaleDateString("nb-NO", {
    weekday: "long",
    day: "numeric",
    month: "long",
    timeZone: "Europe/Oslo",
  })
}

/**
 * Build Norwegian notification title for a shift event
 */
function buildShiftTitle(ownerName: string, eventType: ShiftEventType): string {
  switch (eventType) {
    case "added":
      return `${ownerName} la til en vakt`
    case "updated":
      return `${ownerName} endret en vakt`
    case "deleted":
      return `${ownerName} slettet en vakt`
  }
}

/**
 * Build Norwegian notification body with date and time
 */
function buildShiftBody(shiftDate: string, startTime: string, endTime: string): string {
  const datePart = formatDateNorwegian(shiftDate)
  // Normalize time format (handle both HH:MM and HH:MM:SS)
  const start = startTime.slice(0, 5)
  const end = endTime.slice(0, 5)
  return `${datePart} kl. ${start}-${end}`
}

// ============================================================================
// Main Enqueue Functions
// ============================================================================

/**
 * Enqueue a shift notification.
 *
 * For same-day shifts: Inserts directly to outbox for immediate delivery
 * For future shifts: Upserts into notification_time_windows for 15-min batching
 *
 * @param params - Shift notification parameters
 */
export async function enqueueShiftNotification(params: ShiftNotificationParams) {
  const { ownerId, ownerName, shiftId, shiftDate, startTime, endTime, eventType, mutationId } =
    params
  const supabase = await createSupabaseServerClient()
  const todayOslo = getTodayOslo()

  // Step 1: Get non-muted viewers for this owner
  const { data: shares } = await supabase
    .from("shift_shares")
    .select("viewer_id")
    .eq("owner_id", ownerId)
    .eq("muted", false)

  if (!shares?.length) return

  const viewerIds = shares.map((s) => s.viewer_id)

  // Step 2: Get notification preferences for these viewers
  const { data: prefs } = await supabase
    .from("notification_preferences")
    .select("user_id, shared_shifts_enabled")
    .in("user_id", viewerIds)

  // Build a map of user_id -> shared_shifts_enabled (default true if no row)
  const prefsMap = new Map(prefs?.map((p) => [p.user_id, p.shared_shifts_enabled]) ?? [])

  // Filter to eligible viewers (shared_shifts_enabled !== false)
  const eligibleViewers = viewerIds.filter((id) => prefsMap.get(id) !== false)

  if (eligibleViewers.length === 0) return

  // SAME-DAY: Insert directly to outbox for immediate delivery
  if (shiftDate === todayOslo) {
    const title = buildShiftTitle(ownerName, eventType)
    const body = buildShiftBody(shiftDate, startTime, endTime)

    const rows = eligibleViewers.map((viewerId) => ({
      owner_id: ownerId,
      recipient_id: viewerId,
      notification_type: `shared_shift_${eventType}`,
      due_at: new Date().toISOString(),
      title,
      body,
      data_payload: {
        type: `shared_shift_${eventType}`,
        owner_id: ownerId,
        shift_dates: [shiftDate], // JSON array, not comma string
      },
      // Stable idempotency: shift_id + event_type + viewer_id + mutation_id
      // mutation_id ensures retries are deduped but real events are not
      idempotency_key: `shift:${shiftId}:${eventType}:${viewerId}:${mutationId}`,
    }))

    await supabase.schema("internal").from("notifications_outbox").upsert(rows, {
      onConflict: "idempotency_key",
      ignoreDuplicates: true,
    })
    return
  }

  // NON-TODAY: Upsert into time window
  await upsertNotificationWindow({ ownerId, shiftDate, eventType })
}

/**
 * Upsert into notification time window via RPC for atomic operation
 */
async function upsertNotificationWindow(params: WindowUpsertParams) {
  const supabase = await createSupabaseServerClient()
  const windowStart = getWindowStart()

  // Note: Function is in internal schema
  await supabase.schema("internal").rpc("upsert_notification_window", {
    p_owner_id: params.ownerId,
    p_window_start: windowStart,
    p_event_type: params.eventType,
    p_shift_date: params.shiftDate,
  })
}

/**
 * Enqueue a direct notification (non-shift types like share_started, feedback, etc.)
 *
 * These always go directly to the outbox for immediate delivery.
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
  const supabase = await createSupabaseServerClient()

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

/**
 * Generate a stable mutation ID for a request.
 * Used to deduplicate retries while allowing real duplicate events.
 */
export function generateMutationId(): string {
  return crypto.randomUUID()
}

/**
 * Extract owner name from Supabase user object.
 * Falls back to "Noen" if no name available.
 */
export function getOwnerName(user: { user_metadata?: Record<string, unknown> }): string {
  const fullName = user.user_metadata?.full_name
  if (typeof fullName === "string" && fullName.trim().length > 0) {
    return fullName.trim()
  }
  const name = user.user_metadata?.name
  if (typeof name === "string" && name.trim().length > 0) {
    return name.trim()
  }
  return "Noen"
}
