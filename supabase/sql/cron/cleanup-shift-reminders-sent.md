# Cron Job: cleanup-shift-reminders-sent

## Overview

Cleans up old shift reminder records to prevent table bloat.

## Schedule

```
0 3 * * *
```

**Translation:** Every day at 3:00 AM UTC

## SQL Command

```sql
DELETE FROM shift_reminders_sent WHERE sent_at < NOW() - INTERVAL '7 days';
```

## What It Does

Removes entries from `shift_reminders_sent` table that are older than 7 days. This table tracks which shift reminders have been sent to prevent duplicate notifications.

## Tables Affected

- `shift_reminders_sent` - Tracks sent shift reminders for deduplication

## Dependencies

None - runs pure SQL cleanup.

## Related Functions

- `get_shifts_due_for_reminder()` - Queries shifts that need reminders (uses `shift_reminders_sent` for deduplication)

## Related Edge Functions

- `process-shift-reminders` - Processes due reminders and inserts into `shift_reminders_sent`

## Monitoring

Check for table size growth if cleanup isn't working:

```sql
SELECT
  COUNT(*) AS total_records,
  COUNT(*) FILTER (WHERE sent_at < NOW() - INTERVAL '7 days') AS stale_records
FROM shift_reminders_sent;
```
