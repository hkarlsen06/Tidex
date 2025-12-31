# Cron Job: process-shift-notifications

## Overview

Main notification processor that handles shift changes (creates, updates, deletes) and triggers push notifications.

## Schedule

```
* * * * *
```

**Translation:** Every minute

## SQL Command

```sql
SELECT run_shift_notification_workers();
```

## What It Does

Calls `run_shift_notification_workers()` which:

1. **Processes pending shift deletes** - Runs `process_pending_shift_deletes()` to:
   - Claim pending deletes that are ready to process
   - Detect delete-then-recreate patterns (treated as updates)
   - Queue aggregated notifications for viewers

2. **Processes shift update events** - Runs `process_shift_update_events()` to:
   - Claim pending update events
   - Batch updates by owner
   - Queue aggregated notifications for viewers

3. **Triggers push notification delivery** - If there are pending notifications:
   - Calls `send-push-notifications` edge function via `net.http_post`

## Tables Affected

- `pending_shift_deletes` - Read and update status
- `shift_update_events` - Read and update status
- `notification_queue` - Insert new notifications
- `shift_shares` - Read to find viewers
- `notification_preferences` - Read to check viewer preferences

## Dependencies

- **Vault secrets:** `supabase_url`, `service_role_key`
- **Extension:** `pg_net` for HTTP calls

## Related Functions

- `run_shift_notification_workers()` - Main orchestrator
- `process_pending_shift_deletes()` - Handles deleted shifts
- `process_shift_update_events()` - Handles updated shifts

## Related Edge Functions

- `send-push-notifications` - Delivers the actual push notifications

## Monitoring

Check for processing backlogs:

```sql
SELECT
  (SELECT COUNT(*) FROM pending_shift_deletes WHERE status = 'pending') AS pending_deletes,
  (SELECT COUNT(*) FROM shift_update_events WHERE status = 'pending') AS pending_updates,
  (SELECT COUNT(*) FROM notification_queue WHERE status = 'pending') AS pending_notifications;
```
