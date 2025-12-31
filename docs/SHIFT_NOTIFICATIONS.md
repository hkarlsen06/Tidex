# Shift Notification System

This document describes how push notifications work for shared shifts, including the different notification types, flows, and edge cases.

## Overview

When a user creates, updates, or deletes a shift, notifications are sent to users who are following that user's shifts (via `shift_shares`). The system handles several complex scenarios including recurring shifts, delete-then-recreate patterns, and batched updates.

## Notification Types

The `notification_queue` table supports these shift-related types:

| Type | Description | When Used |
|------|-------------|-----------|
| `shared_shift_created` | New shift added | Direct INSERT of a new shift |
| `shared_shift_updated` | Shift modified | Direct UPDATE of shift, or recurring conversion |
| `shared_shift_deleted` | Shift removed | Processed via pending deletes (not direct) |
| `shared_shift_changes` | Batched changes | Cron-processed updates/deletes (multiple shifts) |
| `recurring_shift_created` | Recurring pattern added | New recurring shift pattern created |

## Notification Flows

### 1. Creating a New Shift

```
INSERT into user_shifts
    ↓
on_shift_created_notify trigger
    ↓
queue_shift_created_notification()
    ↓
Inserts 'shared_shift_created' into notification_queue
    ↓
on_shifts_inserted_send_notifications trigger
    ↓
trigger_push_notifications_after_insert()
    ↓
Calls send-push-notifications edge function
```

**Message**: "{owner_name} la til en vakt" (added a shift)

### 2. Updating an Existing Shift

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
run_shift_notification_workers() calls send-push-notifications edge function
```

**Message**: "{owner_name} endret {count} vakt(er)" (changed X shift(s))

### 3. Deleting a Shift

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

**Message for update**: "{owner_name} endret en vakt"
**Message for delete**: "{owner_name} slettet en vakt"

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

This special handling was added in migration `fix_recurring_conversion_notification_type` to ensure that editing a recurring shift shows "updated" instead of "added".

### 5. Creating a Recurring Shift Pattern

```
INSERT into recurring_shifts
    ↓
Trigger: queue_recurring_shift_created_notification()
    ↓
Inserts 'recurring_shift_created' into notification_queue
```

**Message**: "{owner_name} la til en gjentakende vakt" (added a recurring shift)

## Key Database Objects

### Tables

- `notification_queue` - Pending/processed notifications
- `pending_shift_deletes` - Delayed delete processing for replacement detection
- `shift_update_events` - Captured shift updates for batched processing
- `push_devices` - User FCM tokens for push delivery
- `notification_preferences` - User notification settings

### Functions

| Function | Purpose |
|----------|---------|
| `queue_shift_created_notification()` | Trigger function for shift creation |
| `queue_pending_shift_delete()` | Trigger function for shift deletion |
| `capture_shift_updates_stmt()` | Trigger function for shift updates |
| `process_pending_shift_deletes()` | Cron: processes delayed deletes |
| `process_shift_update_events()` | Cron: processes direct updates |
| `run_shift_notification_workers()` | Cron: orchestrates both processors and triggers edge function |
| `claim_pending_notifications()` | Atomic queue claim for edge function |
| `trigger_push_notifications_after_insert()` | Calls edge function after queue insert |

### Cron Jobs

| Job | Schedule | Purpose |
|-----|----------|---------|
| `process-shift-notifications` | Every minute | Runs `run_shift_notification_workers()` |
| `cleanup-shift-notification-events` | Daily 4 AM | Cleans old processed events |

## Edge Function: send-push-notifications

The `send-push-notifications` edge function:

1. Claims pending notifications atomically (prevents double-processing)
2. Consolidates notifications from same sender to same recipient
3. Builds appropriate message based on notification type
4. Sends via FCM HTTP v1 API
5. Handles invalid token cleanup
6. Updates notification status

### Consolidation Logic

Multiple notifications of the same type from the same sender are consolidated:
- Single shift → Shows full details (date, time range)
- Multiple shifts → Shows count ("X vakter")
- Mixed updates/deletes → Combined message ("endret X og slettet Y")

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
}
```

