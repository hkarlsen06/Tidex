-- Migration: Enable instant push notifications via pg_net
-- This replaces the cron-based polling with direct edge function invocation
-- when notifications are queued, resulting in instant delivery.
--
-- Architecture:
-- 1. Row-level trigger (on_shift_created_notify) queues notifications per shift
-- 2. Statement-level trigger (on_shifts_inserted_send_notifications) fires ONCE after all inserts
-- 3. This ensures batch inserts (e.g., 6 shifts) get consolidated into one push notification

-- Step 1: Create the statement-level trigger function that calls the edge function
CREATE OR REPLACE FUNCTION trigger_push_notifications_after_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  supabase_url TEXT;
  service_key TEXT;
  pending_count INTEGER;
BEGIN
  -- Check if there are any pending notifications to process
  SELECT COUNT(*) INTO pending_count
  FROM notification_queue
  WHERE status = 'pending';

  -- Only trigger if there are pending notifications
  IF pending_count > 0 THEN
    -- Get secrets from vault
    SELECT decrypted_secret INTO supabase_url
    FROM vault.decrypted_secrets WHERE name = 'supabase_url';

    SELECT decrypted_secret INTO service_key
    FROM vault.decrypted_secrets WHERE name = 'service_role_key';

    -- Only call if we have the required secrets
    IF supabase_url IS NOT NULL AND service_key IS NOT NULL THEN
      PERFORM extensions.http_post(
        url := supabase_url || '/functions/v1/send-push-notifications',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || service_key
        ),
        body := '{}'::jsonb
      );
    END IF;
  END IF;

  RETURN NULL;
END;
$$;

-- Step 2: Create the statement-level trigger (fires ONCE after all inserts complete)
CREATE TRIGGER on_shifts_inserted_send_notifications
  AFTER INSERT ON user_shifts
  FOR EACH STATEMENT
  EXECUTE FUNCTION trigger_push_notifications_after_insert();

-- Step 3: Remove the cron job since we now trigger instantly
SELECT cron.unschedule('process-push-notifications');

-- Add comments
COMMENT ON FUNCTION trigger_push_notifications_after_insert IS
'Statement-level trigger that fires ONCE after all shift inserts complete.
Triggers the send-push-notifications edge function via pg_net for instant delivery.
This ensures batch inserts (e.g., 6 shifts) result in one consolidated notification.';
