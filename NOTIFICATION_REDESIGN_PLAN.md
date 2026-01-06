# Shift Share Push Notification System Redesign (v2)

## Overview

Redesign the notification system with **app-only enqueueing** (no database triggers), deterministic 15-minute window batching for non-today shifts, and immediate delivery for same-day changes. All notification types unified into a single `notifications_outbox` table.

## Core Rules

1. **No database triggers** - All notification logic runs in app/server code only
2. **App-only enqueueing** - Server actions enqueue notifications directly
3. **Same-day = immediate** - Insert directly to outbox with `due_at = now()`; multiple notifications acceptable
4. **Non-today = 15-minute windows** - Aggregate into `notification_time_windows` (clock-aligned :00, :15, :30, :45)
5. **One notification per window per sender-recipient** - Worker fans out when window ends
6. **Unified outbox** - All notification types (shifts, shares, feedback, admin) use `notifications_outbox`
7. **Pre-computed messages** - Norwegian title/body stored in outbox; edge function just sends

---

## 1. Inventory of Current Components

### Tables to REMOVE
| Table | Reason |
|-------|--------|
| `public.pending_shift_deletes` | No longer needed (app-only enqueueing) |
| `public.shift_update_events` | No longer needed (app-only enqueueing) |
| `public.pending_summary_notifications` | No more summary preference |
| `internal.notification_queue` | Replaced by unified `notifications_outbox` |

### Tables to MODIFY
| Table | Change |
|-------|--------|
| `shift_shares` | Replace `notification_frequency` with `muted` boolean |
| `notification_preferences` | Remove `summary_time` column |

### Tables to CREATE
| Table | Purpose |
|-------|---------|
| `internal.notification_time_windows` | Aggregate non-today shift mutations per 15-min window |
| `internal.notifications_outbox` | Unified delivery queue with pre-built messages |

### Triggers to REMOVE (ALL)
| Trigger | Table |
|---------|-------|
| `queue_shift_created_notification` | `user_shifts` |
| `capture_shift_updates_stmt` | `user_shifts` |
| `queue_pending_shift_delete` | `user_shifts` |
| `queue_share_started_notification` | `shift_shares` |
| `queue_feedback_submitted_notification` | `feedback` |
| `queue_feedback_responded_notification` | `feedback` |
| `queue_recurring_shift_created_notification` | `recurring_shifts` |
| `trigger_push_notifications_after_insert` | `notification_queue` |
| `trigger_push_notifications_after_share_insert` | `shift_shares` |

### SQL Functions to REMOVE
| Function | Reason |
|----------|--------|
| `process_pending_shift_deletes()` | No longer needed |
| `process_shift_update_events()` | No longer needed |
| `process_summary_notifications()` | No longer needed |
| `run_shift_notification_workers()` | Replace with new version |
| `claim_pending_notifications()` | Replace with outbox version |
| `queue_shift_created_notification()` | Move to app |
| `capture_shift_updates_stmt()` | Move to app |
| `queue_pending_shift_delete()` | Move to app |
| `queue_share_started_notification()` | Move to app |
| `queue_feedback_submitted_notification()` | Move to app |
| `queue_feedback_responded_notification()` | Move to app |
| `queue_recurring_shift_created_notification()` | Move to app |
| `trigger_send_push_notifications()` | No longer needed |

### SQL Functions to CREATE
| Function | Purpose |
|----------|---------|
| `internal.upsert_notification_window()` | Atomic window updates from app |
| `internal.process_notification_windows()` | Process due windows, fan out to outbox |
| `internal.claim_outbox_notifications()` | Atomic claim for edge function |
| `run_notification_workers()` | New orchestrator |

### Edge Function to MODIFY
| Function | Change |
|----------|--------|
| `send-push-notifications` | Read ONLY from `notifications_outbox`, no message building |

### Cron Jobs to MODIFY
| Job | Change |
|-----|--------|
| `process-shift-notifications` | Call new `run_notification_workers()` |

---

## 2. Database Schema

### A. `internal.notification_time_windows`

```sql
CREATE TABLE internal.notification_time_windows (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  window_start TIMESTAMPTZ NOT NULL,

  -- Mutation counts
  added_count INT NOT NULL DEFAULT 0,
  updated_count INT NOT NULL DEFAULT 0,
  deleted_count INT NOT NULL DEFAULT 0,

  -- Affected dates (capped at 31 for bounded storage)
  affected_dates DATE[] NOT NULL DEFAULT '{}',
  truncated_dates BOOLEAN NOT NULL DEFAULT FALSE,

  -- Processing status
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'finalized')),

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Unique per owner per window
  UNIQUE (owner_id, window_start)
);

CREATE INDEX idx_ntw_status_window ON internal.notification_time_windows (status, window_start)
  WHERE status = 'pending';
CREATE INDEX idx_ntw_owner ON internal.notification_time_windows (owner_id);
```

### B. `internal.notifications_outbox`

```sql
CREATE TABLE internal.notifications_outbox (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Targeting
  owner_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,  -- NULL for admin broadcasts
  recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  broadcast_id UUID,  -- For admin broadcasts

  -- Notification type for routing/analytics
  notification_type TEXT NOT NULL,

  -- Delivery timing
  due_at TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Status tracking
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'sending', 'sent', 'failed', 'skipped')),
  claimed_at TIMESTAMPTZ,
  processed_at TIMESTAMPTZ,
  error_message TEXT,
  attempts INT NOT NULL DEFAULT 0,  -- Track retry attempts

  -- Pre-computed message (Norwegian)
  title TEXT NOT NULL,
  body TEXT NOT NULL,

  -- Deep link and metadata (NOT for rendering)
  data_payload JSONB NOT NULL DEFAULT '{}',

  -- Idempotency
  idempotency_key TEXT NOT NULL UNIQUE,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_outbox_due ON internal.notifications_outbox (status, due_at)
  WHERE status = 'pending';
CREATE INDEX idx_outbox_recipient ON internal.notifications_outbox (recipient_id);
CREATE INDEX idx_outbox_broadcast ON internal.notifications_outbox (broadcast_id)
  WHERE broadcast_id IS NOT NULL;
```

