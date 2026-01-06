# Cron Job: cleanup-shift-notification-events

## Overview

Cleans up old processed notification data to prevent table bloat.

## Schedule

```
0 4 * * *
```

**Translation:** Every day at 4:00 AM UTC

## SQL Command

```sql
DELETE FROM internal.notification_time_windows WHERE status = 'finalized' AND updated_at < NOW() - INTERVAL '3 days';
DELETE FROM internal.notifications_outbox WHERE status = 'sent' AND created_at < NOW() - INTERVAL '3 days';
```

## What It Does

1. **Deletes finalized time windows** - Removes entries from `internal.notification_time_windows` that have been processed and are older than 3 days
2. **Deletes sent outbox notifications** - Removes entries from `internal.notifications_outbox` that have been sent and are older than 3 days

## Tables Affected

- `internal.notification_time_windows` - Aggregates non-today shift mutations into 15-minute windows
- `internal.notifications_outbox` - Holds notifications ready for delivery

## Dependencies

None - runs pure SQL cleanup.

## Related Functions

- `internal.process_notification_windows()` - Processes windows and sets status to 'finalized'
- `send-push-notifications` edge function - Sends notifications and sets outbox status to 'sent'

## Monitoring

Check for table size growth if cleanup isn't working:

```sql
SELECT
  schemaname || '.' || relname AS table_name,
  pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_catalog.pg_statio_user_tables
WHERE relname IN ('notification_time_windows', 'notifications_outbox')
ORDER BY pg_total_relation_size(relid) DESC;
```

Check pending items that haven't been processed:

```sql
SELECT
  (SELECT COUNT(*) FROM internal.notification_time_windows WHERE status != 'finalized') AS unfinalized_windows,
  (SELECT COUNT(*) FROM internal.notifications_outbox WHERE status != 'sent') AS unsent_outbox;
```
