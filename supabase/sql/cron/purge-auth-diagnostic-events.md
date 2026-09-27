# Cron job: purge-auth-diagnostic-events

## Schedule

```
45 4 * * 0
```

Every Sunday at 04:45 UTC.

## SQL command

```sql
DELETE FROM internal.auth_diagnostic_events
WHERE occurred_at < now() - interval '90 days';
```

## What it does

Deletes auth diagnostic rows older than 90 days. The iOS app writes these rows
through `public.record_auth_diagnostic_event`, including anonymous launch and
session reports, so the table grows without a limit otherwise.

Created by `supabase/migrations/20260927130300_harden_auth_diagnostic_events.sql`.

## Monitoring

```sql
SELECT count(*), min(occurred_at) FROM internal.auth_diagnostic_events;
```
