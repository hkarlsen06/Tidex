-- Migration: Create cron jobs for shift reminder processing
-- - Main job runs every 10 minutes to process shift reminders
-- - Cleanup job runs daily to delete old sent records

-- Cron job to process shift reminders every 10 minutes
-- Uses net.http_post from pg_net extension with vault secrets
SELECT cron.schedule(
  'process-shift-reminders',
  '*/10 * * * *',  -- Every 10 minutes
  $$
  SELECT
    net.http_post(
      url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url') || '/functions/v1/process-shift-reminders',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key')
      ),
      body := '{}'::jsonb
    ) AS request_id;
  $$
);

-- Cleanup old sent records daily at 3 AM
SELECT cron.schedule(
  'cleanup-shift-reminders-sent',
  '0 3 * * *',  -- Daily at 3 AM
  $$
  DELETE FROM shift_reminders_sent WHERE sent_at < NOW() - INTERVAL '7 days';
  $$
);
