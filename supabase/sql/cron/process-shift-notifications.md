# Cron Job: process-shift-notifications

## Overview

Main notification processor that handles non-today shift changes (creates, updates, deletes) aggregated into 15-minute windows, and triggers push notifications.

## Schedule

```
*/15 * * * *
```

**Translation:** Every 15 minutes (at :00, :15, :30, :45)

## SQL Command

```sql
SELECT run_notification_workers();
```

## What It Does

Calls `run_notification_workers()` which:

1. **Processes completed time windows** - Runs `internal.process_notification_windows()` to:
   - Find windows where `window_start + 15 minutes <= now()` and status is 'pending'
   - Build **localized** notification messages based on each recipient's locale:
     - Norwegian (default): "Alvilde la til 2 vakter og endret 1 vakt"
     - English: "Alvilde added 2 shifts and updated 1 shift"
   - Fan out to each non-muted recipient with `shared_shifts_enabled`
   - Insert rows into `internal.notifications_outbox`
   - Mark windows as 'finalized'

2. **Triggers push notification delivery** - If there are pending outbox notifications:
   - Calls `send-push-notifications` edge function via `net.http_post`

## Tables Affected

- `internal.notification_time_windows` - Read pending windows, update status
- `internal.notifications_outbox` - Insert new notifications
- `shift_shares` - Read to find non-muted viewers
- `notification_preferences` - Read to check `shared_shifts_enabled`
- `auth.users` - Read owner name for notification title

## Dependencies

- **Vault secrets:** `supabase_url`, `service_role_key`
- **Extension:** `pg_net` for HTTP calls

## Related Functions

- `run_notification_workers()` - Main orchestrator (public schema)
- `internal.process_notification_windows()` - Processes completed windows
- `internal.upsert_notification_window()` - Called by app to aggregate mutations

## Related Edge Functions

- `send-push-notifications` - Delivers the actual push notifications

## How It Works

1. App server actions (createShifts, updateShift, deleteShift) call `enqueueShiftNotification()`
2. For non-today shifts, this upserts into `internal.notification_time_windows` via RPC
3. Multiple changes in the same 15-min window are aggregated (counts incremented, dates appended)
4. This cron job runs every minute and processes windows that have completed
5. Notifications are fanned out to each eligible recipient in the outbox
6. A trigger on outbox insert invokes the edge function to send push notifications

## Monitoring

Check for processing status:

```sql
SELECT
  (SELECT COUNT(*) FROM internal.notification_time_windows WHERE status = 'pending') AS pending_windows,
  (SELECT COUNT(*) FROM internal.notification_time_windows WHERE status = 'processing') AS processing_windows,
  (SELECT COUNT(*) FROM internal.notifications_outbox WHERE status = 'pending') AS pending_outbox;
```

Check recent windows:

```sql
SELECT
  id, owner_id, window_start,
  added_count, updated_count, deleted_count,
  array_length(affected_dates, 1) as date_count,
  status
FROM internal.notification_time_windows
ORDER BY window_start DESC
LIMIT 10;
```
