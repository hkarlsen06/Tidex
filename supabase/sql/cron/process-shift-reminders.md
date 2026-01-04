# Cron Job: process-shift-reminders

## Overview

Triggers the edge function that sends shift reminder notifications to users before their shifts start.

## Schedule

```
* * * * *
```

**Translation:** Every minute

## SQL Command

```sql
SELECT
  net.http_post(
    url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url') || '/functions/v1/process-shift-reminders',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key')
    ),
    body := '{}'::jsonb
  ) AS request_id;
```

## What It Does

1. Retrieves Supabase URL and service role key from vault
2. Calls `process-shift-reminders` edge function via HTTP POST
3. Edge function queries `get_shifts_due_for_reminder()` to find shifts needing reminders
4. Edge function sends push notifications and records sent reminders

## Tables Affected (via edge function)

- `user_shifts` - Read to find upcoming shifts
- `internal.push_devices` - Read to get device tokens
- `notification_preferences` - Read to check reminder settings
- `shift_reminders_sent` - Insert to track sent reminders

## Dependencies

- **Vault secrets:** `supabase_url`, `service_role_key`
- **Extension:** `pg_net` for HTTP calls

## Related Functions

- `get_shifts_due_for_reminder()` - Returns shifts that need reminder notifications

## Related Edge Functions

- `process-shift-reminders` - Main reminder processing logic

## Reminder Logic

Users can configure multiple reminder times (e.g., [60, 300] = 1 hour and 5 hours before).
The function uses a narrow time window to ensure reminders fire exactly once:
- Window: `[reminder_minutes - 1, reminder_minutes]` minutes before shift

## Monitoring

Check reminder delivery:

```sql
SELECT
  DATE(sent_at) AS date,
  COUNT(*) AS reminders_sent
FROM shift_reminders_sent
WHERE sent_at >= NOW() - INTERVAL '7 days'
GROUP BY DATE(sent_at)
ORDER BY date DESC;
```