### C. Modify `shift_shares`

```sql
-- Add new muted column
ALTER TABLE shift_shares ADD COLUMN muted BOOLEAN NOT NULL DEFAULT FALSE;

-- Migrate data: notification_frequency = 'muted' -> muted = true
UPDATE shift_shares SET muted = TRUE WHERE notification_frequency = 'muted';

-- Drop old column (after verification)
ALTER TABLE shift_shares DROP COLUMN notification_frequency;
```

### D. Modify `notification_preferences`

```sql
-- Remove summary_time (no longer needed)
ALTER TABLE notification_preferences DROP COLUMN summary_time;
```

---

## 3. App Enqueue Module

All notification enqueueing happens in app/server code. **No database triggers.**

### A. Shared Notification Utilities

**New file: `lib/notifications/enqueue.ts`**

```typescript
import { createSupabaseServerClient } from "@/lib/supabase/server"

// Types
type ShiftEventType = "added" | "updated" | "deleted"

interface ShiftNotificationParams {
  ownerId: string
  ownerName: string
  shiftId: string
  shiftDate: string       // ISO date string YYYY-MM-DD
  startTime: string       // HH:MM
  endTime: string         // HH:MM
  eventType: ShiftEventType
  mutationId: string      // Server-generated unique ID for this mutation request
}

interface WindowUpsertParams {
  ownerId: string
  shiftDate: string
  eventType: ShiftEventType
}

// Helpers
function getTodayOslo(): string {
  return new Date().toLocaleDateString("sv-SE", { timeZone: "Europe/Oslo" })
}

function getWindowStart(): string {
  // Get current time in Oslo timezone
  // Note: This approach works in Node.js but add tests for DST boundaries
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

  // Build ISO string for the window start in Oslo time
  // Format: YYYY-MM-DDTHH:MM:00+XX:XX (Oslo offset)
  const windowDate = new Date(Date.UTC(year, month, day, hour, windowMinute, 0))

  // Adjust for Oslo offset (CET/CEST)
  const osloOffset = getOsloOffsetMinutes(now)
  windowDate.setMinutes(windowDate.getMinutes() - osloOffset)

  return windowDate.toISOString()
}

function getOsloOffsetMinutes(date: Date): number {
  // Calculate Oslo's UTC offset for the given date
  const utcDate = new Date(date.toLocaleString("en-US", { timeZone: "UTC" }))
  const osloDate = new Date(date.toLocaleString("en-US", { timeZone: "Europe/Oslo" }))
  return (osloDate.getTime() - utcDate.getTime()) / 60000
}

function formatDateNorwegian(dateStr: string): string {
  const date = new Date(dateStr + "T12:00:00")
  return date.toLocaleDateString("nb-NO", {
    weekday: "long",
    day: "numeric",
    month: "long",
    timeZone: "Europe/Oslo",  // Ensure Oslo timezone for consistency
  })
}

function buildShiftTitle(ownerName: string, eventType: ShiftEventType): string {
  switch (eventType) {
    case "added": return `${ownerName} la til en vakt`
    case "updated": return `${ownerName} endret en vakt`
    case "deleted": return `${ownerName} slettet en vakt`
  }
}

function buildShiftBody(shiftDate: string, startTime: string, endTime: string): string {
  const datePart = formatDateNorwegian(shiftDate)
  return `${datePart} kl. ${startTime.slice(0, 5)}-${endTime.slice(0, 5)}`
}

// Main enqueue function for shift notifications
export async function enqueueShiftNotification(params: ShiftNotificationParams) {
  const { ownerId, ownerName, shiftId, shiftDate, startTime, endTime, eventType, mutationId } = params
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
        shift_dates: [shiftDate],  // JSON array, not comma string
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

// Window upsert via RPC for atomic operation
async function upsertNotificationWindow(params: WindowUpsertParams) {
  const supabase = await createSupabaseServerClient()
  const windowStart = getWindowStart()

  await supabase.rpc("upsert_notification_window", {
    p_owner_id: params.ownerId,
    p_window_start: windowStart,
    p_event_type: params.eventType,
    p_shift_date: params.shiftDate,
  })
}

// For non-shift notifications (share_started, feedback, admin broadcasts, etc.)
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

// Generate a stable mutation ID for a request
export function generateMutationId(): string {
  return crypto.randomUUID()
}
```

### B. SQL RPC for Atomic Window Upsert

**New file: `supabase/sql/functions/notification/upsert_notification_window.sql`**

