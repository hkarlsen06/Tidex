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
import { createSupabaseServiceClient } from "@/lib/supabase/service"

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
  // For "updated" events: include old times to show what changed
  oldStartTime?: string // HH:MM or HH:MM:SS
  oldEndTime?: string // HH:MM or HH:MM:SS
}

interface WindowUpsertParams {
  ownerId: string
  shiftId: string // Added for net-effect tracking
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
 * Check if locale is Norwegian (no, nb, nn)
 */
function isNorwegianLocale(locale: string): boolean {
  return locale === "no" || locale === "nb" || locale === "nn"
}

/**
 * Format a date string to localized format
 * Norwegian: "onsdag 15. januar"
 * English: "Wednesday, January 15"
 */
function formatDateLocalized(dateStr: string, locale: string): string {
  const date = new Date(dateStr + "T12:00:00")
  if (isNorwegianLocale(locale)) {
    return date.toLocaleDateString("nb-NO", {
      weekday: "long",
      day: "numeric",
      month: "long",
      timeZone: "Europe/Oslo",
    })
  }
  return date.toLocaleDateString("en-US", {
    weekday: "long",
    month: "long",
    day: "numeric",
    timeZone: "Europe/Oslo",
  })
}

/**
 * Build localized notification title for a shift event
 */
function buildShiftTitle(ownerName: string, eventType: ShiftEventType, locale: string): string {
  if (isNorwegianLocale(locale)) {
    switch (eventType) {
      case "added":
        return `${ownerName} la til en vakt`
      case "updated":
        return `${ownerName} endret en vakt`
      case "deleted":
        return `${ownerName} slettet en vakt`
    }
  }
  // English (default)
  switch (eventType) {
    case "added":
      return `${ownerName} added a shift`
    case "updated":
      return `${ownerName} updated a shift`
    case "deleted":
      return `${ownerName} deleted a shift`
  }
}

/**
 * Build localized notification body with date and time
 * @param isToday - If true, uses "I dag"/"Today" prefix instead of full date
 * @param locale - User's locale preference
 * @param oldStartTime - For updates: show old time in parentheses
 * @param oldEndTime - For updates: show old time in parentheses
 */
function buildShiftBody(
  shiftDate: string,
  startTime: string,
  endTime: string,
  isToday: boolean,
  locale: string,
  oldStartTime?: string,
  oldEndTime?: string
): string {
  const isNorwegian = isNorwegianLocale(locale)

  // Normalize time format (handle both HH:MM and HH:MM:SS)
  const start = startTime.slice(0, 5)
  const end = endTime.slice(0, 5)

  // Build time string, with old time on separate line if this is an update
  const timeStr = `${start}–${end}`
  let oldTimeStr: string | undefined
  if (oldStartTime && oldEndTime) {
    const oldStart = oldStartTime.slice(0, 5)
    const oldEnd = oldEndTime.slice(0, 5)
    // Only show old time if it actually changed
    if (oldStart !== start || oldEnd !== end) {
      oldTimeStr = isNorwegian
        ? `(var ${oldStart}–${oldEnd})`
        : `(was ${oldStart}–${oldEnd})`
    }
  }

  const datePart = isToday
    ? isNorwegian
      ? "I dag"
      : "Today"
    : formatDateLocalized(shiftDate, locale)
  const mainLine = `${datePart} ${timeStr}`

  return oldTimeStr ? `${mainLine}\n${oldTimeStr}` : mainLine
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
  const {
    ownerId,
    ownerName,
    shiftId,
    shiftDate,
    startTime,
    endTime,
    eventType,
    mutationId,
    oldStartTime,
    oldEndTime,
  } = params
  const supabase = createSupabaseServiceClient()
  const todayOslo = getTodayOslo()

  // Step 1: Get non-muted viewers for this owner with their locale preferences
  const { data: shares } = await supabase
    .from("shift_shares")
    .select("viewer_id")
    .eq("owner_id", ownerId)
    .eq("muted", false)

  if (!shares?.length) return

  const viewerIds = shares.map((s) => s.viewer_id)

  // Step 2: Get notification preferences and user locales for these viewers
  const [{ data: prefs }, { data: users }] = await Promise.all([
    supabase.from("notification_preferences").select("user_id, shared_shifts_enabled").in("user_id", viewerIds),
    supabase.auth.admin.listUsers().then((res) => ({
      data: res.data.users.filter((u) => viewerIds.includes(u.id)),
    })),
  ])

  // Build a map of user_id -> shared_shifts_enabled (default true if no row)
  const prefsMap = new Map(prefs?.map((p) => [p.user_id, p.shared_shifts_enabled]) ?? [])

  // Build a map of user_id -> locale (default 'en')
  const localeMap = new Map(
    users?.map((u) => [u.id, (u.user_metadata?.locale as string) ?? "en"]) ?? []
  )

  // Filter to eligible viewers (shared_shifts_enabled !== false)
  const eligibleViewers = viewerIds.filter((id) => prefsMap.get(id) !== false)

  if (eligibleViewers.length === 0) return

  // SAME-DAY: Insert directly to outbox for immediate delivery (with localized messages)
  if (shiftDate === todayOslo) {
    const rows = eligibleViewers.map((viewerId) => {
      const locale = localeMap.get(viewerId) ?? "en"
      return {
        owner_id: ownerId,
        recipient_id: viewerId,
        notification_type: `shared_shift_${eventType}`,
        due_at: new Date().toISOString(),
        title: buildShiftTitle(ownerName, eventType, locale),
        body: buildShiftBody(shiftDate, startTime, endTime, true, locale, oldStartTime, oldEndTime),
        data_payload: {
          type: `shared_shift_${eventType}`,
          owner_id: ownerId,
          changes: [{ shift_id: shiftId, date: shiftDate, op: eventType }],
          // Legacy field for backward compatibility
          shift_dates: [shiftDate],
        },
        // Stable idempotency: shift_id + event_type + viewer_id + mutation_id
        // mutation_id ensures retries are deduped but real events are not
        idempotency_key: `shift:${shiftId}:${eventType}:${viewerId}:${mutationId}`,
      }
    })

    await supabase.schema("internal").from("notifications_outbox").upsert(rows, {
      onConflict: "idempotency_key",
      ignoreDuplicates: true,
    })
    return
  }

  // NON-TODAY: Upsert into time window (with shiftId for net-effect tracking)
  await upsertNotificationWindow({ ownerId, shiftId, shiftDate, eventType })
}

/**
 * Upsert into notification time window via RPC for atomic operation
 */
async function upsertNotificationWindow(params: WindowUpsertParams) {
  const supabase = createSupabaseServiceClient()
  const windowStart = getWindowStart()

  // Note: Function is in internal schema
  // Pass shift_id for net-effect tracking (add+delete=nothing, add+edit=add, etc.)
  await supabase.schema("internal").rpc("upsert_notification_window", {
    p_owner_id: params.ownerId,
    p_window_start: windowStart,
    p_event_type: params.eventType,
    p_shift_date: params.shiftDate,
    p_shift_id: params.shiftId,
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
