-- Function: run_shift_notification_workers
-- Description: Main orchestrator that runs both shift notification processors and triggers push
-- Used by: process-shift-notifications cron job (every minute)

CREATE OR REPLACE FUNCTION public.run_shift_notification_workers()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_delete_result RECORD;
  v_update_result RECORD;
  v_has_pending BOOLEAN;
BEGIN
  -- Run both processors
  SELECT * INTO v_delete_result FROM process_pending_shift_deletes();
  SELECT * INTO v_update_result FROM process_shift_update_events();

  -- Check if there are any pending notifications to send
  SELECT EXISTS (
    SELECT 1 FROM notification_queue WHERE status = 'pending'
  ) INTO v_has_pending;

  -- If there are pending notifications, trigger the edge function
  IF v_has_pending THEN
    PERFORM net.http_post(
      url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url') || '/functions/v1/send-push-notifications',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key')
      ),
      body := '{}'::jsonb
    );
  END IF;

  -- Return combined result
  RETURN jsonb_build_object(
    'pending_deletes', jsonb_build_object(
      'owners_processed', COALESCE(v_delete_result.owners_processed, 0),
      'updated', COALESCE(v_delete_result.total_updated, 0),
      'deleted', COALESCE(v_delete_result.total_deleted, 0)
    ),
    'direct_updates', jsonb_build_object(
      'owners_processed', COALESCE(v_update_result.owners_processed, 0),
      'updated', COALESCE(v_update_result.total_updated, 0)
    ),
    'triggered_send', v_has_pending
  );
END;
$function$;