```sql
CREATE OR REPLACE FUNCTION internal.upsert_notification_window(
  p_owner_id UUID,
  p_window_start TIMESTAMPTZ,
  p_event_type TEXT,
  p_shift_date DATE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'internal', 'pg_temp'
AS $$
BEGIN
  INSERT INTO notification_time_windows (
    owner_id, window_start,
    added_count, updated_count, deleted_count,
    affected_dates
  )
  VALUES (
    p_owner_id, p_window_start,
    CASE WHEN p_event_type = 'added' THEN 1 ELSE 0 END,
    CASE WHEN p_event_type = 'updated' THEN 1 ELSE 0 END,
    CASE WHEN p_event_type = 'deleted' THEN 1 ELSE 0 END,
    ARRAY[p_shift_date]
  )
  ON CONFLICT (owner_id, window_start) DO UPDATE SET
    added_count = notification_time_windows.added_count +
      CASE WHEN p_event_type = 'added' THEN 1 ELSE 0 END,
    updated_count = notification_time_windows.updated_count +
      CASE WHEN p_event_type = 'updated' THEN 1 ELSE 0 END,
    deleted_count = notification_time_windows.deleted_count +
      CASE WHEN p_event_type = 'deleted' THEN 1 ELSE 0 END,
    affected_dates = CASE
      WHEN array_length(notification_time_windows.affected_dates, 1) >= 31 THEN
        notification_time_windows.affected_dates
      WHEN p_shift_date = ANY(notification_time_windows.affected_dates) THEN
        notification_time_windows.affected_dates
      ELSE
        array_append(notification_time_windows.affected_dates, p_shift_date)
    END,
    truncated_dates = CASE
      WHEN array_length(notification_time_windows.affected_dates, 1) >= 31 THEN TRUE
      ELSE notification_time_windows.truncated_dates
    END,
    updated_at = now();
END;
$$;
```

---

## 4. Shift Mutation Paths (Files to Modify)

All shift mutation server actions must call `enqueueShiftNotification()` after successful database operations.

### Standalone Shifts

| File | Action | Event Type | Notes |
|------|--------|------------|-------|
| `app/[locale]/(app)/shifts/add/actions.ts` | `createShifts()` | `added` | Loop over created shifts |
| `app/[locale]/(app)/shifts/_actions/updateShift.ts` | `updateShift()` | `updated` | Only if date/time changed |
| `app/[locale]/(app)/shifts/_actions/deleteShift.ts` | `deleteShift()` | `deleted` | Remove old `pending_shift_deletes` insert |
| `app/[locale]/(app)/shifts/_actions/deleteShifts.ts` | `deleteShifts()` | `deleted` | Loop over deleted shift IDs |
| `app/[locale]/(app)/shifts/_actions/copyShifts.ts` | `copyShifts()` | `added` | Loop over copied shifts |

### Recurring Shifts

| File | Action | Event Type | Notes |
|------|--------|------------|-------|
| `app/[locale]/(app)/shifts/add/_actions/createRecurringShift.ts` | `createRecurringShift()` | N/A | Use `enqueueDirectNotification()` for `recurring_shift_created` |
| `app/[locale]/(app)/shifts/_actions/updateRecurringShift.ts` | `updateRecurringShift()` | `updated` | Enqueue for all affected virtual instances |
| `app/[locale]/(app)/shifts/_actions/deleteRecurringShift.ts` | `deleteRecurringShift()` | `deleted` | Enqueue for all affected virtual instances |
| `app/[locale]/(app)/shifts/_actions/convertRecurringShiftToStandalone.ts` | `convertRecurringShiftToStandalone()` | `updated` | Single date conversion |

### Non-Shift Notifications (Also Migrate to Outbox)

| Current Location | Notification Type | Migration Notes |
|------------------|-------------------|-----------------|
| `queue_share_started_notification` trigger | `share_started` | Find share creation action, call `enqueueDirectNotification()` |
| `queue_feedback_submitted_notification` trigger | `feedback_submitted` | Find feedback submission action, call `enqueueDirectNotification()` |
| `queue_feedback_responded_notification` trigger | `feedback_responded` | Find feedback response action, call `enqueueDirectNotification()` |
| Admin broadcast functions | `admin_broadcast` | Update to insert directly to outbox |

### Example: `createShifts()` modification

```typescript
// In app/[locale]/(app)/shifts/add/actions.ts
import { enqueueShiftNotification, generateMutationId } from "@/lib/notifications/enqueue"

export async function createShifts(formData: FormData) {
  // ... existing validation and insert logic ...
  // user and ownerName should already be available from session/profile lookup

  const mutationId = generateMutationId()

  const { data: createdShifts, error } = await supabase
    .from("user_shifts")
    .insert(shifts)
    .select()

  if (error) throw error

  // ownerName should come from user profile/settings, not auth.getUser()
  // Caller already has this from session or profile lookup earlier in the action
  const ownerName = userProfile?.full_name ?? "Noen"

  // Enqueue notifications for each created shift
  await Promise.all(
    createdShifts.map((shift) =>
      enqueueShiftNotification({
        ownerId: user.id,
        ownerName,
        shiftId: shift.id,
        shiftDate: shift.shift_date,
        startTime: shift.start_time,
        endTime: shift.end_time,
        eventType: "added",
        mutationId,
      })
    )
  )

  // ... revalidation ...
}
```

### Example: `updateShift()` modification (only notify if date/time changed)

```typescript
// In app/[locale]/(app)/shifts/_actions/updateShift.ts
import { enqueueShiftNotification, generateMutationId } from "@/lib/notifications/enqueue"

export async function updateShift(shiftId: string, updates: ShiftUpdates) {
  // ... existing validation ...

  // Fetch current shift to compare
  const { data: oldShift } = await supabase
    .from("user_shifts")
    .select("shift_date, start_time, end_time")
    .eq("id", shiftId)
    .single()

  // Perform the update
  const { data: newShift, error } = await supabase
    .from("user_shifts")
    .update(updates)
    .eq("id", shiftId)
    .select()
    .single()

  if (error) throw error

  // ONLY notify if date or time actually changed
  const dateChanged = oldShift.shift_date !== newShift.shift_date
  const startChanged = oldShift.start_time !== newShift.start_time
  const endChanged = oldShift.end_time !== newShift.end_time

  if (dateChanged || startChanged || endChanged) {
    const mutationId = generateMutationId()
    await enqueueShiftNotification({
      ownerId: user.id,
      ownerName,
      shiftId: newShift.id,
      shiftDate: newShift.shift_date,
      startTime: newShift.start_time,
      endTime: newShift.end_time,
      eventType: "updated",
      mutationId,
    })
  }

  // ... revalidation ...
}
```

