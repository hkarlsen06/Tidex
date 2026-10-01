-- pg_cron records every run in cron.job_run_details and never deletes them.
-- process-pending-push-notifications alone adds 1,440 rows a day. Keep 10 days,
-- enough to look back at failures, the same window as the Logflare logs on mdr.

SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'purge-cron-run-details';

SELECT cron.schedule(
  'purge-cron-run-details',
  '20 4 * * *',
  $cron$DELETE FROM cron.job_run_details WHERE end_time < now() - interval '10 days';$cron$
);
