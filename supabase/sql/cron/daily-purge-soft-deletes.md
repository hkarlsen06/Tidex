# Cron Job: daily_purge_soft_deletes

## Overview

Hard-deletes user data rows that have been soft-deleted past the retention window.

## Schedule

```cron
30 3 * * *
```

**Translation:** Every day at 3:30 AM UTC

## SQL Command

```sql
SELECT internal.purge_soft_deletes(interval '30 days');
```

## What It Does

Deletes rows whose `deleted_at` timestamp is older than 30 days.

For message rows, it first enqueues Storage API deletion requests for matching attachment objects through `pg_net`, then deletes only message rows that no longer have matching Storage objects. This keeps message metadata around until the object cleanup has succeeded. Deleting message rows cascades message attachment and reaction metadata, and nullable message references are set to `NULL` by their foreign keys.

## Tables Affected

- `storage.objects` - Attachment objects for purged soft-deleted messages
- `public.messages`
- `public.events`
- `public.payroll_adjustments`
- `public.user_shifts`
- `public.recurring_shifts`
- `public.wage_snapshots`
- `public.jobs`

## Related Function

- `internal.purge_soft_deletes(interval)` - Performs the cleanup with a default 30-day retention window