### Example: `deleteShift()` modification

```typescript
// In app/[locale]/(app)/shifts/_actions/deleteShift.ts
import { enqueueShiftNotification, generateMutationId } from "@/lib/notifications/enqueue"

export async function deleteShift(shiftId: string, recurringId?: string, shiftDate?: string) {
  // ... existing logic ...

  const mutationId = generateMutationId()

  if (recurringId && shiftDate) {
    // Virtual recurring shift deletion - add to exclusions
    // ... existing exclusion update ...

    // Enqueue notification (no actual row deleted, so manual enqueue)
    await enqueueShiftNotification({
      ownerId: user.id,
      ownerName,
      shiftId: `${recurringId}:${shiftDate}`, // Composite ID for virtual shift
      shiftDate,
      startTime,
      endTime,
      eventType: "deleted",
      mutationId,
    })
  } else {
    // Standalone shift deletion
    const { data: deletedShift } = await supabase
      .from("user_shifts")
      .delete()
      .eq("id", shiftId)
      .select()
      .single()

    // Enqueue notification
    await enqueueShiftNotification({
      ownerId: user.id,
      ownerName,
      shiftId: deletedShift.id,
      shiftDate: deletedShift.shift_date,
      startTime: deletedShift.start_time,
      endTime: deletedShift.end_time,
      eventType: "deleted",
      mutationId,
    })
  }

  // REMOVE: Old pending_shift_deletes insert
  // DELETE THIS ENTIRE BLOCK (was lines 56-73):
  // const { error: pendingDeleteError } = await supabase
  //   .from("pending_shift_deletes")
  //   .insert({...});

  // ... revalidation ...
}
```

---

## 5. Worker Implementation

### `process_notification_windows()`

Processes windows whose end time has passed, fans out to outbox.

```sql
CREATE OR REPLACE FUNCTION internal.process_notification_windows()
RETURNS TABLE(windows_processed INT, outbox_rows_created INT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $$
DECLARE
  v_window RECORD;
  v_owner_name TEXT;
  v_title TEXT;
  v_body TEXT;
  v_action_parts TEXT[];
  v_windows_processed INT := 0;
  v_outbox_created INT := 0;
  v_window_end TIMESTAMPTZ;
BEGIN
  -- Process windows where window_end has passed (window_start + 15 min)
  FOR v_window IN
    SELECT *
    FROM internal.notification_time_windows
    WHERE status = 'pending'
      AND window_start + INTERVAL '15 minutes' <= now()
    ORDER BY window_start
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Mark as processing
    UPDATE internal.notification_time_windows
    SET status = 'processing'
    WHERE id = v_window.id;

    -- Calculate window end for due_at
    v_window_end := v_window.window_start + INTERVAL '15 minutes';

    -- Get owner name
    SELECT COALESCE(
      raw_user_meta_data->>'full_name',
      raw_user_meta_data->>'name',
      email,
      'Noen'
    ) INTO v_owner_name
    FROM auth.users WHERE id = v_window.owner_id;

    IF v_owner_name IS NULL THEN
      v_owner_name := 'Noen';
    END IF;

    -- Build Norwegian message
    -- Format: "Alvilde slettet 2 vakter, la til 2 vakter, og endret 1 vakt"
    v_action_parts := '{}';

    IF v_window.deleted_count > 0 THEN
      v_action_parts := array_append(v_action_parts,
        'slettet ' || v_window.deleted_count ||
        CASE WHEN v_window.deleted_count = 1 THEN ' vakt' ELSE ' vakter' END);
    END IF;

    IF v_window.added_count > 0 THEN
      v_action_parts := array_append(v_action_parts,
        'la til ' || v_window.added_count ||
        CASE WHEN v_window.added_count = 1 THEN ' vakt' ELSE ' vakter' END);
    END IF;

    IF v_window.updated_count > 0 THEN
      v_action_parts := array_append(v_action_parts,
        'endret ' || v_window.updated_count ||
        CASE WHEN v_window.updated_count = 1 THEN ' vakt' ELSE ' vakter' END);
    END IF;

    -- Build title with Norwegian conjunction rules
    IF array_length(v_action_parts, 1) = 1 THEN
      v_title := v_owner_name || ' ' || v_action_parts[1];
    ELSIF array_length(v_action_parts, 1) = 2 THEN
      v_title := v_owner_name || ' ' || v_action_parts[1] || ' og ' || v_action_parts[2];
    ELSE
      v_title := v_owner_name || ' ' || v_action_parts[1] || ', ' ||
                 v_action_parts[2] || ', og ' || v_action_parts[3];
    END IF;

    v_body := 'Trykk for å se endringene';

    -- Fan out to each non-muted recipient
    INSERT INTO internal.notifications_outbox (
      owner_id, recipient_id, notification_type, due_at, title, body, data_payload, idempotency_key
    )
    SELECT
      v_window.owner_id,
      ss.viewer_id,
      'shared_shift_changes',
      v_window_end,  -- due_at = window_end for clarity
      v_title,
      v_body,
      jsonb_build_object(
        'type', 'shared_shift_changes',
        'owner_id', v_window.owner_id,
        'shift_dates', to_jsonb(v_window.affected_dates),  -- JSON array, not comma string
        'added_count', v_window.added_count,
        'updated_count', v_window.updated_count,
        'deleted_count', v_window.deleted_count
      ),
      -- Stable idempotency: owner_id:recipient_id:window_start
      v_window.owner_id || ':' || ss.viewer_id || ':' || v_window.window_start::text
    FROM shift_shares ss
    LEFT JOIN notification_preferences np ON np.user_id = ss.viewer_id
    WHERE ss.owner_id = v_window.owner_id
      AND ss.muted = FALSE
      AND COALESCE(np.shared_shifts_enabled, TRUE) = TRUE
    ON CONFLICT (idempotency_key) DO NOTHING;

    GET DIAGNOSTICS v_outbox_created = v_outbox_created + ROW_COUNT;

    -- Mark window as finalized
    UPDATE internal.notification_time_windows
    SET status = 'finalized', updated_at = now()
    WHERE id = v_window.id;

    v_windows_processed := v_windows_processed + 1;
  END LOOP;

  RETURN QUERY SELECT v_windows_processed, v_outbox_created;
END;
$$;
```

