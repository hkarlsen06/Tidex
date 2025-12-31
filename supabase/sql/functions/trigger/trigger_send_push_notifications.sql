-- Function: trigger_send_push_notifications
-- Description: Utility function to manually trigger push notification processing
-- Used by: Manual invocation when needed

CREATE OR REPLACE FUNCTION public.trigger_send_push_notifications()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'net', 'pg_temp'
AS $function$
DECLARE
  supabase_url TEXT;
  service_key TEXT;
  pending_count INT;
BEGIN
  SELECT COUNT(*) INTO pending_count FROM notification_queue WHERE status = 'pending';

  IF pending_count > 0 THEN
    SELECT decrypted_secret INTO supabase_url FROM vault.decrypted_secrets WHERE name = 'supabase_url';
    SELECT decrypted_secret INTO service_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';

    IF supabase_url IS NOT NULL AND service_key IS NOT NULL THEN
      -- Use pg_net (net schema)
      PERFORM net.http_post(
        url := supabase_url || '/functions/v1/send-push-notifications',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || service_key
        ),
        body := '{}'::jsonb
      );
    END IF;
  END IF;
END;
$function$;
