-- Function: run_notification_workers
-- Description: Orchestrates notification processing - called by pg_cron every minute
-- Used by: pg_cron job 'process-shift-notifications'
-- Schema: public (to allow RPC call from cron)
--
-- This function is the main entry point for the notification system.
-- It should be called by pg_cron every minute.
--
-- Workflow:
--   1. Process any completed 15-minute windows (fans out to outbox)
--   2. Check if there are pending notifications in the outbox
--   3. If pending notifications exist, trigger the edge function to send them
--
-- Returns:
--   JSON object with:
--     - windows_processed: Number of time windows processed
--     - outbox_rows_created: Number of outbox rows created from windows
--     - triggered_send: Whether the edge function was triggered
--
-- Cron setup:
--   SELECT cron.schedule('process-shift-notifications', '* * * * *', 'SELECT run_notification_workers()');

CREATE OR REPLACE FUNCTION public.run_notification_workers()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $$
DECLARE
  v_window_result RECORD;
  v_has_pending BOOLEAN;
BEGIN
  -- Process due windows (fans out to outbox)
  SELECT * INTO v_window_result FROM internal.process_notification_windows();

  -- Check for pending outbox notifications that are due
  SELECT EXISTS (
    SELECT 1 FROM internal.notifications_outbox
    WHERE status = 'pending' AND due_at <= now()
  ) INTO v_has_pending;

  -- Trigger edge function if pending notifications exist
  IF v_has_pending THEN
    PERFORM net.http_post(
      url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url')
             || '/functions/v1/send-push-notifications',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' ||
          (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key')
      ),
      body := '{}'::jsonb
    );
  END IF;

  RETURN jsonb_build_object(
    'windows_processed', COALESCE(v_window_result.windows_processed, 0),
    'outbox_rows_created', COALESCE(v_window_result.outbox_rows_created, 0),
    'triggered_send', v_has_pending
  );
END;
$$;

-- Grant execute to service_role
GRANT EXECUTE ON FUNCTION public.run_notification_workers TO service_role;