### `claim_outbox_notifications()`

```sql
CREATE OR REPLACE FUNCTION internal.claim_outbox_notifications(batch_size INT DEFAULT 50)
RETURNS SETOF internal.notifications_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'internal', 'pg_temp'
AS $$
BEGIN
  -- Reset stale claims (stuck > 15 minutes) with bounded retries
  UPDATE notifications_outbox
  SET
    status = CASE
      WHEN attempts >= 10 THEN 'failed'  -- Max 10 attempts, then permanent failure
      ELSE 'pending'
    END,
    claimed_at = NULL,
    attempts = attempts + 1,
    error_message = CASE
      WHEN attempts >= 10 THEN 'Max retry attempts exceeded'
      ELSE error_message
    END
  WHERE status = 'sending'
    AND claimed_at < now() - INTERVAL '15 minutes';

  -- Claim and return batch (only pending with < 10 attempts)
  RETURN QUERY
  UPDATE notifications_outbox
  SET status = 'sending', claimed_at = now()
  WHERE id IN (
    SELECT id FROM notifications_outbox
    WHERE status = 'pending'
      AND due_at <= now()
      AND attempts < 10
    ORDER BY due_at
    LIMIT batch_size
    FOR UPDATE SKIP LOCKED
  )
  RETURNING *;
END;
$$;
```

### `run_notification_workers()`

```sql
CREATE OR REPLACE FUNCTION public.run_notification_workers()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $$
DECLARE
  v_window_result RECORD;
  v_has_pending BOOLEAN;
BEGIN
  -- Process due windows (fans out to outbox)
  SELECT * INTO v_window_result FROM internal.process_notification_windows();

  -- Check for pending outbox notifications that are due
  SELECT EXISTS (
    SELECT 1 FROM internal.notifications_outbox
    WHERE status = 'pending' AND due_at <= now()
  ) INTO v_has_pending;

  -- Trigger edge function if pending notifications exist
  IF v_has_pending THEN
    PERFORM net.http_post(
      url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url')
             || '/functions/v1/send-push-notifications',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' ||
          (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key')
      ),
      body := '{}'::jsonb
    );
  END IF;

  RETURN jsonb_build_object(
    'windows_processed', COALESCE(v_window_result.windows_processed, 0),
    'outbox_rows_created', COALESCE(v_window_result.outbox_rows_created, 0),
    'triggered_send', v_has_pending
  );
END;
$$;
```

---

## 6. Edge Function Changes

### File: `supabase/functions/send-push-notifications/index.ts`

**Complete rewrite** - Read ONLY from `notifications_outbox`, no message building.

```typescript
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "jsr:@supabase/supabase-js@2"

const supabaseUrl = Deno.env.get("SUPABASE_URL")!
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!

interface OutboxNotification {
  id: string
  owner_id: string | null
  recipient_id: string
  notification_type: string
  title: string
  body: string
  data_payload: Record<string, unknown>
}

interface PushDevice {
  id: string
  fcm_token: string
}

Deno.serve(async (_req) => {
  const supabase = createClient(supabaseUrl, supabaseServiceKey, {
    db: { schema: "internal" },
  })

  // Claim batch of notifications from outbox
  const { data: notifications, error: claimError } = await supabase.rpc(
    "claim_outbox_notifications",
    { batch_size: 50 }
  )

  if (claimError) {
    console.error("Failed to claim notifications:", claimError)
    return new Response(JSON.stringify({ error: claimError.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    })
  }

  if (!notifications?.length) {
    return new Response(JSON.stringify({ processed: 0 }), {
      headers: { "Content-Type": "application/json" },
    })
  }

  let sentCount = 0
  let skippedCount = 0
  let failedCount = 0

  for (const notification of notifications as OutboxNotification[]) {
    // Get push devices for recipient
    const { data: devices } = await supabase
      .from("push_devices")
      .select("id, fcm_token")
      .eq("user_id", notification.recipient_id)

    if (!devices?.length) {
      // No devices - mark as skipped
      await supabase
        .from("notifications_outbox")
        .update({
          status: "skipped",
          processed_at: new Date().toISOString(),
          error_message: "No push devices registered",
        })
        .eq("id", notification.id)
      skippedCount++
      continue
    }

    // Send to each device
    let allSent = true
    for (const device of devices as PushDevice[]) {
      try {
        // Convert data_payload for FCM (all values must be strings)
        // Arrays are JSON stringified, primitives are String()
        const fcmData: Record<string, string> = {}
        for (const [key, value] of Object.entries(notification.data_payload)) {
          if (Array.isArray(value)) {
            fcmData[key] = JSON.stringify(value)  // e.g., shift_dates: '["2026-01-06"]'
          } else if (typeof value === "object" && value !== null) {
            fcmData[key] = JSON.stringify(value)
          } else {
            fcmData[key] = String(value)
          }
        }

        const success = await sendFcmNotification(device.fcm_token, {
          title: notification.title,
          body: notification.body,
          data: fcmData,
        })

        if (!success) {
          // Token might be invalid - clean up
          await supabase.from("push_devices").delete().eq("id", device.id)
        }
      } catch (error) {
        console.error(`FCM send failed for device ${device.id}:`, error)
        allSent = false
      }
    }

    // Update outbox status
    if (allSent) {
      await supabase
        .from("notifications_outbox")
        .update({
          status: "sent",
          processed_at: new Date().toISOString(),
        })
        .eq("id", notification.id)
      sentCount++
    } else {
      await supabase
        .from("notifications_outbox")
        .update({
          status: "failed",
          processed_at: new Date().toISOString(),
          error_message: "Some devices failed",
        })
        .eq("id", notification.id)
      failedCount++
    }
  }

  return new Response(
    JSON.stringify({
      processed: notifications.length,
      sent: sentCount,
      skipped: skippedCount,
      failed: failedCount,
    }),
    { headers: { "Content-Type": "application/json" } }
  )
})

async function sendFcmNotification(
  fcmToken: string,
  payload: { title: string; body: string; data: Record<string, string> }
): Promise<boolean> {
  // FCM HTTP v1 API implementation
  const accessToken = await getGoogleAccessToken()
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID")

  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: fcmToken,
          notification: {
            title: payload.title,
            body: payload.body,
          },
          data: payload.data,  // Already converted to Record<string, string>
          apns: {
            payload: {
              aps: {
                sound: "default",
                badge: 1,
              },
            },
          },
          android: {
            priority: "high",
            notification: {
              sound: "default",
            },
          },
        },
      }),
    }
  )

  if (!response.ok) {
    const error = await response.json()
    console.error("FCM error:", error)
    // Return false for invalid tokens so they get cleaned up
    if (error.error?.details?.[0]?.errorCode === "UNREGISTERED") {
      return false
    }
  }

  return response.ok
}

async function getGoogleAccessToken(): Promise<string> {
  // Implementation depends on your auth setup
  // Could use service account JSON or workload identity
  const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT")
  // ... OAuth2 token exchange
  return "access_token"
}
```

