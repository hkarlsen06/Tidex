-- Gate the push-notification cron fallback so it only invokes the Edge
-- Function when there is due work or stale in-flight work to recover.
--
-- The immediate outbox trigger still wakes delivery on inserts/updates; this
-- cron remains as a once-per-minute fallback without producing empty pg_net
-- calls when the queue is idle.

SELECT cron.unschedule('process-pending-push-notifications')
WHERE EXISTS (
  SELECT 1
  FROM cron.job
  WHERE jobname = 'process-pending-push-notifications'
);

SELECT cron.schedule(
  'process-pending-push-notifications',
  '* * * * *',
  $$
    WITH secrets AS (
      SELECT
        (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url') AS supabase_url,
        (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key') AS service_role_key
    ),
    queue_work AS (
      SELECT EXISTS (
        SELECT 1
        FROM internal.notifications_outbox no
        WHERE no.status = 'pending'
          AND no.due_at <= now()
          AND no.attempts < 10
      ) OR EXISTS (
        SELECT 1
        FROM internal.notifications_outbox no
        WHERE no.status = 'sending'
          AND no.claimed_at < now() - INTERVAL '15 minutes'
      ) AS has_work
    )
    SELECT net.http_post(
      url := secrets.supabase_url || '/functions/v1/send-push-notifications',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || secrets.service_role_key
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 5000
    )
    FROM secrets
    CROSS JOIN queue_work
    WHERE secrets.supabase_url IS NOT NULL
      AND secrets.service_role_key IS NOT NULL
      AND queue_work.has_work;
  $$
);
