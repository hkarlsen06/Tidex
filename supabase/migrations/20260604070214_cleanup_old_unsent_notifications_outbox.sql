SELECT cron.unschedule(jobid)
FROM cron.job
WHERE jobname = 'cleanup-shift-notification-events';

SELECT cron.schedule(
  'cleanup-shift-notification-events',
  '0 4 * * 0',
  $$
  DELETE FROM internal.notifications_outbox
  WHERE (status = 'sent' AND created_at < NOW() - INTERVAL '30 days')
     OR (status <> 'sent' AND due_at < NOW() - INTERVAL '3 weeks');
  $$
);
