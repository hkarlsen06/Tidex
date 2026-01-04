-- Function: trigger_push_notifications_after_insert
-- Description: Trigger function that calls send-push-notifications edge function after notification insert
-- Used by: AFTER INSERT trigger on notification_queue

CREATE OR REPLACE FUNCTION public.trigger_push_notifications_after_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'internal', 'pg_temp'
AS $function$
DECLARE
  supabase_url TEXT;
  service_key TEXT;
  pending_count INTEGER;
BEGIN
  -- Check if there are any pending notifications to process
  SELECT COUNT(*) INTO pending_count
  FROM internal.notification_queue
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
      -- Use net.http_post (correct schema for pg_net extension)
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

  RETURN NULL;
END;
$function$;
