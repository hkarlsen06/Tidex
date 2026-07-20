# Cron Job: process-live-activities

## Overview

Invokes `send-push-notifications` to reconcile server-driven ActivityKit Live
Activities for registered iOS devices. The Edge Function starts an activity for
an ongoing shift and ends any registered activity whose shift is no longer
ongoing.

## Schedule

```text
1,16,31,46 * * * *
```

This runs one minute after every quarter hour, in UTC. Shift interpretation is
performed using each device's registered IANA time zone.

## Invocation

The job reads `supabase_url` and `service_role_key` from Supabase Vault and
sends this authenticated JSON body:

```json
{"process_live_activities": true}
```

The target function is:

```text
/functions/v1/send-push-notifications
```

## Idempotency

`internal.live_activity_deliveries` has both a unique device/shift key and a
partial unique index allowing only one `starting`, `active`, or `ending` row per
device. Claim RPCs use a 15-minute stale-claim window and cap delivery attempts
at 10.

An APNs-accepted start remains `starting` with `start_sent_at` populated until
the app registers the ActivityKit update token. The cron therefore does not
send a second push-to-start notification while that callback is pending.

## Monitoring

```sql
SELECT status, count(*)
FROM internal.live_activity_deliveries
GROUP BY status
ORDER BY status;

SELECT *
FROM cron.job_run_details
WHERE jobid = (
  SELECT jobid FROM cron.job WHERE jobname = 'process-live-activities'
)
ORDER BY start_time DESC
LIMIT 20;
```

Never select or log the token columns while diagnosing production delivery.
