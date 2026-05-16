DROP FUNCTION IF EXISTS internal.purge_soft_deletes();

SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'daily_purge_soft_deletes';

SELECT cron.schedule(
  'daily_purge_soft_deletes',
  '30 3 * * *',
  $$SELECT internal.purge_soft_deletes(interval '30 days');$$
);
