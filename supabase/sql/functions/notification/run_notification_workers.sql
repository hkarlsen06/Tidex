-- Function: run_notification_workers
-- Description: Orchestrates notification processing - called by pg_cron every 15 minutes
-- Used by: pg_cron job 'process-shift-notifications'
-- Schema: public (to allow RPC call from cron)
--
-- This function is the main entry point for the notification system.
-- It should be called by pg_cron every 15 minutes.
--
-- Workflow:
--   1. Process any completed 15-minute windows (fans out to outbox)
--   2. The trigger_send_push_after_insert on notifications_outbox automatically
--      invokes send-push-notifications when rows are inserted
--
-- Returns:
--   JSON object with:
--     - windows_processed: Number of time windows processed
--     - outbox_rows_created: Number of outbox rows created from windows
--
-- Cron setup:
--   SELECT cron.schedule('process-shift-notifications', '*/15 * * * *', 'SELECT run_notification_workers()');

CREATE OR REPLACE FUNCTION public.run_notification_workers()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'internal', 'pg_temp'
AS $$
DECLARE
  v_window_result RECORD;
BEGIN
  -- Process due windows (fans out to outbox)
  -- Note: The trigger_send_push_after_insert on notifications_outbox
  -- automatically invokes send-push-notifications when rows are inserted
  SELECT * INTO v_window_result FROM internal.process_notification_windows();

  RETURN jsonb_build_object(
    'windows_processed', COALESCE(v_window_result.windows_processed, 0),
    'outbox_rows_created', COALESCE(v_window_result.outbox_rows_created, 0)
  );
END;
$$;

-- Grant execute to service_role
GRANT EXECUTE ON FUNCTION public.run_notification_workers TO service_role;
