# Cron job: purge-cron-run-details

## Schedule

```
20 4 * * *
```

Every day at 04:20 UTC.

## SQL command

```sql
DELETE FROM cron.job_run_details
WHERE end_time < now() - interval '10 days';
```

## What it does

Deletes pg_cron run history older than 10 days. pg_cron logs every run of
every job in `cron.job_run_details` and never prunes it, so the minutely
`process-pending-push-notifications` job alone adds 1,440 rows a day. Before
this job the table had grown to 94 MB, all of it included in every backup.

Ten days is enough to look back at failed runs. It matches the Logflare log
retention that `/srv/tidex/log-retention.sh` enforced on `mdr`. That script
was not carried over to `one-s`, so Logflare logs there are not pruned yet.

Created by `supabase/migrations/20261001042000_purge_cron_run_details.sql`.

## Monitoring

```sql
SELECT count(*), min(start_time),
  pg_size_pretty(pg_total_relation_size('cron.job_run_details'))
FROM cron.job_run_details;
```
