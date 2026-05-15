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
DELETE FROM internal.notifications_outbox WHERE status = 'sent' AND created_at < NOW() - INTERVAL '3 days';
```

## What It Does

1. **Deletes sent outbox notifications** - Removes entries from `internal.notifications_outbox` that have been sent and are older than 3 days

## Tables Affected

- `internal.notifications_outbox` - Holds notifications ready for delivery

## Dependencies

None - runs pure SQL cleanup.

## Related Functions

- `send-push-notifications` edge function - Sends notifications and sets outbox status to 'sent'
- `process-pending-push-notifications` cron job - Once-per-minute fallback that invokes `send-push-notifications` only when due pending notifications or stale sending notifications exist

## Monitoring

Check for table size growth if cleanup isn't working:

```sql
SELECT
  schemaname || '.' || relname AS table_name,
  pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_catalog.pg_statio_user_tables
WHERE relname IN ('notifications_outbox')
ORDER BY pg_total_relation_size(relid) DESC;
```

Check pending items that haven't been processed:

```sql
SELECT COUNT(*) AS unsent_outbox FROM internal.notifications_outbox WHERE status != 'sent';
```

Check whether the push fallback cron has work to process:

```sql
SELECT EXISTS (
  SELECT 1
  FROM internal.notifications_outbox no
  WHERE no.status = 'pending'
    AND no.due_at <= now()
    AND no.attempts < 10
) OR EXISTS (
  SELECT 1
  FROM internal.notifications_outbox no
  WHERE no.status = 'sending'
    AND no.claimed_at < now() - INTERVAL '15 minutes'
) AS push_fallback_has_work;
```
