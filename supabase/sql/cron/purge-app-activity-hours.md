# Cron job: purge-app-activity-hours

## Schedule

```
50 4 * * *
```

Every day at 04:50 UTC.

## SQL command

```sql
DELETE FROM internal.app_activity_hours
WHERE hour < now() - interval '32 days';
```

## What it does

Deletes hourly activity rows older than 32 days. `public.record_app_activity`
adds one row per user per hour with an app open, and the admin active-users
charts only read the last 30 days. Deleting old rows also means the table
never holds a long history of when each user opens the app.

Created by `supabase/migrations/20260929130000_app_activity_details.sql`.

## Monitoring

```sql
SELECT count(*), min(hour) FROM internal.app_activity_hours;
```
