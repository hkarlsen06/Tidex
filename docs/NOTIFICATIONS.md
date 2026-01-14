# Push Notifications System

This document provides comprehensive documentation of the push notification system in Tidex, covering architecture, implementation details, and patterns for creating new notification types.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Database Schema](#database-schema)
4. [Notification Types](#notification-types)
5. [Notification Flows](#notification-flows)
6. [Edge Functions](#edge-functions)
7. [Client-Side Implementation](#client-side-implementation)
8. [FCM Integration](#fcm-integration)
9. [Cron Jobs](#cron-jobs)
10. [Key Design Patterns](#key-design-patterns)
11. [Creating New Notification Types](#creating-new-notification-types)
12. [Troubleshooting](#troubleshooting)
13. [File References](#file-references)
14. [Environment Variables](#environment-variables)

---

## Overview

The notifications system supports the following notification types:

| Type | Delivery | Description |
|------|----------|-------------|
| **Shared Shift Notifications** | Instant | When someone shares a shift with you |
| **Shift Reminder Notifications** | Scheduled (cron) | Reminders before your shifts start |
| **Share Started Notifications** | Instant | When someone starts sharing their shifts with you |
| **Recurring Shift Notifications** | Instant | When someone creates a recurring shift pattern |
| **Batched Change Notifications** | Cron (1 min) | Consolidated updates/deletes from shift changes |

All notifications use **Firebase Cloud Messaging (FCM) HTTP v1 API** for delivery to iOS (via APNS) and Android devices.

---

## Architecture

### High-Level Flow

```
                                    PUSH NOTIFICATION SYSTEM
    ═══════════════════════════════════════════════════════════════════════════════

    ┌─────────────────────────────────────────────────────────────────────────────┐
    │                           CLIENT-SIDE (Native App)                          │
    └─────────────────────────────────────────────────────────────────────────────┘

    ┌──────────────────┐     ┌──────────────────┐     ┌──────────────────────────┐
    │   App Launches   │────>│  Request FCM     │────>│  Save Token to Server    │
    │                  │     │  Permission      │     │  (push_devices table)    │
    └──────────────────┘     └──────────────────┘     └──────────────────────────┘
                                                                   │
                                                                   ▼
    ┌──────────────────────────────────────────────────────────────────────────────┐
    │                                                                              │
    │   push_devices table                                                         │
    │   ┌────────────────────────────────────────────────────────────────────┐    │
    │   │ id | user_id | fcm_token | platform | device_id | last_seen_at    │    │
    │   │ ─────────────────────────────────────────────────────────────────── │    │
    │   │ ... | abc-123 | dX9f...  | ios      | vendor-id | 2025-01-15 10:00│    │
    │   └────────────────────────────────────────────────────────────────────┘    │
    │                                                                              │
    └──────────────────────────────────────────────────────────────────────────────┘
```

### Instant vs Cron-Based Delivery

| Delivery Type | Used For | Reason |
|---------------|----------|--------|
| **Instant (trigger)** | Shared shifts, share started, recurring patterns | Users expect immediate notification |
| **Cron (1 min)** | Batched updates/deletes | Allows replacement detection and consolidation |
| **Cron (10 min)** | Shift reminders | Time-based, slight delay acceptable |

---

## Database Schema

### `push_devices` - FCM Token Storage

```sql
CREATE TABLE push_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  fcm_token TEXT NOT NULL UNIQUE,  -- Globally unique token
  platform TEXT NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
  device_id TEXT,        -- iOS identifierForVendor for token rotation
  device_model TEXT,     -- e.g., "iPhone 14 Pro"
  app_version TEXT,      -- e.g., "1.2.0"
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**RLS Policies:** Users can only manage their own devices.

### `notification_preferences` - User Settings

```sql
CREATE TABLE notification_preferences (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  shared_shifts_enabled BOOLEAN NOT NULL DEFAULT true,
  shift_reminders_enabled BOOLEAN NOT NULL DEFAULT true,
  shift_reminder_minutes INTEGER NOT NULL DEFAULT 300
    CHECK (shift_reminder_minutes IN (60, 120, 300, 1440)),
  quiet_hours_start TIME,
  quiet_hours_end TIME,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

**Reminder options:**
- `60` = 1 hour before
- `120` = 2 hours before
- `300` = 5 hours before (default)
- `1440` = 24 hours before

### `notification_queue` - Delivery Queue

```sql
CREATE TABLE notification_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL CHECK (type IN (
    'shared_shift_created',
    'shared_shift_updated',
    'shared_shift_deleted',
    'shared_shift_changes',
    'recurring_shift_created',
    'admin_broadcast',
    'share_started'
  )),
  recipient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sender_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  payload JSONB NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending', 'processing', 'sent', 'failed', 'skipped'
  )),
  claimed_at TIMESTAMPTZ,      -- For atomic claiming
  processed_at TIMESTAMPTZ,
  error_message TEXT,
  idempotency_key TEXT UNIQUE  -- Prevent duplicate notifications
);
```

**Status flow:** `pending` → `processing` → `sent`/`failed`/`skipped`

### `shift_reminders_sent` - Reminder Duplicate Prevention

```sql
CREATE TABLE shift_reminders_sent (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  shift_instance_key TEXT NOT NULL,  -- "single:{id}:{date}:{start}"
  reminder_minutes INTEGER NOT NULL,
  sent_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, shift_instance_key, reminder_minutes)  -- Distributed lock
);
```

The unique constraint acts as a **distributed lock** - if two workers try to send the same reminder simultaneously, only one succeeds.

### `pending_shift_deletes` - Delayed Delete Processing

```sql
CREATE TABLE pending_shift_deletes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shift_id UUID NOT NULL,
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  shift_date DATE NOT NULL,
  start_time TIME NOT NULL,
  end_time TIME NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  check_at TIMESTAMPTZ NOT NULL,  -- When to process (now + 90 seconds)
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Used for replacement detection (delete-then-recreate patterns).

### `shift_update_events` - Captured Updates

```sql
CREATE TABLE shift_update_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shift_id UUID NOT NULL,
  owner_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  shift_date DATE NOT NULL,
  event_type TEXT NOT NULL,  -- 'update'
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Captured shift updates for batched cron processing.

---

## Notification Types

### Type Reference

| Type | Database Value | Description | Delivery |
|------|----------------|-------------|----------|
| New shift | `shared_shift_created` | Direct INSERT of a new shift | Instant |
| Shift modified | `shared_shift_updated` | Direct UPDATE, or recurring conversion | Instant |
| Shift removed | `shared_shift_deleted` | Processed via pending deletes | Cron |
| Batched changes | `shared_shift_changes` | Multiple updates/deletes | Cron |
| Recurring pattern | `recurring_shift_created` | New recurring shift pattern | Instant |
| Share started | `share_started` | Someone started sharing with you | Instant |
| Shift reminder | N/A (direct send) | Reminder before your shift | Cron (10 min) |

### Idempotency Keys

Each notification has a unique idempotency key to prevent duplicates:

| Pattern | Used For |
|---------|----------|
| `shift_created:{shift_id}:{viewer_id}` | New shifts |
| `shift_recurring_converted:{shift_id}:{viewer_id}` | Recurring conversions |
| `shift_changes:{owner_id}:{viewer_id}:{hash}` | Batched deletes |
| `shift_direct_updates:{owner_id}:{viewer_id}:{hash}` | Batched updates |
| `recurring_created:{recurring_id}:{viewer_id}` | Recurring patterns |
| `share_started:{owner_id}:{viewer_id}` | Share started |

---

## Notification Flows

### 1. Creating a New Shift (Instant)

```
INSERT into user_shifts
    ↓
on_shift_created_notify trigger (ROW-level, runs FIRST via 'a_' prefix)
    ↓
queue_shift_created_notification()
    ↓
Inserts 'shared_shift_created' into notification_queue
    ↓
on_shifts_inserted_send_notifications trigger (STATEMENT-level, runs LAST via 'z_' prefix)
    ↓
trigger_push_notifications_after_insert()
    ↓
Calls send-push-notifications edge function via pg_net
    ↓
Edge function claims, consolidates, and sends via FCM
```

**Message**: "{owner_name} la til en vakt" (added a shift)

### 2. Updating an Existing Shift (Cron)

```
UPDATE user_shifts (date, start_time, or end_time changed)
    ↓
trg_capture_shift_updates_stmt trigger
    ↓
capture_shift_updates_stmt()
    ↓
Inserts into shift_update_events table
    ↓
[Cron: every minute] process-shift-notifications
    ↓
run_shift_notification_workers()
    ↓
process_shift_update_events()
    ↓
Inserts 'shared_shift_changes' into notification_queue
    ↓
Calls send-push-notifications edge function
```

**Message**: "{owner_name} endret {count} vakt(er)" (changed X shift(s))

### 3. Deleting a Shift (Cron with Replacement Detection)

Deletions use a delayed processing system to detect delete-then-recreate patterns:

```
DELETE from user_shifts
    ↓
on_shift_deleted_queue_pending trigger
    ↓
queue_pending_shift_delete()
    ↓
Inserts into pending_shift_deletes (status='pending', check_at=now()+90s)
    ↓
[Cron: every minute] process-shift-notifications
    ↓
run_shift_notification_workers()
    ↓
process_pending_shift_deletes()
    ↓
Checks if a new shift was created on the same date (replacement detection)
    ↓
If replacement found: 'shared_shift_changes' with updated_count > 0
If no replacement: 'shared_shift_changes' with deleted_count > 0
    ↓
Calls send-push-notifications edge function
```

**Replacement detection logic:**
- On DELETE: Insert into `pending_shift_deletes` with 90-second delay
- On INSERT: Check if there's a pending delete for the **same date**
- If match found: Suppress "created" notification, cron sends "updated" instead
- If no match: Normal "created" notification sent immediately

### 4. Editing a Recurring Shift (Conversion)

When a user edits a recurring (virtual) shift, it's converted to a standalone shift:

```
User edits recurring shift in UI
    ↓
updateShift() server action
    ↓
convertRecurringShiftToStandalone()
    ↓
1. Adds date to recurring_shifts.exclusions array
2. INSERT new standalone shift into user_shifts
    ↓
on_shift_created_notify trigger
    ↓
queue_shift_created_notification()
    ↓
Detects: NEW.shift_date is in exclusions of a recurring_shift
    ↓
Inserts 'shared_shift_updated' (NOT 'shared_shift_created')
```

**Message**: "{owner_name} endret en vakt" (changed a shift)

### 5. Creating a Recurring Shift Pattern (Instant)

```
INSERT into recurring_shifts
    ↓
Trigger: queue_recurring_shift_created_notification()
    ↓
Inserts 'recurring_shift_created' into notification_queue
    ↓
Statement trigger calls send-push-notifications edge function
```

**Message**: "{owner_name} la til en gjentakende vakt" (added a recurring shift)

### 6. Someone Starts Sharing With You (Instant)

```
INSERT into shift_shares
    ↓
on_share_started_notify trigger
    ↓
queue_share_started_notification()
    ↓
Inserts 'share_started' into notification_queue
    ↓
z_on_share_inserted_send_notifications trigger
    ↓
trigger_push_notifications_after_share_insert()
    ↓
Calls send-push-notifications edge function
```

**Message**: "{owner_name} deler vaktene sine med deg" (shares their shifts with you)
**Body**: "Trykk for å dele tilbake" (Tap to share back)

**Deep Link**: `/sharing?manage=true&highlight={owner_id}`
- Opens the manage sharing modal automatically
- Highlights the person who shared with you
- The "Share back" button pulses to draw attention
- Highlight fades after 5 seconds

### 7. Shift Reminders (Cron-based)

```
                                 ┌────────────────────┐
                                 │  pg_cron job       │
                                 │  */10 * * * *      │
                                 └────────────────────┘
                                          │
                                          │ Every 10 minutes
                                          ▼
    ┌──────────────────────────────────────────────────────────────────────────────┐
    │  process-shift-reminders (Edge Function)                                     │
    │  ┌─────────────────────────────────────────────────────────────────────────┐ │
    │  │ 1. get_shifts_due_for_reminder() - SQL function                        │ │
    │  │    ┌────────────────────────────────────────────────────────────────┐  │ │
    │  │    │ - Query user_shifts where shift_date >= today                  │  │ │
    │  │    │ - Join with notification_preferences (shift_reminders_enabled) │  │ │
    │  │    │ - Calculate minutes_until_shift in Europe/Oslo timezone        │  │ │
    │  │    │ - Narrow window: reminder_minutes-10 <= minutes <= reminder    │  │ │
    │  │    └────────────────────────────────────────────────────────────────┘  │ │
    │  │                                                                         │ │
    │  │ 2. For each due reminder:                                               │ │
    │  │    ┌────────────────────────────────────────────────────────────────┐  │ │
    │  │    │ CLAIM: INSERT INTO shift_reminders_sent                        │  │ │
    │  │    │        (unique constraint acts as distributed lock)            │  │ │
    │  │    │        - Success: Send notification                            │  │ │
    │  │    │        - Conflict (23505): Skip (already sent)                 │  │ │
    │  │    └────────────────────────────────────────────────────────────────┘  │ │
    │  │                                                                         │ │
    │  │ 3. Send via FCM HTTP v1 API to user's devices                          │ │
    │  │ 4. Clean up invalid tokens                                             │ │
    │  └─────────────────────────────────────────────────────────────────────────┘ │
    └──────────────────────────────────────────────────────────────────────────────┘
```

**Narrow window logic:**
```sql
-- Only send when within [reminder_minutes - 10, reminder_minutes]
WHERE mins_until <= reminder_mins
  AND mins_until >= (reminder_mins - 10)
```

This prevents early sends while ensuring 10-minute polling catches all reminders.

---

## Edge Functions

### `send-push-notifications` (Instant & Cron Delivery)

Triggered immediately for instant notifications and by cron for batched changes.

**Flow:**
1. `claim_pending_notifications(50)` - Atomic claim with `FOR UPDATE SKIP LOCKED`
2. Consolidate notifications from same sender to same recipient
3. Get OAuth2 access token from Google (cached for 1 hour)
4. Send to FCM HTTP v1 API
5. Update queue status (`sent`/`failed`/`skipped`)
6. Delete invalid tokens

**Consolidation example:**
- User A creates 6 shifts that User B receives
- Instead of 6 notifications, User B gets: "User A la til 6 vakter"

### `process-shift-reminders` (Cron-based)

Runs every 10 minutes via `pg_cron`.

**Flow:**
1. `get_shifts_due_for_reminder()` - Find shifts in the narrow window
2. For each: try INSERT into `shift_reminders_sent` (claim)
   - Success: send notification
   - Constraint violation (23505): skip (already sent)
3. Send to user's devices via FCM
4. Clean up invalid tokens

### Message Building

The `buildNotificationMessage()` function handles all notification types:

```typescript
switch (type) {
  case "single_shift":
    // Checks notificationType for created/updated/deleted
    if (notificationType === "shared_shift_updated") → "endret en vakt"
    if (notificationType === "shared_shift_deleted") → "slettet en vakt"
    default → "la til en vakt"

  case "multiple_shifts":
    // Same logic but with count

  case "shift_changes":
    // Batched from cron - uses updated_count/deleted_count

  case "recurring":
    → "la til en gjentakende vakt"

  case "share_started":
    → "deler vaktene sine med deg"
}
```

---

## Client-Side Implementation

The iOS app is fully native SwiftUI. Push notification handling is implemented in:

- `ios/App/TidexApp/TidexApp.swift` - Firebase initialization
- `ios/App/TidexApp/Native/Services/Push/` - FCM token management and notification handling

### Token Registration

FCM tokens are stored in the `push_devices` table. The native app:
1. Requests notification permission via `UNUserNotificationCenter`
2. Receives APNs token and exchanges for FCM token via Firebase SDK
3. Saves FCM token to Supabase `push_devices` table with device metadata

### Notification Tap Handling

When a user taps a notification, the app navigates based on payload type:
- `shift_reminder` → Opens shifts view for that date
- `share_started` → Opens sharing view with manage modal
- Shared shift notifications → Opens sharing view highlighting the shift

### Deep Linking

Notifications include data for deep linking:
- `owner_id` - The shift owner's user ID
- `shift_id` - The specific shift ID (for highlighting)
- `shift_date` - For calendar navigation
- `shift_dates` - Comma-separated dates for multiple shifts

---

## FCM Integration

Both edge functions use FCM HTTP v1 API (not legacy API):

```typescript
// OAuth2 authentication
const accessToken = await getFcmAccessToken() // Cached for 1 hour

// Send notification
await fetch(`https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`, {
  method: "POST",
  headers: {
    Authorization: `Bearer ${accessToken}`,
    "Content-Type": "application/json",
  },
  body: JSON.stringify({
    message: {
      token: fcmToken,
      notification: { title, body },
      data: { type, shift_id, shift_date, owner_id },
      apns: { payload: { aps: { sound: "default", "mutable-content": 1 } } },
      android: { notification: { sound: "default" } },
    },
  }),
})
```

**Invalid token handling:**
- `UNREGISTERED`, `INVALID_ARGUMENT`, `NOT_FOUND` errors trigger token deletion
- Automatic cleanup keeps `push_devices` table clean

---

## Cron Jobs

| Job | Schedule | Purpose |
|-----|----------|---------|
| `process-shift-notifications` | `* * * * *` | Runs `run_shift_notification_workers()` for updates/deletes |
| `process-shift-reminders` | `*/10 * * * *` | Triggers shift reminder edge function |
| `cleanup-shift-reminders-sent` | `0 3 * * *` | Cleans up old reminder records (7 days) |
| `cleanup-shift-notification-events` | `0 4 * * *` | Cleans up resolved notification events (7 days) |

---

## Key Design Patterns

### 1. Claim-Before-Send Pattern

Prevents duplicate notifications when multiple workers process the same queue:

**For shared shifts (notification_queue):**
```sql
-- claim_pending_notifications() uses FOR UPDATE SKIP LOCKED
UPDATE notification_queue
SET status = 'processing', claimed_at = now()
WHERE id IN (
  SELECT id FROM notification_queue
  WHERE status = 'pending'
  FOR UPDATE SKIP LOCKED
  LIMIT 50
)
RETURNING *;
```

**For reminders (shift_reminders_sent):**
```sql
-- Unique constraint acts as distributed lock
INSERT INTO shift_reminders_sent (user_id, shift_instance_key, reminder_minutes)
VALUES ($1, $2, $3)
ON CONFLICT DO NOTHING;
-- If insert succeeds → send notification
-- If conflict → already sent, skip
```

### 2. Trigger Execution Order

**Critical**: PostgreSQL executes triggers alphabetically by name when they have the same timing.

```
1. a_on_shift_created_queue_notification (ROW-level) - Runs FIRST
   - Decides if notification should be sent
   - Inserts into notification_queue

2. z_on_shifts_inserted_send_notifications (STATEMENT-level) - Runs LAST
   - Checks if pending notifications exist
   - Calls edge function
```

The `a_` and `z_` prefixes ensure correct ordering.

### 3. Replacement Detection

Avoids sending both "deleted" and "created" for delete-then-recreate patterns:

1. On DELETE: Insert into `pending_shift_deletes` with 90-second delay
2. On INSERT: Check if there's a pending delete for the **same date**
3. If match found: Suppress "created" notification
4. Cron processes pending deletes and sends "updated" instead

### 4. Recurring Conversion Detection

When editing a recurring shift creates a standalone:

1. On INSERT: Check if `NEW.shift_date` exists in `exclusions` array of any `recurring_shifts`
2. If found: Use `shared_shift_updated` type instead of `shared_shift_created`
3. Use different idempotency key prefix (`shift_recurring_converted:`)

### 5. Consolidation

Multiple shifts from same sender are consolidated:
- Single shift: "Ola la til en vakt - Fredag 15. januar kl. 08:00-16:00"
- Multiple shifts: "Ola la til 6 vakter - Trykk for å se vaktene"
- Mixed: "Ola endret 3 og slettet 2 vakter"

### 6. Timezone Handling

All shift times are processed in Europe/Oslo timezone:
```sql
((shift_date::TEXT || ' ' || start_time)::TIMESTAMP AT TIME ZONE 'Europe/Oslo')
```

---

## Creating New Notification Types

### Step 1: Add Type to Database

```sql
-- Add to notification_queue type check constraint
ALTER TABLE notification_queue
DROP CONSTRAINT notification_queue_type_check,
ADD CONSTRAINT notification_queue_type_check
CHECK (type IN (
  'shared_shift_created',
  'shared_shift_updated',
  'shared_shift_deleted',
  'shared_shift_changes',
  'recurring_shift_created',
  'admin_broadcast',
  'share_started',
  'your_new_type'  -- Add here
));
```

### Step 2: Create Queue Function

```sql
CREATE OR REPLACE FUNCTION queue_your_notification()
RETURNS TRIGGER AS $$
DECLARE
  v_recipient_id UUID;
  v_sender_id UUID;
  v_idempotency_key TEXT;
BEGIN
  -- 1. Determine recipient(s)
  -- 2. Check notification preferences
  -- 3. Build idempotency key
  -- 4. Insert into queue

  FOR v_recipient_id IN
    SELECT viewer_id FROM shift_shares
    WHERE owner_id = NEW.user_id
    AND NOT blocked
  LOOP
    -- Check if recipient wants this notification
    IF NOT EXISTS (
      SELECT 1 FROM notification_preferences
      WHERE user_id = v_recipient_id
      AND your_setting_enabled = true
    ) THEN
      CONTINUE;
    END IF;

    v_idempotency_key := 'your_type:' || NEW.id || ':' || v_recipient_id;

    INSERT INTO notification_queue (type, recipient_id, sender_id, payload, idempotency_key)
    VALUES (
      'your_new_type',
      v_recipient_id,
      NEW.user_id,
      jsonb_build_object(
        'entity_id', NEW.id,
        'extra_data', 'value'
      ),
      v_idempotency_key
    )
    ON CONFLICT (idempotency_key) DO NOTHING;
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
```

### Step 3: Create Trigger

```sql
-- Row-level trigger (named with 'a_' prefix to run first)
CREATE TRIGGER a_on_your_event_notify
  AFTER INSERT ON your_table
  FOR EACH ROW
  EXECUTE FUNCTION queue_your_notification();

-- Statement-level trigger to send (named with 'z_' prefix to run last)
-- Or reuse existing trigger_push_notifications_after_insert()
```

### Step 4: Update Edge Function

In `supabase/functions/send-push-notifications/index.ts`:

```typescript
// Add to buildNotificationMessage()
case "your_new_type":
  return {
    title: `${senderName} did something`,
    body: "Tap to see details",
  }

// Add to notification data payload
data: {
  type: notification.type,
  entity_id: payload.entity_id,
  // Add any data needed for deep linking
}
```

### Step 5: Handle Client-Side Tap

In `lib/notifications/push-service.ts`:

```typescript
private handleNotificationTap(payload: PushNotificationPayload): void {
  switch (payload.type) {
    case "your_new_type":
      window.location.href = `/${locale}/your-route?id=${payload.entity_id}`
      break
    // ... other cases
  }
}
```

### Step 6: Add User Preference (Optional)

If users should be able to disable this notification:

```sql
ALTER TABLE notification_preferences
ADD COLUMN your_setting_enabled BOOLEAN NOT NULL DEFAULT true;
```

Update the queue function to check this preference.

---

## Troubleshooting

### Notification shows "added" instead of "updated"

Possible causes:
1. **Recurring conversion not detected**: Check if the date is properly in the `exclusions` array
2. **Old edge function**: Ensure `send-push-notifications` is deployed with latest code
3. **Race condition**: The recurring exclusion update might not have committed before the insert trigger ran
4. **Trigger order wrong**: Verify triggers are named with `a_` and `z_` prefixes

### Delete+recreate shows "added" instead of "updated"

The replacement detection system should suppress "created" when:
1. A shift is deleted (creates `pending_shift_deletes` entry with 90s delay)
2. A new shift is created on the **same date** within 90 seconds

Check:
1. **Trigger order**: Queue trigger must run before send trigger
2. **pending_shift_deletes**: Verify the delete created an entry with `status = 'pending'`
3. **Timing**: The `check_at` must be > now() for suppression to work

### Notification not sent

Check:
1. `notification_queue` for pending/failed entries
2. `push_devices` for valid FCM tokens
3. `notification_preferences` settings for recipient
4. `shift_shares` for active share relationship (not blocked)
5. Edge function logs in Supabase dashboard

### Duplicate notifications

The idempotency key should prevent duplicates. If occurring:
1. Check if different key patterns are being used for same logical event
2. Verify `ON CONFLICT (idempotency_key) DO NOTHING` clause is working
3. Check for race conditions between row and statement triggers

### FCM token errors

Common FCM errors and actions:
- `UNREGISTERED` - Token invalid, delete from `push_devices`
- `INVALID_ARGUMENT` - Token format wrong, delete from `push_devices`
- `NOT_FOUND` - Token not found, delete from `push_devices`
- `QUOTA_EXCEEDED` - Rate limited, implement backoff

---

## File References

| File | Purpose |
|------|---------|
| [lib/notifications/push-service.ts](../lib/notifications/push-service.ts) | Client-side FCM registration & tap handling |
| [components/settings/notifications/NotificationSettingsForm.tsx](../components/settings/notifications/NotificationSettingsForm.tsx) | Settings UI component |
| [supabase/functions/send-push-notifications/index.ts](../supabase/functions/send-push-notifications/index.ts) | Shared shift & queue delivery |
| [supabase/functions/process-shift-reminders/index.ts](../supabase/functions/process-shift-reminders/index.ts) | Reminder processing |
| [supabase/sql/functions/](../supabase/sql/functions/) | SQL function definitions |
| [supabase/sql/cron/](../supabase/sql/cron/) | Cron job documentation |

### Key SQL Functions

| Function | Purpose |
|----------|---------|
| `queue_shift_created_notification()` | Trigger for shift creation |
| `queue_pending_shift_delete()` | Trigger for shift deletion |
| `capture_shift_updates_stmt()` | Trigger for shift updates |
| `queue_share_started_notification()` | Trigger for shift_shares creation |
| `queue_recurring_shift_created_notification()` | Trigger for recurring shifts |
| `process_pending_shift_deletes()` | Cron: processes delayed deletes |
| `process_shift_update_events()` | Cron: processes direct updates |
| `run_shift_notification_workers()` | Cron: orchestrates processors |
| `claim_pending_notifications()` | Atomic queue claim |
| `get_shifts_due_for_reminder()` | Find shifts needing reminders |
| `trigger_push_notifications_after_insert()` | Calls edge function after queue insert |
| `trigger_push_notifications_after_share_insert()` | Calls edge function after share creation |

---

## Environment Variables

```env
# Supabase (in Edge Functions)
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...

# FCM HTTP v1 (from Google service account)
FCM_PROJECT_ID=your-firebase-project
FCM_CLIENT_EMAIL=firebase-adminsdk@...iam.gserviceaccount.com
FCM_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----\n...
```

**Vault secrets** (for pg_cron/pg_net):
- `supabase_url` - Used by triggers to call edge functions
- `service_role_key` - Authorization for edge function calls

---

## Settings UI

Users configure notifications at `/{locale}/settings/notifications`:

**Components:**
- `NotificationSettingsForm.tsx` - Client component with auto-save

**Features:**
- Shared shifts toggle (on/off)
- Shift reminders toggle (on/off)
- Reminder timing selector (1hr, 2hr, 5hr, 24hr options)
- Permission status check (shows warning if denied on iOS)
- Request permission button (when permission is "prompt")

**Auto-save:** Changes are saved immediately via server actions:
- `updateNotificationSettings()` - Shared shifts preference
- `updateShiftReminderSettings()` - Reminder preferences