## Replacement Detection

To avoid sending both "deleted" and "created" when a user does delete-then-recreate (common in some UIs), the system:

1. On DELETE: Inserts into `pending_shift_deletes` with 90-second delay
2. On INSERT: Checks if there's a pending delete for the **same date**
3. If match found: Suppresses "created" notification, cron sends "updated" instead
4. If no match: Normal "created" notification sent immediately

Matching criteria:
- Same user and date (regardless of start/end times)

## Recurring Conversion Detection

When a recurring shift is "edited", it creates a standalone shift. To show "updated" instead of "added":

1. On INSERT: Check if `NEW.shift_date` exists in `exclusions` array of any `recurring_shifts` for this user
2. If found: Use `shared_shift_updated` type instead of `shared_shift_created`
3. Use different idempotency key prefix (`shift_recurring_converted:`) to avoid conflicts

## Idempotency Keys

Each notification has a unique idempotency key to prevent duplicates:

| Pattern | Used For |
|---------|----------|
| `shift_created:{shift_id}:{viewer_id}` | New shifts |
| `shift_recurring_converted:{shift_id}:{viewer_id}` | Recurring conversions |
| `shift_changes:{owner_id}:{viewer_id}:{hash}` | Batched deletes |
| `shift_direct_updates:{owner_id}:{viewer_id}:{hash}` | Batched updates |
| `recurring_created:{recurring_id}:{viewer_id}` | Recurring patterns |

## Deep Linking

Notifications include data for deep linking:
- `owner_id` - The shift owner's user ID
- `shift_dates` - Comma-separated dates for calendar highlighting

The app navigates to `/sharing?user={owner_id}&dates={shift_dates}` and highlights the relevant dates in the calendar view.

## Trigger Execution Order

**Critical**: The INSERT triggers on `user_shifts` must execute in a specific order:

1. `a_on_shift_created_queue_notification` (ROW-level) - Runs FIRST
   - Checks if notification should be suppressed (replacement detection, recurring conversion)
   - If not suppressed, inserts into `notification_queue`

2. `z_on_shifts_inserted_send_notifications` (STATEMENT-level) - Runs LAST
   - Checks if there are any pending notifications in queue
   - If yes, calls the `send-push-notifications` edge function

The `a_` and `z_` prefixes ensure alphabetical ordering since PostgreSQL executes triggers with the same `action_order` alphabetically by name.

**Why this matters**: If the send trigger ran before the queue trigger, it would send whatever was already in the queue before the current shift's notification decision was made, potentially causing incorrect notifications.

## Troubleshooting

### Notification shows "added" instead of "updated"

Possible causes:
1. **Recurring conversion not detected**: Check if the date is properly in the `exclusions` array
2. **Old edge function**: Ensure `send-push-notifications` is deployed with latest code
3. **Race condition**: The recurring exclusion update might not have committed before the insert trigger ran
4. **Trigger order wrong**: Verify triggers are named with `a_` and `z_` prefixes for correct ordering

### Delete+recreate shows "added" instead of "updated"

The replacement detection system should suppress the "created" notification when:
1. A shift is deleted (creates `pending_shift_deletes` entry with 90s delay)
2. A new shift is created on the **same date** within 90 seconds

**Note**: The system matches on same date only - any shift created on the same date as a recently deleted shift is considered a replacement, regardless of start/end times.

If this isn't working, check:
1. **Trigger order**: The queue trigger must run before the send trigger
2. **pending_shift_deletes**: Verify the delete created an entry with `status = 'pending'`
3. **Timing**: The `check_at` must be > now() for suppression to work

### Notification not sent

Check:
1. `notification_queue` for pending/failed entries
2. `push_devices` for valid FCM tokens
3. `notification_preferences.shared_shifts_enabled` for recipient
4. `shift_shares` for active share relationship (not blocked)

### Duplicate notifications

The idempotency key should prevent duplicates. If occurring:
1. Check if different key patterns are being used for same logical event
2. Verify ON CONFLICT clause is working