**Key changes from current implementation:**
1. ❌ REMOVED: `claim_pending_notifications()` RPC call
2. ❌ REMOVED: `buildNotificationMessage()` function and all message building logic
3. ❌ REMOVED: Consolidation logic
4. ❌ REMOVED: Reading from `notification_queue`
5. ✅ ADDED: Read only from `notifications_outbox`
6. ✅ ADDED: Send pre-computed `title`/`body` directly
7. ✅ ADDED: Include `data_payload` in FCM data field

---

## 7. Migration Strategy (Hard Cutover)

### Step 1: Create new tables
```sql
-- Run table creation SQL for:
-- internal.notification_time_windows
-- internal.notifications_outbox
```

### Step 2: Create new SQL functions
```sql
-- Create:
-- internal.upsert_notification_window()
-- internal.process_notification_windows()
-- internal.claim_outbox_notifications()
-- public.run_notification_workers()
```

### Step 3: Modify existing tables
```sql
-- Add muted column, migrate data
ALTER TABLE shift_shares ADD COLUMN muted BOOLEAN NOT NULL DEFAULT FALSE;
UPDATE shift_shares SET muted = TRUE WHERE notification_frequency = 'muted';
```

### Step 4: Deploy new edge function
```bash
supabase functions deploy send-push-notifications --no-verify-jwt
```

### Step 5: Update cron job
```sql
SELECT cron.alter_job(
  (SELECT jobid FROM cron.job WHERE jobname = 'process-shift-notifications'),
  command := 'SELECT run_notification_workers()'
);
```

### Step 6: Deploy app code with enqueue module
- Deploy `lib/notifications/enqueue.ts`
- Update all shift mutation server actions to call enqueue functions
- Update share creation, feedback submission/response to use `enqueueDirectNotification()`

### Step 7: Verify end-to-end
- Test same-day shift creation → immediate notification
- Test future shift creation → 15-min window batch
- Test share_started, feedback notifications

### Step 8: Cleanup old schema (24-48 hours later)
```sql
-- Drop old triggers
DROP TRIGGER IF EXISTS queue_shift_created_notification ON user_shifts;
DROP TRIGGER IF EXISTS capture_shift_updates_stmt ON user_shifts;
DROP TRIGGER IF EXISTS queue_pending_shift_delete ON user_shifts;
DROP TRIGGER IF EXISTS queue_share_started_notification ON shift_shares;
DROP TRIGGER IF EXISTS queue_feedback_submitted_notification ON feedback;
DROP TRIGGER IF EXISTS queue_feedback_responded_notification ON feedback;
DROP TRIGGER IF EXISTS queue_recurring_shift_created_notification ON recurring_shifts;
DROP TRIGGER IF EXISTS trigger_push_notifications_after_insert ON internal.notification_queue;

-- Drop old functions
DROP FUNCTION IF EXISTS queue_shift_created_notification();
DROP FUNCTION IF EXISTS capture_shift_updates_stmt();
DROP FUNCTION IF EXISTS queue_pending_shift_delete();
DROP FUNCTION IF EXISTS queue_share_started_notification();
DROP FUNCTION IF EXISTS queue_feedback_submitted_notification();
DROP FUNCTION IF EXISTS queue_feedback_responded_notification();
DROP FUNCTION IF EXISTS queue_recurring_shift_created_notification();
DROP FUNCTION IF EXISTS trigger_send_push_notifications();
DROP FUNCTION IF EXISTS process_pending_shift_deletes();
DROP FUNCTION IF EXISTS process_shift_update_events();
DROP FUNCTION IF EXISTS process_summary_notifications();
DROP FUNCTION IF EXISTS claim_pending_notifications();

-- Drop old tables
DROP TABLE IF EXISTS public.pending_shift_deletes;
DROP TABLE IF EXISTS public.shift_update_events;
DROP TABLE IF EXISTS public.pending_summary_notifications;
DROP TABLE IF EXISTS internal.notification_queue;

-- Drop old columns
ALTER TABLE shift_shares DROP COLUMN IF EXISTS notification_frequency;
ALTER TABLE notification_preferences DROP COLUMN IF EXISTS summary_time;
```

