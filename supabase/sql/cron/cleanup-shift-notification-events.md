# Cron Job: cleanup-shift-notification-events

## Overview

Cleans up old resolved shift notification events to prevent table bloat.

## Schedule

```
0 4 * * *
```

**Translation:** Every day at 4:00 AM UTC

## SQL Command

```sql
DELETE FROM pending_shift_deletes WHERE status = 'resolved' AND check_at < NOW() - INTERVAL '7 days';
DELETE FROM shift_update_events WHERE status = 'sent' AND updated_at < NOW() - INTERVAL '7 days';
```

## What It Does

1. **Deletes resolved pending shift deletes** - Removes entries from `pending_shift_deletes` that have been resolved and are older than 7 days
2. **Deletes sent shift update events** - Removes entries from `shift_update_events` that have been sent and are older than 7 days

## Tables Affected

- `pending_shift_deletes` - Tracks deleted shifts for deferred notification processing
- `shift_update_events` - Tracks shift updates for notification batching

## Dependencies

None - runs pure SQL cleanup.

## Related Functions

- `process_pending_shift_deletes()` - Processes pending deletes and sets status to 'resolved'
- `process_shift_update_events()` - Processes update events and sets status to 'sent'

## Monitoring

Check for table size growth if cleanup isn't working:

```sql
SELECT
  relname AS table_name,
  pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_catalog.pg_statio_user_tables
WHERE relname IN ('pending_shift_deletes', 'shift_update_events')
ORDER BY pg_total_relation_size(relid) DESC;
```
