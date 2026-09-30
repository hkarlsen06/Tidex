-- Tidex has been free since 2026-09-28 and sells no subscriptions, so no free trial can start.
-- Removes the hourly cron job that queued trial-ending push reminders and the function it ran.
SELECT cron.unschedule('queue-subscription-trial-reminders')
WHERE EXISTS (
  SELECT 1
  FROM cron.job
  WHERE jobname = 'queue-subscription-trial-reminders'
);

DROP FUNCTION IF EXISTS internal.queue_subscription_trial_reminders(integer);