---

## 8. Test Plan

### Unit Tests
1. **Window calculation**: Verify clock-aligned windows (e.g., 14:23 → 14:15, 14:47 → 14:45)
2. **Same-day detection**: Verify Europe/Oslo timezone handling
3. **Message formatting**: Norwegian pluralization ("1 vakt" vs "2 vakter")
4. **Affected dates cap**: Verify cap at 31 dates
5. **Idempotency keys**: Verify stable keys don't include timestamps

### Integration Tests
1. **Create shift on today**: Verify immediate outbox insert with `due_at = now()`
2. **Create shift on future date**: Verify window aggregation
3. **Multiple shifts same owner same window**: Verify single window row with correct counts
4. **Window processing**: Verify fan-out to multiple recipients with `due_at = window_end`
5. **Muted relationship**: Verify no outbox row created
6. **Master toggle off**: Verify no outbox row created

### Concurrency Tests
1. **Two workers processing same window**: Verify SKIP LOCKED prevents duplicates
2. **High-volume shift creation**: Verify upsert handles concurrent updates
3. **Edge function concurrent claims**: Verify no duplicate sends

### E2E Tests
1. **Today shift flow**: Create → immediate notification → device receives
2. **Future shift flow**: Create → wait 15 min → notification → device receives
3. **Batch flow**: Create 5 shifts in 2 minutes → single notification with counts
4. **Non-shift flow**: Share started → immediate notification → device receives

---

## 9. Files to Modify (Summary)

### New Files to Create
| File | Purpose |
|------|---------|
| `lib/notifications/enqueue.ts` | App enqueue module |
| `supabase/sql/tables/notification_time_windows.sql` | Window table schema |
| `supabase/sql/tables/notifications_outbox.sql` | Outbox table schema |
| `supabase/sql/functions/notification/upsert_notification_window.sql` | Window upsert RPC |
| `supabase/sql/functions/notification/process_notification_windows.sql` | Window processor |
| `supabase/sql/functions/notification/claim_outbox_notifications.sql` | Outbox claim |
| `supabase/sql/functions/notification/run_notification_workers.sql` | New orchestrator |

### Files to Modify
| File | Change |
|------|--------|
| `app/[locale]/(app)/shifts/add/actions.ts` | Add enqueue calls for created shifts |
| `app/[locale]/(app)/shifts/_actions/updateShift.ts` | Add enqueue call for updates |
| `app/[locale]/(app)/shifts/_actions/deleteShift.ts` | Add enqueue call, remove `pending_shift_deletes` |
| `app/[locale]/(app)/shifts/_actions/deleteShifts.ts` | Add enqueue calls for bulk delete |
| `app/[locale]/(app)/shifts/_actions/copyShifts.ts` | Add enqueue calls for copied shifts |
| `app/[locale]/(app)/shifts/add/_actions/createRecurringShift.ts` | Add enqueue call |
| `app/[locale]/(app)/shifts/_actions/updateRecurringShift.ts` | Add enqueue calls |
| `app/[locale]/(app)/shifts/_actions/deleteRecurringShift.ts` | Add enqueue calls |
| `app/[locale]/(app)/shifts/_actions/convertRecurringShiftToStandalone.ts` | Add enqueue call |
| `supabase/functions/send-push-notifications/index.ts` | Complete rewrite |
| Settings UI components | Update for muted toggle |

### SQL Files to Remove (After Migration)
- `supabase/sql/functions/notification/process_pending_shift_deletes.sql`
- `supabase/sql/functions/notification/process_shift_update_events.sql`
- `supabase/sql/functions/notification/process_summary_notifications.sql`
- `supabase/sql/functions/trigger/queue_shift_created_notification.sql`
- `supabase/sql/functions/trigger/capture_shift_updates_stmt.sql`
- `supabase/sql/functions/trigger/queue_pending_shift_delete.sql`
- `supabase/sql/functions/trigger/queue_share_started_notification.sql`
- `supabase/sql/functions/trigger/queue_feedback_submitted_notification.sql`
- `supabase/sql/functions/trigger/queue_feedback_responded_notification.sql`
- `supabase/sql/functions/trigger/queue_recurring_shift_created_notification.sql`

---

## 10. Retention & Cleanup

### Outbox retention
```sql
-- Daily cleanup of old outbox rows (7 days)
DELETE FROM internal.notifications_outbox
WHERE processed_at < now() - INTERVAL '7 days';
```

### Window retention
```sql
-- Daily cleanup of finalized windows (7 days)
DELETE FROM internal.notification_time_windows
WHERE status = 'finalized'
  AND updated_at < now() - INTERVAL '7 days';
```

Add to `cleanup-shift-notification-events` cron job or create new job.

---

## 11. Step-by-Step Implementation Checklist

### Phase 1: Database Schema
- [ ] Create `internal.notification_time_windows` table
- [ ] Create `internal.notifications_outbox` table
- [ ] Add `muted` column to `shift_shares`
- [ ] Migrate `notification_frequency='muted'` to `muted=true`

### Phase 2: SQL Functions
- [ ] Create `internal.upsert_notification_window()` RPC
- [ ] Create `internal.process_notification_windows()` function
- [ ] Create `internal.claim_outbox_notifications()` function
- [ ] Create `run_notification_workers()` orchestrator

### Phase 3: App Enqueue Module
- [ ] Create `lib/notifications/enqueue.ts` with:
  - [ ] `enqueueShiftNotification()` function
  - [ ] `enqueueDirectNotification()` function
  - [ ] `generateMutationId()` function
  - [ ] Helper functions for Norwegian message building

### Phase 4: Update Shift Mutations
- [ ] Update `createShifts()` in `app/[locale]/(app)/shifts/add/actions.ts`
- [ ] Update `updateShift()` in `app/[locale]/(app)/shifts/_actions/updateShift.ts`
- [ ] Update `deleteShift()` in `app/[locale]/(app)/shifts/_actions/deleteShift.ts`
- [ ] Update `deleteShifts()` in `app/[locale]/(app)/shifts/_actions/deleteShifts.ts`
- [ ] Update `copyShifts()` in `app/[locale]/(app)/shifts/_actions/copyShifts.ts`
- [ ] Update `createRecurringShift()` in `app/[locale]/(app)/shifts/add/_actions/createRecurringShift.ts`
- [ ] Update `updateRecurringShift()` in `app/[locale]/(app)/shifts/_actions/updateRecurringShift.ts`
- [ ] Update `deleteRecurringShift()` in `app/[locale]/(app)/shifts/_actions/deleteRecurringShift.ts`
- [ ] Update `convertRecurringShiftToStandalone()` in `app/[locale]/(app)/shifts/_actions/convertRecurringShiftToStandalone.ts`

### Phase 5: Update Non-Shift Notifications
- [ ] **CRITICAL**: Search repo for all `shift_shares` inserts:
  - [ ] Search: `from('shift_shares').insert` and `insert into shift_shares`
  - [ ] Confirm every path calls `enqueueDirectNotification()` for `share_started`
- [ ] Find and update share creation flow to use `enqueueDirectNotification()`
- [ ] Find and update feedback submission to use `enqueueDirectNotification()`
- [ ] Find and update feedback response to use `enqueueDirectNotification()`
- [ ] Update admin broadcast functions to insert directly to outbox

### Phase 6: Update Cron
- [ ] Modify `process-shift-notifications` cron to call `run_notification_workers()`

### Phase 7: Edge Function
- [ ] Rewrite `send-push-notifications` to read only from outbox
- [ ] Remove all message building logic
- [ ] Remove `claim_pending_notifications()` usage
- [ ] Deploy edge function

### Phase 8: UI Updates
- [ ] Update settings UI for muted toggle (replace frequency dropdown)

### Phase 9: Verification
- [ ] Test same-day shift creation (immediate notification)
- [ ] Test future shift creation (15-min batch)
- [ ] Test multiple shifts same window (aggregation)
- [ ] Test muted relationships (no notification)
- [ ] Test recurring shift operations
- [ ] Test share_started notification
- [ ] Test feedback notifications

### Phase 10: Cleanup (24-48 hours after verification)

**GATE: Only proceed when ALL of these are true:**
- [ ] `share_started` notifications working via outbox
- [ ] `feedback_submitted` notifications working via outbox
- [ ] `feedback_responded` notifications working via outbox
- [ ] `recurring_shift_created` notifications working via outbox
- [ ] Admin broadcasts working via outbox
- [ ] Edge function no longer references `claim_pending_notifications()`

**Then cleanup:**
- [ ] Drop all old triggers
- [ ] Drop all old trigger functions
- [ ] Drop old processor functions
- [ ] Drop `notification_frequency` column from `shift_shares`
- [ ] Drop `summary_time` column from `notification_preferences`
- [ ] Drop old tables (`pending_shift_deletes`, `shift_update_events`, `pending_summary_notifications`, `notification_queue`)
- [ ] Update cleanup cron job for new tables
- [ ] Delete old SQL files from repo

---

## 12. Key Decisions & Assumptions

1. **No database triggers**: All notification logic runs in app code only. DB writes outside the app do not create notifications (intentional).
2. **No 90-second delay**: Same-day changes are instant; delete+recreate on same day sends 2 notifications (acceptable).
3. **Clock-aligned windows**: :00, :15, :30, :45 for predictability.
4. **Hard cutover**: No parallel run period (beta product).
5. **Affected dates cap**: 31 dates max in `notification_time_windows`.
6. **Norwegian only**: Title/body pre-computed in Norwegian (no multi-locale support needed).
7. **Single outbox**: All notification types (shifts, shares, feedback, admin) use `notifications_outbox`.
8. **Stable idempotency keys**: No `now()` or epoch timestamps in keys. Use `mutationId` for same-day dedup.
9. **Window due_at**: Set to `window_end` (window_start + 15 min) for clarity.
10. **Recurring virtual shifts**: App enqueues directly (no trigger fires since no row exists).
11. **Separate queries for viewer eligibility**: No PostgREST implicit joins; query `shift_shares` then `notification_preferences` separately.
12. **shift_dates as JSON array**: Stored as `to_jsonb(array)` in Postgres, sent as `JSON.stringify(array)` in FCM data.
13. **ownerName from caller**: Server actions should pass `ownerName` from existing session/profile data, not re-fetch from `auth.users`.
14. **updateShift change detection**: Compare old vs new date/time values; only notify if actually changed.
15. **Bounded retries**: 15-minute stale claim timeout, max 10 attempts, then permanent failure.
16. **Timezone consistency**: All date formatting uses `timeZone: "Europe/Oslo"` explicitly.
